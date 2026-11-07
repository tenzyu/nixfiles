{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    package = pkgs.callPackage ../../packages/splitcast {};
    example = builtins.fromJSON (builtins.readFile package.example);
    voicevoxPkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "voicevox-onnxruntime";
    };
  in {
    packages = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      splitcast = package;
      splitcast-obs = package.obs; # Retained until stock OBS isolation is verified.
      splitcast-obs-stock-candidate = pkgs.obs-studio.override {browserSupport = false;};
      splitcast-rs-core = pkgs.rustPlatform.buildRustPackage {
        pname = "splitcast-rs-core";
        version = "0.1.0";
        src = ../../packages/splitcast-rs;
        cargoLock.lockFile = ../../packages/splitcast-rs/Cargo.lock;
      };
      splitcast-voicevox = voicevoxPkgs.voicevox-engine;
    };
    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      splitcast-package =
        pkgs.runCommand "splitcast-package-check" {
          nativeBuildInputs = [package package.python pkgs.ffmpeg-full];
        } ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          splitcast --help
          PYTHONPATH=${package}/lib/splitcast python -c 'import websocket; from splitcast.config import Config; Config.load("${package}/share/splitcast/example.json")'
          ffmpeg -nostdin -hide_banner -v error -f lavfi -i anullsrc=r=48000:cl=mono \
            -t 0.1 -af ${pkgs.lib.escapeShellArg "ladspa=f=${package.rnnoise}/lib/ladspa/librnnoise_ladspa.so:p=${example.audio.rnnoise_label}:c=${example.audio.rnnoise_control}"} \
            -f null -
          touch "$out"
        '';
    };
  };
}
