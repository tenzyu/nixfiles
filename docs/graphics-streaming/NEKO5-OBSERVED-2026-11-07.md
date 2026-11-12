# neko5 / osu!lazer observed runtime, 2026-11-07

Status: **observed snapshot**, not a reproducible performance benchmark. This document is the repo-facing observation index. The attached original user archive `neko5-active-20261107-143057.tar.gz` and 20 user-designated original text logs are the authoritative raw inputs; prior same-named Library files are superseded. No raw logs, device serials, MACs, tokens or network addresses are committed here.

Base for this documentation patch: `tenzyu/nixfiles` `main` `1c2d78964608fe02086977b4642989def316d004` (2026-11-07). This note does not prove that the local NixOS generation came from that revision.

## Verified facts and calculations

| Domain | Observed data | Meaning / limitation |
|---|---|---|
| Host | dynabook BJ65/FS A6BJFSFAL511, i5-10210U, 4C8T, ~16 GiB installed | 4 cores and iGPU share package power/DRAM; no achievable frame-time ceiling measured |
| OS | NixOS 26.05.20261020.cd4ea8d, Linux 7.3.0 `PREEMPT_DYNAMIC`, `intel_pstate` / `performance` | Kernel runtime observed; actual preemption mode not determined from `uname` alone |
| Display | eDP-1, Chimei Innolux 0x15E6, **1366x768 @ 60.003 Hz**, VRR false | Nominal scan period 1000/60.003 = 16.6658 ms; game internal 1280x720 is not physical panel mode |
| Direct Scanout | **8/8 foreground samples** `active=osu!`, workspace 2, `directScanoutTo=62a16dd115f0`, no reported block reason | Correct earlier inactive-workspace false-negative; not proof for every presented frame or simultaneous capture |
| Presentation | `activelyTearing=false`, `tearingBlockedBy=[NOT_TORN]` throughout eight samples | Direct Scanout **does not** imply active tearing, immediate presentation, or 1000Hz photons |
| GPU | Comet Lake-U GT2 i915 (`8086:9b41`), i915 initialized | Hardware encode capability/profile and render/Video engine pressure not measured |
| Audio output | `osu!` ALSA client → PipeWire 1.6.6 → built-in ALC257 analog sink → HDA PCH `snd_hda_intel` | Local physical audio path confirmed; HyperX SoloCast is microphone input, not game sink |
| ALSA playback | `S32_LE`, stereo, 48,000 Hz, `period_size=1024`, `buffer_size=32768` frames | Period=21.3333ms, total PCM buffer capacity=682.6667ms. Capacity is **not** measured acoustic latency. |
| PipeWire settings | `clock.rate=48000`, `clock.quantum=1024`, `min=32`, `max=2048`, `force=0` | Metadata are configured graph settings, not proof that a specific connected stream's cycle ran at 1024 during gameplay |
| PipeWire `pw-top` | Captured nodes shown as state `C`, QUANT=0, ERR=0 | Inactive/changed node snapshot, not a valid continuous XRUN or BUSY/WAIT recording; `ERR=0` here proves nothing about an active graph |
| O3C | full-speed USB `1-2`, `8089:0009`, interrupt IN `ep_81 bInterval=01`, `power/control=on` | Descriptor asks for ~1ms polling. User set 1000Hz; physical scan-to-game delay still unmeasured |
| Wacom | CTL-472 full-speed USB `1-4.2` through VIA hub `1-4`, `056a:037a`; interrupt IN `ep_81/ep_82 bInterval=02`, PM=on | USB endpoints request ~2ms intervals, **not** 1ms; actual positional reports and firmware not directly measured |
| Additional hub | Logitech receiver `1-4.1`; SoloCast `1-4.3`; AX88179 USB Ethernet `1-4.4` but disconnected | Sharing hub does not by itself prove interference or contention. USB host is Intel xHCI 8086:02ed |
| Connectivity | Wi-Fi AX201 `iwlwifi` active, Tailscale interface; physical wired links down | Actual direct-vs-DERP tailnet path to neko7, throughput and RTT not measured |
| CPU temperature | x86_pkg_temp **95–98 °C** in eight ~1.1-second samples | High priority power/thermal diagnostic; not a demonstrated PROCHOT/throttling event |
| CPU frequency | cpu0 `scaling_cur_freq` **2.900–3.083 GHz** in samples | Single-core instantaneous state, not a multi-core sustained CPU frequency or throttling proof |
| Capture | SplitCast feature disabled in repository configuration | No game+SplitCast performance or security result; the capture architecture remains a proposal |

## One-way signal flow (game is never downstream of SplitCast)

- O3C: USB 1-2 `bInterval=1` → `usbhid`/evdev → libinput → Hyprland/Wayland → SDL3 → framework queue → Update/judgement.
- CTL-472: USB 1-4.2 `bInterval=2` → HID/raw interface as actually opened → in-process OTD → framework queue → Update/judgement. No claim of 1000Hz pen reports.
- Audio: game/BASS → ALSA compatibility → PipeWire 48kHz graph → ALSA HDA `S32_LE` → ALC257 headphones/speakers. Only a separate, nonblocking application-audio tap may feed SplitCast.
- Update: gameplay clocks / queue / hit objects → draw node snapshots → Draw OpenGL → Mesa/i915 → Wayland Hyprland → direct scanout → 1366x768/60.003Hz panel.
- SplitCast proposed: independent KMS capture → bounded DMA-BUF/VAAPI conversion+encode → prioritized transport → neko7 remux/decode/composite/OBS/NVENC; no game process hooks.

