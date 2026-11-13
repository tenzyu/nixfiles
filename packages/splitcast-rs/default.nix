{
  lib,
  rustPlatform,
  makeWrapper,
  callPackage,
  bash,
  coreutils,
  ffmpeg-full,
  gpu-screen-recorder,
  mediamtx,
  pipewire,
  pulseaudio,
  openssh,
  v4l-utils,
  rnnoise-plugin,
  obs-studio,
  webAssets ? callPackage ../splitcast-web {},
}: let
  obs = import ../../modules/50-features/splitcast/_internal/obs.nix {inherit obs-studio;};
  runtime = [coreutils ffmpeg-full gpu-screen-recorder mediamtx pipewire pulseaudio openssh v4l-utils obs];
in
  rustPlatform.buildRustPackage {
    pname = "splitcast-rs-core";
    version = "0.1.0";
    src = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ./Cargo.toml
        ./Cargo.lock
        ./src
        ./tests
        ./example.toml
        ../splitcast-protocol
      ];
    };
    sourceRoot = "source/splitcast-rs";
    cargoLock.lockFile = ./Cargo.lock;
    nativeBuildInputs = [makeWrapper bash coreutils];
    postInstall = ''
      wrapProgram "$out/bin/splitcast-rs-core" \
        --set SPLITCAST_WEB_ASSETS ${webAssets} \
        --prefix PATH : ${lib.makeBinPath runtime} \
        --prefix LADSPA_PATH : ${rnnoise-plugin.ladspa}/lib/ladspa
      ln -s splitcast-rs-core "$out/bin/splitcast"
    '';
    passthru = {
      example = ./tests/example.json;
      rnnoise = rnnoise-plugin.ladspa;
      inherit obs;
      web = webAssets;
    };
    meta = {
      mainProgram = "splitcast";
      description = "Rust SplitCast agent candidate (no implicit service cutover)";
      platforms = lib.platforms.linux;
    };
  }
