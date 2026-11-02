#!/usr/bin/env python3
"""Short authorized hardware checks. Run with the Python from --package's wrapper.

Only metadata survives. Camera receivers run for five seconds with at most nine
seconds of camera input. Raw mic capture is three seconds and synthetic NVENC
is ten. No app acceptance or performance claim.
"""

import argparse
import base64
from contextlib import contextmanager
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
import wave
from zoneinfo import ZoneInfo


PACKAGE = "/nix/store/pl7g7h76d8ajbgib6fyx14bwhlp0m78q-splitcast-0.1.0"
PYTHON = "/nix/store/bp92j4bqak0r1scr4afhzi1r1zpicxsv-python3-3.13.15-env/bin/python"
ROOT = Path(__file__).resolve().parents[2] if "__file__" in globals() else None
STATUSES = {"PASS", "FAIL", "BLOCKED", "NOT_RUN"}


def now():
    return datetime.now(ZoneInfo("Asia/Tokyo")).isoformat(timespec="seconds")


class Blocked(Exception):
    pass


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


class Session:
    def __init__(self, directory, package):
        self.directory = directory
        self.children = []
        self.logs = []
        self.commands = []
        self.aliases = {str(directory): "<private-temp>"}
        wrapper = (Path(package) / "bin/splitcast").read_text()
        self.bins = re.findall(r"PATH='(/nix/store/[^']+/bin)'", wrapper)
        self.plugins = re.findall(r"LADSPA_PATH='(/nix/store/[^']+)'", wrapper)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("MTX_")}
        self.env["PATH"] = ":".join(self.bins) + ":" + self.env.get("PATH", "")
        self.env["LADSPA_PATH"] = ":".join(self.plugins)
        self.env["LD_LIBRARY_PATH"] = "/run/opengl-driver/lib:" + self.env.get("LD_LIBRARY_PATH", "")

    def safe(self, value):
        text = str(value)
        for original, alias in sorted(self.aliases.items(), key=lambda x: -len(x[0])):
            text = text.replace(original, alias)
        return text

    def argv(self, args):
        executable = shutil.which(str(args[0]), path=self.env["PATH"])
        if executable is None:
            raise Blocked(f"missing executable {args[0]}")
        return [executable, *map(str, args[1:])]

    def start(self, args, name, env=None, stdin=None):
        argv = self.argv(args)
        log = (self.directory / f"{len(self.logs)}-{name}.log").open("w+b")
        self.logs.append(log)
        child = subprocess.Popen(argv, shell=False, start_new_session=True,
                                 stdin=stdin if stdin is not None else subprocess.DEVNULL,
                                 stdout=log, stderr=log, env=env or self.env)
        record = {"argv": [self.safe(a) for a in argv], "started_jst": now()}
        self.commands.append(record)
        self.children.append((child, record, log))
        return child

    def stop(self, child):
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=4)
        for p, record, _ in self.children:
            if p is child:
                record["exit_code"] = p.returncode

    def run(self, args, timeout=30, env=None, check=True):
        child = self.start(args, "command", env=env)
        try:
            child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.stop(child)
            raise RuntimeError(f"{args[0]} exceeded {timeout}s deadline")
        _, record, log = self.children[-1]
        record["exit_code"] = child.returncode
        log.seek(0)
        output = log.read().decode(errors="replace")
        if check:
            require(child.returncode == 0, f"{args[0]} exited {child.returncode}; {diagnosis(output)}")
        return child.returncode, output

    def wait(self, child, timeout):
        try:
            child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.stop(child)
            raise RuntimeError("owned media process exceeded deadline")
        log = next(log for p, _, log in self.children if p is child)
        log.seek(0)
        output = log.read().decode(errors="replace")
        require(child.returncode == 0, f"media process exited {child.returncode}; {diagnosis(output)}")

    def clean(self):
        for child, _, _ in reversed(self.children):
            self.stop(child)
        for log in self.logs:
            log.close()
        return all(p.poll() is not None for p, _, _ in self.children)


def diagnosis(output):
    known = ["Permission denied", "Device or resource busy", "Cannot load libcuda",
             "Cannot load libnvidia-encode", "No VA display found", "Failed to initialise VAAPI",
             "Connection refused", "Invalid argument", "Failed to load module", "Unknown PCM",
             "Error initializing", "No such file or directory", "Failed to create sink",
             "Failed to load plugin", "Failed to initialize", "Failed to open", "Input/output error"]
    return ", ".join(x for x in known if x.lower() in output.lower()) or "inspect private ephemeral log during rerun"


