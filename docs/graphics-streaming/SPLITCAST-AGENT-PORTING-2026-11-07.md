# Agent-executable SplitCast rewrite / port contract

Status: **proposed implementation work**. User demands an ideal design independent of current ADR/code completeness. This is the task contract for a coding agent, not a claim of deployed parity.

## Read before writing

- Baseline `main` SHA: `1c2d78964608fe02086977b4642989def316d004`.
- Authoritative runtime evidence: `NEKO5-OBSERVED-2026-11-07.md` and its referenced latest user archive. Ignore same-named pre-2026-11-07 Library files.
- Upstream source for game input and audio: `osu.Framework/Input/InputManager.cs`, `Platform/SDL3/SDL3Window.Input.cs`, `Input/Handlers/Tablet/OpenTabletDriverHandler.cs`, `Audio/AudioManager.cs`, `Threading/GameThread.cs`, `Platform/GameHost.cs`. Linux: `drivers/hid/usbhid/hid-core.c`, `drivers/input/evdev.c`, `sound/pci/hda/hda_intel.c`, DRM/KMS/dma-buf/i915 and PipeWire documentation. Do not infer runtime values from source defaults when observed hw_params contradict them.
- Migration inventory only: `packages/splitcast/splitcast/{config.py,media.py,server.py,...}`, `packages/splitcast-rs/src/{lib.rs,main.rs}`, `modules/50-features/splitcast/_internal/{nixos.nix,home-manager.nix,obs.nix}`, `scripts/splitcast/{verify.py,perf.py}`, old RFC/ADR and synthetic test logs.

## Fixed contracts before implementation

1. `Game` is an external read-only dependency. No launch/restart/capture hook injected into osu!, its Draw or Audio thread, and no change to local ALC257 sink or OTD mapping.
2. `CaptureBackend` trait permits `probe`, `prepare`, `capture_next`, `stop` with bounded acquisition deadlines, selected connector identity, format/modifier contracts, and a way to distinguish **no frame** from **fatal capture**. Implement GSR-backed baseline first; privileged KMS custom path only as independently validated variant. No automatically enabled capture service.
3. `AudioTap` selects only the exact game application stream (not default sink monitor) and separately captures physical SoloCast mic. No game output reroute. Source disappearance is an explicit degradable error; clock source and sample timestamps are logged in monotonic units.
4. `Encoder` accepts DMA-BUF/frames with explicit color space, stride/modifiers, fences, and a bounded queue, reports hardware encoder used and drop reason. No software fallback; config validation fails if H.264 VAAPI/iHD unavailable.
5. `Transport` owns a bounded network queue, independent audio/video packetization, timestamps, loss/RTT/jitter counters, explicit authenticated session, and no backpressure onto game/display. Compare SSH/RTSP/TCP baseline against authenticated UDP only in a security-reviewed test.
6. `Production` receives on neko7, synchronizes AV, manages OBS scene/source state, exact external interface binding and Twitch opt-in; NVENC availability measured, not assumed.
7. `ControlPlane` state machine in Rust with explicit generation token and idempotent stop, no GPU admin privileges, private credential files, stable API schema and strict unknown-key rejection.
8. `ProcessOwner` uses systemd transient scopes or cgroup v2, verifies process descendants are gone, cleans pipes, sockets, DMA-BUF FDs, file locks and GPU resources on failure. Process-group kill alone is insufficient.

## File-by-file migration order and acceptance gates

| Step | Current artifact to inspect | Target module / change | Required test (all fail closed) |
|---|---|---|---|
| 01 | `packages/splitcast/splitcast/config.py`, `example.json` | Rust typed config, versioned schema, validation | Valid/invalid corpus parity; no arbitrary command injection, secret exposure |
| 02 | Python session agent/controller | Rust `session`, `process_owner`, `api` | repeated start/stop, lease takeover, crash injection, no orphaned descendants |
| 03 | Python GSR/FFmpeg capture commands | Rust `capture_backend` + metadata contract | codec/profile discovery, privilege denial, known-good DSO, no game launch change |
| 04 | Python app audio/physical mic routing | Rust `audio_tap`, `clock` | no default sink movement, game-only stream verified, mic on separate path, no loopback TTS |
| 05 | Python SSH/MediaMTX | Rust `transport` + `receiver` | bounded queue/memory, reconnect/drop/dup/reorder tests, encrypted link, no unsafe listener |
| 06 | Python OBS/overlay/VOICEVOX/Twitch | Rust production integrations or wrappers | OBS loopback/firewall probe, NVENC capture, public start explicit, stop outputs on lease expiry |
| 07 | `scripts/splitcast/verify.py`, Python unit suites | Rust integration suites and hardware A/B/A | negative cases, recovery, secret leakage, no user-observed osu regression |
| 08 | Existing HM/systemd modules | opt-in Rust service behind explicit feature switch | `nix flake check`, host builds, `git apply --check`, rollback and backout verified |

Do not delete Python files or switch `splitcast-capture.enable` from false until 1–8 are passed. For old Python functionality not yet implemented in Rust, report unsupported and refuse to launch rather than silently ignoring the requested feature.

## Capture → game invariant gate

Baseline **solo game** under matching replay, mods, skin, compositor state, audio device and temperature regime; then A/B/A with capture and game. Record Input queue latency, audio XRUN/hitsound onset, Update/Draw frame-time p50/p95/p99/p99.9, `directScanoutTo` sampled while osu is foreground, GPU Render/Video engine use, CPU thermals/RAPL/thermal throttle, Wi-Fi and Tailscale peer route. A baseline with different thermal state is not a valid comparator. No arbitrary p99 tolerance is adopted by this document; apply statistical non-inferiority only with an explicitly justified bound accepted by user. Any established functional regression or inability to measure a safety-critical dimension blocks production promotion.

## Output of each agent iteration

1. Code + isolated test files + failure-injection output.
2. Machine-readable evidence record naming actual `main` SHA, source versions, machine role, runtime state, measurement clock, sample counts and unknowns.
3. Diff of proposed behavior against Python, distinguishing verified parity and intentional design change.
4. Single `git diff` / patch and test logs; no production switching, irreversible permission changes or live streaming without approval.
5. Updated HTML architecture, SVG layers, report, ADR, priority TSV and evidence TSV. **Never publish an appendix while leaving the canonical asset stale.**
