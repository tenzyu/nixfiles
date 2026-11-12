# neko5: Input / Audio / Update / Draw / activity-first / SplitCast

Baseline: `tenzyu/nixfiles@46ba6a27fc585ba8f8930e7cfd00bba0ad916f3f` (2026-11-12 22:48 JST). The patch is **not applied** to the user's repository or NixOS. The official osu!lazer AppImage and every bundled library remain byte-for-byte unchanged. All source-level observations below are from upstream source or the dated 2026-11-07 / 2026-11-12 diagnostic archives, not claims of new performance measurements. Existing `docs/graphics-streaming/architecture/index.html` is an architectural reference; it is not a source of runtime evidence by itself.

## A. Input: minimize upstream-to-judgement cost

1. SayoDevice O3C: switch firmware scan/debounce → USB `1-2`, descriptor interrupt IN `bInterval=1` full-speed → xHCI completion → `usbhid` → input subsystem/evdev → libinput → Hyprland/Wayland → SDL3 event → osu!framework `KeyboardHandler.PendingInputs` → `InputManager.GetPendingInputs` → osu! judgement. The 1ms descriptor is a USB service interval, **not** proof of 8000Hz USB output or 1ms keydown-to-judgement.
2. Wacom CTL-472: digitizer/firmware sensor rate (stock up to ~133 points/s) → USB `1-4.2`, interrupt IN `bInterval=2` full-speed → HIDRAW → **in-process OpenTabletDriver** → input manager. OTD daemon remains disabled. The descriptor's 2ms is **not** equivalent to 500Hz tablet positions. A separate, user-approved 1000Hz firmware flash with stock recovery is allowed, but is never automated by a Nix rebuild. The reported firmware may have nonuniform tracking at edges; preserve mapping/rotation and button/tip thresholds.
3. Current osu!framework `SDLGameHost` registers `KeyboardHandler`, `OpenTabletDriverHandler`, `PenHandler`, `MouseHandler` in that priority order. Its `InputManager` has a 50ms positional **source-switch debounce**, not a 50ms report delay. Do not disable PenHandler or remap SDL events blindly.
4. The patch adds udev `power/control=on` only for the *observed VID/PID* `8089:0009`, `056a:037a`. Both were already `on` on 2026-11-07: the rule is a regression guard, **not a claim of measured improvement**. It does not alter HID descriptors. Device IDs must be rechecked after custom firmware.
5. The patch does not add redundant polling threads, disable IOMMU mitigations, set arbitrary `irqbalance` masks, or inject anything into osu!.

## B. Audio: BASS -128 plus onboard hardware PCM tuning

* User observation: BASS `-256` and `-128` feel good; custom DT/FUN were okay at `-256`; at `-64`, crackles occur. The new `osu-first` launcher selects `-128` by default and allows `OSU_FIRST_BASS_PERIOD=-256`. It refuses `-64` as a *default competition profile*. This parameter belongs to the official upstream runtime hook (`OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD`), not a patched BASS library.
* PipeWire's ALSA-compatible client, graph quantum, ALSA sink `api.alsa.period-size`, `api.alsa.period-num`, `api.alsa.headroom`, and BASS's own device period are **distinct buffers/clock domains**. `pw-top QUANT/RATE` is not acoustic latency. A graph quantum of 256/48000 = 5.333ms cannot prove total delay.
* Observed legacy ALSA HDA PCM: `rate=48000`, `S32_LE`, stereo, `period_size=1024`, `buffer_size=32768`. The latter is ring capacity, **not** 682.7ms of actual audible delay.
* New targeted WirePlumber rule, matched only on `alsa_output.pci-0000_00_1f.3.*`: period-size **128 frames** (2.667ms at 48k), period-num **3** (384 frames / 8.0ms nominal buffer *capacity* for a non-batch device), headroom **64 frames** (1.333ms configured headroom), `disable-tsched=false`, suspend-timeout=0. Numbers describe the **request**, not proven hw_params. ALC257/HDA is not a USB DAC; don't copy `snd_usb_audio BATCH` claims.
* This is an aggressive 128-frame candidate and is **not proven glitch-free** with Discord/SplitCast; if sound crackles, revert this one block or change period-size to 256 without altering BASS. The PipeWire graph remains in auto mode; no system-wide `clock.force-quantum=32` and no global `SCHED_FIFO`. Per-process `PIPEWIRE_LATENCY` remains optional (e.g. `OSU_FIRST_PIPEWIRE_LATENCY=128/44100`) because extra shrinking may cause crackling while Discord/streaming are active. Physical output may still resample 44.1→48k.
* To roll back only the audio hardware request, remove the `90-neko5-alc257-lowlatency` block from `neko5-osu-first.nix` and rebuild; NixOS switch alone may not hot-recreate the device. Restart WirePlumber only after closing other audio apps. The previous system generation remains bootable.

