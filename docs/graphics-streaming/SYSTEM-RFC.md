# Next-generation capture/stream architecture (proposal)

Updated for `tenzyu/nixfiles` `main` `d373e872031eb6c4a9839d1ef234ae803647ff9d`, 2026-11-06. Approved choices and incomplete implementation stages are tracked in [DECISIONS-2026-11-06.md](DECISIONS-2026-11-06.md).

This is a **design and measurement specification, not an implemented SplitCast replacement**. Hardware acceptance is pending. Do not enable SplitCast services, patch the kernel, delete the existing OBS security patch, or change the proven osu! graphics and input state from this document alone.

Source-of-truth for prior implementation-level findings: [RESEARCH-2026-11-05.md](RESEARCH-2026-11-05.md). Current production/testing code lives under `packages/splitcast`, `modules/50-features/splitcast` and `scripts/splitcast`. Historical acceptance evidence belongs under `docs/evidence`.

## Non-negotiable game invariant

- Native SDL3/Wayland, OpenGL, osu! configured for 1280×720 fullscreen, tablet input via in-process OTD. No Vulkan, Zink, forced XWayland or Gamescope workaround.
- User-observed known-good fullscreen: press Hyprland `Win+F` (`internal=2`, `client=0`), obtain desired input mapping and observed Direct Scanout. Automating this at window map is a *separate unverified change*.
- Failure of media transport, KMS capture, or remote OBS must not kill or block osu!. No extra monthly paid infrastructure.
- Avoid CAP_SYS_ADMIN on OBS, entire FFmpeg, shells or Rust agent; restrict KMS capture privileges to the existing helper or a narrowly-audited replacement.

## Change state (as of refreshed main)

| Topic | Actual main | Intended / still unresolved |
|---|---|---|
| osu launcher | Direct script with `osu-lazer`/`osu-lazer-raw` symlinks | Retain; do not duplicate |
| Hyprland osu rule | One `immediate=true` match | Static `fullscreen_state = "2 0"` chosen and added; launch-time success still unverified |
| OTD | `hardware.opentabletdriver.enable = true` | Daemon disable confirmed; `daemon.enable=false` added by this patch |
| Local OBS | obs-vkcapture installed and enabled | obs-vkcapture removed from managed local OBS; no automatic GL hook |
| Remote OBS | patched OBS websocket listens only on loopback | Stock candidate added alongside disabled firewall gate; switch only after verified external isolation |
| SplitCast implementation | Python control/agent, GSR, SSH/MediaMTX, FFmpeg, OBS | Full Rust migration selected; inactive Rust core introduced, Python stays authoritative pending parity |
| SplitCast capture on neko5 | both NixOS and HM feature disabled | Keep disabled until hardware acceptance |

## Capture implementation and zero-copy

### Why this can be efficient

On a documented GSR-derived source lineage (`antonlobanovskiy/gpu-screen-recorder`), `src/capture/kms.c` imports KMS DMA-BUF objects as EGL images / GL textures, `src/color_conversion.c` converts RGB into NV12/P010 in GPU shaders, and `src/encoder/video/vaapi.c` exports VA encode surfaces as DRM_PRIME_2 objects and binds them through EGL. CPU pixel readback is avoided in this design. This is not a proof of zero GPU copies, nor does it prove exactly how user's installed GSR 5.13.8 was built.

RGB scanout is not generally compatible with directly encoding to H.264's typical 4:2:0 format. Format/memory-layout conversions and synchronization may remain even if both sides use DMA-BUF. VA-API input surfaces, DRM format modifiers, i915 tiling/compression and layout compatibility matter. Optimizing `memcpy` out of the CPU path does not remove memory bandwidth use.

### Candidate matrix

