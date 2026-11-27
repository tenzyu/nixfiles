# Materialized Catppuccin evaluation inputs

These three directories contain ordinary source files reproduced from the pinned Catppuccin Nix packages. They are not a binary cache, imported derivation outputs, or a new signing authority. The manifest binds each directory to the exact upstream derivation and NAR content. A changed upstream derivation automatically uses the original package instead of stale data. Nix checks the declared content hash when using the materialized path.

Generate/update from the repository root:

```sh
python3 assets/catppuccin-materialized/verify.py --refresh
python3 assets/catppuccin-materialized/verify.py --require-current
```

Review the generated source and upstream licenses together. Ordinary regression and native machine gates are unchanged. A changed source subtree is independently reproduced before admission; integration pushes independently reproduce matching inputs again. Stale entries fall back to native packages; no IFD prohibition is imposed on unrelated future configuration.

Initial source provenance: Catppuccin Nix revision `30ad3b76f1b20ed045d1dfd10ac2f3d89ff1df50`, independently reproduced in GitHub Actions run 45948487626, job 140338584096. Port revisions: Firefox `1aa345a3312f0a649068418679ceb81a9c599d36`, palette `07d02aa110ef9eb7e7427afca5c73ba9cf7f8ebd`, Starship `5906cc369dd8207e063c0e6e2d27bd0c0b567cb8`. MIT licenses are included outside the hashed data directories.