## C. Update: minimize scheduling interference without modifying osu!framework

* `ThreadRunner.RunMainLoop()` executes Input on the main SDL window thread, not a separate dedicated input thread. In MultiThreaded mode Update and Draw have their own managed threads. Switching to SingleThread would serialize them and tie the Update target to Draw; it is not selected.
* `GameHost.updateFrameSyncMode` at 60.003Hz, Limit8x = Update min(16×60.003,1000) = **960.048Hz**, Draw min(8×60.003,1000) = **480.024Hz**. `Unlimited` targets 1000/1000. These are targets, not observed execution rates.
* `ThrottledFrameClock` calls `UnixNativeSleep.nanosleep()` in the common Linux path. The launcher sets Linux `PR_SET_TIMERSLACK` to **1000ns** (from a common 50,000ns default, actual default varies). This bounds intentional expiry coalescing; it does **not** bound CPU dispatch latency. Fork/exec and child thread creation inherit the value. The setting is process-local and vanishes on exit.
* The launcher uses a transient user systemd scope with `CPUWeight=10000` and `CPUUClampMin=35%`. Both influence resource allocation/CPU performance hints under contention, not instruction count or IRQ latency. It deliberately does **not** request managed .NET `SCHED_FIFO` (GC priority inversion risk). This is competition-first, not workstation-fairness-first. Failure to create the scope is reported, not silently ignored.
* The 2026-11-07 snapshot showed `PREEMPT_DYNAMIC` and no `preempt=` boot flag. The NixOS profile requests `preempt=full`, which switches kernel-code preemption points; user-space remains preemptible regardless. It does not install an RT kernel, alter HZ or bypass security mitigations. More preemption can also increase overhead; the previous boot generation is the rollback.
* Existing desktop profile already sets the `performance` governor, thermald, zram and Intel microcode. These are retained, not duplicated. Thermals at 95–98°C with previously observed package throttling remain a potential upper bound. Avoid Intel C-state forcing and disabling thermal protection in this patch.

## D. Draw: 60Hz output freshness, verified compositor route

* `Root.UpdateSubTree → UpdateSubTreeMasking → GenerateDrawNodeSubtree → TripleBuffer<DrawNode> → DrawThread → GL → SDL_GL_SwapWindow → EGL/Wayland → Hyprland → KMS scanout`. The per-Update DrawNode tree traversal is expensive in scene-size terms, but source changes to suppress it are prohibited by tournament binary integrity. DrawNodes are reused by invalidation IDs: not all are allocated each update.
* `GameHost.Swap()` performs `Renderer.WaitUntilIdle()` (`GL.Finish()`) when GL+VerticalSync is active. `Limit8x/Unlimited` select VSync-off at framework level, so forcing GL sync elsewhere is disfavored. Do not force Vulkan/Zink or Gamescope; do not set `MESA_GLTHREAD=true` without proving its queue is beneficial.
* The known-good direct-scanout state from 2026-11-12 diagnostics is Hyprland `fullscreen=2`, `fullscreenClient=0`, with `directScanoutTo != 0`, no blocker; `2/2` gave `TRANSFORM`. Latest main's Win+F state-aware Lua binding and lack of a map-time fullscreen rule are preserved. `render.direct_scanout=1` remains active and the game's logical resolution 1280×720 remains unchanged. `XRGB8888` eDP is already 8-bit SDR.
* At 60.003Hz there is one nominal scanout start every **16.666ms**. Rendering 480/1000fps can make a more recent game state ready for the next scanout, but cannot make the panel complete 1000 full refreshes. Disabling VSync does not force immediate asynchronous KMS presentation. Stock SDL's Wayland `wp_tearing_control_v1` hint is not guaranteed; the report's patched SDL3 is rejected.
* Hyprland `immediate` tearing rule is **not** added. Its upstream wiki warns unsupported drivers can freeze, and the user's recent Fullscreen regression makes that risk concrete. Tearing requires both compositor support and actual client presentation eligibility. As a reversible future branch, it can be explicitly reconsidered after proving stable 2/0 + Draw delivery; not a safe global fix.
* `osu-first` stops mako notifications and pauses Waybar while the game scope runs, restoring only components that were active before launch. This prevents popups/panels from obstructing a fullscreen candidate; it does not guarantee frame-by-frame scanout and cannot prevent `SIGKILL` from skipping the wrapper's cleanup. Recovery: `pkill -CONT -x waybar; systemctl --user start mako.service`.
* Frame-sync policy: keep 8x as conservative baseline; for maximum immediate-state freshness at physical 60Hz, `Unlimited` is a valid alternative but adds roughly +520 Draw executions/s for only +40 Update executions/s versus 8x. The option is changed in game UI, not by writing undocumented `framework.ini` values; user retains decision.

