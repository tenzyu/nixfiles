{lib, ...}: {
  flake.modules.nixos.locale = {
    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
    console.font = lib.mkDefault "Lat2-Terminus16";
  };
}
