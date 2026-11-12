# neko5 osu!lazer Audio: measurement, causal identification and adoption protocol

**As of:** 2026-11-07 15:30 JST. **Decision:** Existing PipeWire, BASS, ALSA and game output behavior are unchanged by this document. No optimum has been demonstrated. The 15:30 user ZIP is the primary runtime observation; its SHA256 is in `architecture/facts-2026-11-07.json`. Old Library files with the same names are not trusted.

## Observations and independent time domains

| Boundary | Measured now | Meaning / limitation |
| --- | --- | --- |
| PipeWire settings metadata | rate=48kHz; default quantum=1024; **forced** quantum=256 | Both default and temporary force exist simultaneously; settings alone are not evidence of data-loop activity. |
| Sink driver | `alsa_output.pci-0000_00_1f.3.analog-stereo`, R, 256/48000, S32LE 2ch | ALC257 *graph driver* was active with a **5.333ms cycle**; no proof of 5.333ms full audio output latency. |
| Client follower | `alsa_playback.osu!`, R, 441/44100, F32LE 2ch | Client advertised **10ms suggested quantum** at 44.1kHz; not a measurement of BASS callback/stream period. Resampling or conversion can occur in PipeWire. |
| ALSA PCM (`hw_params`) | MMAP_INTERLEAVED S32_LE stereo 48kHz, period_size 1024, buffer_size 32768 | File was captured before switching foreground to osu!. There is no per-second hardware period trace. A 32768-frame ring capacity **is not 682.7ms physical latency**. |
| Sink `ERR` | Initial table: 0, then 12 on becoming running, then 12→12 in two consecutive R entries | `ERR` includes XRUNs and errors. Cannot attribute the 12 cumulative events to the quantum switch or assert there were 12 audible glitches. There are no continuous matched baseline measurements. |
| CPU package | 94–98°C; cpu0 package_throttle_count 15811→15815 (+4) in ~13s | Thermal throttling **did happen in this sample**. No proof it was caused by quantum, nor of resulting audio/gameplay performance loss. |
| Subjective | Little obvious change; some impression of earlier clicks/hitsounds | Useful hypothesis, no statistically or physically calibrated endpoint. |

### Distinct timing quantities (do not combine without instrumentation)

- Input `t_physical_contact` / `t_evdev` / `t_framework_received` / `t_judgement`.
- osu! Audio Thread `t_audio_Update`, BASS sample `.Play` enqueue `t_mixer_insert`, BASS device period `P_BASS`, output queue depth `Q_BASS`.
- PipeWire driver scheduling quantum `P_PW = Q_driver / R_driver`, follower requested `Q_follower / R_follower`, processing wake-up lag, ERR.
- ALSA actual PCM period, `snd_pcm_delay`/hardware pointer and DMA; DAC and analog amplifier latency; microphone acquisition timestamps, microphone pipeline and acoustic propagation.

A useful schematic for triggered samples is `t_acoustic = t_input + L_input+Update + L_sample_start + L_BASS_feed + L_PipeWire+ALSA + L_DAC+acoustic`. Fixed and random terms must be estimated separately. BASS sample starts can be quantized to its mixer period (`ppy/osu-framework#6650`). Track clock may incorporate startup delay and does not have identical timing semantics to on-demand hitsounds.

### Why 256 may not feel different

Shortening the PipeWire graph period while BASS continues to schedule on its own device/mixer period changes one queue boundary, not all boundaries. The osu! follower's 441/44100 suggestion signals a **10ms request**, while the sink driver executes 256/48000. This juxtaposition is **not** proof of effective hit-sound scheduling at 10ms; the actual BASS device information has to be obtained from the game's native audio backend. The hardware's ALSA period, amount of buffered audio (`snd_pcm_delay`), RT scheduling, and .NET Update/Draw stalls also remain possible constraints. A successful graph-level setting is a necessary but insufficient condition for audibly reducing sample-onset variance.

BASS primary documentation: <https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_PERIOD.html> (negative values specify samples, effective period returned via BASS_GetInfo) and <https://www.un4seen.com/doc/bass/BASS_CONFIG_DEV_BUFFER.html> (buffer may be rounded by device; min twice update period). PipeWire `pw-top`: <https://man.archlinux.org/man/pw-top.1.en.html>. PipeWire server setting: <https://docs.pipewire.org/page_man_pipewire_1.html>. osu!framework issue: <https://github.com/ppy/osu-framework/issues/6650>.

## Three verification levels: do not promote one to the next

**L1 — configured and applied (completed for 256 only).** Check `clock.force-quantum=256` *and* driver node `R 256 48000` while osu! is playing. Report the follower's advertised Q/R and hardware period separately. This establishes active graph scheduling only.

**L2 — stable operation / no-regression (not completed).** Repeat matched workload using a **0→256→0→256** sequence with equal time windows, same game/audio output hardware, same beatmap/replay/skin/Mods and matched temperature/cooling state. Log running-node ERR deltas *within each stable block*, first/last ALSA hw_params, temperature and package thermal-throttle *counter delta*, CPUFreq, Direct Scanout, and osu foreground. Record whether nodes restart / IDs change. Reject any condition with new audio dropouts, persistent XRUN delta or game performance regression, but do not infer absolute hit latency from this result. GPU/Update/Draw p99 needs separate instrumented capture—these scripts do not provide it.

