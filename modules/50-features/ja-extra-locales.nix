{lib, ...}: {
  flake.modules.nixos.ja-extra-locales = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.ja-extra-locales.enable {
      i18n.extraLocaleSettings = lib.mkDefault {
        LC_ADDRESS = "ja_JP.UTF-8";
        LC_IDENTIFICATION = "ja_JP.UTF-8";
        LC_MEASUREMENT = "ja_JP.UTF-8";
        LC_MONETARY = "ja_JP.UTF-8";
        LC_NAME = "ja_JP.UTF-8";
        LC_NUMERIC = "ja_JP.UTF-8";
        LC_PAPER = "ja_JP.UTF-8";
        LC_TELEPHONE = "ja_JP.UTF-8";
        LC_TIME = "ja_JP.UTF-8";
      };
    };
  };
}
