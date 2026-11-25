{
  flake.modules.homeManager.easyeffects = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf (config.local.features.easyeffects.enable && !config.local.features.splitcast-capture.enable) {
      # Installation only, not automatic DSP activation. Preserve the existing
      # exclusion when SplitCast owns capture and processing.
      home.packages = [pkgs.easyeffects];
    };
  };
}
