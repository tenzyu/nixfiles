# neko5 / osu!lazer / SplitCast — code-first cost model

Date: 2026-11-08. Repo main verified: `1c2d78964608fe02086977b4642989def316d004`. Scope: performance constraints from implementation **before** additional live measurement. No daemon, pipeline, or kernel knobs are changed by this document.

## Evidence discipline

- **S (source contract)**: directly derived from linked public implementation or upstream docs. This is about code structure, not a measured performance number.
- **M (mathematical)**: arithmetic from measured constants, payload sizes and sample rates. Does not assert actual resource consumption.
- **H (hypothesis)**: mechanism exists; benefit not established for neko5.
- **E (user snapshot)**: reported/configured runtime observation 2026-11-07, not a universal device property.
- Existing SplitCast ADR and current Python implementation are migration inventory, not constraints on ideal design.

## A. Audio: actual critical path and its intrinsic cost

`SampleChannelBass.Play()` → `SampleChannel.Play()` → `AudioComponent.EnqueueAction(new Task(action))` unless already on the Audio Thread → `ConcurrentQueue<Task>` → Audio Thread `AudioManager.Update` and `AudioComponent.Update()` draining via `Task.RunSynchronously()` → `SampleChannelBass.playInternal()` → `BassAudioMixer.ChannelPlay()` (`AddChannelToBassMix`, `BassMix.ChannelRemoveFlag(MixerChanPause)`) → native BASS mixer data generation → ALSA-compatible BASS device output → PipeWire ALSA plugin → PipeWire data-loop → ALSA PCM → `snd_hda_intel` and `ALC257` → DAC.

**Derived from source (S):** `new Task` and queue admission are relatively small per-event operations but they are not instantaneous. `RunSynchronously()` runs the work on Audio Thread, not by launching a separate ThreadPool job for every hit. The mixer play path alters channel/mixer state; it does not reread a sample file on every start when the sample has already been loaded. `SampleBassFactory` loads and stores the sample using `Bass.SampleLoad()` and obtains playback channels from the decoded sample through `Bass.SampleGetChannel()`.

**Important hidden boundaries (S):**
1. A pending action cannot be observed on the device until the Audio Thread drains the queue. Audio Thread target 1000Hz is not its minimum wake-to-run guarantee.
2. Native BASS pulls/generates audio in periods. Issue #6650 identifies 0..1 output-generation-period quantization of sample onset. Do not equate Play() with physical onset.
3. `AudioManager.InitBass()` by default selects `DeviceBufferLength=10` ms; experimental `OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD=-N` changes BASS device period and requests `DeviceBufferLength=1`, rounded by BASS to ≥2×actual period. This is a more direct lever than shrinking PipeWire graph quantum in isolation.
4. `BassAudioMixer.createMixer()` sets `ChannelAttribute.Buffer=0` on a mixer to avoid preparing source audio far in advance. `BassFlags.MixerChanBuffer` on mixer source channels is a different buffer feature for source data access/analysis and should not be removed by name alone.
5. BASS track playback uses `StreamSystem.NoBuffer`, and osu! gameplay timing uses `FramedBeatmapClock` with an interpolator (`DriftRecoveryHalfLife=80`) and offsets. Lowering hardware output latency can change the effective audio/gameplay sync; a fixed offset is not a fix for onset jitter.
6. Linux `sound/hda/controllers/intel.c::azx_position_ok()` can reject premature HDA period interrupts and defer period elapsed notification through `azx_irq_pending_work()` with 1ms retry sleeps. Its existence does not show the workaround occurred on neko5; read the kernel log before setting `bdl_pos_adj` or `position_fix`.

**Arithmetic (M):** at 48 kHz, a graph with Q=512 runs 93.75 cycles/s, Q=256 187.5, Q=128 375, and Q=64 750. Increasing Q rate from 256 to 128 adds 187.5 cycles/s. If the fixed per-cycle cost were C=0.1ms *hypothetically*, additional CPU usage would be 18.75 ms/s = 1.875% of one logical core; if C=0.02ms, 0.375% of one core. Sample-rate DSP work may remain almost constant because total samples/s is unchanged. These are not observed CPU usage or actual per-cycle costs. In contrast, a theoretical onset quantization period could shrink from 10ms to 2.667ms if **BASS's effective period** really changed; graph quantum alone does not prove that.

