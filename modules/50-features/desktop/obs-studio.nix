{
  flake.modules.homeManager.obs-studio = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.obs-studio.enable {
      # Keep the upstream package and its binary-cache eligibility.
      programs.obs-studio.enable = true;
    };
  };
}