**L3 — actual sample-onset latency / jitter (not completed).** Use the existing HyperX SoloCast to simultaneously capture a physical key click and the emitted hitsound from headphones or internal speakers, at a consistent short distance in quiet conditions. Keep physical distances fixed across conditions. Use a simple, repeatable map with spaced individual hits and distinct audio envelopes, and collect repeated paired events in each condition (preferably >=100 pairs for defensible upper-tail estimates). Align each click transient and corresponding hitsound in one PCM microphone recording (same ADC clock), compute per-pair Δt, then compare p50, p95, and confidence intervals via resampling across repeated trials; include false-match handling and annotate any missing hitsounds. **Caveat:** mechanical click does not equal electrical switch contact, the mic's noise processing may change onset, and headphone acoustic propagation differs by distance; the measurement is a *relative acoustic proxy*, not verified key-contact→DAC latency. For real electrical latency, use an electrically measured actuation marker and synchronized loopback/oscilloscope or an instrumented osu! fork + calibrated external timestamp reference. Neither exists in current evidence.

No software-only sysfs/pw-top/ALSA status can prove end-to-end click→audible onset to 1ms. Also, using a microphone introduces additional USB/audio work; measure it separately and do not treat it as an unperturbed performance run.

## One user action for L2: controlled, reversible experiment

From the nixfiles root, **with osu! already launched**:

```bash
nix shell nixpkgs#pipewire nixpkgs#python3 --command python3 scripts/osu-performance/audio-compare.py
```

Then focus osu! during the first 8 seconds; the script changes only shared `clock.force-quantum`, automatically records four 50-second blocks with 4-second warmups, resets to 0 at the end, and writes a `.tar.gz` in the current directory. It uses an advisory lock compatible with `osu-audio-quantum-lab` so the two cannot run simultaneously. It does not edit Nix configs, start/restart osu!, or enable SplitCast. It writes raw text snapshots of `pw-top`, PCM params, active-window checks and CPU temperature/throttle counters, plus parsed `experiment.json`. Use only with matching gameplay conditions and no production/recording workload. Cross-block absolute ERR values cannot be compared as simple raw totals; compare within-block differences for identical node identities.

Optional acoustic proxy: add `--record-mic` to that command to save four private 48kHz SoloCast WAV recordings; before doing so, ensure that keyboard clicks and emitted hitsounds are individually distinguishable in the capture and that no conversations or private audio will be inadvertently recorded. The recorder can change graph activity, so do not mix recorded and unrecorded trials. The WAV files might be tens of megabytes. The analysis of event correspondence requires manual inspection or a validated classifier; this tool does **not** claim to calculate physical latency automatically.

For just a shorter stability smoke: `... audio-compare.py --block-seconds 25`; **not** adequate for acoustic p99 claims. For a 128-frame test: `... audio-compare.py --quantum 128` only if 256 stability passes. If the experiment is externally SIGKILLed or power fails, check `osu-audio-quantum-lab status`; restore with `osu-audio-quantum-lab restore` only after ensuring no other intentional forced setting exists. Nothing should be made a permanent default yet.

### Adoption gates

1. **Correct comparison**: same output and workloads, reproducible across at least 2 balanced cycles; stream/sink actually running, not `C/0/0`; metadata force matched the measured driver rate/quantum in each condition.
2. **Audio integrity**: no sustained ERR increases beyond reference, no new dropouts, no audible pops, no sample-scheduling regressions. The given trace shows a 0→12 node activation transition; that alone does not establish an XRUN problem.
3. **Measurable latency improvement**: actual acoustic relative proxy onset distribution or calibrated electrical/audio capture supports effect (with uncertainty). Lower quantum alone is *not* a latency success criterion.
4. **No game regression**: Input, Update, Draw p95/p99/p99.9 and Direct Scanout remain at their game-only maxima within measurement resolution; thermal pressure accounted for. Audio graph changes share CPU scheduler and RT scheduling with game.
5. **Explicit adoption**: only then propose per-stream vs global PipeWire configuration and optionally BASS-specific changes with separate crash/rollback tests. A single successful manual trial cannot establish optimum. SplitCast captures remain off during the baseline; its eventual audio tap tested separately.

**Insufficient evidence even after L2:** BASS internal buffer depth, actual acoustic onset, Input→ruleset jitter, `snd_pcm_delay` while playing, and per-frame Update/Draw timings. Acquiring those requires controlled instrumentation, not simply another `pw-top` snapshot.

### Thermal protection in the experiment runner

Intel specifies **Tjunction = 100°C** for Core i5-10210U: <https://www.intel.com/content/www/us/en/products/sku/195436/intel-core-i510210u-processor-6m-cache-up-to-4-20-ghz/specifications.html>. Because user data already recorded 98°C and rising throttle counters, the collector monitors `x86_pkg_temp` while executing and **ends only the experiment** at a default 99°C, attempting to restore quantum 0. It does not change CPU voltage, fans or governor and never kills osu!lazer. A thermal stop is not a passing trial. Running the game for long periods at 94–98°C should be investigated independently of audio tuning; no safe sustained performance target is inferred from this short sample.
