{
  flake.modules.homeManager.ozone-wayland = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.ozone-wayland.enable {
      home.sessionVariables.NIXOS_OZONE_WL = "1";
    };
  };
}
