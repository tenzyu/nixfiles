# Rust completion evidence

## Goal and evidence boundary

Make neko5 to neko7 SplitCast usable under Rust ownership without changing official osu!lazer or sacrificing local gameplay. This report distinguishes target, source facts, local observations and blocked live checks. It is not a cutover approval.

The attached Wiki was extracted outside Git at `/tmp/opencode/splitcast-wiki-20261113/osu-llm-wiki`. Its private raw evidence is not included in this repository. Read order was `entrypoints/OPENCODE.md`, `MEMORY.md`, `wiki/INDEX.md`, `wiki/CONTRACT.md`, `wiki/SPLITCAST-TARGET.md`, then `wiki/SCENARIOS.md`.

## Reference and running system

| Item | Observation |
| --- | --- |
| Fetched origin/main | `6ceeb53b0d1e267fa01f04c94fdb6226877c93cf` |
| Reference capture time | 2026-11-13 14:43 JST |
| Original checkout | Local main at `cd9fece`, five local commits retained unchanged |
| Work branch | `splitcast-rust-completion-20261113`, based on fetched origin/main |
| Execution host | neko7 |
| neko7 running generation | `/nix/store/j1wxm4gnqk19ga8b3fpgi81i1zcpg2pl-nixos-system-neko7-26.05.20261020.cd4ea8d` |
| neko7 named user services | `splitcast-agent.service`, `splitcast-production.service`, `splitcast-capture.service` reported inactive |
| neko5 initial access | Default SSH identity failed with `Permission denied (publickey)`. This was an initial observation, not a continuing connectivity diagnosis. |
| neko5 subsequent access | The operator installed the task-specific restricted public key. Authenticated command execution then succeeded. No PTY, agent forwarding or port forwarding was granted. |
| neko5 running generation | `/nix/store/1f59zcfqr9dw9qwkvy3kka3fdk8zs1d9-nixos-system-neko5-26.05.20261108.ac588ef` |
| neko5 kernel | `7.3.3`, observed through authenticated SSH |
| Final reference re-fetch | `origin/main` was still `6ceeb53b0d1e267fa01f04c94fdb6226877c93cf` at 18:53 JST, before this run's publication. |

The running generation is not inferred from Git. No NixOS activation or production service change was performed.

## Initial verification

The first offline Cargo test attempt could not link because the shell had no `cc`. Adding a C compiler repaired the environment. This failure is not behavioral red evidence. Later tests reproduced actual lease, HTTP, process, credential and configuration bugs before their fixes.

## Implementation and verification status

| Area | Implemented source | Verification and remaining boundary |
| --- | --- | --- |
| Configuration | TOML-first input, transitional JSON, one native strict validator, finite routes, bounded credential reads | TOML equivalence, negative cases and a 46-case frozen Python-oracle corpus pass. This is config coverage, not full behavioral parity. |
| Views | Rust TUI and Rust/WASM, using `splitcast-protocol`; generated browser glue has no business logic | Scripted TUI driver, actual CLI/loopback HTTP tests, three shared-protocol tests, three native web-model tests and the revised WASM package build pass. A live browser interaction test is not established. |
| State and authority | Phase variants hold inbound authority, outbound preparation obligations and selected output; peer IDs are a validated type | Local emergency Stop, correct-owner renewal, local ownership protection, expiry-before-command, recording idempotency, lost-Prepare cleanup and unconfirmed-Stop retry pass. |
| Worker ownership | Typed worker collection, pinned process identity through teardown, bounded native helper I/O | Real early-exit and TERM-ignoring descendant tests pass. Process-group escape and controller SIGKILL require the declared service cgroup. |
| Production audio | Owned, cookie-authenticated private Pulse server with a null sink, no hardware modules | The opt-in real-daemon test passed readiness, process-group shutdown, failed post-stop connection and socket-file cleanup. This is not an end-to-end microphone or forced-controller-death trial. |
| Receiver and OBS | Native Rust HTTP and WebSocket control, strict loopback addressing, progress observations, private state, preview protocol | Local real socket/WebSocket fault tests pass. Actual GSR-fed OBS decode, screenshot and recording are not accepted. |
| Speech | Native bounded synthesis worker with cancellation, expiry, replay IDs and finite retries | Component tests pass against a local HTTP peer. Delivery, playback, remote mixing, persistent replay and EventSub remain incomplete. The live command path refuses those features rather than reporting silent success. |
| Route editing | Strict local selection patches while Idle, persistent private settings | Cross-host shared camera/TTS selection transactions are not implemented and are explicitly refused. Arbitrary processor/target graph editing is not implemented. |
| Recovery and budgets | Heartbeat failure stops owned capture; failed workers and stalled progress stop the session; finite service and transport resources | No automatic Twitch restart. Full reconnect/recovery parity, per-stage latest-frame semantics and GPU-aware quality degradation are not established. |
| Nix | Both package names select Rust; TOML generation, stock-secure OBS binding policy, gated service, cgroup cleanup and stream-only resource limits | The final repaired Rust/WASM package and `splitcast-configs` check passed. Built `selfcheck` passed without media, and `validate` accepted the example. Built offline Doctor reported `ok=false`, with no selected capture source and no cutover approval. |

