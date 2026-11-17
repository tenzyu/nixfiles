{
  flake.modules.nixos.waydroid = {
    config,
    lib,
    pkgs,
    ...
  }: let
    waydroidScript = pkgs.callPackage (pkgs.fetchFromGitHub {
        owner = "casualsnek";
        repo = "waydroid_script";
        rev = "48dbfaf34a6ddbe78688c530f9ba1c26522aafb2";
        hash = "sha256-UBbnYhiRCf4sMwpEDMlpJuTEsN66B2hZ8BPz6cCGXAc=";
      }
      + "/package.nix") {};
  in {
    config = lib.mkIf config.local.features.waydroid.enable {
      virtualisation.waydroid = {
        enable = true;
        package = pkgs.waydroid-nftables;
      };

      environment.systemPackages = [
        pkgs.unstable.waydroid-helper
        waydroidScript
      ];
    };
  };
}
