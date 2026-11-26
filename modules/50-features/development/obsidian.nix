{
  flake.local.featurePolicies.obsidian.unfree = [
    "obsidian"
  ];

  flake.modules.nixos.obsidian = {};

  flake.modules.homeManager.obsidian = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.obsidian.enable {
      home.packages = [pkgs.obsidian];
    };
  };
}
