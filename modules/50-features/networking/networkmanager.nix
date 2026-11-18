{
  flake.modules.nixos.networkmanager = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.networkmanager.enable {
      networking.networkmanager.enable = true;
      networking.networkmanager.wifi.powersave = false;

      networking.nameservers = [
        "1.1.1.1"
        "1.0.0.1"
        "8.8.8.8"
        "8.8.4.4"
      ];
    };
  };

}
