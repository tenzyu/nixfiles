# Consume the independent SplitCast flake

SplitCast source is not vendored here. The `splitcast` input provides packages, NixOS prerequisites and the Home Manager agent module. The local feature files only import those modules and map existing role-enable settings. Host files supply peer settings through `home-manager.users.<user>.services.splitcast.settings`.

The input uses `github:tenzyu/splitcast`, published at https://github.com/tenzyu/splitcast. `flake.lock` pins the revision. Update this input with `nix flake update splitcast`. A lock update does not deploy SplitCast.

The capture role remains disabled. The production integration remains configured, but `services.splitcast.rustCandidate` remains false and the user unit has no autostart target. No operating-system switch or service start is part of this extraction.

Run SplitCast's own verification from its repository. This consumer reuses its package and configuration checks, rather than retaining a second implementation or test suite. The independent repository's `docs/operations.md`, `docs/design-review.md`, `docs/verification.md`, and `MEMORY.md` are the current references. The historical graphics research and isolated experiments were transferred there as non-current evidence.

Before any later deployment, evaluate the actual consumer configuration, inspect the selected package and generated TOML, confirm cgroup teardown and credential ownership, and obtain separate authorization for physical capture, privileges, firewall changes, public publication and activation. Restoring a Git input does not itself restore a running generation.
