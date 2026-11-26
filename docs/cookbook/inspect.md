# Read-only inspection

Run from the checkout in the existing direnv shell:

```sh
git rev-parse HEAD
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath
nix eval --json .#nixosConfigurations.neko5.options.services.openssh.enable.definitionsWithLocations --apply 'map (d: d.file)'
rg -n 'flake.modules.(nixos|homeManager).ssh' modules
```

Use the effective `config` for values and `options.<path>.definitionsWithLocations` for surviving definition locations. Native priority merging does not expose discarded definitions as current provenance. `nix repl` and nixd provide interactive exploration. The historical feature-trace CLI is archived.

```sh
nix build -L --no-link .#checks.x86_64-linux.validation
```

See [validation](ci-validation.md) for focused checks. No command here activates a host or moves data. `nixos-rebuild test` activates units and is not an inspection command. Stop on evaluation, build or permission failure.