def ff(*args):
    return ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin", "-y", *map(str, args)]


def probe(s, path):
    _, text = s.run(["ffprobe", "-v", "error", "-count_packets", "-count_frames",
                     "-show_entries", "stream=codec_name,codec_type,width,height,avg_frame_rate,nb_read_packets,nb_read_frames,sample_rate,channels:format=duration",
                     "-of", "json", path], timeout=45)
    data = json.loads(text)
    require(bool(data.get("streams")), "recording has no streams")
    require(all(int(x.get("nb_read_packets", 0)) > 0 for x in data["streams"]), "recording has no packets")
    s.run(ff("-xerror", "-i", path, "-f", "null", "-"), timeout=45)
    return data


def check(s, name, function):
    start = len(s.commands)
    item = {"id": name, "started_jst": now()}
    try:
        item["observed"] = function()
        item["status"] = "PASS"
    except Blocked as exc:
        item.update(status="BLOCKED", reason=s.safe(exc))
    except Exception as exc:
        item.update(status="FAIL", reason=s.safe(exc))
    item["finished_jst"] = now()
    item["commands"] = s.commands[start:]
    return item


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def listeners(pid):
    inodes = set()
    for fd in Path(f"/proc/{pid}/fd").iterdir():
        try:
            value = fd.readlink().as_posix()
        except FileNotFoundError:
            continue
        if value.startswith("socket:["):
            inodes.add(value[8:-1])
    found = []
    for protocol in ("tcp", "tcp6", "udp", "udp6"):
        for line in Path(f"/proc/{pid}/net/{protocol}").read_text().splitlines()[1:]:
            fields = line.split()
            if fields[9] in inodes and (not protocol.startswith("tcp") or fields[3] == "0A"):
                address, port = fields[1].split(":")
                found.append({"protocol": protocol, "address_hex": address, "port": int(port, 16)})
    return found


@contextmanager
def mediamtx(s):
    port = free_port()
    config = s.directory / "mediamtx.yml"
    config.write_text(f"""logLevel: info
rtsp: true
rtspAddress: 127.0.0.1:{port}
rtspTransports: [tcp]
rtmp: false
hls: false
webrtc: false
srt: false
api: false
metrics: false
pprof: false
playback: false
pathDefaults:
  record: false
paths:
  camera:
""")
    child = s.start(["mediamtx", config], "mediamtx")
    try:
        for _ in range(80):
            require(child.poll() is None, "isolated MediaMTX exited")
            opened = listeners(child.pid)
            if opened:
                require(opened == [{"protocol": "tcp", "address_hex": "0100007F", "port": port}],
                        "MediaMTX has unexpected listener")
                yield f"rtsp://127.0.0.1:{port}/camera", opened
                return
            time.sleep(0.1)
        raise RuntimeError("MediaMTX readiness timeout")
    finally:
        s.stop(child)