| Candidate | Advantages | Reasons not to choose as default |
| --- | --- | --- |
| GSR KMS + VAAPI | Existing tool, no game hook, possible Direct Scanout coexistence, hardware encode | Privileged KMS helper, screen-wide capture/privacy, GPU shader conversion, no actual DS/framerate proof yet |
| Custom KMS → VAAPI with constrained helper (`libdrmtap` inspiration) | Control over plane selection, explicit DMA-BUF fd ownership and synchronization | Kernel DRM privilege boundary, device-specific modifiers, substantial implementation/testing obligation; optimized claim unproven |
| FFmpeg `kmsgrab → hwmap=derive_device=vaapi → scale_vaapi → h264_vaapi` | Smaller stack, potential direct VA-API/VPP path without GSR OpenGL shaders; documented by FFmpeg | DRM master or CAP_SYS_ADMIN required for ordinary FFmpeg process (unacceptable without a restricted privilege boundary); modifier/device support and performance not validated |
| wl-screenrec DMA-BUF + VAAPI | Efficient CPU use, modern capture protocols | Hyprland screencopy/screenshare path can block DS even though pixels stay on GPU |
| obs-vkcapture OpenGL hook | Game-only capture, can avoid portal and compositor capture | Existing SIGSEGV in user's EGL export path; injection into game crash domain; must forbid internal Vulkan fallback |
| OBS PipeWire Portal | Widely supported, manageable permissions | Known Hyprland DS screen-sharing block; ordinary path uses compositor cooperation |
| `obs-kmscap` plugin | Hardware framebuffer in OBS | Some implementations require CAP_SYS_ADMIN on full OBS binary, unacceptable privilege expansion; performance impact on neko5 if local OBS runs |
| Remote raw pixels | No local encode | Tens to hundreds of MB/s; WAN/network and CPU/network overhead are unacceptable candidates without exceptional network evidence |
| Separate virtual display/DRM driver | Interesting for headless sources | Doesn't solve capturing the *physical* osu! display without changing user-visible compositor or introducing kernel modules |

### Zero-copy terminology

Z0: no full-frame round-trip GPU→host RAM→GPU.
Z1: DMA-BUF fd reuse without an extra CPU copy.
Z2: no shader blit, color conversion, or GPU-side memory write before encode.
Z3: no GPU synchronization or encoder work (physically impossible if capturing/encoding).

**Target Z0/Z1**. Do not claim Z2 without instrumentation proving identical source/output layout and hardware encoder acceptance. Z3 is not a target.

### Safety and privacy

KMS framebuffer access generally requires DRM master or CAP_SYS_ADMIN for buffer handles; use narrow capability/polkit helper processes, never grant CAP_SYS_ADMIN to OBS, the entire agent, or user shells. The helper should enumerate only selected active DRM output, export minimal fds, validate request dimensions, use SCM_RIGHTS, drop privileges and close handles. DRM/KMS capture is monitor-wide, not game-only. Treat screen privacy and high-power capabilities as first-class admission criteria.

The stock OBS 28+ already includes obs-websocket. In existing SplitCast the custom patch changes the WebSocket `listen` to `127.0.0.1` because stock websocket can bind a wildcard address. We do not replace this security property with a password alone. The lab uses no OBS websocket; production must restrict ingress at least via verified firewall/namespaces plus strong authentication, or retain the patch until there is an equivalent safety mechanism. On a trusted Tailscale interface, firewall rules may intentionally bypass other restrictions; verify external reachability.

### Network and codec policy

Initial test: H.264 60fps, 12 Mbps constant bitrate, 1-second keyframe interval, GSR hard-fails if hardware encoding unavailable. RTMP over SSH local forward to a loopback-only MediaMTX, read on neko7 over RTSP/TCP; OBS is a *consumer*, not a game capture client. `--keyint 1` targets ~1-second GOP, not low-latency glass-to-glass proof.

Post-validation: compare direct Tailscale media transport, RTP/UDP or SRT against SSH/TCP. SSH over Tailscale may encrypt twice and TCP retransmissions can induce jitter/head-of-line blocking. Any direct listener requires explicit firewall, address binding and auth policy. Test retransmission and jitter under real RTT/loss; avoid inventing network performance.

### Acceptance gates

