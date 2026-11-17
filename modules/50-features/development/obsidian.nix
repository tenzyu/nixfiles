{
  flake.local.featurePolicies.obsidian.unfree = [
    "obsidian"
  ];

  flake.modules.nixos.obsidian = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.obsidian.enable {};
  };

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
