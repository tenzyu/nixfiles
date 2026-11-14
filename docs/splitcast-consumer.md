# Consume the independent SplitCast flake

SplitCast source is not vendored here. The `splitcast` input provides packages, NixOS prerequisites and the Home Manager agent module. The local feature files only import those modules and map existing role-enable settings. Host files supply peer settings through `home-manager.users.<user>.services.splitcast.settings`.

The input pins the verified cache candidate `d2205d06b0dc695c3d9b7372fafa7facee769fa9` from https://github.com/tenzyu/splitcast. It keeps SplitCast's own Nixpkgs lock because overriding Nixpkgs with `follows` changes store paths and prevents cache hits.

`modules/50-features/nix.nix` configures the candidate's GitHub Release cache and the public key from `nix/cache-public-key` at that revision. Signature checks remain enabled. The release is `nix-cache-d2205d06b0dc695c3d9b7372fafa7facee769fa9-43561723796-1`. Its manifest SHA-256 is `fbc58a9d412b7a7c4e59f37c21835fc5cf464e677603f534bf355db43c688387`.

To select a later cached candidate, update the revision in `flake.nix` and the cache URL together, verify its signing key and successful consumer job, then run `nix flake update splitcast`. A lock update does not deploy SplitCast.

The capture role remains disabled. The production integration remains configured, but `services.splitcast.rustCandidate` remains false and the user unit has no autostart target. No operating-system switch or service start is part of this extraction.

Run SplitCast's own verification from its repository. This consumer reuses its package and configuration checks, rather than retaining a second implementation or test suite. The independent repository's `docs/operations.md`, `docs/design-review.md`, `docs/verification.md`, and `MEMORY.md` are the current references. The historical graphics research and isolated experiments were transferred there as non-current evidence.

Before any later deployment, evaluate the actual consumer configuration, inspect the selected package and generated TOML, confirm cgroup teardown and credential ownership, and obtain separate authorization for physical capture, privileges, firewall changes, public publication and activation. Restoring a Git input does not itself restore a running generation.
