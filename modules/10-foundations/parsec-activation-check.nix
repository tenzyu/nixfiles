{inputs, ...}: {
  perSystem = {pkgs, lib, ...}: let
    home = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        (import ../50-features/services/parsec.nix).flake.modules.homeManager.parsec
        {
          options.local.features.parsec.enable = lib.mkEnableOption "Parsec";
          config = {
            local.features.parsec.enable = true;
            home = {
              username = "fixture";
              homeDirectory = "/unused-parsec-fixture";
              stateVersion = "26.05";
            };
          };
        }
      ];
    };
    inherit (home.config.home.activation) parsecConfig parsecTouchpadGpmap;
    review = lib.findFirst (package: lib.getName package == "parsec-activation-review") (throw "missing Parsec review command") home.config.home.packages;
    fixtures = ../../assets/parsec-activation/test_activation.py;
    # Execute the production DAG fragments with HM's actual `run` function,
    # without invoking any unrelated activation, profiles, or Parsec package.
    activation =
      assert parsecConfig.after == ["writeBoundary"];
      assert parsecTouchpadGpmap.after == ["writeBoundary"];
        pkgs.writeShellScript "parsec-activation-fixture" ''
          set -euo pipefail
          source ${inputs.home-manager}/lib/bash/home-manager.sh
          if [[ -v PARSEC_FIXTURE_FAULT ]]; then
            run() {
              ${pkgs.python3}/bin/python3 -I ${fixtures} --inject "''${@:3}"
            }
          fi
          ${parsecConfig.data}
          ${parsecTouchpadGpmap.data}
        '';
  in {
    checks.parsec-activation = pkgs.runCommand "parsec-activation-tests" {} ''
      ${pkgs.python3}/bin/python3 -I ${fixtures} ${activation} ${review}/bin/parsec-activation-review
      touch "$out"
    '';
  };
}
