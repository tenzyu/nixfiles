# Pull-request Nix validation

## Always-on gate

`.github/workflows/nix-validation.yml` always builds the existing
`framework-cli`, `deprecated-patterns`, and `feature-name-shape`
checks, runs the framework test suite and isolated T3 Serve tests, and
evaluates all three host system derivation paths. Evaluation is not a
build, boot, service activation, or runtime acceptance test.

## Additional checks driven by the diff

`scripts/ci/select-checks.py` compares the checked-out HEAD with its
first parent for pull requests; on push to main it uses the event's
`before` SHA, including multi-commit pushes. The checkout fetches full
history to make that base reachable. If Git cannot resolve the base, the
selector fails closed: it chooses all focused optional checks and
the SplitCast cache probe rather than silently skipping checks.
Test fixtures and pure library unit tests alone do not force unrelated
optional feature checks. Selection is deterministic, deduplicated and tested.

| Changed source | Additional check |
| --- | --- |
| Home modules or `assets/home-layout/` | `home-migration` |
| `home-authority.nix` and its enforcement fixture | `home-authority-vm` and `home-authority-seal-vm` |
| `nix-store-clean.nix` or `assets/nix-store-clean/` | `nix-store-clean` |
| `opencode-direnv.nix` or `assets/opencode/` | `opencode-direnv` |
| `rtk.nix` or `assets/rtk/` | `rtk-rewrites` |
| `flake.nix`, `flake.lock`, shared overlays, host declarations, or internal adapter implementation | All five focused optional checks and cache probe |
| Zsh, Firefox or common feature (owners of home migration rules) | `home-migration` |
| SplitCast media features (including cache settings) or `nix.nix` | SplitCast cache probe only |

These selected check derivations actually build. The always-on
`deprecated-patterns` and `feature-name-shape` derivations use
`lib.fileset.toSource` to include only their inspected Nix modules
(and `README.md` for deprecated patterns), so unrelated files do not
enter their static check source closures. The SplitCast `configs`
check currently depends on the Rust package; it is intentionally *not*
always built for an unrelated PR. It remains available as
`nix build --no-link .#checks.x86_64-linux.splitcast-configs`.
The manually dispatched `full-audit` job retains `nix flake check`.

## Physical HOME authority evidence

When HOME authority test inputs change, the selective-check mapping
includes both the independent `home-authority-seal-vm` and the
negative-control `home-authority-vm` as applicable. The former runs a
real physical-root syscall matrix and a second NixOS specialisation,
rolls back and reboots a disposable VM. The results are **not** evidence
for the user's physical host, nor do they automatically enable enforcement.

The VM emits a structured `home-authority-evidence.json` into its Nix
test output. CI validates and uploads the file as the
`home-authority-vm-evidence` artifact, retaining actual kernel,
filesystem, privilege, generation and service observations. A missing
report fails CI. The `root.enforce = true` Nix assertion remains closed
until privileged-host policy, reliable upgrade/rollback, and real clients
have independently passed the admission contract in
[ADR-0004](../adr/0004-home-authority-contract.md).

The final [CI #44986156842](https://github.com/tenzyu/nixfiles/actions/runs/44986156842)
confirmed all three evidence-related steps succeeded: VM export, static
host configuration evaluation, and artifact upload (ID `14739244772`).
The JSON deliberately reports
`vm_stale_fd_and_namespace=PASS` with
`two_generation_managed_links`, `reboot_services`,
`transition_writer_exclusion`, `privileged_physical_root`, and
`production_enforce` all **BLOCKED**. This is a passing *measurement
pipeline*, not an admission of `root.enforce = true`.

The artifact also contains `home-authority-host-evaluated.json`,
the evaluated `local.homeAuthority` configuration for neko5 and neko7.
This is **static configuration evidence only** and is marked
`runtime_observed: false`. It cannot establish the real filesystem type,
live process references, account-root authority or state cutover safety.

## SplitCast cache evidence

For selected changes, `scripts/ci/audit-splitcast-cache.sh` reads the
locked SplitCast revision, obtains the configured release substituter
from evaluated neko7 Nix settings, and obtains the real output store
paths of `splitcast`, `splitcast-web` and `splitcast-obs` from the
pinned SplitCast Flake input. It attempts bounded read-only NAR-info
queries against that substituter and records the results in the
GitHub Actions step summary.

A lock revision different from the cache release name is **not** a
proof of cache miss: store paths can be reused between source revisions.
A successful `nix path-info --store` call is *not* an independent
download/signature/build verification. Failed queries can mean missing
objects, network errors, inaccessible releases or timeouts.
Neither result proves neko7's current daemon is substituting from
this cache. Use real host-side store substitution logs for that claim.

The default CI probe remains diagnostic. At the reviewed baseline, SplitCast
and SplitCast Web NAR-info were **not confirmed**, while SplitCast OBS
metadata was reachable. That is not signed cache availability.

On demand, workflow_dispatch input `cache_strict=true` executes
`audit-splitcast-cache.sh --strict`. It copies each pinned package output
and its dependency closure into an isolated temporary local store. Nix must
accept it under `require-sigs=true` with the configured SplitCast key;
otherwise this separate job fails. Large closures are intentionally not
downloaded for every PR. Neither result proves real neko7 daemon substitution.

The consumer-specific URL and signing key live in
`modules/50-features/media/_internal/cache.nix`, projected only by
enabled SplitCast capture/production roles, not the common Nix feature.

## Validation and rollback

```sh
python3 -m unittest discover -v -s scripts/ci -p 'test_select_checks.py'
python3 scripts/ci/select-checks.py --base HEAD^
python3 scripts/ci/select-checks.py --base HEAD^ --cache-only
bash -n scripts/ci/audit-splitcast-cache.sh
```

CI configuration changes do not activate hosts or change their closures.
Rollback is a Git revert of the CI-only commit(s). On a `flake.lock`
change, the optional focused checks may take longer than the baseline;
a timeout is a failed verification, never an accepted build.
