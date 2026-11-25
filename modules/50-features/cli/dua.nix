{
  flake.modules.homeManager.dua = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.dua.enable {
      home.packages = [pkgs.dua];
    };
  };
}
