{...}: {
  flake.modules.nixos.nix-store-clean = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cleaner = pkgs.writeShellApplication {
      name = "nix-store-clean-current-system";
      runtimeInputs = [
        pkgs.nix
        pkgs.python3
      ];
      text = ''
        exec ${lib.getExe pkgs.python3} ${../../../assets/nix-store-clean/cli.py} "$@"
      '';
    };
  in {
    config = lib.mkIf config.local.features.nix-store-clean.enable {
      environment.systemPackages = [cleaner];
    };
  };

  perSystem = {pkgs, ...}: {
    checks.nix-store-clean =
      pkgs.runCommand "nix-store-clean-tests" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        cp ${../../../assets/nix-store-clean/cli.py} cli.py
        cp ${../../../assets/nix-store-clean/test_cli.py} test_cli.py
        export PYTHONDONTWRITEBYTECODE=1
        python -m unittest discover -v
        mkdir -p "$out"
      '';
  };
}