def camera(s, device):
    label = "NearStream" if "NearStream" in device.name else "Toshiba" if "TOSHIBA" in device.name else "USB camera"
    s.aliases[str(device)] = f"<by-id:{label}:index0>"
    _, formats = s.run(["v4l2-ctl", "-d", device, "--list-formats-ext"])
    modes = []
    current = None
    size = None
    for line in formats.splitlines():
        match = re.search(r"\[\d+\]: '([^']+)'", line)
        if match:
            current = match[1]
        match = re.search(r"Size: Discrete (\d+x\d+)", line)
        if match:
            size = match[1]
        match = re.search(r"\(([\d.]+) fps\)", line)
        if match:
            modes.append({"format": current, "size": size, "fps": float(match[1])})
    candidates = [m for m in modes if m["format"] in ("H264", "MJPG", "YUYV")
                  and m["size"] == "1280x720" and m["fps"] == 30]
    if not candidates:
        candidates = [m for m in modes if m["format"] in ("H264", "MJPG", "YUYV")
                      and m["size"] == "640x480" and m["fps"] == 30]
    if not candidates:
        raise Blocked("no supported 720p30 or 480p30 hardware-compatible camera mode")
    selected = min(candidates, key=lambda m: ("H264", "MJPG", "YUYV").index(m["format"]))
    passthrough = selected["format"] == "H264"
    args = [] if passthrough else ["-vaapi_device", "/dev/dri/renderD128"]
    args += ["-f", "v4l2", "-input_format", {"H264": "h264", "MJPG": "mjpeg", "YUYV": "yuyv422"}[selected["format"]],
             "-video_size", selected["size"], "-framerate", "30", "-i", str(device)]
    args += ["-c:v", "copy"] if passthrough else ["-vf", "format=nv12,hwupload", "-c:v", "h264_vaapi", "-b:v", "2500k", "-g", "30", "-bf", "0"]
    output = s.directory / "camera-received.mkv"
    with mediamtx(s) as (url, opened):
        sender = s.start(ff(*args, "-t", "9", "-an", "-f", "rtsp", "-rtsp_transport", "tcp", url), "camera-send")
        try:
            time.sleep(1)
            require(sender.poll() is None, "camera sender failed before receiver startup")
            s.run(ff("-rtsp_transport", "tcp", "-i", url, "-t", "5", "-c:v", "copy", "-an", output), timeout=18)
            info = probe(s, output)
            stream = info["streams"][0]
            require(stream["codec_name"] == "h264" and int(stream["nb_read_frames"]) >= 120,
                    "camera receiver did not decode five seconds of H.264")
            return {"camera": label, "stable_discovery": "v4l/by-id index0", "advertised_modes": modes,
                    "selected_mode": selected, "encoder": "passthrough" if passthrough else "h264_vaapi",
                    "decode": "FFmpeg software MJPEG input decode and receive H.264 decode" if not passthrough else "receive H.264 decode",
                    "receive_seconds": 5, "listeners": opened, "recording": info,
                    "scope": "local camera to loopback RTSP TCP to decoded receive; no OBS composition or lip sync"}
        finally:
            s.stop(sender)
            output.unlink(missing_ok=True)