The former Python implementation and related Python scripts are removed. Before removal, the delegated baseline ran 55 package tests with 10 skips and 18 script tests. The frozen config corpus preserves only its declared cases. It does not justify claiming every deleted test has been ported. Historical Git and NixOS generations, not a retained Python runtime, are the rollback source.

The final complete ordinary Cargo run passed 102 tests, with the real audio and synthetic SSH tests ignored by default. Clippy passed all targets with warnings denied. A separate empty-`PATH` invocation passed the native receiver HTTP test. The opt-in private audio test also passed. [Selected red and green output](../evidence/splitcast-rust-regressions-20261113.txt) records the observed failures and results. Full local logs remain outside Git at `/tmp/opencode/splitcast-accepted-final-cargo.log`, `/tmp/opencode/splitcast-accepted-final-clippy.log` and the paths named in that evidence file.

Final host evaluation, without activation, returned `captureEnabled=false`, `captureRust=false`, `captureServicePresent=false` and `productionRust=false`. The production feature remains configured, but its `ExecStart` selects the migration gate and `WantedBy` is empty. The service uses `KillMode=control-group`, `TimeoutStopSec=20`, `UMask=0077`, `CPUWeight=25`, `Nice=10` and `MemoryMax=2G`. An initial query used the wrong service attribute name and failed; the corrected query read `splitcast-production`. The machine-readable result is `/tmp/opencode/splitcast-final-gates.json`.

The final repaired package is `/nix/store/jdmqn5j3bp29h69vszaxb13nl7191sas-splitcast-rs-core-0.1.0`; the successful config check is `/nix/store/pars44nmircdfjzpvs06ih7h49wvqw4q-splitcast-host-configs-check`. The build log is `/tmp/opencode/splitcast-accepted-final-nix.log`. The installed artifact's `selfcheck`, `validate` and offline `doctor` results are in `/tmp/opencode/splitcast-accepted-installed-*`. A build produced store paths only, without an activation or service start.

## Real two-host evidence

The synthetic-only SSH test produced a 600.022-second recording on neko7 from generated H.264/AAC on neko5. It contained 9,000 video packets and 28,126 audio packets and passed full-file decoding. A deliberate SSH-client kill also passed independent teardown checks. Both hosts' owned units and cgroups were absent afterward. See [the reproducible test and raw evidence](../evidence/splitcast-synthetic-ssh-20261113.md).

An independent local probe of the existing artifact confirmed the same codecs, packet counts, duration and 27,747,018-byte file size. A second full decode mapped both streams with `-xerror` and exited zero with an empty error log. This did not rerun any physical capture or host operation.

This used 320×180 at 15 fps with a synthetic sine wave. It was not the Rust agent's media transport, did not run OBS, and did not capture the game, microphone, camera or desktop. It proves neither the nominal 1280×720/60/12Mbps path nor bounded frame age or competitive performance.

## Permissions and resource boundaries

- No game executable, bundled SDL/BASS/framework, renderer setting, input mapping, local output route, firmware or NixOS generation was changed.
- No production service was started or replaced. No public listener or Twitch output was started.
- Credentials are private owned files. No operational control token, OBS password, Twitch key or SSH private key is included in Git or this report.
- Synthetic transport used verified limits of one CPU equivalent and 512MiB per media unit, with an eleven-minute runtime limit. These are configured and observed limits, not measured utilization or latency.
- Actual neko5 game-plus-stream CPU/GPU/temperature/frame-time distributions and neko7 production GPU/VRAM/CPU/memory load remain unmeasured. No speedup, physical latency or zero-impact claim is made.
- The old five local commits on the original checkout's main were not rebased, discarded or overwritten.
- After the permitted host checks finished, the task-specific `splitcast-validation-20261113` authorization was removed from neko5. The same SSH session verified that no matching authorized-key line remained. Repeating an opt-in host test now requires renewed operator authorization.