**Action order from code, no new measurement as a prerequisite:**
A1 preserve the known-good current local audio path; do not force direct ALSA, which can break PipeWire monitoring for SplitCast.
A2 prioritize a launch-time *BASS-period* experiment above more PipeWire-only quantum sweeps; use the existing BASS environment toggle only on a separate test launch with prior settings intact.
A3 independently distinguish actual BASS period (`BASS_GetInfo().minbuf` and BASS device log), mixer schedule phase, PipeWire driver QUANT, and ALSA PCM; do not infer one from another.
A4 avoid unnecessary runtime resampling where it can be eliminated at the configured interface without changing audio pitch, playback rate, or the game clock. The observed osu stream was 44100 Hz and the device 48000 Hz; that **proves a potential sample-rate-conversion boundary**, not a meaningful CPU bottleneck by itself.
A5 no permanent low-quantum default until backend stability and clock semantics are accounted for; safety gate is a **later** task, not a substitute for code analysis.

Key code: https://github.com/ppy/osu-framework/blob/master/osu.Framework/Audio/Sample/SampleChannelBass.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Audio/AudioComponent.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Audio/Mixing/Bass/BassAudioMixer.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Audio/Sample/SampleBassFactory.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Audio/AudioManager.cs ; https://github.com/ppy/osu-framework/issues/6650 ; https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_PERIOD.html ; https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_BUFFER.html ; https://github.com/torvalds/linux/blob/master/sound/hda/controllers/intel.c .

## B. Input: bounded USB polling vs software scheduling

**Keyboard source path:** O3C endpoint `bInterval=1` (Full-speed interrupt IN, E) → xHCI event/URB → `usbhid` → Linux input core → evdev → libinput → Hyprland Wayland → SDL3 `SDL_KeyboardEvent` → `KeyboardHandler.handleKeyDown/Up()` → `PendingInputs.Enqueue(new KeyboardKeyInput)` → `InputManager.Update()` calling `GetPendingInputs()` and `.Apply(CurrentState, this)` → ruleset judgement. **Tablet source path:** CTL-472 endpoint `bInterval=2` (Full-speed, E), via USB hub → HID/hidraw as supported by device → in-process OTD report mapping → `OpenTabletDriverHandler.enqueueInput()` → pending inputs → judgement.

**Cost in code:** evdev and keyboard handler process *events*, so do not multiply all stages by 1ms as though each stage were a polling gate. `InputManager.Update()` is a *frame* gate, however, so events may be held until the next Update; at a perfectly regular 1000Hz Update loop the phase-dependent waiting interval is <1ms, but no bound follows under scheduler stalls. Position-source switching debounce of 50ms prevents input-provider flapping; it is not mouse sample interval. The keyboard SDL event timestamp is not passed into the `KeyboardKeyInput` constructor in the inspected code. No kernel governor tweak recovers source timestamps lost at this edge.

**Conclusions:** `usbhid.mousepoll=1` is not a method to raise an O3C keyboard or CTL-472 digitizer's USB endpoint rate; a 2ms configured interval limits each of those endpoints' scheduled poll opportunities, and application polling cannot manufacture reports between them. Do not replace working in-process OTD with external daemon. The precise acquisition driver is interface-specific; do not claim *all* tablets use hidraw. Removing libinput/Hyprland is not a free optimization: it changes focus, mapping and Wayland handling. A custom direct-hid keyboard input path is theoretically possible but requires faithful debouncing/ordering/focus rules and is not justified merely by event forwarding overhead.

Sources: https://github.com/torvalds/linux/blob/master/drivers/usb/host/xhci-ring.c ; https://github.com/torvalds/linux/blob/master/drivers/input/evdev.c ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Input/Handlers/Keyboard/KeyboardHandler.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Input/InputManager.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Input/Handlers/Tablet/OpenTabletDriverHandler.cs .

## C. Update: frame gate, GC and draw snapshot cost

`GameThread.processFrame()` executes `Scheduler.Update()` and `synchronizationContext.RunWork()`, then `OnNewFrame`, then `ThrottledFrameClock.ProcessFrame()`; on the Update thread, GameHost `UpdateFrame()` invokes `Root.UpdateSubTree()`, `Root.UpdateSubTreeMasking()` and `Root.GenerateDrawNodeSubtree()` into `TripleBuffer<DrawNode>`. Time elapsed in wakeup/scheduler is distinct from work completed in the frame. `ThrottledFrameClock.throttle()` computes remaining target time, uses native sleep where available, and carries accumulated sleep error. It does not create a 1000Hz hard real-time guarantee.

