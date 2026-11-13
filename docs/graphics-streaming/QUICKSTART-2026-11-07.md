# Follow-up operation: one-liner and rollback

No changes are automatically applied. The patch only adds documentation, bounded read-only capture script, and an **opt-in** PipeWire experiment command to the enabled osu-lazer Home Manager feature.

## Apply on known main

```
git rev-parse HEAD
# Expected 1c2d78964608fe02086977b4642989def316d004; stop and rebase if different.
git status --short
git apply --check path/to/neko5-game-first-20261107.patch
git apply path/to/neko5-game-first-20261107.patch
nix flake check --no-build
nh os build
```

The overlay does not enable SplitCast, change kernel parameters, rewire game audio or modify fullscreen. Do not run `nh os switch` until manually reviewed. Home Manager opt-in command is available after the configuration is applied by the user.

## Audio profiling while game is already running

```
osu-audio-quantum-lab status
osu-audio-quantum-lab run 256 -- sleep 180
osu-audio-quantum-lab status   # in another shell to see forced quantum
# On completion the wrapper restores graph force to 0.
osu-audio-quantum-lab restore  # only after an unexpected crash/killed session
```

Compare 256, then 128 or 64 only if the previous condition is stable. Running the experiment affects other PipeWire clients and could produce XRUNs. No change to osu!lazer's own BASS sample/period setting is made. The wrapper refuses when another force-quantum value is already set.

## When more measurements are needed

```
bash scripts/osu-performance/collect-active.sh
```

Wait for the 8-second countdown, focus osu!, remain there while 12 samples run. Output directory is printed. It records **only read-only** snapshots; it is not a frame-time or XRUN benchmark. The more demanding `scripts/splitcast/perf.py` intentionally requires an explicit 600-second comparable workload and external frame CSV. Do not claim a latency improvement from this snapshot collector.

## Reversal

```
osu-audio-quantum-lab restore
# Before `git apply`, check that the patch matches the intended HEAD.
git apply -R --check path/to/neko5-game-first-20261107.patch
git apply -R path/to/neko5-game-first-20261107.patch
```

The patch writes only repository source files. It does not auto-commit, push, publish or deploy. Changing a NixOS/Home Manager generation requires the user's separate action. The active Rust port remains inactive until all porting and acceptance gates pass.

## Audio causality test (new, 2026-11-07 15:30)

With osu! open, from repo root:

```bash
nix shell nixpkgs#pipewire nixpkgs#python3 --command python3 scripts/osu-performance/audio-compare.py
```

The program waits 8 seconds for focus, performs **0 → 256 → 0 → 256** (each 50 seconds, plus 4-second warmups), saves timestamped pw-top/ALSA/thermal/activewindow observations, and restores `clock.force-quantum=0` on ordinary completion, SIGINT or SIGTERM. It also stops the measurement (not osu!) if the observed package temperature reaches 99°C; Intel specifies Tjunction=100°C for the i5-10210U. It refuses to run when another process holds the audio-lab lock or the graph is already forced. A SIGKILL/power loss requires manual status + restore. It does not change osu!lazer or activate SplitCast. Use the *same beatmap/skin/audio volume*, preferably repeatable autoplay/replay for comparable load; mixed workload intervals do not prove a causal improvement. Actual click-to-hitsound delay requires a separate acoustic or instrumented game-level test. See `AUDIO-VALIDATION-2026-11-07.md`.

Optional acoustic capture uses `--record-mic` to capture private SoloCast audio files during every block. Position the microphone to pick up both the physical keypad click and the headphone/speaker sound; check that both events are distinguishable **before interpreting any millisecond differences**. The recording can contain speech and surroundings; review locally before uploading. Physical switch contact precedes/follows acoustic click by an unknown amount, so this is **relative acoustic timing**, not true electrical switch-to-ear latency.