def nvenc(s):
    _, gpu = s.run(["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"])
    output = s.directory / "nvenc.mp4"
    s.run(ff("-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=60", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
             "-t", "10", "-c:v", "h264_nvenc", "-preset", "p4", "-tune", "ll", "-rc", "cbr", "-b:v", "6000k",
             "-g", "120", "-bf", "0", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", output), timeout=65)
    info = probe(s, output)
    video = next(x for x in info["streams"] if x["codec_type"] == "video")
    require((video["width"], video["height"], video["avg_frame_rate"], int(video["nb_read_frames"])) ==
            (1920, 1080, "60/1", 600), "NVENC decode did not produce 600 1080p60 frames")
    output.unlink()
    return {"gpu": gpu.strip(), "encoder": "h264_nvenc", "input": "synthetic video and tone", "seconds": 10,
            "recording": info, "scope": "FFmpeg encode and decode only; not OBS NVENC and not full A08"}


def private_mic(s, encoded):
    raw = s.directory / "raw.wav"
    raw.write_bytes(base64.b64decode(encoded, validate=True))
    env = dict(s.env)
    env.pop("DBUS_SESSION_BUS_ADDRESS", None)
    env.pop("DISPLAY", None)
    env.update(XDG_RUNTIME_DIR=str(s.directory), PULSE_RUNTIME_PATH=str(s.directory / "pulse"),
               PULSE_STATE_PATH=str(s.directory / "pulse-state"), PULSE_SERVER=f"unix:{s.directory}/pulse.sock")
    config = s.directory / "pulse.pa"
    config.write_text(f""".fail
load-module module-native-protocol-unix socket={s.directory}/pulse.sock auth-anonymous=1
load-module module-null-sink sink_name=processed rate=48000 channels=1
load-module module-ladspa-sink sink_name=rnnoise master=processed plugin=librnnoise_ladspa label=noise_suppressor_mono control=50,200,0,0,0 rate=48000 channels=1
""")
    pulse = s.start(["pulseaudio", "--daemonize=no", "--use-pid-file=no", "--exit-idle-time=-1", "--disable-shm=yes", "-nF", config], "private-pulse", env=env)
    output = s.directory / "processed.wav"
    receiver = None
    sender = None
    try:
        for _ in range(80):
            require(pulse.poll() is None, "private Pulse failed to load RNNoise")
            if (s.directory / "pulse.sock").exists():
                code, text = s.run(["pactl", "-f", "json", "list", "modules"], env=env, check=False)
                if code == 0 and "module-ladspa-sink" in text:
                    break
            time.sleep(0.1)
        else:
            raise RuntimeError("private Pulse RNNoise readiness timeout")
        modules = json.loads(text)
        require(any(m["name"] == "module-ladspa-sink" for m in modules), "RNNoise module not loaded")
        require(not listeners(pulse.pid), "private Pulse unexpectedly opened a network listener")
        receiver = s.start(ff("-f", "pulse", "-i", "processed.monitor", "-t", "4", "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", output), "mic-receive", env=env)
        time.sleep(0.4)
        sender = s.start(ff("-re", "-i", raw, "-f", "pulse", "rnnoise"), "mic-process", env=env)
        s.wait(sender, 10)
        s.wait(receiver, 12)
        info = probe(s, output)
        with wave.open(str(output), "rb") as wav:
            samples = wav.readframes(wav.getnframes())
        from array import array
        levels = array("h", samples)
        nonzero = sum(x != 0 for x in levels)
        return {"processor": "remote private Pulse module-ladspa-sink RNNoise", "modules": [m["name"] for m in modules],
                "ladspa_paths": s.plugins, "control": "50,200,0,0,0", "rate": 48000, "channels": 1,
                "private_unix_socket": True, "network_listeners": [], "recording": info,
                "processed_nonzero_samples": nonzero, "raw_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
                "processed_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
                "scope": "3s real raw mic transferred via SSH, processed into isolated monitor; no speech-quality or noise-reduction claim"}
    finally:
        for child in (sender, receiver, pulse):
            if child is not None:
                s.stop(child)
        raw.unlink(missing_ok=True)
        output.unlink(missing_ok=True)


def remote_inventory(s):
    result = {"kernel": os.uname().release, "cameras": len(list(Path("/dev").glob("video*"))),
              "display_present": bool(os.environ.get("DISPLAY")),
              "pipewire_socket_present": (Path(f"/run/user/{os.getuid()}") / "pipewire-0").exists(),
              "xvfb_available": bool(shutil.which("Xvfb", path=s.env["PATH"]) or
                                     list(Path("/nix/store").glob("*xorg-server*/bin/Xvfb")))}
    _, text = s.run(["obs", "--version"])
    result["obs_version"] = next((x for x in text.splitlines() if "OBS Studio" in x), "version output unavailable")
    code, _ = s.run(["sudo", "-n", "true"], check=False)
    result["sudo_noninteractive"] = code == 0
    return result


def remote(package, host, task, payload=None, timeout=100):
    request = {"package": package, "task": task, "payload": payload,
               "source": Path(__file__).read_text()}
    loader = "import json,sys; REQUEST=json.load(sys.stdin); exec(compile(REQUEST['source'],'hardware-worker','exec'))"
    argv = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host,
            shlex.join([PYTHON, "-c", loader])]
    child = subprocess.Popen(argv, shell=False, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, start_new_session=True)
    try:
        stdout, _ = child.communicate(json.dumps(request).encode(), timeout=timeout)
        require(child.returncode == 0, f"SSH worker failed with exit {child.returncode}")
        result = json.loads(stdout)
        require(result["cleanup_owned_children"], "remote worker cleanup incomplete")
        result["transport"] = {"argv": ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host,
                                       f"{PYTHON} -c <stdin JSON source loader>"],
                               "task": task, "exit_code": child.returncode, "payload": "source and private data over SSH stdin"}
        return result
    finally:
        if child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=4)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()


def worker(request):
    def interrupted(signum, frame):
        raise RuntimeError(f"worker interrupted by signal {signum}")
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGALRM):
        signal.signal(sig, interrupted)
    signal.alarm(90)
    with tempfile.TemporaryDirectory(prefix="splitcast-hardware-") as directory:
        s = Session(Path(directory), request["package"])
        try:
            tasks = {"remote_nvenc": lambda: nvenc(s), "remote_inventory": lambda: remote_inventory(s),
                     "remote_rnnoise": lambda: private_mic(s, request["payload"]),
                     "remote_voicevox": lambda: voicevox(s)}
            result = check(s, request["task"], tasks[request["task"]])
        finally:
            clean = s.clean()
        result["cleanup_owned_children"] = clean
        signal.alarm(0)
        print(json.dumps(result))


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def routes(s):
    _, sink = s.run(["pactl", "get-default-sink"])
    _, source = s.run(["pactl", "get-default-source"])
    _, inputs = s.run(["pactl", "-f", "json", "list", "sink-inputs"])
    _, sinks = s.run(["pactl", "-f", "json", "list", "sinks"])
    _, sources = s.run(["pactl", "-f", "json", "list", "sources"])
    return {"sink": sink.strip(), "source": source.strip(), "inputs": json.loads(inputs),
            "sinks": json.loads(sinks), "sources": json.loads(sources)}


