{lib, ...}: {
  flake.modules.nixos.us-xserver-keyboard = {
    services.xserver.xkb = lib.mkDefault {
      layout = "us";
      variant = "";
    };
  };
}
