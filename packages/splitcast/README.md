# Operate SplitCast

SplitCast keeps the player's game audio local and sends production inputs to a separate host. One Python agent on each host owns only the subprocess groups it starts. systemd is the outer process boundary. Stop leaves the control API available.

This package contains the application, schema, example, browser controls, and tests. The Nix package and host modules are maintained separately. Hardware capture, a real OBS/NVENC recording, Twitch, and long-duration synchronization still require the hardware acceptance tests. Synthetic tests do not establish those results.

## Configure both roles

Use `example.json` as the complete version-1 configuration. Every field is required. Unknown fields are rejected. `schema.json` is the emitted structural schema. The runtime also checks finite route connections, matching camera enablement, unique ports, loopback VOICEVOX, stable camera paths, and application-only game capture.

Keep these root fields unchanged:

```text
version role peer capture audio camera obs tts routes
```

On production, set `role` to `production` and `peer.control_port` to `17871`. On capture, use `role=capture` and `peer.control_port=17870`, with `peer.remote_control_port=17871` and `peer.forward_control_port=17872`. The latter is a capture-side SSH forward, not another production listener. Production does not initiate a reverse connection, so its remote-control and forward-control fields are unused.

The `peer` object supplies the SSH host and port, control ports, credential paths, state directory, retry limit, and readiness timeout. Use an existing SSH host alias or `user@host`. SSH is batch-only, verifies the existing host key, and opens loopback forwards for both media transports and remote control. Production's remote-owner lease lasts `max(30, 8 * peer.timeout_seconds)` seconds. This derives the deadline from the operation timeout with a minimum of 30 seconds. Capture sends authenticated owner heartbeats during both Ready and Running supervision. Another owner cannot renew, start, or stop that session. An expired lease stops owned production infrastructure and output before a new owner can prepare it. A locally prepared production session has no remote lease and cannot be claimed remotely.

The capture agent forwards local `1935` to production `1935`, local `8554` to production `8554`, and local `17872` to production `17871`. MediaMTX also serves its API on production `127.0.0.1:9997`. OBS uses `127.0.0.1:4455`. VOICEVOX uses `127.0.0.1:50021`. No application listener binds a public interface. Media URLs contain no passwords. Media access is confined to the host and SSH account boundary.

The control agent creates a random token at `peer.token_file` if the file is absent. Provision a private copy of production's token on capture at `peer.remote_token_file`. All credential files must be owned by the agent user and private, normally mode `0600`. Provision `obs.password_file` on production before Prepare. `obs.twitch_key_file` is read only for an explicitly selected Twitch start. Configuration holds paths, never token or password values.

For EventSub, `tts.credentials_file` on production contains this private JSON object:

```json
{
  "client_id": "YOUR_CLIENT_ID",
  "access_token": "YOUR_USER_ACCESS_TOKEN",
  "refresh_token": "YOUR_USER_REFRESH_TOKEN",
  "broadcaster_user_id": "YOUR_BROADCASTER_ID",
  "user_id": "YOUR_TOKEN_OWNER_ID"
}
```

The token needs `user:read:chat` and the Twitch permissions required for the selected broadcaster. Obtain a refresh token through Twitch's authorization code flow. For a confidential client, also add `client_secret` to the private JSON file. The application validates the client, user, and scope. If Twitch returns HTTP 401, it attempts a refresh and atomically replaces both tokens in the private file. An adjacent private lock file prevents simultaneous refreshes. The application creates a `channel.chat.message` EventSub WebSocket subscription and makes at most four connection attempts after failures. If refresh fails or the grant is revoked, authorize again, replace the private file, and use `tts on` to restart a finished listener. The refresh path has not been tested against live Twitch credentials.

## Select actual inputs

Run the production agent and capture agent. Use discovery to list both hosts' stable camera paths, camera formats, Pulse sources and sinks, GSR capture targets, and GSR application audio names. Discovery does not capture camera or screen frames.

