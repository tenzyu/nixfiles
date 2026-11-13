# Design decisions and rejection rules

## Goal

Streaming observes authorized game output. It must not modify or schedule work inside official osu!lazer. Remote failures may stop streaming, never gameplay. All application logic is Rust. Native video tools remain separate media workers owned by Rust.

## Accepted structures

| Decision | Why | Executable guard |
| --- | --- | --- |
| A portable command crate serves all views. | TUI and WASM must not invent different start or validation semantics. Effects remain in the native agent. | Protocol tests reject unknown arguments and default Start to recording. |
| TOML and transitional Nix JSON enter one native validator. | Configuration format must not bypass route or privacy constraints. | Frozen oracle corpus and TOML equivalence tests. |
| Session owns lifecycle and selected output. | A second output flag can disagree with the actual transition. | Explicit-publication lifecycle and repeated-start regressions. |
| Agent owns leases and resources. | A peer must not claim local preparation, revive an expired lease, or prevent local emergency Stop. | Lease tests include a positive matching-owner renewal. |
| Authority belongs to the session phase. | Idle cannot retain a peer lease, and Running cannot exist without a selected output. Parallel optional fields permit both mistakes. | `lifecycle::Phase` carries authority and output only in the variants that can hold them. |
| Capture's outbound preparation obligation also belongs to its phase. | Connectivity and an accepted handshake do not establish cleanup authority. A lost Prepare response can still require rollback. | Record a fresh remote owner immediately before compatible Prepare; retain it through Failed and Stopping until release is confirmed. A rejected handshake never records an owner. |
| Worker identity is a finite enum and teardown visits the owned collection. | A separate string-based cleanup list forgets newly added workers. | The worker teardown test includes audio, speech and tunnel workers without a second stop list. |
| Production audio uses an owned private Pulse server with only a null sink. | A module loaded into a shared audio daemon survives controller SIGKILL. Its lifetime must follow the owned process and enclosing cgroup instead. | The ignored real-daemon test verifies readiness, shutdown, failed socket connection and socket-file cleanup. |
| Child identity remains unreaped until group teardown. | An exited leader can leave descendants, and a reaped PID can be reused. | Real TERM-ignoring descendant tests use `/proc` observations. |
| An outer service cgroup remains mandatory for crash containment. | A process group cannot contain `setsid` escape or clean itself up after controller SIGKILL. | Nix keeps `KillMode=control-group` and `SendSIGKILL=true`. A live forced-death check remains a separate gate. |
| Requests, outputs and queues have explicit bounds. | Slow or malicious consumers must not retain unlimited memory or suspend lease checks through HTTP parsing. | Absolute HTTP deadlines, duplicate framing, bounded subprocess output and stalled OBS regressions. |
| Media health uses track types and advancing counters. | A path name or an open socket does not establish useful media. | Game, audio-only microphone, missing-track, counter-reset and stall tests. |
| Fail closed before cutover. | Removing Python must not make `rustCandidate=false` silently start Rust. | Nix service selects a migration-gated executable while the flag is false. |

## Rejected designs

| Rejected design | Failure | Replacement |
| --- | --- | --- |
| Append string-based dispatch and JSON fragments to one CLI file. | Parsing, state and view decisions diverge. JSON quote trimming corrupts valid text. | Typed portable commands, native JSON parsing, agent module and separate views. |
| Treat `jq -e false` as a malformed boolean. | Disabled camera and TTS are valid configuration. | Native boolean parsing and positive disabled-feature fixtures. |
| Declare success after killing or reaping only the leader. | Descendants can retain audio devices, sockets and GPU work. | Pinned identity through TERM and KILL, followed by reaping and cgroup containment. |
| Restart the read timeout after each byte. | A slow client can keep one operation alive forever. | One absolute deadline across the transaction. |
| Treat any audio sink monitor as game audio. | Discord, microphone or TTS can enter the stream without consent. | Only an explicitly selected `app:` game branch. Local playback is not rerouted. |
| Compare absolute timestamps from two unsynchronized hosts. | The difference includes an unknown clock offset. | Local monotonic progress observations and relative speech expiry. Physical latency requires separate measurement. |
| Assume KMS capture or hardware encoding is free. | Copy, fences, memory bandwidth and thermal costs can affect Draw and Direct Scanout. | Source inspection followed by an authorized live non-regression gate. No portal fallback or renderer change to hide failure. |
| Keep Python as a hidden runtime fallback. | The process owner is not actually migrated. | Remove Python source and delegates. Rollback uses an earlier Git revision or existing NixOS generation. |
| Use a tunnel worker as permission to stop a remote session. | Discovery and compatibility rejection also create tunnels. | Derive every owner-bearing request from the phase's remote preparation obligation. |
| Put lifecycle, validation or publishing decisions in JavaScript. | Views become independent controllers. | Rust/WASM browser logic and generated loader glue only. A future desktop view uses GPUI. |

## Limits that tests must not conceal

Incoming MediaMTX byte progress does not prove fresh decoded pixels, bounded age in GSR or OBS, or Direct Scanout preservation. Native-tool queue flags are not measured end-to-end latency. A synthetic SSH recording is not a Rust-agent or gameplay acceptance test.

The actor serializes effects. Individual external operations need deadlines, but a collection of bounded calls is not an immediate cancellation guarantee. Keep aggregate shutdown and lease timing visible in live tests. Never describe the controller as real-time.

## Remote ownership repair sketch

Independent review reproduced Stop after a rejected Rust-peer handshake. Two read-only design sketches compared an optional Agent-owned peer handle with role-specific phase-owned obligations. The synthesis keeps the existing phase transitions and nests capture preparation authority inside them. It avoids an independent Agent field and avoids duplicating the entire lifecycle by role.

Usage remains `prepare`, session controls and `stop`. Session records `CaptureAuthority::LocalOnly` before compatibility and `CaptureAuthority::RemoteAttempt(OwnerId)` immediately before the remote Prepare request. Ready capture requires a remote attempt. Failure and Stopping retain it. Confirmed release clears it; unconfirmed release prevents transition to Idle and permits an explicit retry. Discovery never changes this authority.

The native actor performs network effects. Its owner-bearing request helper obtains the owner from Session and serializes the shared command type. `record_remote_attempt(owner)`, `remote_owner()` and `remote_released()` keep the obligation in `lifecycle.rs`. The actor's permanent random owner string is deleted. A shared raw-microphone predicate belongs to native configuration validation and is reused by the TUI. The camera compatibility contract copies the complete validated camera document rather than maintaining another field list.

This is a focused repair, not completion of role-specific backend separation. A full separate CapturePhase and ProductionPhase was rejected for this unit because it duplicates existing transition machinery without being needed to fix the reproduced cleanup defect.

Before enabling capture or Rust service selection, verify the complete feature contract, two-host failure recovery and competitive non-regression. Retain a failed or blocked result instead of changing the acceptance rule to fit the implementation.
