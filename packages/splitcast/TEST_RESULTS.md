# Application verification

The defect-repair suite ran on 2026-11-01 in `/tmp/opencode/splitcast-app`. All 45 tests passed with no skips. It used Python 3.13.15, websocket-client 1.9.0, GSR 5.13.8, FFmpeg-full 8.1.2, MediaMTX 1.18.2, RNNoise plugin 1.10, loopback-patched OBS 32.1.2, pactl 17.0 against PipeWire 1.6.6, geckodriver 0.36.0, and Firefox 158.0.1.

The complete command was:

```sh
nix shell nixpkgs#gpu-screen-recorder nixpkgs#pulseaudio nixpkgs#python313 \
  nixpkgs#ffmpeg-full nixpkgs#mediamtx nixpkgs#geckodriver --command env \
SPLITCAST_OBS_BINARY=/nix/store/jrbma5c750j0c5lv7md06ms9if84zivk-obs-studio-splitcast-32.1.2/bin/obs \
SPLITCAST_RNNOISE_PLUGIN=/nix/store/l1cl9jjcsz2xc0vjhp0rimgmcg3bs0cy-rnnoise-plugin-1.10/lib/ladspa/librnnoise_ladspa.so \
PYTHONPATH=packages/splitcast:/nix/store/zm523bqamq1f8xsxlwqwm58cpg16wr10-python3.13-websocket-client-1.9.0/lib/python3.13/site-packages \
python3 -m unittest discover -s packages/splitcast/tests -v
```

The observed output ended with `Ran 45 tests in 53.705s` and `OK`. The actual OBS probe printed `delivered peak=0.18170166` for `MicProcessed`. It checked an uncorked source-output owned by the actual OBS PID and bound to the owned sink's monitor before launching RNNoise. Then it observed nonzero samples through OBS's `InputVolumeMeters` events. Temporary media, OBS profiles, Pulse modules, and browser profiles are cleaned up by the tests.

After publication through `apply_patch`, the same complete command ran from `/home/tenzyu/.nixfiles` and passed all 45 tests with no skips. Its output ended with `Ran 45 tests in 55.985s`, `OK`, and `delivered peak=0.18176270`. A directory comparison found no application or test differences between the worktree and main. The final process probe found no test agent, dedicated test OBS, MediaMTX, or geckodriver left running. Pulse sink enumeration contained no `splitcast_test_` sink.

The previous application suite passed 31 tests from both locations before these five defects were reported. Those tests did not cover late Pulse device connection, counter epochs, prepared owner abandonment, or local-account bearer retrieval. The new suite retains those 31 tests and adds 14 regression and actual-device tests. The Firefox and HTTP tests now cover the private CLI bootstrap instead of unauthenticated token retrieval.

## Defect evidence

| Defect | Before repair | After repair |
|---|---|---|
| GSR help status | Actual 5.13.8 `--help` printed valid flags and exited `1`; the generic probe rejected it | Help alone accepts `0` or `1`; actual `--info` succeeds and exact hardware `h264` passes; missing selections still fail doctor |
| Late processed sink | Actual OBS Pulse negative control stays disconnected when an unchanged device appears late | Real Backend Prepare creates the sink first; actual OBS source-output and RNNoise sample delivery pass |
| Counters across sessions | Controlled real Backend Start failed from cycle two with lower transport counters | Five cycles through real Backend and Media methods pass with controlled external observations; decreases rebaseline and a subsequent seven-second stall fails |
| Ready and abandoned owners | A separate run against the original main source killed real MediaMTX with exit `-9`; supervision still reported `ready` and `output=None` | Actual receiver death degrades and exhausts bounded retries; actual prepared OBS/receiver/sink cleanup passes on owner deadline expiry; authenticated HTTP tests reject wrong owners and wrong bearers and permit reclaim after expiry |
| Bearer disclosure | A forged `Sec-Fetch-Site: same-origin` request returned HTTP `200` with the private token | Unauthenticated metadata variants return errors without the token; real Firefox uses CLI fragment bootstrap, strips it, reloads from sessionStorage, isolates origins, and supports manual entry |

The initial nine-test regression run reported four assertion failures and eight errors. The errors included missing new APIs and repeated lifecycle failures, so that count alone is not proof of each defect. The actual probes and behavioral mismatches above are the evidence.

The production hardware doctor was bypassed only inside the focused OBS/Pulse integration fixtures because this capture host has Intel graphics and cannot satisfy production NVENC. Those fixtures test Prepare ordering, actual audio delivery, and cleanup. They do not establish a working NVENC output. The installed-GSR test runs real doctor and verifies that the unconfigured example fails closed.

## Integration coverage

