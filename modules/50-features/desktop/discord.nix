{
  flake.local.featurePolicies.discord.unfree = [
    "discord"
    "discord-unwrapped"
  ];

  flake.modules.nixos.discord = {};

  flake.modules.homeManager.discord = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.discord.enable {
      home.packages = [pkgs.unstable.discord];
    };
  };
}