**Structural cost:** Update walks gameplay/scene components; cost depends on active drawables/hitobjects and UI state, plus queue processing, allocations and GC. The upstream `GameHost.updateFrameSyncMode()` explicitly caps default Draw and Update to 1000Hz because excessive rates can cause allocation/GC and GPU pipeline stalls, and the input rate is 1000Hz. Removing that cap is *counter to the existing source-level performance design*, not a guaranteed improvement.

**Actions from code:** preserve standard multithread execution. Prioritize avoiding out-of-band application work on CPU cores used by Input/Update/Audio; keep heavy background Discord/Firefox/other application workloads from creating CPU and memory/thermal pressure. In-game change candidates are per-frame allocations and unnecessary updates within active scene graph, not blind kernel tuning. Retain full gameplay correctness and content; do not alter hit windows or judge timestamps to “optimize” them.

Sources: https://github.com/ppy/osu-framework/blob/master/osu.Framework/Threading/GameThread.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Timing/ThrottledFrameClock.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Platform/GameHost.cs .

## D. Draw: draw snapshots, graphics work, display scanout

Path: generated DrawNode snapshot → `DrawFrame()` read from `TripleBuffer` → depth/opaque/render passes → GL command submit → Mesa Iris → i915 GEM/exec/sync → SDL3 GL swap/Wayland surface → Hyprland Direct Scanout (user-confirmed when osu foreground) → DRM plane/vblank/page flip → eDP 60.003Hz. In GL+VSync, GameHost `Swap()` calls `Renderer.WaitUntilIdle()` (GL `Finish`) after swap, a direct GPU/CPU synchronization barrier. Only applies under the stated condition; do not generalize to all fullscreen frames.

**Structural cost:** Renderer batching, DrawNode creation and GL commands have real per-frame overhead. 1000Hz over a ~60Hz physical display does not produce 1000 *complete* displayed frames; higher draw rates may increase freshness of image submitted at the next scanout and tearing changes what is visible mid-scan. Hence “cap to 60” and “uncap above 1000” are both ungrounded universals. Keep known 1280x720 OpenGL/Wayland and Direct Scanout policy. Preserve the ability to reach framework ceiling and avoid GPU-backed overlay or capture hooks in the game process.

Sources: https://github.com/ppy/osu-framework/blob/master/osu.Framework/Platform/GameHost.cs ; https://github.com/ppy/osu-framework/blob/master/osu.Framework/Graphics/OpenGL/GLRenderer.cs ; https://docs.kernel.org/gpu/drm-kms.html ; https://wiki.hypr.land/configuring/extra/tearing/ .

## E. SplitCast: readback vs DMA-BUF by structural cost

Ideal per-host boundary: on neko5, existing OpenGL→Wayland→Hyprland→KMS plane path untouched. SplitCast uses a minimally privileged KMS framebuffer broker (`DRM_IOCTL_MODE_GETFB2` + PRIME handle-to-FD) to share a DMA-BUF with a bounded capture/VAAPI worker, convert RGB→NV12 (on GPU/VA VPP if compatible), hardware H.264 encode, compressed transport over Tailscale. Local game sound remains on ALC257; an independent PipeWire application monitor duplicates it without feeding it back. On neko7, ingest/decode, AV clock alignment, OBS overlay/mic/TTS, NVENC and publishing. Rust controls process ownership and lifecycle, **not** media kernels.

**Data-volume arithmetic (M):** 1280×720 RGBA8 one frame = 3,686,400 bytes; at 60fps = 221.184 MB/s of *raw* pixel payload. The confirmed 1366×768 full display is 251.781 MB/s at 60fps. NV12 at 1366×768/60fps is 94.418 MB/s. At an *illustrative* H.264 target of 12Mbit/s, compressed payload is ~1.5 MB/s excluding transport overhead; raw 720p RGBA is ~147 times as many bytes per second. These are format/payload calculations, not actual UMA memory bus traffic. Each additional full-frame CPU readback/copy implies an additional material payload movement even before synchronization; DMA-BUF avoids *CPU round trips*, but not surface format conversion, GPU memory bandwidth use, or dma_fence waits.

