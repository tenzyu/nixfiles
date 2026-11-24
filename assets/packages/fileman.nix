{
  lib,
  rustPlatform,
  pkg-config,
  wrapGAppsHook4,
  cmake,
  gtk4,
  libadwaita,
  libarchive,
  pigz,
  ffmpeg,
  poppler-utils,
  rclone,
  fuse3,
  ntfs3g,
}: let
  src = (builtins.fetchTree {
    type = "github";
    owner = "0znio";
    repo = "fileman";
    rev = "5b06a25011a13c46464072ddbda6e98e2db82fb1";
  }).outPath;
in
  rustPlatform.buildRustPackage {
    pname = "fileman";
    version = "0.5.2";
    inherit src;
    cargoLock.lockFile = "${src}/Cargo.lock";
    nativeBuildInputs = [pkg-config wrapGAppsHook4 cmake];
    dontUseCmakeConfigure = true;
    buildInputs = [gtk4 libadwaita libarchive];
    cargoBuildFlags = ["--bin" "fileman"];
    cargoTestFlags = ["--bin" "fileman"];
    nativeCheckInputs = [(lib.getBin libarchive) pigz];
    preCheck = ''
      export HOME="$(mktemp -d)"
    '';
    postInstall = ''
      install -Dm644 data/dev.fileman.Files.desktop "$out/share/applications/dev.fileman.Files.desktop"
      substituteInPlace "$out/share/applications/dev.fileman.Files.desktop" \
        --replace-fail 'Exec=fileman ' "Exec=$out/bin/fileman "
      mkdir -p "$out/share/icons"
      cp -r data/icons/hicolor "$out/share/icons/"
    '';
    preFixup = ''
      gappsWrapperArgs+=(--prefix PATH : "${lib.makeBinPath [(lib.getBin libarchive) pigz ffmpeg poppler-utils rclone fuse3 ntfs3g]}")
    '';
    meta = {
      description = "GTK4 file manager";
      homepage = "https://github.com/0znio/fileman";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "fileman";
    };
  }
