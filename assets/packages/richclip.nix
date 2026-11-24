{
  lib,
  rustPlatform,
  pkg-config,
  sqlite,
  python3,
}: let
  src = (builtins.fetchTree {
    type = "github";
    owner = "dstoc";
    repo = "richclip";
    rev = "6ac7f21e7d1db887ffbf7dc4de3f4097c05c09d2";
  }).outPath;
in
  rustPlatform.buildRustPackage {
    pname = "richclip";
    version = "0.1.3";
    inherit src;
    cargoLock.lockFile = "${src}/Cargo.lock";
    # Nix's Rust packaging uses the system SQLite instead of the vendored
    # libsqlite3-sys copy. Both richclip binaries link against libsqlite3.
    nativeBuildInputs = [pkg-config];
    buildInputs = [sqlite];
    # review_activation_dispatch spawns a Python Wayland wire fixture.
    # Keep the regression test enabled without adding a runtime dependency.
    nativeCheckInputs = [python3];
    cargoBuildFlags = ["-p" "richclip" "-p" "richclip-wayland"];
    cargoTestFlags = ["-p" "richclip" "-p" "richclip-wayland"];
    preCheck = ''
      export HOME="$(mktemp -d)"
      unset WAYLAND_DISPLAY WAYLAND_SOCKET
    '';
    postInstall = ''
      test -x "$out/bin/richclip"
      test -x "$out/bin/richclipd"
    '';
    meta = {
      description = "Multi-MIME Wayland clipboard history";
      homepage = "https://github.com/dstoc/richclip";
      platforms = lib.platforms.linux;
      mainProgram = "richclip";
    };
  }