## Highest-priority unknowns

1. **Thermal behavior:** correlate package temperature, per-core APERF/MPERF or CPUFreq, RAPL power limits and `thermal_throttle` counters with p99/p99.9 Update/Draw under an identical replay; current evidence is insufficient for thermal throttling claim.
2. **Render timing:** current captures establish Direct Scanout in foreground, but not frame presentation timestamps, actual game Update/Draw rates, latency distribution, VSync/tearing semantics, or Capture ON direct-scanout continuity.
3. **Audio:** compare actual BASS output period and connected PipeWire node quantum with an **active** `pw-top -b -n` capture, ALSA hw_params and XRUNs, and only then experiment with reversible 256/128/64 frame settings. Never treat ALSA buffer capacity as actual latency.
4. **Input:** evdev timestamps and HIDs; actual Wacom report cadence, firmware, pressure, and OpenTabletDriver input source; the USB descriptor alone is not application latency.
5. **SplitCast:** VAAPI/Intel media engine entrypoints, GSR capture/permission boundary, direct-vs-relay route and encoder/display resource interference are entirely untested in this archive.

## Safe operation

`osu-audio-quantum-lab status` is read-only. `osu-audio-quantum-lab run 256 -- <workload>` changes the **shared** PipeWire graph quantum until the workload exits, then restores the previous automatic setting. It is **experimental**, not a recommended always-on game launcher. If killed with SIGKILL, run `osu-audio-quantum-lab restore`; never leave a forced graph setting silently active. Use `scripts/osu-performance/collect-active.sh` for bounded *read-only* follow-up sampling.

Runtime docs should keep this snapshot separated from: (a) deterministic upstream source behavior, (b) design proposals, (c) observed post-change results, and (d) unverified hypotheses. See `EVIDENCE-2026-11-07.tsv`.

## 2026-11-07 15:30 JST: Audio 256-frame experiment (newer follow-up, not a baseline A/B)

Source of truth is the user-uploaded `neko5-observation-20261107-153001.zip`; SHA-256 `d3457f068ac93d56fefab5c5007b38457f1ba69bee931abcae2063613acf2904`. This supersedes previous *hypotheses* for the conditions it actually measured; the earlier 14:30 raw archive remains an independent dated baseline. 12 thermal/active-window samples were captured at 15:30:09–15:30:22 JST while osu! was in foreground. No SplitCast capture session was running. The user set `osu-audio-quantum-lab run 256 -- sleep 180`, then launched osu! during the forced interval, and subjectively reported little difference; the script confirmed restoration to `clock.force-quantum=0` after sleep exited.

| Observable | Value | Scope / cannot conclude |
|---|---|---|
| `pw-metadata` | `clock.force-quantum=256`, `clock.rate=48000`, `clock.quantum=1024` | The default quantum remains 1024; *force* was 256 while experiment ran. |
| ALC257 PipeWire driver node | `R`, `QUANT=256`, `RATE=48000`, ~5.333ms cycle | Observed two running `pw-top` rows; **confirms effective graph driver quantum**, not hardware acoustic latency. |
| osu! ALSA follower | `R`, `QUANT=441`, `RATE=44100`, F32LE, stereo | **Follower quantum is a suggestion** (10ms by ratio), not proof of its callback cadence/BASS device period. Graph conversion/resampling to 48k device may occur. |
| HDA ALSA `hw_params` | S32_LE stereo 48000, period 1024 (~21.333ms), buffer_size 32768 | Sampled **before** foreground capture; does not establish the period throughout playing or instantaneous buffered playback depth. |
| `pw-top ERR` | HDA output 0 initially, then 12 upon activation; two running rows stayed 12→12. WEBRTC VoiceEngine 18. | No time-aligned baseline, no XRUN-vs-error classification. 12 startup events cannot be attributed to forced quantum, and should not be added to other nodes. |
| CPU package temp | **94–98°C** (12 samples) | High temperature established. |
| `package_throttle_count` | cpu0 package **15811→15815 (+4)** | **Thermal throttle events occurred during the observation**. Cause, severity, effect on osu! frame tails or on audio timing remain unproved. Earlier statement that throttling was unverified applied only to the previous capture and is now superseded. |
| Subjective hitsound | "click and sound effect seem closer" but not clear difference | User impression, not physical latency measurement; no acoustic stimulus/response timestamps. |

Critical correction: changing PipeWire graph quantum from its default value to 256 does not necessarily change BASS output buffer/update period, the PipeWire follower's requested latency, HDA hardware period, or end-to-end audible latency. The prior conclusion that the active quantum was unverified is superseded **for the running ALC257 driver**, but remains unverified for BASS. See `AUDIO-VALIDATION-2026-11-07.md` and opt-in `scripts/osu-performance/audio-compare.py`.