Set `capture.target` explicitly. `portal` uses the interactive desktop portal selection. A monitor target captures that monitor, not an OpenGL hook or an automatically verified game-only window. Set `capture.game_audio` to `app:EXACT_GAME_NAME`. Sink-monitor audio, combined audio selectors, and the SplitCast-TTS application are rejected.

Set `audio.mic_source` to the raw physical input. Set `audio.tts_sink` to a chosen local output. SplitCast never changes the default sink or moves the game to a remote monitoring path. TTS playback has the Pulse application name `SplitCast-TTS` and is excluded from game application capture.

For a camera, set `camera.enabled`, its route's `enabled`, `camera.location`, and its stable `/dev/v4l/by-id/` path. `mode=h264` copies native camera H.264. `mode=hardware` requests YUYV and explicitly uses `h264_vaapi` or `h264_nvenc`. VA-API also requires `camera.hw_device`. Choose an exact width, height, and frame rate from discovery. There is no software-video-encoding fallback in application commands.

Camera selection is shared between the two configurations. Saving camera or TTS selections through the capture control API saves those selections on production through SSH first. Both agents must be idle. A failed remote save prevents the local save. A local disk failure after a successful remote save can leave selections different; Prepare detects that difference and refuses to start.

Set production `audio.rnnoise_plugin` to the RNNoise LADSPA library. Plugin 1.10 was tested with `rnnoise_label=noise_suppressor_mono` and `rnnoise_control=50|200|0|0|0`. These are VAD threshold, grace, retroactive grace, and two placeholder ports. Doctor executes synthetic samples through the actual filter and refuses readiness if its controls do not match the installed plugin.

Production decodes the independent mic stream over RTSP/TCP, resamples it to 48 kHz, runs LADSPA RNNoise, a high-pass filter, gain, and a limiter. FFmpeg writes the processed samples to the explicitly named `audio.processed_sink`. OBS captures only that sink's `.monitor` source. This path does not install or run RNNoise on capture.

The mic audio offset uses OBS's audio sync offset. `camera.offset_ms` adds a nonnegative OBS asynchronous video delay. Independent transports and fixed offsets do not establish A/V synchronization. Measure markers, drift, and reconnect behavior on the hardware before daily-use acceptance.

## Use the CLI

The development entry point is:

```sh
PYTHONPATH=packages/splitcast python -m splitcast agent --config /path/to/config.json
```

The Nix wrapper names it `splitcast`. `--config PATH` and `--config=PATH` work before or after the command. Supply it exactly once, before any standard `--` argument delimiter. These invocations are equivalent:

```sh
splitcast --config /path/to/config.json status
splitcast status --config /path/to/config.json
splitcast agent --config /path/to/config.json
```

The available operations are:

```sh
splitcast --config CONFIG doctor --offline
splitcast --config CONFIG doctor
splitcast --config CONFIG devices
splitcast --config CONFIG routes
splitcast --config CONFIG routes --settings '{"capture":{"target":"portal","game_audio":"app:osu!"}}'
splitcast --config CONFIG ui
splitcast --config CONFIG prepare
splitcast --config CONFIG preview --output /tmp/production-preview.png
splitcast --config CONFIG start
splitcast --config CONFIG start --output recording
splitcast --config CONFIG mic mute
splitcast --config CONFIG mic unmute
splitcast --config CONFIG tts on
splitcast --config CONFIG tts mute
splitcast --config CONFIG tts unmute
splitcast --config CONFIG tts skip
splitcast --config CONFIG tts clear
splitcast --config CONFIG say 'A test comment' --id unique-message-id
splitcast --config CONFIG overlay 'Current map'
splitcast --config CONFIG diagnostics --output /tmp/splitcast-diagnostics.json
splitcast --config CONFIG stop
```

