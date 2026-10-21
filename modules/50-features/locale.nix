{lib, ...}: {
  flake.modules.nixos.locale = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.locale.enable {
      i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
      # The per-host locale subset changes the derivation and requires local
      # localedef work. The standard archive contains the same required locales
      # and is published in cache.nixos.org (larger archive, no locale loss).
      i18n.glibcLocales = lib.mkDefault pkgs.glibcLocales;
      console.font = lib.mkDefault "Lat2-Terminus16";
    };
  };
}
