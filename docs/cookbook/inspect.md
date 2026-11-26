# Read-only inspection

Run these commands from the checkout in the active direnv shell:

```sh
git rev-parse HEAD
nix flake show
nix eval .#nixosConfigurations --apply builtins.attrNames --json
nix eval --raw .#nixosConfigurations.neko7.config.system.build.toplevel.drvPath
nix eval --json .#nixosConfigurations.neko5.options.services.openssh.enable.definitionsWithLocations --apply 'map (d: d.file)'
rg -n 'flake.modules.(nixos|homeManager).ssh' modules
```

Read effective values from `config`. Find the locations of surviving definitions in `options.<path>.definitionsWithLocations`. Native priority merging does not expose discarded definitions as current provenance. `nix repl` and nixd provide interactive exploration. The historical feature-trace CLI is archived.

```sh
nix build -L --no-link .#checks.x86_64-linux.validation
```

See the [focused validation commands](ci-validation.md). No command here activates a host or moves data. `nixos-rebuild test` activates units and is not an inspection command. Stop on evaluation, build or permission failure.
