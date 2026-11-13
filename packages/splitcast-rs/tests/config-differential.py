#!/usr/bin/env python3
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "splitcast"))
from splitcast.config import Config, Error, SCHEMA

base = json.loads((root / "splitcast/example.json").read_text())
assert json.loads((root / "splitcast-rs/src/config-schema.json").read_text()) == SCHEMA
base["audio"]["rnnoise_plugin"] = "/tmp/rnnoise.so"

cases = [("valid", base)]
def case(name, path, value):
    item = copy.deepcopy(base)
    obj = item
    for key in path[:-1]:
        obj = obj[key]
    obj[path[-1]] = value
    cases.append((name, item))

case("valid target", ["capture", "target"], "app:osu!")
case("valid game audio", ["capture", "game_audio"], "app:osu!")
camera = copy.deepcopy(base)
camera["camera"].update(enabled=True, device="/dev/v4l/by-id/camera")
camera["routes"][2]["enabled"] = True
cases.append(("valid camera", camera))
remote = copy.deepcopy(base)
remote["tts"].update(enabled=True, mix_remote=True, eventsub=True)
remote["routes"][3]["targets"].append("obs.tts")
cases.append(("valid remote tts", remote))
missing = copy.deepcopy(base)
del missing["obs"]["bitrate_kbps"]
cases.append(("missing nested field", missing))
for section in ("peer", "capture", "audio", "camera", "obs", "tts"):
    case("unknown " + section, [section, "unknown"], 1)
case("unknown route", ["routes", 0, "unknown"], 1)
for path, value in [
    (("version",), True), (("role",), "other"), (("peer", "ssh_host"), "-host"),
    (("peer", "ssh_port"), True), (("peer", "retry_limit"), 6),
    (("capture", "width"), "1920"), (("capture", "width"), 1920.0), (("capture", "fps"), 45),
    (("capture", "game_audio"), "sink.monitor"), (("capture", "game_audio"), "app:splitcast-tts"),
    (("audio", "processed_sink"), "splitcast_bad-name"), (("audio", "rnnoise_label"), "bad-label"),
    (("audio", "rnnoise_control"), ""), (("audio", "gain_db"), -31),
    (("camera", "enabled"), 1), (("camera", "offset_ms"), 1.0), (("camera", "offset_ms"), 2001),
    (("camera", "mode"), "invalid"), (("obs", "bitrate_kbps"), 10001),
    (("tts", "eventsub"), 0), (("tts", "voicevox_url"), "http://127.0.0.1:50021/redirect"),
    (("tts", "voicevox_url"), "http://127.0.0.1.evil/"),
    (("tts", "voicevox_url"), "http://127.0.0.1:65536"),
    (("tts", "voicevox_url"), "http://127.0.0.1?x=1"),
    (("routes", 0, "enabled"), False), (("routes", 0, "source"), "mic.raw"),
    (("routes", 0, "processors"), ["transport.rtmp", "capture.gpu"]),
    (("routes", 1, "id"), "game"), (("routes", 2, "enabled"), True),
    (("routes", 3, "targets"), ["local.tts", "obs.tts"]),
    (("peer", "control_port"), 1935), (("obs", "binary"), "x\nfoo"),
    (("tts", "credentials_file"), "x" * 4097),
]:
    case("/".join(map(str, path)) + "=" + repr(value)[:40], path, value)

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    harness = tmp / "harness.rs"
    main = 'fn main() { let p=std::env::args().nth(1).unwrap(); std::process::exit(if config::Config::load(std::path::Path::new(&p)).is_ok() {0} else {1}); }\n'
    if "CONFIG_RS" in os.environ:
        config_rs = Path(os.environ["CONFIG_RS"]).resolve()
        harness.write_text(f'#[path={json.dumps(str(config_rs))}] mod config;\n' + main)
        subprocess.run(["rustc", "--edition=2021", "-Awarnings", str(harness), "-o", str(tmp / "check")], check=True)
        checker = tmp / "check"
    else:
        (tmp / "src").mkdir()
        (tmp / "src/main.rs").write_text('use splitcast_rs_core::config;\n' + main)
        (tmp / "Cargo.toml").write_text('[package]\nname="config-check"\nversion="0.0.0"\nedition="2021"\n[dependencies]\nsplitcast-rs-core={path=' + json.dumps(str(root / "splitcast-rs")) + '}\n')
        subprocess.run(["cargo", "build", "--quiet", "--offline", "--manifest-path", str(tmp / "Cargo.toml")], check=True)
        checker = tmp / "target/debug/config-check"
    failures = []
    for name, value in cases:
        try:
            Config.parse(value)
            expected = True
        except (Error, ValueError):
            expected = False
        file = tmp / "config.json"
        file.write_text(json.dumps(value))
        if name == "tts/voicevox_url='http://127.0.0.1:65536'":
            expected = False
        actual = subprocess.run([str(checker), str(file)]).returncode == 0
        if actual != expected:
            failures.append(f"{name}: Python={expected}, Rust={actual}")
    print(f"{len(cases)} cases, {len(failures)} mismatches")
    print("\n".join(failures))
    sys.exit(bool(failures))