`doctor --offline` probes this host without an agent. `ui` reads the owning user's private token file and prints a private fragment URL. Other commands use the loopback agent. Doctor returns exit code `1` for unavailable capabilities. Command errors return `2` and a JSON error on stderr. Successful commands return JSON on stdout, except `ui`, which prints its URL. Doctor accepts GSR's documented help output with exit code `0` or `1` only for `--help`. Other probes require exit code `0`. The GPU check requires the exact `h264` capability from `--info`; `h264_software` alone does not pass.

Prepare checks capabilities, opens SSH, authenticates production, verifies shared routes, and starts the owned production receiver and isolated OBS. It creates the owned processed-mic Pulse sink before OBS creates `MicProcessed`. It does not start capture, the mic processor, or any output. Ready means the infrastructure is prepared. Its preview can remain blank until Start. Start on capture launches the senders, starts a selected production camera if applicable, waits for moving production media, starts processed mic audio, checks OBS decoding, and activates the selected output. Running requires observed media, processed samples, and output bytes. Output activation never uses an automatic public-stream selection.

`start --output twitch` explicitly activates the public Twitch output and reads the production-only key file. This worker did not execute that command. Stop before changing the output. Recording is always the default.

Mic and TTS accept `status`. TTS also accepts `off`. Runtime toggles do not rewrite the base config. Persist startup preferences with `routes --settings '{"tts":{"enabled":true}}'` while idle. Use `mix_remote=true` to add the separate `obs.tts` target. The queue holds at most `tts.queue_limit` jobs, including the current synthesis and playback. Text, audio size, audio duration, age, retries, and the replay ledger are bounded. Acknowledged jobs are not replayed after ambiguous connection failures. This is at-most-once playback and may drop speech during a failure.

## Use browser controls

Run `splitcast --config CONFIG ui` as the user who runs the agent. Open the printed `http://127.0.0.1:PORT/#token=...` URL in your browser. Treat this bootstrap URL as a private credential. The browser removes the fragment from its current history entry immediately and keeps the token in `sessionStorage` for that origin. Reloading the same tab keeps its authentication. A different port or origin needs its own token. The fragment never enters an HTTP request, query string, or agent access log.

If you open the bare address, such as `http://127.0.0.1:17870/`, use **Control token** and **Connect**, or open a fresh CLI bootstrap URL. Controls stay disabled until authentication succeeds. The HTTP API never returns the bearer token. Forged `Sec-Fetch-Site` headers grant no access. Requests require the token, a matching Origin, an exact loopback Host, finite JSON, and a finite request body deadline. Cross-origin requests and redirects are rejected. The UI renders discovery data and errors as text. Diagnostics export a fixed allowlist and never include raw logs, environment, process arguments, config dumps, speech text, or credentials.

To check a private recording and preview through the capture page:

1. Select **Discover both hosts** and set **SSH host**, **Capture target**, **Game audio**, **Raw microphone**, and **TTS playback sink**. Set **Enable selected camera**, **Camera host**, **Stable camera device**, and **Camera mode** if needed. Select **Save selections while stopped**.
2. Select **Doctor**. Fix every failed check before proceeding. **Show routes** displays the saved selection and routes.
3. Select **Prepare connection**. `ready` confirms owned infrastructure, not incoming media or a successful recording. The preview can remain blank.
4. Keep **Private recording** selected. Select **Start selected output**. This starts capture and writes a recording. Wait for `running`.
5. Select **Refresh preview** to inspect the production image. Use **Mute mic** or **Unmute mic** as needed.
6. Select **Stop**. This stops recording, capture, and owned production infrastructure. It leaves the control agents available.

There is no preview-only capture mode. This workflow writes a private recording. **Twitch public stream** requires explicit selection before **Start selected output**. **TTS on**, **TTS off**, **Mute TTS**, **Unmute TTS**, **Skip speech**, **Clear queue**, **Say**, **Update overlay**, and **Diagnostics** provide the remaining runtime controls.

## Recover and stop