**Decisions from implementation:** do not inject hooks into osu's `eglSwapBuffers` path. Prefer DMA-BUF + VAAPI over CPU `hwdownload` followed by re-upload. `kmsgrab` alone is not magical zero-copy; `hwmap=derive_device=vaapi,scale_vaapi=format=nv12` explicitly reveals the conversion boundary. Compositor screencopy/portal can invalidate Direct Scanout and should not be substituted silently. ffmpeg's KMS grab has DRM-master/CAP_SYS_ADMIN constraints; never grant the whole agent/OBS that privilege. The capture loop must use a finite queue and drop outdated *stream frames* rather than block the game or hold scanout framebuffers indefinitely. Full rewrite in Rust should keep a narrow hardware helper, not duplicate GPU codecs.

Sources: https://ffmpeg.org/ffmpeg-devices.html#kmsgrab ; https://docs.kernel.org/gpu/drm-uapi.html ; https://docs.kernel.org/7.2/driver-api/dma-buf.html ; https://github.com/tenzyu/nixfiles/blob/1c2d78964608fe02086977b4642989def316d004/packages/splitcast-rs/README.md .

## Source-first priority matrix

| Priority | Concrete action | Code-level benefit mechanism | Why measurement is not prerequisite | Counter-risk / hold |
|---|---|---|---|---|
| P0 | Retain in-process OTD and direct native Wayland/GL/Direct Scanout | Avoid an extra interprocess tablet path and compositor rendering when scanout eligible | Existing implementation & user-confirmed success | Do not disturb mapping/fullscreen |
| P0 | Keep SplitCast entirely outside game process; no GL hook | Removes capture callback/crash from the game frame critical path | Source call graph & process ownership | Still shares GPU/DRAM/power |
| P1 | Audio: optimize BASS sample-onset boundary before further PipeWire-only sweeps | Sample is queued, then starts on native mix request; mixing period quantizes onset | Explicit BASS and osu source statements | Experimental period is unsafe to enable permanently without backend gate |
| P1 | Keep audio graph separate from local output capture; isolate capture service queue | Remote stall can't enter game audio path | Dataflow ownership | PipeWire graph shares resources; app-specific source selection |
| P1 | Reduce background app contention without removing game workloads | Removes runnable processes and thermal/DRAM users rather than disabling gameplay fidelity | Host 4C8T/UMA resource topology | Background apps may carry indispensable functions |
| P1 | Select VAAPI/DMA-BUF and bounded frame queues for SplitCast | Avoids ~221-252 MB/s per raw pixel pass and buffering amplification | Pixel arithmetic & KMS/VAAPI design | Implicit sync/conversion/privileges still need safe implementation |
| P2 | Study allocation/concurrency in `SampleChannelBass`, `InputManager`, scene graph | Reduces per-event or per-frame work without changing timing semantics | Source identifies queue allocations/snapshot generation | Preserve note/hit correctness, avoid unsafe pooling |
| P2 | Distinguish BASS native period, PipeWire graph quantum and ALSA period | Prevents adjusting the wrong time boundary | Separate config variables / code paths | Requires runtime observation for *final numeric result*, not to establish architecture |
| Reject | `usbhid.mousepoll=1` as keyboard/tablet report-rate boost | Wrong device input path/USB descriptor contract | Endpoints already give distinct bIntervals | Could add load, no new reports |
| Reject | Blanket PREEMPT_RT / isolcpus / `i915.enable_guc=3` | Changes unrelated kernel subsystems before identifying critical path | Code lacks causal reason; small 4C host | Can worsen total scheduling & thermal behavior |
| Reject | Claim 256-frames graph quantum yields 5.33ms key→sound latency | Ignores task queue, BASS, backend & DAC buffers | Code proves multiple independent stages | False latency claim |

## Next engineering artifact—not another generic benchmark

Produce an optional **instrumented osu!framework build** with timestamp probes at:
`KeyboardHandler.enqueueInput`, `InputManager.GetPendingInputs`, osu! judgement, `SampleChannelBass.Play`, `AudioComponent.EnqueueAction/Update`, `BassAudioMixer.ChannelPlay`, and BASS device information queries. Use a fixed-memory trace buffer rather than console IO in hot paths, preserve monotonic timebase identity, and flush only outside the active loop. If *physical* input-to-speaker delay is subsequently wanted, that requires an external synchronized acoustic/electrical test; it is **not** a prerequisite to reason about the code structure above.

No permanent game or kernel configuration change is justified solely by this source cost model. The correct immediate output is a source map + priority decision, not another request for a short A/B sample.
