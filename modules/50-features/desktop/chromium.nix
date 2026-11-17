{
  flake.modules.homeManager.chromium = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.chromium.enable {
      programs.chromium = {
        enable = true;
      };
    };
  };
}
