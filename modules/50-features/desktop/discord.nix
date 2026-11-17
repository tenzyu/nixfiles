{
  flake.local.featurePolicies.discord.unfree = [
    "discord"
    "discord-unwrapped"
  ];

  flake.modules.nixos.discord = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.discord.enable {};
  };

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
