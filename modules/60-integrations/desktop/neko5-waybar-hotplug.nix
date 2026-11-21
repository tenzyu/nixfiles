{
  # neko5 has a hot-pluggable Logitech HID battery in addition to BAT1.
  # Keep the upstream Waybar hotplug fix scoped to that hardware + feature.
  flake.modules.nixos.neko5-hardware = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf (
      config.local.features.neko5-hardware.enable
      && config.local.users.tenzyu.features.waybar.enable
    ) {
      home-manager.users.tenzyu.programs.waybar.package = pkgs.unstable.waybar;
    };
  };
}
