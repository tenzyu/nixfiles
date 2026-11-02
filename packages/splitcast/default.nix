{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  ffmpeg-full,
  gpu-screen-recorder,
  pipewire,
  pulseaudio,
  mediamtx,
  v4l-utils,
  rnnoise-plugin,
  openssh,
  coreutils,
  procps,
  iproute2,
  obs-studio,
}: let
  python = python3.withPackages (p: [p.websocket-client]);
  obs = import ../../modules/50-features/splitcast/_internal/obs.nix {inherit obs-studio;};
  runtime = [
    python
    ffmpeg-full
    gpu-screen-recorder
    pipewire
    pulseaudio
    mediamtx
    v4l-utils
    openssh
    coreutils
    procps
    iproute2
    obs
  ];
in
  stdenvNoCC.mkDerivation (final: {
    pname = "splitcast";
    version = "0.1.0";
    src = lib.cleanSource ./.;
    nativeBuildInputs = [makeWrapper];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/splitcast" "$out/bin" "$out/share/splitcast"
      cp -r . "$out/lib/splitcast/"
      cp example.json "$out/share/splitcast/example.json"
      makeWrapper ${python}/bin/python "$out/bin/splitcast" \
        --add-flags '-m splitcast' \
        --prefix PYTHONPATH : "$out/lib/splitcast" \
        --prefix PATH : ${lib.makeBinPath runtime} \
        --prefix LADSPA_PATH : ${rnnoise-plugin.ladspa}/lib/ladspa
      runHook postInstall
    '';
    passthru = {
      inherit obs python runtime;
      example = final.src + "/example.json";
      rnnoise = rnnoise-plugin.ladspa;
    };
    meta = {
      description = "Two-host capture and production controller";
      mainProgram = "splitcast";
      platforms = lib.platforms.linux;
    };
  })
