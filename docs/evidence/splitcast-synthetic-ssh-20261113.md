# Synthetic two-host validation on 2026-11-13

This test covers synthetic transport from neko5 to neko7. It does not run the SplitCast agent, OBS, GSR, or osu!.

The source is FFmpeg `testsrc2` at 320×180 and 15 frames per second, plus a generated 440 Hz sine wave at 48 kHz. FFmpeg encodes software H.264 and AAC on neko5. SSH stdout carries MPEG-TS to neko7, where FFmpeg records Matroska without re-encoding. A second pass decodes both recorded streams to a null output. Nothing opens a listener or reads a display, microphone, camera, or audio device.

## Isolation and cleanup

`packages/splitcast-rs/tests/synthetic_ssh.rs` is an ignored integration test that also compiles with standalone `rustc --test`. It uses no production configuration or agent code. Each run uses a unique transient user service name on both hosts, with these properties:

- `CPUQuota=100%`
- `MemoryMax=512M`
- `RuntimeMaxSec=660`
- `TimeoutStopSec=5`
- `KillMode=control-group`

The source has finite generated inputs. The remote shell stops its service on exit and handles HUP, INT, and TERM. Rust explicitly stops both services, including through a separate SSH connection, and checks that neither unit is active. A Rust cleanup guard repeats that cleanup on an assertion failure. A killed validation process cannot run its Rust cleanup guard. Remote exit handling and the service runtime limit provide fallbacks, not proof of immediate cleanup during total host or network failure.

Recordings and raw diagnostic files remain in mode-0700 directories under `/tmp/opencode/splitcast-synthetic-*` on neko7. They contain generated media only. The committed evidence omits account identities and unrelated machine logs. No key material is recorded.

## Reproduction

Prerequisites are explicitly authorized SSH execution on neko5, a working user systemd manager on both hosts, and the exact FFmpeg store path in the test. The cached FFmpeg closure was copied with `nix copy --to ssh-ng://neko5`, using the restricted validation key through `NIX_SSHOPTS`. This does not install a profile or activate NixOS. The complete local closure reports 1.4 GiB, much of which already existed remotely.

From the isolated worktree, compile the test with a cached Rust compiler and C linker:

```sh
/nix/store/wjc392lc9964vh7qiaz5gng3rz1lrdf2-rustc-wrapper-1.95.0/bin/rustc --edition=2021 -C linker=/nix/store/0592hadxldzhhd3ppc6nskslzd39fwlz-gcc-wrapper-15.3.0/bin/cc --test packages/splitcast-rs/tests/synthetic_ssh.rs -o /tmp/opencode/splitcast-synthetic-ssh-test
/tmp/opencode/splitcast-synthetic-ssh-test --ignored --nocapture
SPLITCAST_SYNTHETIC_SECONDS=600 /tmp/opencode/splitcast-synthetic-ssh-test --ignored --nocapture
SPLITCAST_SYNTHETIC_DISCONNECT=1 /tmp/opencode/splitcast-synthetic-ssh-test --ignored --nocapture
```

The last invocation kills the live SSH client after three seconds. It verifies explicit independent teardown, not recording validity or remote-trap-only behavior. The normal runs require successful source and sink exits, nonzero video and audio packet counts, duration within one second of the request, and successful full-file audio and video decode.

## Setup failures

- The first compile failed with `error: linker cc not found`. Selecting the cached C linker explicitly repaired the compile.
- The first closure copy hit the tool's 120-second timeout with `error: interrupted by the user`. The copy was retried without that tool timeout. No privilege or package-profile change was attempted.

## Results

The short run passed. Its evidence directory is `/tmp/opencode/splitcast-synthetic-1141418-1794550539590`.

| Requested duration | Recorded duration | H.264 packets | AAC packets | File size | Full decode |
| --- | --- | --- | --- | --- | --- |
| 10 seconds | 10.026 seconds | 150 | 470 | 482,800 bytes | Passed |
| 600 seconds | 600.022 seconds | 9,000 | 28,126 | 27,747,018 bytes | Passed |

Source, sink, and decode stderr files were empty. Both transport processes exited successfully. Explicit teardown verified both units inactive. A stop request after automatic unit collection printed `Unit ... not loaded`, which is consistent with an already absent unit, not a media error.

The 600-second run passed in `/tmp/opencode/splitcast-synthetic-1141560-1794550560866`. Its source, sink, and decode stderr files were empty. While it was live, `systemctl --user show` on both hosts reported `ActiveState=active`, `CPUQuotaPerSecUSec=1s`, `MemoryMax=536870912`, `RuntimeMaxUSec=11min`, `TimeoutStopUSec=5s`, and `KillMode=control-group`. The raw property snapshots are `local-unit-properties.txt` and `remote-unit-properties.txt` in that directory.

The disconnect probe passed in `/tmp/opencode/splitcast-synthetic-1149845-1794551171203`. Both transport processes were live before the Rust test killed the SSH client. Independent teardown then reported `LoadState=not-found`, `ActiveState=inactive`, and `MainPID=0` on both hosts. The interrupted file was not counted as a valid recording.

During the long run, the test's cleanup check was strengthened from an `is-active` exit-code check to successful `systemctl show` output with explicit `ActiveState=inactive` and `MainPID=0`. It now saves `local-teardown.txt` and `remote-teardown.txt`. The long-run recording used the earlier check, so those stronger snapshots were also collected separately after completion. Both hosts reported `LoadState=not-found`, `ActiveState=inactive`, and `MainPID=0`.

The final test version passed another complete 10-second recording in `/tmp/opencode/splitcast-synthetic-1149925-1794551182705`, including the stronger cleanup check. A negative invocation with `SPLITCAST_SYNTHETIC_SECONDS=1` failed with `only authorized 10s/600s runs` before starting any subprocess. The ordinary invocation without `--ignored` skipped the test, as intended.

Selected exact probe and teardown output is retained in [the text evidence log](splitcast-synthetic-ssh-20261113.txt). Recordings stay private and are not committed.

Final filesystem checks found all four owned service cgroups absent on both hosts. Together with control-group kill mode and inactive units with zero main PIDs, this verifies that these runs left no owned media service processes behind.

## Limits

GSR and gameplay validation are **BLOCKED**. The permitted environment has no GSR capability wrapper for privileged KMS capture. No privilege helper was installed, and desktop capture was not substituted. osu! was not launched. Official game files, bundled native libraries, input configuration, PipeWire routes, and Hyprland settings were not changed.

This synthetic SSH pipeline does not prove bounded frame age under congestion, production transport behavior, OBS integration, feature parity, native capture, direct scanout preservation, physical audio or input behavior, or impact on gameplay. The test uses low-resolution software encoding to bound resources, not to evaluate the target hardware path. It makes no latency, speedup, or game-performance claim. RuntimeMaxSec fallback enforcement is configured but not deliberately exhausted.

The constraints came from the task and the 2026-11-13 Wiki `MEMORY.md` and `wiki/SPLITCAST-TARGET.md` under `/tmp/opencode/splitcast-wiki-20261113/osu-llm-wiki`.