def route_summary(route):
    sink = next((x for x in route["sinks"] if x["name"] == route["sink"]), {})
    source = next((x for x in route["sources"] if x["name"] == route["source"]), {})
    return {"default_sink_sha256": digest(route["sink"]), "default_source_sha256": digest(route["source"]),
            "default_sink_description": sink.get("description"), "active_port": sink.get("active_port"),
            "default_source_description": source.get("description"),
            "raw_sources": [{"description": x.get("description"), "hardware": "HARDWARE" in x.get("flags", []),
                             "monitor": bool(x.get("monitor_source")), "muted": x.get("mute"),
                             "device_class": x.get("properties", {}).get("device.class")}
                            for x in route["sources"]],
            "existing_playback_routes": [{"stream_id": x["index"], "sink_id": x["sink"]} for x in route["inputs"]]}


def mic(s, before, package, host, selected):
    if before is None:
        raise Blocked("local audio server or source list inaccessible")
    name = selected or before["source"]
    source = next((x for x in before["sources"] if x["name"] == name), None)
    if not source or "HARDWARE" not in source.get("flags", []) or source.get("monitor_source"):
        raise Blocked("selected source is absent or not a raw hardware mic")
    if source.get("mute"):
        raise Blocked("selected raw microphone is muted; mute unchanged")
    s.aliases[name] = "<selected-raw-mic>"
    path = s.directory / "mic.wav"
    try:
        s.run(ff("-f", "pulse", "-i", name, "-t", "3", "-ar", "48000", "-ac", "1", "-c:a", "pcm_s16le", path), timeout=12)
        info = probe(s, path)
        with wave.open(str(path), "rb") as wav:
            from array import array
            levels = array("h", wav.readframes(wav.getnframes()))
        require(any(levels), "raw mic returned only zero samples")
        raw_hash = hashlib.sha256(path.read_bytes()).hexdigest()
        result = remote(package, host, "remote_rnnoise", base64.b64encode(path.read_bytes()).decode())
        if result["status"] == "PASS":
            require(result["observed"]["raw_sha256"] == raw_hash, "SSH-transferred raw mic content hash differs")
        return {"selected_description": source["description"], "selected_from_source_list": True,
                "selection": "explicit" if selected else "observed default raw hardware mic",
                "local_processing": "resample to 48k mono only; no RNNoise or EasyEffects", "seconds": 3,
                "raw_recording": info, "raw_sha256": raw_hash,
                "raw_nonzero_samples": sum(x != 0 for x in levels), "remote": result}
    finally:
        path.unlink(missing_ok=True)


def voicevox(s):
    candidates = sorted(Path("/nix/store").glob("*-voicevox-engine-*/bin/*"))
    candidates = [x for x in candidates if x.is_file() and os.access(x, os.X_OK)]
    if not candidates:
        raise Blocked("built VOICEVOX engine executable absent; model and core artifacts alone are not an engine")
    port = free_port()
    engine = s.start([candidates[0], "--host", "127.0.0.1", "--port", str(port)], "voicevox")
    try:
        base = f"http://127.0.0.1:{port}"
        for _ in range(150):
            require(engine.poll() is None, "VOICEVOX engine exited")
            try:
                with urllib.request.urlopen(base + "/version", timeout=1) as response:
                    version = json.load(response)
                break
            except (OSError, ValueError):
                time.sleep(0.2)
        else:
            raise RuntimeError("VOICEVOX readiness timeout")
        opened = listeners(engine.pid)
        require(opened and all(x["protocol"] == "tcp" and x["address_hex"] == "0100007F" for x in opened), "VOICEVOX non-loopback listener")
        query = urllib.parse.urlencode({"text": "テストです。", "speaker": 3})
        with urllib.request.urlopen(urllib.request.Request(base + "/audio_query?" + query, data=b""), timeout=20) as response:
            body = response.read()
        request = urllib.request.Request(base + "/synthesis?speaker=3", data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=25) as response:
            audio = response.read()
        path = s.directory / "tts.wav"
        path.write_bytes(audio)
        info = probe(s, path)
        return {"version": version, "speaker": 3, "text": "テストです。", "recording": info,
                "listeners": opened, "audio_base64_private": base64.b64encode(audio).decode()}
    finally:
        s.stop(engine)


