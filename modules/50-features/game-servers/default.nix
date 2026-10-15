{
  flake.local.featurePolicies.game-server-containers.unfree = [
    "steamcmd" "steam" "steam-run" "steam-original" "steam-unwrapped"
  ];
  flake.modules.nixos.game-server-containers = {config, lib, ...}: {
    config = lib.mkIf config.local.features.game-server-containers.enable {
      networking.nat = {
        enable = true;
        externalInterface = "ens18";
      };
    };
  };
}
