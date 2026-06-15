{
  flake.modules.homeManager.starship = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.starship.enable {
      programs.starship = {
        enable = true;
      };
    };
  };
}
