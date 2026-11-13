#!/usr/bin/env python3
"""Lightweight coherence check; does not establish scientific or runtime correctness."""
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]/'docs/graphics-streaming'
ARCH=ROOT/'architecture'
FACTS=json.loads((ARCH/'facts-2026-11-07.json').read_text())
HTML=(ARCH/'index.html').read_text()
REPORT=(ARCH/'REPORT-2026-11-07.md').read_text()
EVIDENCE=(ROOT/'EVIDENCE-2026-11-07.tsv').read_text()
PRIORITY=(ROOT/'PRIORITY-2026-11-07.tsv').read_text()
errors=[]
def check(cond,desc):
    if not cond:errors.append(desc)
for name in ['verified','overview','input','audio','update_draw','splitcast','kernel','measured']:
    p=ARCH/(name+'.svg')
    check(p.is_file(),name+'.svg missing')
    if p.is_file():
        try:ET.parse(p)
        except ET.ParseError:errors.append(name+'.svg invalid XML')
for name in ['verified','overview','input','audio','update_draw','splitcast','kernel','measured','decision']:
    check('data-tab="'+name+'"' in HTML, 'missing tab '+name)
check(len(re.findall('class="tab(?: active)?"',HTML))==9, 'wrong tab count')
check('119' not in HTML or HTML.count('class="detail"')==119, 'detail cards count mismatch')
for value in ['8 / 8','95–98','2ms descriptor','1ms descriptor','1024 frames','Direct Scanout']:
    check(value in HTML,'HTML missing '+value)
for value in ['95–98','bInterval=2','8/8','1024','snd_hda_intel']:
    check(value in REPORT,'report missing '+value)
for value in ['E01','E06','E07','E08']:
    check(value in EVIDENCE,'evidence missing '+value)
check('P01' in PRIORITY and 'P05' in PRIORITY,'priority table missing key tasks')
check(FACTS['display']['foreground_direct_scanout_count']==FACTS['display']['sample_count']==8,'sample mismatch')
check(FACTS['input']['wacom']['interrupt_in_binterval_ms']==2,'Wacom interval mismatch')
check(FACTS['audio']['alsa_period_frames']==1024,'audio period mismatch')
check(FACTS['thermals']['throttling_verified'] is False,'throttling incorrectly verified')
latest=FACTS.get('follow_up_2026_11_07_1530',{})
check(latest.get('audio',{}).get('force_quantum_metadata_frames')==256,'follow-up force256 absent')
check(latest.get('audio',{}).get('driver_node',{}).get('active_quantum_frames')==256,'follow-up sink quantum absent')
check(latest.get('thermal',{}).get('delta')==4 and latest.get('thermal',{}).get('thermally_throttled_during_capture') is True,'follow-up throttle mismatch')
for phrase in ['441/44100','12→12','thermal_throttle','256/48000']:
    check(phrase in HTML or phrase in REPORT,'missing latest detail '+phrase)
check((ROOT/'AUDIO-VALIDATION-2026-11-07.md').is_file(),'missing audio validation protocol')
check((Path(__file__).parent/'audio-compare.py').is_file(),'missing audio A/B collector')

print('PASS: ' if not errors else 'FAIL: ', 'asset consistency guards')
for e in errors:print(' -',e)
sys.exit(1 if errors else 0)
