{config, ...}: {
  flake.modules.nixos.hyprlock = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.hyprlock.enable {
      programs.hyprlock.enable = true;
    };
  };
}
