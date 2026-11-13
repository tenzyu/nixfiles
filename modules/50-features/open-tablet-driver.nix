{config, ...}: {
  flake.modules.nixos.open-tablet-driver = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.open-tablet-driver.enable {
      hardware.opentabletdriver = {
        enable = true;
        daemon.enable = false;
      };
    };
  };

  flake.modules.nixos.otd-access = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.otd-access.enable {
      services.udev.extraRules = ''
        SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", TAG+="uaccess"
        SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTR{idVendor}=="0ac3", ATTR{idProduct}=="ff0f", TAG+="uaccess"
      '';
    };
  };
}
