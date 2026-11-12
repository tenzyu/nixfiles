{
  lib,
  rustPlatform,
  makeWrapper,
  coreutils,
  jq,
  curl,
  openssl,
  websocat,
  ffmpeg-full,
  gpu-screen-recorder,
  mediamtx,
  pipewire,
  pulseaudio,
  openssh,
  v4l-utils,
  rnnoise-plugin,
  obs-studio,
}:
let
  obs = import ../../modules/50-features/splitcast/_internal/obs.nix { inherit obs-studio; };
  runtime = [coreutils jq curl openssl websocat ffmpeg-full gpu-screen-recorder mediamtx pipewire pulseaudio openssh v4l-utils obs];
in rustPlatform.buildRustPackage {
  pname = "splitcast-rs-core";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [makeWrapper];
  postInstall = ''
    wrapProgram "$out/bin/splitcast-rs-core" \
      --prefix PATH : ${lib.makeBinPath runtime} \
      --prefix LADSPA_PATH : ${rnnoise-plugin.ladspa}/lib/ladspa
  '';
  passthru = {
    example = ../splitcast/example.json;
    rnnoise = rnnoise-plugin.ladspa;
    inherit obs;
  };
  meta = {
    mainProgram = "splitcast-rs-core";
    description = "Rust SplitCast agent candidate (no implicit service cutover)";
    platforms = lib.platforms.linux;
  };
}