State is one of `idle`, `preparing`, `ready`, `running`, `degraded`, `failed`, and `stopping`. Ready supervision checks owned children, the receiver API, the processed sink, and authenticated OBS or the capture owner's remote heartbeat. A failed infrastructure check degrades Ready and exhausts the configured retry budget before cleanup. A successful prepared retry returns to Ready with no output. It never promotes infrastructure-only readiness to Running. Running supervision also checks moving media, processor progress, and output bytes. Byte counters reset for each session and rebaseline when a publisher or output counter decreases. A small configured retry budget permits sender or mic-processor restarts. A lost OBS or SSH process requires an explicit Stop, Doctor, Prepare cycle after the budget expires. No recovery automatically selects Twitch or restarts the game. TTS failures appear separately and do not stop healthy game media.

Stop terminates only owned process groups in reverse order, even if a group's leader has already exited. It unloads only the Pulse module ID the agent created. It never kills by process name. A missed remote Stop is reported so you can stop production locally before reconnecting. systemd must use its outer cgroup to handle a killed agent. A SIGKILL without that cgroup can leave a runtime Pulse module; inspect it before retrying, because Prepare refuses to reuse an existing processed sink.

OBS runs with a dedicated `XDG_CONFIG_HOME` under `peer.state_dir/production/obs-config`. Its profile and scene collection are named `SplitCast`. Existing user OBS files are not read or overwritten. OBS's WebSocket port must be unused and must be provided by the dedicated loopback-patched build. Authentication and the observed listener address are checked before setup. The profile requests 1080p60 H.264 NVENC for recording and streaming. A real OBS output test is still required to verify the deployed package and GPU.

Settings overrides use atomic replacement in `peer.state_dir/ROLE/settings.json`. The base JSON remains unchanged. To revert selections, stop the session and agent, archive that overrides file, and restart the agent with the original config. Recordings are kept in `obs.recording_dir`. Keep generated OBS state private because OBS can persist its runtime stream key. Credential values are never passed in child argv or included in diagnostics.

## Run meaningful tests

The base suite needs Python 3.13 and websocket-client. To exercise all integrations, place FFmpeg with LADSPA and libx264, ffprobe, MediaMTX, GSR, pactl, geckodriver, and Firefox on PATH. Set `SPLITCAST_RNNOISE_PLUGIN` to the real plugin `.so`. Set `SPLITCAST_OBS_BINARY` to the loopback-patched OBS executable for the real Pulse and OBS tests. These use an owned null sink and synthetic audio, not a physical microphone. The GSR probe reads capabilities without capturing screen or camera frames.

```sh
PYTHONPATH=packages/splitcast python -m unittest discover -s packages/splitcast/tests -v
```

The tests use temporary state directories and synthetic media. The real transport test sends generated H.264/AAC game media, independent Opus mic audio, and a separate generated H.264 camera stream through MediaMTX, reads them over RTSP/TCP, probes and decodes the received files, and verifies source loss. Only that explicit synthetic test uses CPU video encoding. The RNNoise test runs actual synthetic samples through the LADSPA plugin. The speech test uses a synthetic VOICEVOX HTTP endpoint, authenticated audio return, and a synthetic playback consumer instead of a sound device. Firefox drives the actual browser controls and checks untrusted text rendering.

Tests also exercise the real CLI and agent process, HTTP authorization and limits, strict schema, five complete lifecycles, five cycles through the real Backend and Media methods with controlled external observations, publisher and output counter resets, bounded Ready degradation, authenticated lease expiry and reclaim, partial-start rollback, dead-leader group cleanup, speech expiry, deduplication, cancellation, and the OBS authentication/request-ID protocol. The real Pulse test checks OBS source-outputs and nonzero `MicProcessed` volume-meter samples after RNNoise delivery. A negative control confirms that the actual Pulse plugin does not reconnect an unchanged device that appeared late. Firefox exercises CLI bootstrap, immediate fragment removal, reload, origin isolation, manual token entry, recording controls, and untrusted result text. Missing optional test binaries produce explicit skips, not hardware passes.
