{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "adr02-directory-boundary";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;
  cargoBuildFlags = ["--locked"];
  cargoTestFlags = ["--locked"];
  auditable = false;

  # This opt-in build produces a test receipt instead of an installed library.
  installPhase = ''
    touch "$out"
  '';
  meta.platforms = lib.platforms.linux;
}
