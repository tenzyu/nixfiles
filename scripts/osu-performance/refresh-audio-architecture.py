#!/usr/bin/env python3
"""Idempotently revise existing neko5 architecture HTML and report after the BASS runbook is added.

Uses only Python stdlib and a narrow semantic anchor; preserves all existing diagrams/tabs.
"""
from pathlib import Path
import os
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / 'docs/graphics-streaming/architecture/index.html'
REPORT = ROOT / 'docs/graphics-streaming/architecture/REPORT-2026-11-07.md'
MARKER = 'tab-bass-next-20261112'
LINK = '../AUDIO-RUNBOOK-2026-11-12.md'

SECTION = '''<section class="tab" id="tab-bass-next-20261112" style="max-width:1160px;margin:0 auto;padding:24px 18px">
<h2 style="font-size:22px">Audio：BASSデバイス周期の再検討 / 2026-11-12</h2>
<p>基準: tenzyu/nixfiles main 9a6125ab75caff3d36de05bbe2ae3bbf81cce953。PipeWire 256 framesへの設定と、BASSの出力周期の変更は独立。</p>
<div class="evidence"><strong>次の候補：osu!lazer BASS 256サンプル周期を別ランチャーで試行</strong><p>通常起動では BASS DevicePeriod は10ms要求。実験環境変数は BASS_CONFIG_DEV_PERIOD=-256（44.1kHzなら5.805ms要求）。BASS_CONFIG_DEV_BUFFER=1ms要求は周期の2倍以上へ丸められる。ドライバが要求を採用したとは限らない。</p></div>
<table class="facts"><thead><tr><th>境界</th><th>コード・仕様</th><th>最適化判断</th></tr></thead><tbody>
<tr><td>Sample start</td><td>SampleChannelBass.Play → AudioComponent.EnqueueAction → AudioThread → BassAudioMixer.ChannelPlay</td><td>Audio Thread待機とミキサー更新周期を混同しない</td></tr>
<tr><td>BASS device period</td><td>AudioManager.InitBass; OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD</td><td>-256を試す。-128/-64は2026年6月のLinuxクラッシュ報告があるため初期試験では採用しない。10月のBASSライブラリ更新後の現状は未確認</td></tr>
<tr><td>PipeWire graph</td><td>ALC257/R/256/48000を既に確認。force-quantum=0でも実効256の例がある</td><td>新しい実験ではPipeWireを恒久的に変更しない</td></tr>
<tr><td>Output hardware</td><td>ALSA HDA PCM → snd_hda_intel → Realtek ALC257</td><td>ALSA hwへの排他切替はSplitCastの音声複製を阻害し得るので採らない</td></tr>
<tr><td>SplitCast</td><td>neko5 game audio local → separate PipeWire monitor → neko7 audio/OBS</td><td>ゲーム音声のデバイス周期と遠隔監視・配信を独立に扱う</td></tr>
</tbody></table>
<p>起動コマンド（ゲーム終了後、nixfilesルートから実行）:</p>
<pre style="white-space:pre-wrap;background:#101722;padding:14px;border:1px solid #30465a;border-radius:8px">bash scripts/osu-performance/bass-period-lab.sh baseline
bash scripts/osu-performance/bass-period-lab.sh -256</pre>
<p>上記は別々のゲームセッションで実行する。音切れやクラッシュが起きたら実験を終了し通常起動へ戻す。実効BASS出力周期を証明するには、上流コードに BASS_GetInfo の minbuf/latency/freq を計装する必要がある。</p>
<p><a href="''' + LINK + '''">最新のAudio手順書</a> / <a href="https://github.com/ppy/osu/discussions/38001">短周期とBASSmixのLinux SIGSEGV報告</a> / <a href="https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_PERIOD.html">BASS公式周期仕様</a></p>
</section>'''


def atomic_write(p: Path, content: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=p.parent, prefix='.audio-revision-', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(content)
        os.replace(tmp, p)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def update_html() -> str:
    original = HTML.read_text(encoding='utf-8')
    if original.count(MARKER) >= 1:
        # It is normal for the marker to occur twice after injection (button + section).
        if 'data-tab="bass-next-20261112"' in original and 'id="tab-bass-next-20261112"' in original:
            return 'already updated'
        raise RuntimeError('Partial Audio HTML update: refusing to duplicate or repair by guess')
    if original.count('</nav>') != 1 or original.count('<div class="foot">') != 1:
        raise RuntimeError('Unexpected HTML structure: no safe injection point')
    button = '<button aria-selected="false" data-tab="bass-next-20261112" type="button">BASS手順 11/12</button>'
    revised = original.replace('</nav>', button + '</nav>', 1)
    revised = revised.replace('<div class="foot">', SECTION + '<div class="foot">', 1)
    # The original single JS event listener enumerates all buttons after DOM construction.
    assert 'querySelectorAll(\'button[data-tab]\')' in revised
    atomic_write(HTML, revised)
    return 'updated'


def update_report() -> str:
    original = REPORT.read_text(encoding='utf-8')
    marker = '## Audio next step (2026-11-12)'
    if marker in original:
        return 'already updated'
    note = '''\n\n## Audio next step (2026-11-12)

`tenzyu/nixfiles` main `9a6125ab75caff3d36de05bbe2ae3bbf81cce953` now contains the PipeWire quantum lab, but not an experimental BASS device-period launcher. See [Audio Runbook](../AUDIO-RUNBOOK-2026-11-12.md) and `scripts/osu-performance/bass-period-lab.sh` (after integration).

The source-driven next lever is `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-256`, not another PipeWire-only quantum reduction. BASS itself requests an output buffer at least 2x its update period. The actual BASS period/minbuf/latency requires a new in-process `Bass.GetInfo` probe; log text reporting the requested period is insufficient. There is a published Linux BASSmix crash regression under some mod operations at short periods (ppy/osu discussion #38001). Do not enable any experimental period globally or automatically. SplitCast game-audio routing and all Input/Update/Draw constraints stay unchanged.
'''
    atomic_write(REPORT, original + note)
    return 'updated'


if __name__ == '__main__':
    try:
        print('HTML:', update_html())
        print('REPORT:', update_report())
    except (OSError, RuntimeError, AssertionError) as error:
        print(f'FAILED: {error}', file=sys.stderr)
        sys.exit(1)
