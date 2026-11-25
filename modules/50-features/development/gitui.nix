{
  flake.modules.homeManager.gitui = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.gitui.enable {
      home.packages = [pkgs.gitui];
    };
  };
}