## E. Activity-first scenarios and isolation

| profile | purpose | game/binary | external resource effect | keep running |
| --- | --- | --- | --- | --- |
| `osu-first solo` | osu practice | official upstream | systemd scope CPUWeight/uclamp + timer slack + BASS; hide mako/waybar | network, PipeWire, hardware input |
| `osu-first tournament` | osu + Discord | official upstream | same | Discord voice, Tailscale/network, local audio |
| `osu-first stream` | osu + SplitCast | official upstream | same, no capture hook or auto-stream | independent Rust/Python SplitCast candidate/production path |

Default `osu-lazer` and the existing desktop entry remain unchanged; `osu-first` adds an explicitly selected entry. This patch **does not kill browser processes or terminate downloads**. To sacrifice them safely during a session, close them manually before play. SIGSTOP and system-wide background renice were excluded because fatal process loss would leave an unmanaged suspended service. The only globally enabled policy is the NixOS WirePlumber ALSA-node rule plus `preempt=full` and device power rules, all revertible by the previous generation.

### Installation after user approval, not performed now

```bash
cd ~/.nixfiles
git rev-parse HEAD
git status --short
git apply --check /path/to/neko5-extreme-46ba6a2.patch
# only if baseline matches and user explicitly approves:
git apply /path/to/neko5-extreme-46ba6a2.patch
nix flake check --no-build
nh os build
# only after inspecting the derivation and known-good generation:
# nh os switch
```

The flake `main` can advance after 46ba6a2; a conflict requires fetching the new exact revision and rebasing. The scripts and a package candidate are **not deployed** by creating this patch.

## F. SplitCast Rust replacement status and non-regression gates

The Python codebase currently has substantial operational scope (HTTP auth + browser UI, exact version-1 schema, route editing, SSH owner lease, GSR, MediaMTX, microphone FFmpeg/RNNoise, camera, OBS authenticated WebSocket, preview, VOICEVOX queue, Twitch EventSub and recovery). An inactive, dependency-free Rust lifecycle crate previously existed.

This patch adds dependency-free Rust modules for config parsing (via `jq`, no Python), media command generation, authenticated loopback control HTTP, and OBS WebSocket v5 through `websocat`/OpenSSL. It wires the crate into Nix with a wrapped native dependency closure and adds an **explicit opt-in** `rustCandidate` flag to the existing Home Manager module. The default remains the working Python service. It uses GSR/FFmpeg native workers and a systemd user-service cgroup for process cleanup; no direct GL/ASIO patching to osu!.

**The rewrite is NOT feature-complete.** Specifically, the initial Rust candidate rejects TTS/EventSub, preview and mutable routes rather than pretending they work; browser UI, delivery-health parity, codec verification and host-to-host negative tests have not passed. A Rust compiler and Nix are not available in this author's container, so the crate has not passed compilation. The candidate must not be selected on neko7 or neko5 until those defects are resolved and `cargo test` + `nix build` + real two-host tests pass. Reporting this as a completed full rewrite would be false.

### Minimum cutover contract

