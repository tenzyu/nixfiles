# SplitCast Nix gate evidence

This record covers build and evaluation gates for the uncommitted SplitCast work on `feat/splitcast-e2e`.

## Execution scope

The requested gates use `path:/home/tenzyu/.nixfiles` so Nix includes untracked source files. The checkout is shared with ongoing application fixes. Each command records its own source identity. Results apply to that command's source snapshot.

Only this document and `docs/evidence/*nix*.log` belong to this verification task. No code edits, staging, commits, activation, or service operations are part of this run.

## Checklist

- [x] Read `.local/AGENT_PROMPT.md`, the repository Nix skill, and `/home/tenzyu/.agents/skills/poteto-mode/SKILL.md`.
- [x] Inspect branch, revision, dirty state, flake outputs, and disk baseline.
- [x] Attempt the neko5 toplevel build with a 900-second limit.
- [x] Attempt the neko7 toplevel build with a 900-second limit.
- [x] Attempt `nix flake check --no-build` with a 900-second limit.
- [x] Enumerate and build applicable native checks.
- [x] Attempt VOICEVOX with a 600-second limit.
- [x] Record concrete failures, command statuses, elapsed wall time, source fingerprints, and final disk state.

## Baseline

At `2026-11-01T14:24:05Z`, Nix reports `nix (Nix) 2.34.9`. HEAD is `3cf330792d31df0721289d91e5643aa5fdee8f77`. The branch is `feat/splitcast-e2e`.

Tracked changes include both host configurations and `modules/50-features/packages-desktop.nix`. Untracked work includes SplitCast modules, packages, scripts, documentation, `.local/`, and `pstack-claude/`.

The initial `df -h / /nix /tmp` reports the same filesystem for all three paths, with 226 GiB total, 113 GiB used, and 103 GiB available.

Elapsed times in this record describe command execution and timeout handling. They are not performance measurements.

## Source identity method

Gate logs record UTC start and end times, HEAD, and a content fingerprint before and after execution. The branch is recorded in the initial gate logs and final manifest. The fingerprint is SHA-256 over sorted `sha256sum` records for Git-listed tracked and nonignored untracked files, excluding `docs/evidence/**` and the nested `pstack-claude` checkout. It covers file contents and names without recording their contents in the log. It is a working-tree identifier, not a Nix NAR hash. A changing fingerprint means concurrent edits occurred during the attempt.

The initial gate logs also record the tracked binary-diff SHA-256. Build logs record the package-tree SHA-256, which scopes source drift to `packages/splitcast`. Nix store source and derivation paths identify actual imported artifacts where evaluation reaches them. Start and end fingerprints cannot prove an atomic filesystem snapshot during concurrent edits. Ignored files and nested checkout contents are outside this fingerprint, although a path flake can import files outside that set.

The neko5 fingerprint pipeline encountered `pstack-claude/: Is a directory`. Its aggregate hashes cover the successfully hashed files and omit that directory. Later pipelines explicitly exclude it. The package fingerprint had no such error.

The working-tree fingerprint command is:

```sh
git ls-files --cached --others --exclude-standard -z -- . ':!:docs/evidence/**' ':!:pstack-claude' | sort -zu | xargs -0 -r sha256sum | sha256sum
```

The package fingerprint uses the same pipeline with `-- packages/splitcast`. The tracked-diff fingerprint uses `git diff --binary HEAD -- . ':!:docs/evidence/**' | sha256sum`.

Evidence files are excluded from these identifiers but are still present in the path flake. Checks using `lib.cleanSource ../..` can acquire new derivation identities as logs change. SplitCast's package source and both SplitCast check derivations stayed identical across the successful check builds and final flake evaluation.

## Results

The host build gates are not all green. neko5 passed for the earlier application snapshot. neko7 remains blocked by its 900-second realization limit. Four native checks passed. The fifth failed on a pre-existing self-matching lint. The exact requested flake evaluation command passed on its final attempt.