def tts(s, package, host):
    result = remote(package, host, "remote_voicevox")
    if result["status"] != "PASS":
        return {"remote": result}
    audio = result["observed"].pop("audio_base64_private")
    path = s.directory / "tts.wav"
    path.write_bytes(base64.b64decode(audio))
    sink = f"splitcast_hardware_tts_{os.getpid()}"
    module = None
    try:
        _, module = s.run(["pactl", "load-module", "module-null-sink", f"sink_name={sink}"])
        s.run(["paplay", f"--device={sink}", path], timeout=15)
        return {"remote": result, "playback": "paplay to explicit owned local null sink", "heard_by_user": False}
    finally:
        if module is not None:
            s.run(["pactl", "unload-module", module.strip()])
        path.unlink(missing_ok=True)


def tailscale(s, host):
    _, text = s.run(["tailscale", "status", "--json"])
    data = json.loads(text)
    peer = next((x for x in data.get("Peer", {}).values() if x.get("HostName") == host), None)
    if peer is None:
        raise Blocked("named SSH peer not identified in Tailscale status")
    _, ssh_config = s.run(["ssh", "-G", host])
    target = next((line.split(" ", 1)[1] for line in ssh_config.splitlines() if line.startswith("hostname ")), "")
    direct = bool(peer.get("CurAddr"))
    return {"peer": host, "online": peer.get("Online"), "active": peer.get("Active"),
            "path": "direct" if direct else "relay" if peer.get("Relay") and peer.get("Active") else "idle/undetermined",
            "ssh_target_is_peer_tailnet_ip": target in peer.get("TailscaleIPs", []),
            "observed_from": "tailscale status JSON; no address or peer inventory retained"}


def game(s):
    _, text = s.run(["hyprctl", "clients", "-j"])
    windows = [x for x in json.loads(text) if "osu" in x.get("class", "").lower()]
    if not windows:
        raise Blocked("no running osu! window detected; no desktop capture attempted")
    raise Blocked("osu! window exists but an explicitly scoped no-portal game capture target has not been selected")


def version(s, tool, flag):
    _, text = s.run([tool, flag])
    lines = [x for x in text.splitlines() if not x.startswith(" ")]
    return lines[0] if lines else "empty version output"


def result_summary(item):
    if item.get("reason"):
        return item["reason"]
    data = item.get("observed", {})
    if data.get("status") in STATUSES:
        if data.get("reason"):
            return data["reason"]
        data = data.get("observed", {})
    if item["id"] == "remote_inventory":
        return f"{data.get('obs_version')}; {data.get('cameras')} remote camera nodes; display={data.get('display_present')}; PipeWire={data.get('pipewire_socket_present')}; Xvfb={data.get('xvfb_available')}; sudo -n={data.get('sudo_noninteractive')}."
    if item["id"] == "remote_nvenc" and "recording" in data:
        video, audio = data["recording"]["streams"]
        return f"{data['gpu']}. h264_nvenc, 1080p60, 10s. Decoded {video['nb_read_frames']} video frames; {video['nb_read_packets']} H.264 and {audio['nb_read_packets']} AAC packets. FFmpeg only."
    if item["id"].startswith("local_camera") and "recording" in data:
        stream = data["recording"]["streams"][0]
        return f"{data['camera']}, MJPEG 1280x720 at 30 fps to {data['encoder']} to RTSP TCP loopback. Five-second receive, {stream['nb_read_packets']} packets and {stream['nb_read_frames']} decoded frames."
    if item["id"] == "raw_mic_remote_rnnoise" and "remote" in data:
        remote_result = data["remote"]
        if remote_result.get("reason"):
            return remote_result["reason"]
        processed = remote_result.get("observed", {}).get("recording", {}).get("streams", [{}])[0]
        raw = data["raw_recording"]["streams"][0]
        return f"{data['selected_description']}, 3s raw sample, {raw['nb_read_packets']} PCM packets. SSH file transfer, remote private Pulse RNNoise, {processed.get('nb_read_packets')} processed PCM packets. No listening-quality judgment."
    if item["id"] == "remote_voicevox_local_null_playback":
        return data.get("remote", {}).get("reason", "Real synthesis and explicit local null-sink playback completed.")
    if item["id"] == "tailscale_path":
        return f"{data.get('path')}; online={data.get('online')}; active={data.get('active')}; SSH target matches peer tailnet IP={data.get('ssh_target_is_peer_tailnet_ip')}."
    if item["id"] == "preserve_local_audio_routes":
        return "Default source, default sink, and surviving playback stream routes unchanged."
    return json.dumps(data, ensure_ascii=False)


