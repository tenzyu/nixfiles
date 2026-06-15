{
  flake.modules.homeManager.tenzyu-desktop = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.tenzyu-desktop.enable {
      local.features = {
        tenzyu-cli.enable = true;
        kitty.enable = true;
        rofi.enable = true;
        waybar.enable = true;
        mako.enable = true;
        wlogout.enable = true;
        hyprpaper.enable = true;
        packages-desktop.enable = true;
        firefox.enable = true;
        zed-editor.enable = true;
      };
    };
  };
}