All timestamps below are the executor's actual UTC clock on `2026-11-01`. Elapsed seconds are recorded wall-clock durations around each Nix command. Each long command ran under `timeout --signal=TERM --kill-after=30s`, with the limit stated in its log. Exit 124 means that wrapper reached its deadline. Logs preserve combined stdout and stderr through `tee` with shell `pipefail`.

| Gate or attempt | UTC start | UTC end | Seconds | Exit | Result | Log |
| --- | --- | --- | ---: | ---: | --- | --- |
| neko5 toplevel | 14:24:48 | 14:36:42 | 714 | 0 | PASS for initial package snapshot | [neko5](splitcast-nix-neko5.log) |
| neko7 toplevel | 14:36:55 | 14:51:56 | 900 | 124 | BLOCKED at deadline | [neko7](splitcast-nix-neko7.log) |
| Flake evaluation, initial | 14:52:03 | 14:52:23 | 20 | 1 | BLOCKED by invalid store source, resolved on retry | [initial evaluation](splitcast-nix-flake-check.log) |
| `deprecated-patterns` | 14:52:55 | 14:53:07 | 12 | 1 | FAIL, pre-existing lint self-match | [native checks](splitcast-nix-native-checks.log) |
| `feature-name-shape` | 14:53:07 | 14:53:17 | 10 | 0 | PASS | [native checks](splitcast-nix-native-checks.log) |
| `home-migration` | 14:53:17 | 14:53:25 | 8 | 0 | PASS | [native checks](splitcast-nix-native-checks.log) |
| `splitcast-configs` | 14:53:25 | 14:53:53 | 28 | 0 | PASS | [native checks](splitcast-nix-native-checks.log) |
| `splitcast-package` | 14:53:53 | 14:54:07 | 14 | 0 | PASS | [native checks](splitcast-nix-native-checks.log) |
| Flake evaluation with trace | 14:54:30 | 14:55:36 | 66 | 0 | PASS, evaluation only | [trace retry](splitcast-nix-flake-check-retry.log) |
| VOICEVOX | 14:54:30 | 14:57:24 | 174 | 0 | PASS, package built | [VOICEVOX](splitcast-nix-voicevox.log) |
| neko7 remaining-plan diagnostic | 14:57:53 | 14:58:51 | 58 | 0 | Diagnostic only, no toplevel realization | [remaining plan](splitcast-nix-neko7-remaining.log) |
| Flake evaluation, exact command confirmation | 14:59:18 | 15:00:08 | 49 | 0 | PASS, evaluation only | [confirmation](splitcast-nix-flake-check-confirm.log) |

### Full gate commands

The host gates build closures without activating them:

```sh
nix build --no-link path:/home/tenzyu/.nixfiles#nixosConfigurations.neko5.config.system.build.toplevel
nix build --no-link path:/home/tenzyu/.nixfiles#nixosConfigurations.neko7.config.system.build.toplevel
```

The evaluation gate checks native output validity without building check derivations. The traced retry diagnoses the initial invalid-path failure:

```sh
nix flake check --no-build path:/home/tenzyu/.nixfiles
nix flake check --no-build --show-trace path:/home/tenzyu/.nixfiles
```

Native checks were enumerated with `nix eval --json path:/home/tenzyu/.nixfiles#checks.x86_64-linux --apply builtins.attrNames`. It returned five names with exit 0. `uname -m` returned `x86_64`, and `nix config show system` returned `x86_64-linux`.

Each native check was actually attempted, with its own status recorded inside the shared log:

```sh
nix build --no-link --print-out-paths --show-trace path:/home/tenzyu/.nixfiles#checks.x86_64-linux.deprecated-patterns
nix build --no-link --print-out-paths --show-trace path:/home/tenzyu/.nixfiles#checks.x86_64-linux.feature-name-shape
nix build --no-link --print-out-paths --show-trace path:/home/tenzyu/.nixfiles#checks.x86_64-linux.home-migration
nix build --no-link --print-out-paths --show-trace path:/home/tenzyu/.nixfiles#checks.x86_64-linux.splitcast-configs
nix build --no-link --print-out-paths --show-trace path:/home/tenzyu/.nixfiles#checks.x86_64-linux.splitcast-package
```

The optional TTS dependency build used:

```sh
nix build --no-link --print-out-paths path:/home/tenzyu/.nixfiles#splitcast-voicevox
```

### Failure provenance

The neko5 build progressed beyond Catppuccin IFD. It built Whiskers and Catppuccin derivations, then realized `/nix/store/49npcr5cc4s5mlzbjhdkl7paxjp9s00m-nixos-system-neko5-26.05.20261020.cd4ea8d.drv`. Its valid output is `/nix/store/vp6bn703n8262wz2qp4lkg58bxsxqvv9-nixos-system-neko5-26.05.20261020.cd4ea8d`. This pass does not cover the later application source edits.

The neko7 build evaluated successfully and planned 355 derivations plus 67 fetched paths, with 1.5 GiB to download and 4.2 GiB unpacked. It built the SplitCast production service definition and many existing host and container artifacts. At the deadline, its only terminal error was `error: interrupted by the user`, emitted when the timeout wrapper terminated the client. No hash mismatch, unavailable-network error, or SplitCast assertion failure appeared.

The follow-up command was `nix build --dry-run --no-link path:/home/tenzyu/.nixfiles#nixosConfigurations.neko7.config.system.build.toplevel`. It still planned 36 derivations and eight fetched paths, with 1.3 GiB to download and 3.8 GiB unpacked. The remaining plan includes existing NVIDIA, CUDA, llama-cpp, OpenJDK, and Minecraft dependencies, plus final system and updated application-dependent definitions. The target had changed from `/nix/store/gyjc2525fva281v5zzn6v25v6cfn3r2m-nixos-system-neko7-26.05.20261020.cd4ea8d.drv` to `/nix/store/0j270jd75qkr12pzb9n00wp9jxag6iqc-nixos-system-neko7-26.05.20261020.cd4ea8d.drv` after concurrent application edits. The remaining-plan diagnostic proves neither a completed host build nor a specific network failure.

An initially suspected `game.drv` dependency had no build-log body. Inspecting its derivation showed a generated executable using a write-text builder, not a downloaded game payload. It is absent from the remaining plan. The evidence does not justify blaming it for the timeout. See [game log query](splitcast-nix-neko7-game-diagnostic.log) and [corrected dependency inspection](splitcast-nix-dependency-diagnostic.log).

The initial flake evaluation stopped while checking `checks.x86_64-linux.splitcast-configs`, through `home-manager.users.tenzyu.local.features.splitcast-capture.configFile`. Its first concrete error was `path 'g64nm44win17wy9zxyxyf3ihlazx5522-source' is not valid`. The subsequent individual check built SplitCast from that exact store source and passed. Both evaluation retries then passed. The unavailable source was transient. Its underlying store or evaluator cause was not established, and the evidence does not identify a module bug.

`deprecated-patterns` failed with `failing check: deprecated patterns must be removed`. Its only reported matches were its own pattern strings at `modules/10-fundamental/checks.nix:20-23`. Line 14 excludes `modules/10-framework/checks.nix`, which does not exclude the current file. `git show HEAD:modules/10-fundamental/checks.nix` confirms the same stale exclusion and patterns at the starting revision. The canonical correction is to update that self-exclusion in the owning check. This task made no such edit. See [provenance](splitcast-nix-provenance.log).

Diagnostic mistakes are preserved. The enumeration log contains a failed pure `nix eval --raw --expr builtins.currentSystem` probe, followed by successful check enumeration. The first derivation-inspection filter expected an older JSON shape and failed on Nix's versioned `derivations` wrapper. The corrected inspection used `.derivations`. Neither diagnostic failure is an application gate failure.

### Source revisions and fingerprints

HEAD stayed `3cf330792d31df0721289d91e5643aa5fdee8f77` throughout. The tracked binary-diff SHA-256 stayed `8a53feac8ae9ac5f731007eaefa21195c7332a6ea2ea4a321e19f2642e86d991`.

