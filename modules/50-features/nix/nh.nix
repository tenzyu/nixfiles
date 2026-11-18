{
  flake.modules.homeManager.nh = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.nh.enable {
      home.packages = [pkgs.nh];
      home.sessionVariables = lib.mkIf (config.local.context.flakePath != null) {
        NH_OS_FLAKE = config.local.context.flakePath;
      };
    };
  };
}