1. Version-1 full JSON schema, strict routes and credentials handling equal to Python tests, with no secrets in JSON responses/logs.
2. `doctor`, `devices`, `prepare`, `start` (recording/Twitch explicit only), `stop`, `status`, `heartbeat`, `routes`, `mic`, `tts`, `say`, `overlay`, `preview`, `diagnostics` all equivalent.
3. SSH forwards only loopback, remote owner/lease expiration and bounded restart, no child left after agent crash (`KillMode=control-group`). No public `OBS` socket and no unsafe shell expansion.
4. Capture GSR KMS framebuffer with real direct-scanout, Intel VAAPI H.264, bounded transport and no game renderer modification. On neko7, decode/OBS NVENC + RNNoise and clock sync, mic/camera/VOX/overlay as configured.
5. Re-run legacy `packages/splitcast/tests` all categories with Rust CLI/HTTP backend, validate failures and `SIGTERM/SIGKILL` cleanup, then verify Direct Scanout stays available while GSR is capturing. If no DS under capture, architecture must change without sacrificing game input, update or draw.
6. No implicit Twitch start/recording on boot; explicit user approval for production cutover, with rollback retaining the Python service and previous generation.

### Primary upstream sources

- Linux utilization clamping: https://docs.kernel.org/scheduler/sched-util-clamp.html
- Kernel preemption models: https://dri.freedesktop.org/docs/drm/scheduler/sched-preemption.html
- Timer slack: `PR_SET_TIMERSLACK` (`man prctl` / Linux man-pages)
- WirePlumber ALSA buffering: https://pipewire.pages.freedesktop.org/wireplumber/daemon/configuration/alsa.html
- PipeWire ALSA `api.alsa.*`: https://docs.pipewire.org/devel/page_man_pipewire-props_7.html
- Hyprland tearing warnings: https://wiki.hypr.land/configuring/extra/tearing/
- Fikser0: https://github.com/Fikser0/osu-linux-audio-latency
- AppImage/SDL patch precedent (not installed): https://github.com/gmaxpwnage/nix-osu-lazer
- osu! native Wayland community counterexample: https://github.com/ppy/osu/discussions/37338
- GSR/KMS approach and access caveat: https://ffmpeg.org/ffmpeg-devices.html#kmsgrab
- Framework code `GameHost.cs`, `ThreadRunner.cs`, `InputManager.cs`, `UnixNativeSleep.cs` at `ppy/osu-framework`.

## Deep Research report cross-check

The user-supplied 2026-11-12 Deep Research report is an index to *other researchers' individual environments*, not a transferable latency certificate. Its examples cover Fikser0's PipeWire/ALSA configuration and alleged XRUN improvements, `gaavin/nix-osu-lazer`'s 128-frame BASS+PipeWire reports, ThePooN's historical Wine/PulseAudio driver patch, and `rszyma/osu-latency-tweaker`. Only official-app-external changes are eligible here. In particular, custom SDL3 library replacements and libbass patching are prohibited by the tournament binary-integrity constraint. Reported cycle length, full ALSA buffered latency, and acoustic response have different units/measurement boundaries; never sum claimed wins across researchers or adopt their numbers as a neko5 measurement.

## Unmet gates and audit matrix

| Gate | Implemented in this patch | Verified in sandbox | Actual two-host/hardware validation |
|---|---|---|---|
| Official osu! intact | No source/binary change in diff | changed-path check, Git patch subset | tournament rules additionally require organizer acceptance |
| HID power regression guard | Targeted udev rule | source only | effective user HID mode still unknown |
| BASS -128 and -256 fallback | Process-only launcher | mock game invocation | -128 user-observed good; -64 user-observed crackling |
| 128-frame ALC257 request | Targeted WirePlumber rule | source only | graph/node ALSA effective params and crackling unknown |
| Low-jitter CPU scheduling | timer slack 1000ns, uclamp, CPUWeight, preempt=full | script mock and syntax | scheduling win not proven; Nix kernel rebuild not run |
| Draw freshness | DSO & renderer untouched; mako and waybar paused | source only | 2/0 actual DSO already observed in prior snapshot; FPS/tails after patch unknown |
| Python→Rust SplitCast | Partial media/HTTP/OBS control candidate; opt-in false | Rust compilation unavailable | **not complete**: TTS/EventSub/UI/preview/routing/recovery/parity missing |