| Identifier | SHA-256 |
| --- | --- |
| Working tree at neko5 start | `a6e908556bd5ac1e6edde2966cafbe372b7c5ce23d83bb5a8b748edb1af1d866` |
| Working tree at neko5 end and neko7 start | `2a9b53c7ba7762599d7f69afbc0ea8bd65d5dfad97878d4ce7f788a5297fe05a` |
| Working tree at neko7 end and all later gates | `1cc233b9370cfa46b9d3ec8dc9f8b21bd02b0fedc11abab050626a50af291566` |
| Package at neko5 start and end, and neko7 start | `b747443028de2b62d48084105c1c98fbffc2c9d62eda375e3fcbf6b92f85809c` |
| Package at neko7 end and all later builds | `6d1ca63d72d792ea30b332877fbab15df3ca5251cee143648dde5999297e80f3` |

The successful SplitCast check builds used package derivation `/nix/store/dkk241hszqdbs5g385y9kjg8bh12zv4i-splitcast-0.1.0.drv`, source `/nix/store/g64nm44win17wy9zxyxyf3ihlazx5522-source`, and output `/nix/store/illklarxvfspw633npgq25z3vvnncyyg-splitcast-0.1.0`.

`nix hash path /nix/store/g64nm44win17wy9zxyxyf3ihlazx5522-source` returned `sha256-NoWTSbG/02wqc51jWcKc9wQVkZtflNw2BlDwa42PcGg=` with exit 0. This is the actual NAR hash of the checked package source. The [package artifact log](splitcast-nix-package-artifact.log) records the derivation source mapping and build phases. That build log contains installation and fixup, without a unit-test phase. Package realization alone is not a unit-test result.

### Realized outputs

The final [artifact verification](splitcast-nix-final-artifacts.log) ran `nix path-info` on the following paths and exited 0:

```text
/nix/store/vp6bn703n8262wz2qp4lkg58bxsxqvv9-nixos-system-neko5-26.05.20261020.cd4ea8d
/nix/store/mbcy4d08ljlslfndkr75174v7rvgz28l-voicevox-engine-0.25.2
/nix/store/illklarxvfspw633npgq25z3vvnncyyg-splitcast-0.1.0
/nix/store/gi4kxdkwbxvia7ghj6nllw1d7n9kq1pi-splitcast-host-configs-check
/nix/store/kp8zyvvrk7vn53wmk1ramlhcawjq9mjc-splitcast-package-check
```

The successful generic checks returned `/nix/store/kdx2v522nkimdgyb1iljrglqh5hpv0fg-check-feature-name-shape` and `/nix/store/4w3p0dsrxma6p3y98hf0nc9lqaxyywvw-check-home-migration`.

`splitcast-configs` exercised both generated host configurations through the application config loader and checked role, peer settings, and packaged RNNoise and OBS paths. `splitcast-package` exercised CLI help, Python imports, example config loading, and a short FFmpeg RNNoise filter invocation. These passes do not establish live audio, capture, host connectivity, or TTS synthesis.

VOICEVOX realized models 0.16.4, wrapped core 0.16.2, and engine 0.25.2. Its output is available to the application worker. No VOICEVOX service was started.

## Remaining gates and final state

- neko7's full toplevel realization remains BLOCKED at the 900-second budget. The exact retry command is the neko7 build above. There is no concrete dependency build failure to fix from this attempt.
- The native `deprecated-patterns` check remains FAIL because of its existing stale self-exclusion. Its owner can correct that line and rerun the named check.
- neko5 passed against the earlier package fingerprint. Later application changes require their own scoped package verification and, where required for delivery, renewed host closure verification.
- Flake evaluation passed for `x86_64-linux`. Nix explicitly omitted `aarch64-darwin` and `aarch64-linux` as incompatible systems. No cross-platform check result is claimed.
- The successful no-build flake evaluation does not erase the failed check build. The overall required Nix build gates remain incomplete.

At `2026-11-01T15:00:32Z`, the final manifest recorded 226 GiB total, 115 GiB used, and 101 GiB available on the shared filesystem. Disk capacity did not produce an error. The final source and package fingerprints match the later gates above. The staging state remained unchanged, with the same tracked dirty files and untracked work categories.

The Prove It Works principle shaped the verification choice. Gate statuses come from executed commands, and reported output paths were checked against the real Nix store.
