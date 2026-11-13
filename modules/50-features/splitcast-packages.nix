{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    package = pkgs.callPackage ../../packages/splitcast-rs {};
    voicevoxPkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = p: pkgs.lib.getName p == "voicevox-onnxruntime";
    };
  in {
    packages = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      splitcast = package;
      splitcast-obs = package.obs;
      splitcast-obs-stock-candidate = pkgs.obs-studio.override {browserSupport = false;};
      splitcast-rs-core = package;
      splitcast-voicevox = voicevoxPkgs.voicevox-engine;
    };
    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      splitcast-package = pkgs.runCommand "splitcast-package-check" {nativeBuildInputs = [package];} ''
        splitcast selfcheck
        touch "$out"
      '';
    };
  };
}
