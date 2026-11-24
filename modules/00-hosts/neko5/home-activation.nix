{
  configurations.nixos.neko5.module = {
    home-manager.users.tenzyu.imports = [({lib, ...}: {
      # Install the config files normally. Apply reloads at the next app launch,
      # outside Home Manager activation and its protected HOME write checks.
      xdg.configFile = lib.genAttrs [
        "mako/config"
        "waybar/config"
        "waybar/style.css"
      ] (_: {onChange = lib.mkForce "";});
    })];

    # Retain inactive Catppuccin/Waybar generated files as disabled entries.
    # This is separate from the user's explicit Waybar feature selection.
    home-manager.users.tenzyu.xdg.configFile = {
      "waybar/config".enable = false;
      "waybar/style.css".enable = false;
    };
  };
}
