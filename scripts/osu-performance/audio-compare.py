#!/usr/bin/env python3
"""Safe, bounded PipeWire A/B/A/B test. Shared audio graph; opt-in only.

No system/user Nix configuration or osu! process modification. Compares stability,
NOT end-to-end hardware or hitsound timing. Data includes raw pw-top text for audit.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import time

ABORT = False

def interrupted(signum, frame):
    global ABORT
    ABORT = True


def run(*cmd: str, timeout=7):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, errors='replace', timeout=timeout)
        return {'rc': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr}
    except (subprocess.TimeoutExpired, OSError) as e:
        return {'rc': None, 'stdout': '', 'stderr': repr(e)}


def force_value():
    r = run('pw-metadata', '-n', 'settings', '0', 'clock.force-quantum')
    matches = re.findall(r"clock\.force-quantum.*?value:\s*'?(\d+)'?", r['stdout'])
    if not matches:
        raise RuntimeError('Cannot read clock.force-quantum safely: ' + r['stdout'][:1000] + ' ' + r['stderr'][:1000])
    return int(matches[-1])


def set_force(value):
    r = run('pw-metadata','-n','settings','0','clock.force-quantum',str(value))
    if r['rc'] != 0 or force_value() != value:
        raise RuntimeError(f'Could not verify quantum={value}: {r!r}')


def atomic_text(p, s):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding='utf-8')


def read(path):
    try: return Path(path).read_text(errors='replace').strip()
    except OSError: return None


def sys_snapshot():
    snap = {'utc': datetime.now(timezone.utc).isoformat(), 'clock_monotonic_ns': time.monotonic_ns(), 'temperatures_c':{}, 'throttle':{}, 'freq_mhz':{}}
    for p in sorted(Path('/sys/class/thermal').glob('thermal_zone*')):
        n=read(p/'type'); v=read(p/'temp')
        if v and n:
            try: snap['temperatures_c'][n]=round(int(v)/1000,3)
            except ValueError: pass
    for p in sorted(Path('/sys/devices/system/cpu').glob('cpu[0-9]*')):
        n=p.name
        v=read(p/'cpufreq/scaling_cur_freq')
        if v:
            try: snap['freq_mhz'][n]=round(int(v)/1000,2)
            except ValueError: pass
    # CPU0 is sufficient for per-package counters; do not sum identical counters on every core.
    for p in sorted(Path('/sys/devices/system/cpu/cpu0/thermal_throttle').glob('*')):
        v=read(p)
        if v and v.isdigit():snap['throttle'][p.name]=int(v)
    return snap


def alsa_hw():
    return {str(p): read(p) for p in sorted(Path('/proc/asound').glob('card*/pcm*p/sub*/hw_params'))}


def pw_stats(text):
    """Parse the pw-top batch columns without claiming follower QUANT is driver period."""
    data={}
    for line in text.splitlines():
        a=line.split()
        if len(a)<10 or a[0] not in ('R','S','C','I','E','T','t') or not a[1].isdigit():continue
        try:
            q=int(a[2]);rate=int(a[3]);err=int(a[8]);node_id=int(a[1])
        except (ValueError,IndexError):continue
        name=line.strip().split()[-1]
        if not (name.startswith('alsa_output.pci-0000_00_1f.3') or name=='alsa_playback.osu!'):
            continue
        key='hda_output' if name.startswith('alsa_output') else 'osu_stream'
        data.setdefault(key,[]).append({'state':a[0],'id':node_id,'q':q,'rate':rate,'err':err,'name':name})
    result={}
    for k,vals in data.items():
        runrows=[r for r in vals if r['state']=='R' and r['rate']>0]
        identity={(r['id'],r['name']) for r in runrows}
        no_reset=all(y['err']>=x['err'] for x,y in zip(runrows,runrows[1:]))
        comparable=len(identity)==1 and no_reset and len(runrows)>=2
        result[k]={'observed':len(vals),'running':len(runrows), 'quantum_samples':sorted(set((r['q'],r['rate']) for r in runrows)),
                   'err_first':runrows[0]['err'] if runrows else None,
                   'err_last':runrows[-1]['err'] if runrows else None,
                   'err_delta': runrows[-1]['err']-runrows[0]['err'] if comparable else None,
                   'comparable_within_block': comparable,
                   'note':'follower q is suggested, not necessarily graph cycle' if k=='osu_stream' else 'driver q reports graph cycle'}
    return result


def end_process(p):
    if p is None or p.poll() is not None:return
    p.terminate()
    try:p.wait(timeout=3)
    except subprocess.TimeoutExpired:
        p.kill();p.wait(timeout=3)


def main():
    global ABORT
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--block-seconds',type=int,default=50,help='duration of each 0/256/0/256 block (15..300)')
    ap.add_argument('--focus-seconds',type=int,default=8)
    ap.add_argument('--warmup-seconds',type=int,default=4)
    ap.add_argument('--quantum',type=int,choices=[128,256,512],default=256)
    ap.add_argument('--outdir',default=None)
    ap.add_argument('--thermal-stop-c',type=float,default=99.0,help='stop the TEST (not osu!) when x86_pkg_temp reaches threshold, default 99C')
    ap.add_argument('--record-mic',action='store_true',help='optional private acoustic recording; microphone near keypad + headphone')
    ap.add_argument('--mic-target',default='alsa_input.usb-HP__Inc_HyperX_SoloCast-00.analog-stereo')
    args=ap.parse_args()
    minimum = 1 if os.environ.get('OSU_COMPARE_SMOKE_TEST') == '1' else 15
    if not minimum<=args.block_seconds<=300 or not 0<=args.focus_seconds<=30 or not 0<=args.warmup_seconds<=20 or not 85<=args.thermal_stop_c<=105:ap.error('invalid duration or temperature guard')
    for cmd in ('pw-metadata','pw-top'):
        if not shutil.which(cmd):ap.error(f'{cmd} unavailable (nix shell nixpkgs#pipewire ...)')
    if args.record_mic and not shutil.which('pw-record'):ap.error('pw-record missing')
    d=Path(args.outdir or f'audio-comparison-{datetime.now():%Y%m%d-%H%M%S}').absolute()
    d.mkdir(parents=True, exist_ok=False)
    runtime=Path(os.environ.get('XDG_RUNTIME_DIR','/tmp'))
    if not runtime.is_dir():ap.error('XDG_RUNTIME_DIR not found')
    lock=runtime/f'osu-audio-quantum-lab-{os.getuid()}.lock'
    fd=open(lock,'a')
    try: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:ap.error('osu-audio-quantum-lab is active; cannot overlap')
    initial=force_value()
    if initial!=0:ap.error(f'clock.force-quantum={initial} before experiment; run `osu-audio-quantum-lab restore` if safe')
    original_signal={s:signal.getsignal(s) for s in (signal.SIGTERM,signal.SIGINT)}
    for s in original_signal:signal.signal(s,interrupted)
    meta={'created_utc':datetime.now(timezone.utc).isoformat(),'initial_force':initial,
          'condition_sequence':[0,args.quantum,0,args.quantum],
          'block_seconds':args.block_seconds,'focus_seconds':args.focus_seconds,'warmup_seconds':args.warmup_seconds,
          'mic_recording':args.record_mic,'thermal_stop_c':args.thermal_stop_c,
          'limits':['not a physical end-to-end latency test','manual gameplay must use matched workload','ERR includes xruns and errors; cross-node totals must not be added','stage transitions can change device state']}
    results=[];last_set=0;restoration='not attempted';exit_code=0
    try:
        print('Open osu! before beginning. Keep the same beatmap/skin/volume and keep osu! in foreground.',flush=True)
        print(f'Focus osu! now ({args.focus_seconds}s); no additional terminal interaction required.',flush=True)
        for i in range(args.focus_seconds):
            if ABORT:raise KeyboardInterrupt
            time.sleep(1)
        for index,quantum in enumerate(meta['condition_sequence']):
            if ABORT:raise KeyboardInterrupt
            stage=d/f'{index+1:02d}-q{quantum}'
            stage.mkdir()
            print(f'BLOCK {index+1}/4: requested quantum={quantum}, duration={args.block_seconds}s. Keep game active.',flush=True)
            if quantum!=last_set:
                last_set=quantum;set_force(quantum)
            for _ in range(args.warmup_seconds):
                if ABORT:raise KeyboardInterrupt
                time.sleep(1)
            atomic_text(stage/'metadata.txt',run('pw-metadata','-n','settings','0')['stdout'])
            before=sys_snapshot()
            hw_before=alsa_hw()
            active0=run('hyprctl','-j','activewindow') if shutil.which('hyprctl') else {'rc':None,'stdout':''}
            with open(stage/'pw-top.txt','w') as pw_log:
                p=subprocess.Popen(['pw-top','-b','-n',str(args.block_seconds+2)],stdout=pw_log,stderr=subprocess.STDOUT,text=True)
                mic=None
                if args.record_mic:
                    # Audio capture is opt-in; save only private user-selected physical microphone audio.
                    rec=open(stage/'mic.log','w')
                    mic=subprocess.Popen(['pw-record',f'--target={args.mic_target}', '--rate=48000','--channels=1','--format=s16',str(stage/'mic.wav')],stdout=rec,stderr=subprocess.STDOUT)
                started=time.monotonic()
                try:
                    while time.monotonic()-started<args.block_seconds:
                        if ABORT:raise KeyboardInterrupt
                        # The user measured 94-98C and Intel lists Tjunction=100C.
                        # Abort only this experiment, never the game, near thermal limit.
                        sensor = next((z for z in Path('/sys/class/thermal').glob('thermal_zone*') if read(z/'type')=='x86_pkg_temp'),None)
                        cur = read(sensor/'temp') if sensor else None
                        if cur and cur.isdigit() and int(cur)/1000 >= args.thermal_stop_c:
                            raise RuntimeError(f'THERMAL_GUARD: package {int(cur)/1000:.1f}C reached {args.thermal_stop_c:.1f}C. Experiment stopped; game untouched.')
                        time.sleep(min(1, max(.05,args.block_seconds-(time.monotonic()-started))))
                finally:
                    end_process(p)
                    if mic is not None:
                        end_process(mic)
                        rec.close()
            after=sys_snapshot()
            hw_after=alsa_hw()
            active1=run('hyprctl','-j','activewindow') if shutil.which('hyprctl') else {'rc':None,'stdout':''}
            data={'stage':index+1,'requested_quantum':quantum,'force_confirmed':force_value()==quantum,
                  'start':before,'end':after,'alsa_before':hw_before,'alsa_after':hw_after,
                  'active_before':active0['stdout'][:1500],'active_after':active1['stdout'][:1500],
                  'pw_top':pw_stats((stage/'pw-top.txt').read_text(errors='replace'))}
            atomic_text(stage/'stage.json',json.dumps(data,indent=2,ensure_ascii=False))
            results.append(data)
            out=data['pw_top'].get('hda_output',{})
            print(f'  sink running rows={out.get("running",0)} ERR delta={out.get("err_delta")} temp={before["temperatures_c"].get("x86_pkg_temp")}→{after["temperatures_c"].get("x86_pkg_temp")}℃',flush=True)
    except KeyboardInterrupt:
        print('INTERRUPTED: attempting graph restoration',file=sys.stderr,flush=True);exit_code=130
    except Exception as e:
        print('FAILED: '+repr(e),file=sys.stderr,flush=True);exit_code=1
    finally:
        try:
            current=force_value()
            if current==last_set and current!=0:
                set_force(0);restoration='success'
            elif current==0:restoration='already automatic'
            else:restoration=f'external change detected ({current}); preserved'
        except Exception as e:
            restoration='ERROR: '+repr(e)
            print('RESTORE FAILURE; inspect `osu-audio-quantum-lab status`',file=sys.stderr);exit_code=1
        meta['restoration']=restoration
        meta['results_count']=len(results)
        atomic_text(d/'experiment.json',json.dumps({'meta':meta,'results':results},ensure_ascii=False,indent=2))
        archive=d.with_suffix('.tar.gz')
        with tarfile.open(archive,'w:gz') as tar:tar.add(d,arcname=d.name)
        print(f'DONE: {archive}\nRESTORE: {restoration}',flush=True)
        for s,h in original_signal.items():signal.signal(s,h)
    return exit_code

if __name__=='__main__':sys.exit(main())