G0 (safety): no OS/WM/game state mutation or privileges expanded; no new external listener; crash cannot propagate to osu! process.
G1 (display): existing player fullscreen state preserved; pre-capture sampled DS≥90%, smoke capture sampled DS≥95%; promote to stable pipeline only after long-run A/B/A testing with DS≥99% during established fullscreen and no persistent RECORD/CANDIDATE/TRANSFORM failures. Thresholds are proposed requirements, **not measured facts**.
G2 (graphics): collect game frametime p50/p95/p99 and render update rates in three repetitions per state, warm cache/temperature. Suggested evaluation threshold: capture p99 increase ≤max(5% of baseline, 0.5ms) *only as a provisional design target*; user decides acceptability.
G3 (capture): stream has H264 hardware encoder; no CPU fallback; 60 fps and A/V sync. Probe stream continuity and encoder surface queue pressure, not just successful processes.
G4 (resources): observe `intel_gpu_top` Render/3D and Video engines separately; CPU usage normalized to one logical core, RSS, shared memory, memory bandwidth if instrumentable, network throughput, thermal throttling and governor; reject relying on CPU % alone.
G5 (operations): remote exit/disconnect, duplicate start, loss/recovery, process stop, permissions, secret paths, owner lease, no orphan child, and rollback to game-only operation.

### Decisions deferred to further ADRs

- Fast path behind a `CaptureBackend` interface: existing GSR vs self-written restricted KMS-to-VAAPI, on **identical real hardware tests**.
- Transport under Tailscale with encryption and adequate NAT / firewall policies, after measured TCP vs UDP/SRT behavior.
- OBS dedicated headless profile vs GStreamer/libavfilter remote composition; stock OBS is default because plugin and automation ecosystem reduces redevelopment cost.
- Compositor-copy path as fallback when DS is not feasible (opt-in, never silently enabled).

### Primary evidence

