{lib, ...}: {
  flake.features.us-xserver-keyboard.projections.nixos.payload = {
    config,
    lib,
    ...
  }: {
    services.xserver.xkb = lib.mkDefault {
      layout = "us";
      variant = "";
    };
  };
}