## Design and review

The accepted design uses a portable command model, phase-owned authority and output, a typed worker collection and process-owned production audio. The tradeoffs and rejected shapes are in [the implementation wiki](wiki/design.md). The actor still needs further separation of role-specific runtime capabilities. That architectural limit is not hidden behind extra traits or success labels.

An independent GPT-6 Luna read-only review covered revision `50d8ef3` and kept cutover closed. It did not reproduce a source bug or verify the subsequent phase/audio changes. Worker limits initially blocked further reviews. Fresh correctness and comment reviewers ran after resuming.

The later independent correctness reviewer accepted disabled partial publication, not cutover. It reproduced four defects against the actual binary with stub workers and a loopback peer. All four are repaired in `0fbad46` and independently rechecked:

1. Configuration and API selections now use the same raw-microphone predicate as the TUI. Monitor and processed source names are rejected. This validates selection names, not a live device's provenance.
2. Peer compatibility compares the complete validated camera object before remote Prepare, rejecting conflicting capture and production publishers.
3. Owner-bearing requests derive from phase-owned remote preparation, recorded only after compatibility succeeds. Refused and lost Prepare responses still trigger owner-scoped cleanup. Unconfirmed Stop preserves the obligation, stops local workers and refuses false Idle until an explicit release succeeds.
4. Successful remote microphone observations are validated and refresh capture-side `mic_muted` status.

The original reproduction output is `/tmp/opencode/splitcast-independent-sol-probe.log`. Its test harness did not open physical audio, camera or game devices. The independent follow-up ran all 19 actual-artifact integration tests successfully and re-evaluated both deployment gates. Evidence is `/tmp/opencode/splitcast-independent-sol-followup-integration.log` and `/tmp/opencode/splitcast-independent-sol-followup-gates.json`. Its verdict approves disabled partial publication only. Feature parity, live media acceptance and competitive non-regression remain open.

The comment review returned 21 removal recommendations covering 25 lines. All 25 lines were removed. Local helper names now identify single-read fairness and WebSocket error redaction. No runtime behavior changed. No comments were restored, and no rerun was requested. Two dependency-related holds remain, concerning uninterruptible kernel I/O and remote SSH-session cleanup guarantees. The review's proposed extra TUI abstraction and synthetic-test cleanup redesign are not implemented; existing TUI redaction tests pass, and synthetic disconnect evidence retains its stated limits. No new constraint encoding was added. The complete ordinary Cargo suite and warning-denied Clippy passed again after this cleanup in `/tmp/opencode/splitcast-post-review-cargo.log` and `/tmp/opencode/splitcast-post-review-clippy.log`.

## Completion gates

- Feature completion is **PARTIAL**, not merely awaiting approval. Speech delivery, EventSub, shared route transactions, full recovery and other tabled requirements are unfinished.
- Synthetic two-host transport is VERIFIED within its stated scope. Complete two-host SplitCast is NOT VERIFIED.
- GSR and competitive non-regression are BLOCKED. The required privileged KMS helper is absent; no privilege helper was installed or desktop-capture substitute used. No active-game non-regression trial was performed. Historical DSO observations do not validate this candidate.
- Production migration is NOT AUTHORIZED. Preserve both deployment gates and require separate approval for Twitch publication.

## Rollback and approval gates

Keeping `rustCandidate=false` does not run Rust implicitly after Python removal. It selects a fail-closed launcher, and the service has no autostart target. The neko5 capture feature stays disabled. A package build or Git push does not activate either host.

Recover the former implementation from reference `6ceeb53b0d1e267fa01f04c94fdb6226877c93cf` in a separate checkout, or select an already-existing generation only with operator approval. Do not overwrite local work. Enabling capture, selecting Rust services, changing NixOS generations, installing a privileged capture helper and publishing Twitch output are separate approval decisions. No merge or force-push is part of this run; the operator subsequently authorized direct ordinary publication to main and waived a PR.
