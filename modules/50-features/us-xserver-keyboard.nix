{lib, ...}: {
  flake.modules.nixos.us-xserver-keyboard = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.us-xserver-keyboard.enable {
      services.xserver.xkb = lib.mkDefault {
        layout = "us";
        variant = "";
      };
    };
  };
}
