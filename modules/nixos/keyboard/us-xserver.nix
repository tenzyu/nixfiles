{lib, ...}: {
  flake.modules.nixos.usXserverKeyboard = {
    services.xserver.xkb = lib.mkDefault {
      layout = "us";
      variant = "";
    };
  };
}
