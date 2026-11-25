{
  flake.modules.homeManager.cclip = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cclip = pkgs.unstable.callPackage ../../../assets/packages/cclip.nix {};
    # The upstream database bootstrap creates a 0644 file. A private data
    # directory prevents other local users from traversing clipboard history.
    start = pkgs.writeShellApplication {
      name = "cclip-start";
      runtimeInputs = [cclip pkgs.coreutils pkgs.util-linux];
      text = builtins.readFile ../../../scripts/desktop/cclip-start.sh;
    };
  in {
    config = lib.mkIf config.local.features.cclip.enable {
      home.packages = [cclip start];
    };
  };
}
