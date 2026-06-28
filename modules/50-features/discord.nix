{
  flake.local.featurePolicies.discord.unfree = [
    "discord"
  ];

  flake.features.discord.projections.homeManager.payload = {
    pkgs,
    ...
  }: {
    home.packages = [pkgs.unstable.discord];
  };
}