1. GSR upstream https://git.dec05eba.com/gpu-screen-recorder/about/
2. Example code lineage (not identical version proof) https://github.com/antonlobanovskiy/gpu-screen-recorder/blob/master/src/capture/kms.c and src/encoder/video/vaapi.c and src/color_conversion.c
3. Kernel DRM GETFB2 privilege and DMA-BUF export https://www.kernel.org/doc/html/latest/gpu/drm-uapi.html
4. Hyprland scanout code https://github.com/hyprwm/Hyprland/blob/main/src/output/Monitor.cpp
5. GSR CLI flags https://man.archlinux.org/man/gpu-screen-recorder.1.en
6. wl-screenrec source and independent benchmark (author's data, not neko5) https://github.com/rosalyntg/wl-screenrec
7. MediaMTX https://mediamtx.org/docs/features/configuration and https://mediamtx.org/docs/publish/ffmpeg
8. OBS websocket built in https://obsproject.com/kb/remote-control-guide
9. Existing SplitCast patched OBS `modules/50-features/splitcast/_internal/obs-websocket-loopback.patch` and game/media.py, in https://github.com/tenzyu/nixfiles

10. FFmpeg `kmsgrab` with VAAPI mapping/VPP https://ffmpeg.org/ffmpeg-devices.html#kmsgrab
11. Kernel DMA-BUF synchronization and dma_fence contracts https://www.kernel.org/doc/html/latest/driver-api/dma-buf.html

## Kernel, drivers and graphics-userland boundary

### Layers and decisions

| Layer | Current/likely | Mechanism | Probe | Current decision |
|---|---|---|---|---|
| USB HID/input | xHCI, hidraw/libusb, in-game OTD | USB interrupt endpoint, HID reports, udev access | lsusb -t, device power/control, report timestamps | Keep driver; only per-device autosuspend if observed |
| CPU firmware/driver | Intel microcode, intel_pstate HWP | Turbo/EPP adjusts frequency at power/thermal cost | cpufreq sysfs, turbostat, thermal data | Preserve performance governor, measure EPP first |
| CPU scheduler/IRQ | Linux EEVDF/CFS lineage, irqbalance, PREEMPT_DYNAMIC | runnable delays, wakeup and IRQ placement | perf sched timehist, /proc/interrupts | No blanket isolcpus/nohz_full or RT |
| GPU kernel | i915 DRM GEM, engine scheduling | GPU command submission, preemption and RPS, thermal/power budget | sysfs i915 params, debugfs, intel_gpu_top, journal | i915; no forced xe/GuC submission |
| GPU firmware | GuC/HuC/DMC | HuC authenticates media firmware, GuC scheduling on supported generations | i915 parameters and log | Test HuC support, never assume speedup |
| Display driver | KMS planes, atomic modeset | FB/modifier/scanout eligibility, fences | hyprctl + drm inspection in privileged diagnostic | Keep known DS success |
| GL userspace | Mesa Iris/GLVND/EGL | shader driver and GL swap, allocation | GL renderer/version, library maps | Maintain OpenGL; no Vulkan substitutions |
| Interop | DRM PRIME, DMA-BUF, dma_fence, libva | Cross-API FD buffer share with implicit/explicit fences | modifier capability, VAAPI profile, perf waits | Minimize copies and blocking waits |
| Capture | GSR KMS helper | reads KMS plane, wraps/imports buffer | DS pre/during, GSR log, GPU engines | Baseline, not assumed zero-copy |
| Encode | Intel media-driver iHD VA-API | GPU VPP RGB→NV12, fixed-function H264 | vainfo, encoder low_power options, video engine | H264 hardware, no CPU fallback |
| Transport | Tailscale/MediaMTX | encrypted direct/relay route; TCP/UDP HOL vs loss | tailscale ping, bitrate/jitter, dropped frames | Start existing, A/B transport separately |
| Production | neko7 OBS + NVENC | decode, texture upload/compositing, encode | OBS stats, NVML, ffprobe | Keep native OBS, remove custom patch only with security equivalent |
| Control | Rust Tokio/systemd | state machine, process ownership, auth, metrics | child counts, memory, CPU, failure injection | Rust for new agent; no reimplementation of codec |

### Source-of-truth details

1. The NixOS repo's `neko5` enables `kernel-latest`, Intel graphics, desktop-performance, internal OTD; the SplitCast capture feature on GitHub main is disabled. The performance module already configures governor `performance`, thermald, and LZ4 zram. The Intel module installs `intel-media-driver` and sets `LIBVA_DRIVER_NAME=iHD`. No evidence that a live machine has switched to those exact configs.
2. `i915.enable_guc` is platform-dependent. Current Linux source defaults pre-gen12 to 0 and declares unsupported feature bits; Intel GuC submission work targets gen11+. Comet Lake is gen9.5: avoid ungrounded `enable_guc=3` as generic optimization. Verify actual firmware and VAAPI profile; HuC-only can be separately explored if supported.
3. KMS framebuffer access (`DRM_IOCTL_MODE_GETFB2`) exposes GEM handles only to DRM master or CAP_SYS_ADMIN. Do not give a whole Rust service/OBS/FFmpeg this privilege. Reuse a narrow helper with explicit FD passing and no persistent client access when possible. Security should be integral to the performance architecture.
4. DMA-BUF passing avoids userspace pixel copies but not GPU shader/VPP work or synchronisation. A `dma_resv` fence can cause capture/encode to wait or indirectly cause buffering; probe both engines and frame-times.
5. Most video codecs consume YUV 4:2:0 surfaces (e.g., NV12), while the game/display path is commonly RGB(A). A conversion/resizing stage is normal, even with zero CPU readback. Directly importing the KMS RGB framebuffer into the final H264 encoder without conversion is not generally possible.
6. 'Direct Scanout is active' says compositor composition was bypassed, not that capture did not compete for GPU memory bandwidth or extend the game frame time.
7. A 1366x768 RGBA buffer at 60fps is 251,781,120 bytes/s; the corresponding NV12 1.5B/pixel is 94,417,920 bytes/s. A single additional full-frame copy is material on UMA GPUs, but these totals alone do not indicate actual bus traffic or compression/cache effects.

### Experiment and rollback

Phase 0 inventory: run `snapshot.sh`, inspect active kernel generation, i915, VAAPI, CPU frequency, thermal, GSR version and display model.

Phase 1 DS baseline: run `ds_watch.py` under proven osu configuration. Do not re-test the already known input mapping as a prerequisite; record its unchanged state.

Phase 2 GSR KMS: separate recorder, 60fps H264 hardware. Keep game input/graphics constant. Compare A/B/A in at least three blocks with similar game load. No console screenshots during the steady-state sample. Observe Direct Scanout and game frame-times using an appropriate source; record GPU Video/Render engine and thermal throttling.

Phase 3 within-user-space: try one variable per run, e.g. VAAPI `h264_vaapi` low-power encoder if `vainfo` reports `VAEntrypointEncSliceLP`, different output queue depth or CBR, capture resolution and frame rate. Confirm no CPU fallback. Roll back by stopping the recorder and restarting it with the previous args.

Phase 4 kernel-only if evidence shows scheduling/firmware bottleneck: test `preempt=full` only if CONFIG_PREEMPT_DYNAMIC and latency traces warrant it; test `intel_pstate` EPP (without change to governor); experimental i915 params only on a separate boot generation with physical rollback. No permanent `isolcpus`, RT kernel, force_probe xe, global USB autosuspend off, irqbalance disable, or CAP_SYS_ADMIN added to media process without clear evidence.

Phase 5 alternative KMS→VAAPI VPP: privileged KMS broker + restricted VAAPI worker, benchmark against GSR. FFmpeg kmsgrab `hwmap=derive_device=vaapi,scale_vaapi` is a reference pipeline, not a ready unprivileged deployment. No production switch until security and real hardware validated.

Phase 6 Rust control agent: replace Python orchestration only after full behavioral regression suite, fault injection, and verified no regression in capture/data plane. Preserve test intent, secret handling, lease ownership, and failure recovery.

Acceptance goals (not measured): stable DS (initially ≥99% of bounded stable-state samples, with unknown samples counted as failures), game frametime p99 degradation ≤ max(5% baseline, 0.5ms), no game crashes, zero software-encoder fallback, bounded capture buffers, no orphaned child services, and no loss of saved session configuration. A test run is not a proof of zero-copy.

Sources:
- https://www.kernel.org/doc/html/latest/gpu/drm-kms.html
- https://www.kernel.org/doc/html/latest/gpu/drm-uapi.html
- https://www.kernel.org/doc/html/latest/driver-api/dma-buf.html
- https://www.kernel.org/doc/html/latest/admin-guide/pm/intel_pstate.html
- https://www.kernel.org/doc/html/latest/scheduler/sched-preemption.html
- https://www.kernel.org/doc/html/latest/admin-guide/cpu-isolation.html
- https://www.kernel.org/doc/html/latest/driver-api/usb/power-management.html
- https://www.kernel.org/doc/html/latest/hid/hidraw.html
- https://github.com/intel/media-driver
- https://www.ffmpeg.org/ffmpeg-devices.html
- https://gstreamer.freedesktop.org/documentation/va/vapostproc.html
- https://gstreamer.freedesktop.org/documentation/va/vah264enc.html
- https://gstreamer.freedesktop.org/documentation/coreelements/queue.html
- https://gstreamer.freedesktop.org/documentation/rust/stable/latest/docs/gstreamer/
- https://docs.rs/tokio/latest/tokio/process/
- https://tailscale.com/docs/reference/connection-types

## Distributed production

### Domain model / ownership

- `GameRenderer`: existing osu! process. Not managed or restarted by streaming software. Never inject or replace its OpenGL context.
- `CaptureSession`: a single bounded process group per monitor; uses stable monitor identity (DRM connector), checks its mode, privileges and accepted backend. Its state may change independent of the game.
- `VideoEncodeSession`: owns hardware codec, frame pacing, bitrate, encoder queues, and timestamps. No unconditional fallback to libx264.
- `MediaTransport`: authenticated transport to a receiver; owns reconnect budget, buffer limits, backpressure and timing/sequence counters.
- `MediaIngress` (neko7): explicit ingest endpoint (MediaMTX), mux/demux but no unnecessary transcoding.
- `AudioIngress`: gameplay application audio, physical mic and optional camera with independent timestamps and source identity. Do not capture a mixed output that reintroduces TTS.
- `AudioProcessor`: only on neko7; RNNoise, filtering, limiter; preserve local gameplay audio and keep sidetone monitoring out of feedback loop.
- `ProductionGraph`: stock OBS with FFmpeg media input, mic, camera, overlays, NVENC final output, Twitch recording. Video decode and final encode are expected, not accidental extra hops.
- `ControlPlane`: API to coordinate session state and authorization. Has no raw GPU access.
- `HealthObserver`: reads signals from each boundary (DS, dropped frames, encoder errors, bytes, A/V offset, process lifetime); never infers stream health from process existence alone.

### Dataflow

Game display: osu GL → SDL3 native Wayland → Hyprland → physical DRM plane (leave untouched).
Capture: KMS plane metadata → narrowly privileged helper exports DMA-BUF fd(s) → GPU import/detile/scale if needed → color convert (RGBA to NV12) → VAAPI H.264 → mux → encrypted interhost link.
Receive: MediaMTX loopback ingress → OBS FFmpeg input → decoder (prefer hw decode where reliable) → GPU composition with overlay + camera → NVENC H.264 → Twitch / record. OBS FFmpeg source is NOT a second game capture or a GPU readback on neko5.
Audio: osu's application output continues to local headphone sink; separately selected application audio goes to stream. mic captured raw and packetized independently, processed remotely; apply per-stream audio sync offsets only after drift/clock test.

### Control and lifecycle

1. `Idle`: no capture, no leaked port/tunnel. Game unaffected.
2. `Preflight`: check stable connector, codec, privileged helper, direct scanout status, remote receiver readiness. No game process mutation.
3. `Prepared`: remote media ingress, tunnels and production graph ready; control credentials validated; capture not yet streaming.
4. `Running`: capture starts; confirm bytes + valid decoded video + DS stable. Observe codec, frame counters and A/V skew.
5. `Degraded`: if capture fails, stop capture; do not stop osu. If remote disconnects, terminate bounded resource owner and retain idempotent `stop`; optional attempt budget.
6. `Stopped`: terminate children owned by session, close FDs and tunnels, verify receiver path absence, reset counters; keep control API accessible.

All transitions use a session UUID, generation/counter epoch, monotonic clocks, timeouts and idempotent commands. Separate privileged helper with explicit SCM_RIGHTS fd transfer from the unprivileged control agent; never give OBS or the web UI KMS privileges.

### Buffering and backpressure

The game can render arbitrarily fast relative to the capture sampling cadence. The stream requires only <=60 captured frames/s; sample the latest valid frame rather than stalling the game or accumulating an unbounded queue. Queue depth 1-2 is an experiment candidate, **not an established latency optimum**. Timestamp frames at acquisition/presentation boundaries using monotonic timestamps; translate clock epochs between hosts using measured clock skew, never compare raw host-local monotonic values. Avoid carrying a frame across resolution/mode change without revalidating format and modifier.

Capture must be downstream of the game: loss or congestion drops the stream frames, not the display frames. Rate control has bounded VBR/CBR experiment, test bitrate ceiling vs tail latency. Do not assume B-frames enabled or disabled by a generic `-tune` flag; inspect codec extradata and encoder settings.

### Zero-copy acceptance architecture

Track fd lineage across KMS GETFB2 → PRIME export → EGLImage import → encoder surface. Log (in a debug-only privileged channel) DRM fourcc and modifier, plane count, strides, offsets, framebuffer/present timestamps, and whether an additional RGB→NV12 draw or blit occurred. Never log raw pixel bytes or sensitive fd handles into the control API.

A whole-pipeline "zero copy" claim is invalid unless there is no CPU round-trip AND the per-frame GPU stages are explained. On Intel, the encoder consumes its own surfaces, which commonly means drawing/writing NV12 Y/UV planes even if the capture source is a shared DMA-BUF. Optimize memory traffic and GPU work **with measurement**, not with labels.

### Why not immediately rewrite GSR?

A C/Rust rewrite becomes justified only when the prototype demonstrates a concrete bottleneck with evidence: e.g., GSR's OpenGL color conversion consumes excessive Render-engine time, or KMS polling/sync increases game p99. Alternatives could implement VA-API video processing/VPP, modifiers-aware direct import, and constrained KMS helper, but each has high crash/driver/security risk. `libdrmtap` is a research candidate, not a verified drop-in replacement.

### Why not custom OBS?

OBS has reliable scene graph, plugins, browser-source ecosystem and NVENC. Offloaded on neko7, OBS's local per-frame overhead matters much less than on neko5. The existing SplitCast OBS patch changes only the websocket network listen address to loopback. Maintain that security invariant via stock OBS with strong authentication and host firewall, verified in the actual tailscale/proxmox network namespace; otherwise retain the patch until a proven replacement. A dedicated OBS profile/data directory and native systemd service can isolate configuration and lifecycle without forking OBS.

### Separate control vs media plane

- Control: authenticated, rate-limited API with explicit owner leases/command IDs and ACL, no public token retrieval or argv/env secrets.
- Media: compressed H264/AAC or Opus routes on loopback/listener bound to Tailscale with auth; transport encryption and jitter tuned independently.
- Observation: append-only event log plus direct metrics snapshot. Collect p50/p95/p99 frame times from real exported measurements, `intel_gpu_top` engine metrics, CPU and RSS, network RTT/loss, Hyprland DS state and audio/video drift.

### Failure modes to design and test

- screenshot/notification temporarily invalidates DS; don't treat an arbitrary single sample as permanent loss; report sustained and repeated state.
- KMS permissions denied: fail fast, no root application fallback.
- GSR can't use VAAPI: no software fallback; show an actionable diagnosis.
- Monitor geometry, transform, HDR or color space changes: stop current capture, create new negotiation; never reuse stale DMA-BUF layout.
- RTMP over SSH head-of-line blocking under packet loss: bounded queue, defined reconnect and dropped-stream-frame behavior.
- OBS startup failure: game and local audio remain functional.
- Twitch API credentials/recording failure: keep media path and game running where authorized, don't publish unintended content.
- GPU freeze or driver reset: stop capture, do not automatically restart a crashing capture loop without bounded retry/backoff.

### Candidate for a second capture backend: KMS→VAAPI VPP

FFmpeg's official `kmsgrab` documentation shows `hwmap=derive_device=vaapi,scale_vaapi=...:format=nv12` followed by `h264_vaapi`. This can keep frames in GPU hardware surfaces and potentially move color conversion away from GSR's OpenGL shader path. The exact effect on Intel Gen9.5 Render/Video engine arbitration is **unknown**. The normal FFmpeg kmsgrab process requires DRM master or CAP_SYS_ADMIN, so the direct command is NOT enabled in this lab and should not be run as root on the daily-use desktop. Before integrating, factor its KMS buffer export into a narrowly scoped helper. Only adopt it if A/B/A shows lower game p99 and no DS regression on actual hardware.

A more advanced implementation could use DMA-BUF PRIME import into a VA-API VPP surface, GPU RGB→NV12, then an encoder surface with explicit backpressure. Synchronization through dma_fence or implicit reservations must be correct and must not force the game to wait for capture. A 'no glCopy' requirement says nothing about whether the VA blit writes the same number of pixels elsewhere.

## Implementation handoff and verification order

1. Capture `scripts/graphics-lab/snapshot.sh` under **game-only** conditions. Save kernel/driver versions and NixOS generation before attempting a change.
2. Observe existing `Win+F` Direct Scanout with `scripts/graphics-lab/scanout.py` (read-only). This establishes only the measured **current** state, not input-to-photon latency.
3. Run `scripts/graphics-lab/directcast_lab.py --dry-run` before any capture. Start the isolated receiver on `neko7`, then capture with physical-monitor GSR and separately monitor DS. This uses ports 11935/18554, not the production SplitCast listener.
4. Run A/B/A repeats with exactly the same game, thermal state and version. For frame-time percentiles, use the existing independent `scripts/splitcast/perf.py` collector and external frame CSV. Do not add a duplicate benchmark implementation.
5. If GSR fails due to shader/VPP overhead, experiment with scoped KMS→VA-API VPP (no broad CAP_SYS_ADMIN); prefer measured performance to a claimed 'zero-copy'.
6. Advance the approved Rust full-migration implementation in stages, using differential tests and unchanged legacy services until parity. Validate stock OBS network isolation separately; do not replace patched OBS without security evidence.

**Acceptance is not implicit:** unit tests/dry-runs verify script logic, not functional KMS capture, external receiver, true zero-copy, Direct Scanout preservation, pen latency, or NVIDIA OBS production.
