{
  flake.local.featurePolicies.obsidian.unfree = [
    "obsidian"
  ];

  flake.features.obsidian.projections.homeManager.payload = {
    pkgs,
    ...
  }: {
    home.packages = [pkgs.obsidian];
  };
}
