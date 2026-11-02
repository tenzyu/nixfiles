# SplitCast architecture decisions

## Scope and evidence

SplitCast moves production off neko5 without rerouting the player's game audio through neko7. The implementation contract is `.local/AGENT_PROMPT.md` and the attached handoff's `docs/IMPLEMENTATION_CONTRACT.md`. Acceptance IDs remain A01 through A15.

The initial revision is `3cf330792d31df0721289d91e5643aa5fdee8f77`. Work uses `feat/splitcast-e2e`. Existing untracked `.local/`, `docs/`, `scripts/`, and `pstack-claude/` are user work.

Initial observations on 2026-11-01 came from `hostnamectl`, `ssh -o BatchMode=yes neko7`, `nvidia-smi`, `pw-cli info 0`, `v4l2-ctl --list-devices`, and `vainfo`. neko5 runs NixOS 26.05 with PipeWire 1.6.6 and the Hyprland portal. Intel iHD exposes H.264 hardware encoding. NearStream V02AF and TOSHIBA Web Camera devices are present locally. neko7 is a NixOS VM with RTX 4060 Ti and driver 595.71.05. Its PipeWire and display manager are inactive. These observations do not establish successful capture or production.

## Alternatives and synthesis

Two independent read-only explorations compared systemd ownership of every component with a Python agent owning the session's children. OpenCode exposes one general-agent model and no model selector. This was independent exploration, not a diverse-model panel.

| Shape | Benefit | Cost | Decision |
|---|---|---|---|
| One systemd unit per route | Native individual cgroups and restart limits | Cross-host readiness and rollback still need a controller | Keep systemd only as the outer lifecycle boundary |
| One agent per host | One state machine, dynamic device selection, reverse-order rollback | Requires bounded child supervision and explicit ownership | Selected for this personal two-host implementation |

Each agent owns only children it creates. systemd cleans the outer cgroup. Stop never targets process names, the game, the default audio sink, or existing OBS instances. The control API remains available while media is stopped.

## Shared implementation contract

The application lives under `packages/splitcast/`. The entry point is `python -m splitcast` with `PYTHONPATH=packages/splitcast`. Nix wraps it as `splitcast`. Dependencies are Python, websocket-client, GSR, FFmpeg with Pulse support, PipeWire tools, Pulse tools, MediaMTX, V4L2 tools, and a dedicated OBS package.

Configuration is versioned JSON. Its root has `version`, `role`, `peer`, `capture`, `audio`, `camera`, `obs`, `tts`, and `routes`. Configuration contains credential paths, never credential values. The application supplies an example and schema with exactly the fields it accepts. Nix generates role-specific configuration using that example's schema. Runtime overrides have one owner and use atomic replacement.

Routes are finite Source → Processor → Target records. The lifecycle uses explicit idle, preparing, ready, running, degraded, failed, and stopping states. A listening socket is not proof of a ready media route. Unavailable capabilities fail preflight with an actionable reason. Output activation is separate from prepare. Recording is the default output. Twitch requires explicit selection and remote credentials.

The control CLI provides `agent`, `doctor`, `devices`, `prepare`, `start`, `stop`, `status`, `routes`, `mic`, `tts`, `say`, `preview`, `overlay`, and `diagnostics`. The browser UI uses the same command handlers. Loopback HTTP mutations require an origin-bound token. Cross-host access uses existing SSH with explicit loopback forwarding. No firewall ports are added.

## Media choices

GameFeed starts with combined H.264 and game audio in RTMP/FLV through SSH. GSR is the first backend. The observed stable binary is 5.13.8. Its actual help includes `-encoder gpu` and `-fallback-cpu-encoding no`. Screen capture is labelled screen capture, not an OpenGL hook. The application must select application-only audio to keep returned TTS out of GameFeed.

MicFeed and a local CameraFeed use separate RTSP/TCP paths through SSH. SRT/UDP cannot pass through ordinary SSH TCP forwarding. A remote camera uses an explicitly selected V4L2 input. Discovery checks both hosts and preserves the chosen location. No local software-video-encoding fallback is automatic.

RNNoise runs on neko7. FFmpeg LADSPA or a PipeWire filter-chain may supply processing, but the completed path must feed processed samples to OBS separately from GameFeed. Installing the plugin alone is insufficient.

Independent microphone and camera transports do not prove synchronization. Fixed offsets and resampling are configuration, not an A12 pass. Game A/V markers at 0, 10, and 30 minutes, drift, and reconnection must be measured. If the independent paths fail, shared-clock GStreamer RTP/RTCP is the next transport experiment. RTMP, SRT, WebRTC, and RTP performance have not been compared.

TTS jobs carry IDs and expiry. The queue, text, generated audio, retry count, and replay ledger are bounded. A dedicated local playback target keeps TTS out of game capture. Optional production mixing is a separate target. VOICEVOX and Twitch credentials stay on neko7.

## Legacy audit

`git apply --check` rejected `references/neko5-neko7-streaming-complete.patch` at the current neko5 host definition. It was not applied. Reusable ideas include combined GameFeed, separate mic, OBS create-or-update requests, and bounded TTS. Wildcard media listeners, passwords in URLs or argv, assumed device names, unbounded restart loops, and overwriting existing OBS profiles are rejected. Camera forwarding and remote RNNoise require new implementation.

## Verification workflow

1. Record the pre-change inventory and preserve existing audio routes.
2. Implement the application, Nix integration, and measurement tools in separate worktrees.
3. Verify application behavior and real synthetic media before integration.
4. Build both host toplevels and run applicable flake checks.
5. Exercise reachable hardware without activating a NixOS generation or starting a public stream.
6. Record each A01 through A15 result with its command and evidence. Missing permissions or credentials are BLOCKED. Unstarted tests are NOT_RUN.

The completion predicate is an implemented, packaged control and media path with reproducible tests and honest remaining hardware gates. Daily-operation acceptance additionally requires all applicable A01 through A15 evidence. Build success alone does not satisfy that acceptance.