def write_report(report, output):
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    lines = ["# SplitCast isolated hardware evidence", "", f"Observed {report['finished_jst']}.", "",
             "Short isolated hardware-path checks. These results do not pass A01-A15 or current app acceptance.", "",
             "| Subtest | Status | Observed result |", "|---|---|---|"]
    for item in report["subtests"]:
        summary = result_summary(item)
        if len(summary) > 400:
            summary = "Structured observations, packet counts, and commands are in the JSON evidence."
        lines.append(f"| {item['id']} | {item['status']} | {summary.replace('|', '/')} |")
    lines += ["", "## Reproduction", "", "```sh", f"{PYTHON} scripts/splitcast/hardware.py --remote neko7 --package {report['package']}", "```", "",
              f"The existing runtime closure was transferred with `nix copy --to ssh://neko7 {report['package']}`. This is a store transfer, without activation.",
              "The tool invokes media binaries directly. It does not run the package app or validate stale app code.", "",
              "## Boundaries", "", "The camera checks use stable by-id discovery and a supported advertised mode. Five-second receive recordings use at most nine seconds of camera input. H.264 input is copied; MJPEG or YUYV uses explicit VAAPI encoding. Software input and receive decoding are allowed. There is no software video encoding fallback.", "",
              "Raw microphone capture lasts three seconds. The short WAV transfers as a file over SSH before remote processing; this is not live mic streaming. Only metadata and content hashes survive. RNNoise uses a private remote Pulse instance with an owned Unix socket, without restarting the user audio server.", "",
              "VOICEVOX is synthesized only when a built engine exists. Successful audio returns through SSH and plays to an explicit owned null sink. This does not prove audible headphone playback, mute, skip, or mix-minus.", "",
              "All media and private logs are temporary and removed. The worker has a 90-second deadline. Spawned processes have owned process groups and bounded TERM/KILL cleanup. No fault injection, Twitch connection, activation, generation change, or public listener is requested.", "",
              "The JSON contains JST timestamps, sanitized argv, actual binary versions, recording metadata, statuses, route hashes, and cleanup observations. USB serials, tailnet addresses, full status output, window titles, and raw audio/video are excluded.", "",
              "## Limits", "", "Ten seconds of FFmpeg NVENC is not OBS NVENC or full A08. Five-second camera transport is not remote OBS composition or lip sync. The mic sample does not establish perceptual noise reduction. No benchmark, latency, drift, or game performance result is claimed.", "",
              "Model the Domain shaped the per-subtest status records. Prove It Works shaped the encode, packet/frame probe, full decode, listener checks, and before/after route comparison.", ""]
    output.with_suffix(".md").write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument("--remote", default="neko7")
    parser.add_argument("--mic-source", default="", help="exact source from pactl; default is observed hardware mic")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/evidence/splitcast-hardware.json")
    args = parser.parse_args()
    def interrupted(signum, frame):
        raise RuntimeError(f"hardware run interrupted by signal {signum}")
    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, interrupted)
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote), "invalid SSH host alias")
    require(args.output.parent.is_dir(), "evidence output directory must exist")
    report = {"schema_version": 1, "started_jst": now(), "package": args.package,
              "scope": "isolated actual hardware evidence; current app acceptance NOT_RUN", "subtests": []}
    tests = report["subtests"]
    with tempfile.TemporaryDirectory(prefix="splitcast-hardware-") as directory:
        s = Session(Path(directory), args.package)
        before = None
        try:
            report["versions"] = {"local_host_is_neko5": os.uname().nodename == "neko5", "local_kernel": os.uname().release,
                                  "ffmpeg": version(s, "ffmpeg", "-version"),
                                  "mediamtx": version(s, "mediamtx", "--version"),
                                  "pulse": version(s, "pulseaudio", "--version"),
                                  "v4l2": version(s, "v4l2-ctl", "--version")}
            try:
                before = routes(s)
                report["routes_before"] = route_summary(before)
            except Exception as exc:
                tests.append({"id": "local_audio_baseline", "status": "BLOCKED", "started_jst": now(),
                              "reason": s.safe(exc)})
            report["setup_commands"] = list(s.commands)
            for task in ("remote_inventory", "remote_nvenc"):
                tests.append(check(s, task, lambda task=task: remote(args.package, args.remote, task)))
                if tests[-1]["status"] == "PASS":
                    tests[-1]["status"] = tests[-1]["observed"]["status"]
            devices = sorted(Path("/dev/v4l/by-id").glob("*video-index0"))
            if not devices:
                tests.append({"id": "local_camera", "status": "BLOCKED", "reason": "no stable by-id camera detected", "started_jst": now()})
            for i, device in enumerate(devices):
                tests.append(check(s, f"local_camera_{i + 1}", lambda device=device: camera(s, device)))
            tests.append(check(s, "raw_mic_remote_rnnoise", lambda: mic(s, before, args.package, args.remote, args.mic_source)))
            if tests[-1]["status"] == "PASS":
                tests[-1]["status"] = tests[-1]["observed"]["remote"]["status"]
            tests.append(check(s, "remote_voicevox_local_null_playback", lambda: tts(s, args.package, args.remote)))
            if tests[-1]["status"] == "PASS":
                tests[-1]["status"] = tests[-1]["observed"]["remote"]["status"]
            tests.append(check(s, "game_capture", lambda: game(s)))
            tests.append(check(s, "tailscale_path", lambda: tailscale(s, args.remote)))
            inventory = next((x.get("observed", {}).get("observed", {}) for x in tests if x["id"] == "remote_inventory"), {})
            tests.append({"id": "remote_obs_nvenc", "status": "BLOCKED", "started_jst": now(),
                          "reason": "no isolated Xvfb/display available" if not inventory.get("xvfb_available") else "isolated OBS recording not configured", "commands": []})
            for name, reason in (("real_twitch", "real Twitch excluded by authorization"),
                                 ("long_sync_soak", "10/30 minute acceptance outside short hardware run"),
                                 ("fault_injection", "disruptive faults excluded by authorization"),
                                 ("current_app_acceptance", "app code changes independently; stale closure is used only for runtime binaries")):
                tests.append({"id": name, "status": "NOT_RUN", "reason": reason, "started_jst": now(), "commands": []})
        finally:
            report["cleanup_owned_children"] = s.clean()
            if before is not None:
                start = len(s.commands)
                try:
                    after = routes(s)
                    report["routes_after"] = route_summary(after)
                    before_routes = {x["index"]: x["sink"] for x in before["inputs"]}
                    after_routes = {x["index"]: x["sink"] for x in after["inputs"]}
                    streams_unchanged = all(after_routes[k] == v for k, v in before_routes.items() if k in after_routes)
                    unchanged = before["sink"] == after["sink"] and before["source"] == after["source"] and streams_unchanged
                    tests.append({"id": "preserve_local_audio_routes", "status": "PASS" if unchanged else "FAIL", "started_jst": now(),
                                  "observed": {"default_sink_unchanged": before["sink"] == after["sink"],
                                               "default_source_unchanged": before["source"] == after["source"],
                                               "existing_remaining_stream_routes_unchanged": streams_unchanged,
                                               "naturally_ended_streams": len(set(before_routes) - set(after_routes))},
                                  "commands": s.commands[start:]})
                except Exception as exc:
                    tests.append({"id": "preserve_local_audio_routes", "status": "FAIL", "started_jst": now(),
                                  "reason": s.safe(exc), "commands": s.commands[start:]})
                finally:
                    report["cleanup_owned_children"] = s.clean() and report["cleanup_owned_children"]
            report["finished_jst"] = now()
            require(all(x["status"] in STATUSES for x in tests), "unknown result status")
            write_report(report, args.output)
    for test in tests:
        print(f"{test['status']:8} {test['id']}")
    return 1 if any(x["status"] == "FAIL" for x in tests) else 0


if "REQUEST" in globals():
    worker(REQUEST)
elif __name__ == "__main__":
    sys.exit(main())
