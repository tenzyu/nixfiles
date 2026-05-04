{lib, ...}: {
  flake.modules.nixos.fcitx5 = {pkgs, ...}: {
    i18n.inputMethod = {
      enable = lib.mkDefault true;
      type = lib.mkDefault "fcitx5";
      fcitx5.waylandFrontend = lib.mkDefault true;
      fcitx5.addons = [
        pkgs.fcitx5-mozc-ut
      ];
    };
  };
}