| Area | Result | Observed evidence |
|---|---|---|
| Strict configuration and schema | PASS | Runtime schema equals `schema.json`; unknown fields, unsafe audio routes, invalid ports, and inconsistent camera settings fail |
| CLI and standalone agent | PASS | Real `python -m splitcast agent`, both config placements, authenticated status, clean SIGTERM shutdown |
| HTTP control | PASS | Real requests start and stop synthetic session children; wrong token, Host, Origin, MIME type, and oversized or malformed JSON fail |
| Lifecycle | PASS | Five cycles with actual owned subprocesses; duplicate Start does not duplicate PIDs; Stop leaves no live owned children |
| Failure handling | PASS | Partial start rolls back, receiver loss degrades and exhausts retries, missing capability never reaches Ready, speech loss preserves healthy game output |
| Process groups | PASS | Stop kills a descendant after its leader exits; probe timeouts kill owned groups; child restart budget is enforced |
| Media transport | PASS, synthetic | Actual FFmpeg-generated H.264/AAC RTMP plus independent Opus RTSP and H.264 camera RTSP reach MediaMTX; received files are probed and decoded; sender loss is observed |
| RNNoise | PASS, synthetic | Actual LADSPA plugin processes 48 kHz PCM samples; processed output differs from dry samples |
| Speech return | PASS, synthetic | VOICEVOX-shaped HTTP exchange produces an identified WAV, returned through authenticated control HTTP, consumed by a separate synthetic playback process with the selected sink argument |
| Speech bounds | PASS | Queue limit, deduplication, expiry, invalid WAV rejection, mute cancellation, and skipping the current job without dropping the next job |
| OBS protocol | PASS, synthetic | Real websocket-client exchange with a synthetic OBS protocol endpoint; challenge authentication, opcodes, unique request IDs, event and stale-response handling |
| Browser | PASS | Real headless Firefox loads the page, prepares, starts default recording, renders untrusted doctor text without creating markup, and stops |
| Real OBS Pulse connection | PASS, synthetic audio | OBS 32.1.2 source-output binds during Prepare; actual RNNoise samples reach `MicProcessed`; Stop removes the source-output and owned sink |
| Ready and lease cleanup | PASS | Real MediaMTX death degrades Ready; expired prepared production stops actual OBS and MediaMTX and unloads the owned Pulse module |
| Browser authentication | PASS | Real CLI `ui`, immediate fragment removal, sessionStorage reload, different-origin isolation, wrong-token rejection, and manual token entry |
| Diagnostics | PASS | Export keys are allowlisted and do not include an injected secret-bearing error |

Initial failures led to these corrections before the final passing run:

- MediaMTX reports the AAC track as `MPEG-4 Audio`. Readiness now normalizes the codec label.
- The RNNoise 1.10 LADSPA descriptor exposes five controls. The tested example supplies `50|200|0|0|0`.
- The schema parser copies input data so caller mutations cannot alter a parsed role or redirect a live production agent.
- Playback acknowledgement tracks the current job, so Skip cancels it without dropping the next queued job.
- OBS uses the actual `async_delay_filter` filter ID for camera delay.

| Hardware or integration gate | Status | Reason |
|---|---|---|
| GSR capture and real game-only audio | NOT_RUN | Capability and help probes ran; no screen or camera frames were captured |
| Raw physical microphone to processed Pulse monitor to real OBS | NOT_RUN | The actual Pulse/OBS path passed with synthetic Opus mic audio; no physical input was opened |
| Local or production physical camera capture | NOT_RUN | This worker was instructed not to capture cameras |
| Actual OBS 1080p60 NVENC recording | NOT_RUN | Requires the dedicated patched package, display session, and GPU integration trial |
| SSH cross-host media and control | NOT_RUN | Local TCP transports and authenticated return were tested; a real SSH session was not started by this worker |
| Twitch and live EventSub | BLOCKED | No streaming authorization or private Twitch credentials were supplied to this worker |
| Real VOICEVOX and audible local playback | NOT_RUN | The automated return test uses a synthetic service and playback consumer |
| 10-minute and 30-minute synchronization and drift | NOT_RUN | Requires real media markers and the hardware acceptance run |
| Game frame-time and CPU/GPU comparison | NOT_RUN | No game or capture benchmark was run |
| NixOS builds and deployment | NOT_RUN | Owned by the separate Nix and coordinator work; this worker performed no deployment |
| Independent application review | BLOCKED | Nested agents were prohibited in this worker |

The application implements the requested paths, but these results do not establish daily-operation hardware acceptance. OAuth refresh and automatic recovery of a lost OBS or SSH process are not implemented. The operator renews credentials or runs Stop, Doctor, Prepare after those failures. No output is automatically switched to Twitch.
