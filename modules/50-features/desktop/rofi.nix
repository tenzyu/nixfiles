{
  flake.modules.homeManager.rofi = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.rofi.enable {
      programs.rofi = {
        enable = true;
      };
    };
  };
}
