# SplitCast isolated hardware evidence

Observed 2026-11-01T23:34:41+09:00.

Short isolated hardware-path checks. These results do not pass A01-A15 or current app acceptance.

| Subtest | Status | Observed result |
|---|---|---|
| remote_inventory | PASS | OBS Studio - 32.1.2; 0 remote camera nodes; display=False; PipeWire=False; Xvfb=False; sudo -n=False. |
| remote_nvenc | PASS | NVIDIA GeForce RTX 4060 Ti, 595.71.05. h264_nvenc, 1080p60, 10s. Decoded 600 video frames; 600 H.264 and 470 AAC packets. FFmpeg only. |
| local_camera_1 | PASS | NearStream, MJPEG 1280x720 at 30 fps to h264_vaapi to RTSP TCP loopback. Five-second receive, 142 packets and 142 decoded frames. |
| local_camera_2 | PASS | Toshiba, MJPEG 1280x720 at 30 fps to h264_vaapi to RTSP TCP loopback. Five-second receive, 143 packets and 143 decoded frames. |
| raw_mic_remote_rnnoise | PASS | HyperX SoloCast Analog Stereo, 3s raw sample, 36 PCM packets. SSH file transfer, remote private Pulse RNNoise, 42 processed PCM packets. No listening-quality judgment. |
| remote_voicevox_local_null_playback | BLOCKED | built VOICEVOX engine executable absent; model and core artifacts alone are not an engine |
| game_capture | BLOCKED | no running osu! window detected; no desktop capture attempted |
| tailscale_path | PASS | direct; online=True; active=True; SSH target matches peer tailnet IP=True. |
| remote_obs_nvenc | BLOCKED | no isolated Xvfb/display available |
| real_twitch | NOT_RUN | real Twitch excluded by authorization |
| long_sync_soak | NOT_RUN | 10/30 minute acceptance outside short hardware run |
| fault_injection | NOT_RUN | disruptive faults excluded by authorization |
| current_app_acceptance | NOT_RUN | app code changes independently; stale closure is used only for runtime binaries |
| preserve_local_audio_routes | PASS | Default source, default sink, and surviving playback stream routes unchanged. |

## Reproduction

```sh
/nix/store/bp92j4bqak0r1scr4afhzi1r1zpicxsv-python3-3.13.15-env/bin/python scripts/splitcast/hardware.py --remote neko7 --package /nix/store/pl7g7h76d8ajbgib6fyx14bwhlp0m78q-splitcast-0.1.0
```

The existing runtime closure was transferred with `nix copy --to ssh://neko7 /nix/store/pl7g7h76d8ajbgib6fyx14bwhlp0m78q-splitcast-0.1.0`. This is a store transfer, without activation.
The tool invokes media binaries directly. It does not run the package app or validate stale app code.

## Boundaries

The camera checks use stable by-id discovery and a supported advertised mode. Five-second receive recordings use at most nine seconds of camera input. H.264 input is copied; MJPEG or YUYV uses explicit VAAPI encoding. Software input and receive decoding are allowed. There is no software video encoding fallback.

Raw microphone capture lasts three seconds. The short WAV transfers as a file over SSH before remote processing; this is not live mic streaming. Only metadata and content hashes survive. RNNoise uses a private remote Pulse instance with an owned Unix socket, without restarting the user audio server.

VOICEVOX is synthesized only when a built engine exists. Successful audio returns through SSH and plays to an explicit owned null sink. This does not prove audible headphone playback, mute, skip, or mix-minus.

All media and private logs are temporary and removed. The worker has a 90-second deadline. Spawned processes have owned process groups and bounded TERM/KILL cleanup. No fault injection, Twitch connection, activation, generation change, or public listener is requested.

The JSON contains JST timestamps, sanitized argv, actual binary versions, recording metadata, statuses, route hashes, and cleanup observations. USB serials, tailnet addresses, full status output, window titles, and raw audio/video are excluded.

## Limits

Ten seconds of FFmpeg NVENC is not OBS NVENC or full A08. Five-second camera transport is not remote OBS composition or lip sync. The mic sample does not establish perceptual noise reduction. No benchmark, latency, drift, or game performance result is claimed.

Model the Domain shaped the per-subtest status records. Prove It Works shaped the encode, packet/frame probe, full decode, listener checks, and before/after route comparison.
