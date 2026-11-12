# ADR-2026-11-07: Game-first latency and SplitCast clean-room target

**Status:** Proposed target architecture / **NOT** approved for production cutover or automatic service enablement.
**Scope:** neko5 → neko7; osu!lazer Input, Audio, Update, Draw and remote capture/production.
**Design authority:** new measurements and upstream implementation first. Existing Python SplitCast, Rust stub, historical ADRs and synthetic tests are migration inventory, not proof of optimality.
**Baseline Git revision:** `1c2d78964608fe02086977b4642989def316d004`.

## Invariants (highest priority)

- Preserve exact current native SDL3/Wayland, OpenGL, 1280x720 in-game config, working fullscreen pen mapping and confirmed foreground Direct Scanout. No Vulkan/Zink, Gamescope, mandatory XWayland, game-side GL injection or GameMode wrapper inserted by SplitCast.
- Preserve osu!framework's supported capabilities. Its 1000Hz normal thread targets are software configuration, not a performance ceiling for USB, PCM, GPU, panel, or photon output. Do not impose arbitrary target p99 numbers in lieu of measuring the solo game maximum under controlled conditions.
- A capture crash, network stall, game-audio tap failure or OBS restart must never block, signal, restart, or reschedule osu! itself. Avoid new paid infrastructure. neko7 is remote production, not a game rendering dependency.
- No uncontrolled privileges: do not grant OBS/FFmpeg/full Rust agent `CAP_SYS_ADMIN`, DRM master or host-global firewall relaxations. No external listener without explicit authentication and network policy. Keep patched loopback OBS until isolated stock OBS is security-validated.
- Public streaming requires explicit output authorization; recording or stopping is default-safe. Secrets remain in private files, never in Nix derivations or diagnostics.

## Data plane (ideal, not deployed)

1. **Display game-owned:** GL → SDL3 Wayland buffer → Hyprland direct scanout → i915 DRM/KMS → 1366x768 eDP, 60.003Hz. Game draws and flips do not wait for capture or network.
2. **Acquisition:** minimal privileged broker observes the selected KMS plane and exports only validated DMA-BUF FD(s) over Unix SCM_RIGHTS with a strict allowlist; no raw frame bytes or writable GEM handle exposed to the control plane. KMS capture may be screen-wide; enforce privacy and display change invalidation.
3. **Conversion/encode:** unprivileged Intel iHD/VAAPI worker imports DMA-BUF; explicit fourcc/planes/modifier/stride/synchronization checks; RGB→NV12/VPP only when required; H.264 hardware encode only, no silent software fallback. Dropped old frames are acceptable; queued game frames are not.
4. **Audio:** osu! BASS → PipeWire ALSA → ALC257 native output remains the critical path; a separate exact osu application node monitor captures stream audio without altering default sink or routing. SoloCast mic independently sourced and time-stamped; remote processing and optional TTS/overlay remain on neko7.
5. **Transport:** bounded per-stream queues with monotonic timestamps and epochs, sequence numbers, jitter/loss counters and explicit clock correspondence between hosts. Initially existing authenticated Tailscale/SSH tunnel can be kept **for parity testing**, but TCP head-of-line and double encryption require A/B against a secure UDP solution. Do not assume direct Tailnet routing.
6. **Receiver:** neko7 MediaMTX/receiver manages decapsulation, jitter, stream synchronisation and OBS ingest; RTX4060Ti handles composition and NVENC final output, with explicit recording/Twitch selection. Avoid unnecessary decode/encode stages except those mandated by OBS/composition and measured feasibility.
7. **Supervision:** Rust orchestrator after parity; cgroup v2/systemd owns process descendants, bounded TERM→KILL and fail-safe stop. Control service cannot own DRM capability. Restart only its own services, never the game.

## Shared resources and non-interference

Capture can compete for i915 render/video engines, DRAM, package power, cache, CPU IRQ, USB, Wi-Fi/Tailscale, and PipeWire RT budget even if it never touches the game process. `CPUWeight` is not isolation of these hardware resources. An absolute claim of *zero* performance impact cannot be proved by logic or a single run. Use paired A/B/A measurements, compare tails and confidence bands, and refuse cutover when equivalence cannot be supported. Run capture processes with bounded queues; suspend/degrade/stop them first. Never degrade game quality as an automatic response to capture overload.

## Redundancy and lifecycle

- `Idle` → `Preparing` → `Ready` → `Running` → (`Degraded` | `Stopping`) → `Idle`, with `Failed` and explicit clean retry.
- Every session has a monotonic generation/UUID, owner lease and idempotent stop; unexpected termination must not orphan a capture worker, media socket or remote publication.
- A limited remote reconnect budget is permitted only for control/capture; do not automatically initiate public broadcast after process restart.
- Keep live Python implementation untouched until Rust feature parity tests, device tests and security tests succeed; select Rust cutover only after explicit approval. Rollback = old NixOS generation and old Python unit, both unaffected by the optional audio experiment.

## Rejected shortcuts

- Raise all priorities to SCHED_FIFO, isolate CPU cores or disable C-states globally based only on high temperature; not justified.
- Force permanent 32/48/64-frame PipeWire graph quantum without observed XRUN/p99; not justified.
- Replace KMS capture with a portal path if it invalidates Direct Scanout; not acceptable silently.
- Treat 8/8 sampled scanout as 100% per-frame guarantee; not supported.
- Equate Wacom `bInterval=2` with measured 500Hz report cadence or assume 1000Hz firmware; not supported.
- Treat synthetic SplitCast tests, stale ADRs, unverified stock OBS listener isolation or incomplete Rust lifecycle as production acceptance; prohibited.

## Validation and authorization

See `PRIORITY-2026-11-07.tsv` for ordered work, `EVIDENCE-2026-11-07.tsv` for provenance, `SPLITCAST-AGENT-PORTING-2026-11-07.md` for concrete coding tasks, and `NEKO5-OBSERVED-2026-11-07.md` for baseline. This ADR does not enable any services, change system audio, or approve a live stream.

## Audio evidence amendment: 2026-11-07 15:30

The measured PipeWire ALC257 **driver quantum of 256/48000** proves only the data-loop cycle. `alsa_playback.osu!` advertised follower 441/44100 (~10ms suggested period) while the device node ran 256/48000. HDA hardware parameters collected before focus still showed period_size=1024. Do **not** merge these distinct layers or describe a 16ms physical improvement. Initial pw-top node errors increased 0→12 while becoming active and were then stable during two running rows; no matched control was present. CPU0 package throttle count +4 at 94–98°C requires game-only thermal comparison. **Decision: no permanent PipeWire, ALSA or BASS period change** until software scheduling and physical hitsound paths are both measured. Keep existing 48kHz output and local game audio path as default; do not route it through neko7. See `AUDIO-VALIDATION-2026-11-07.md` and `scripts/osu-performance/audio-compare.py`. BASS micro-period and direct ALSA remain separately gated experiments (possible XRUN/crash/exclusive output).
