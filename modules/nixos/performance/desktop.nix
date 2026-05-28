{lib, ...}: {
  flake.modules.nixos.desktopPerformance = {
    powerManagement = {
      enable = true;
      cpuFreqGovernor = lib.mkDefault "performance";
    };

    services = {
      fstrim.enable = lib.mkDefault true;
      power-profiles-daemon.enable = lib.mkDefault true;
      thermald.enable = lib.mkDefault true;
    };

    zramSwap = {
      enable = lib.mkDefault true;
      algorithm = lib.mkDefault "zstd";
      memoryPercent = lib.mkDefault 50;
      priority = lib.mkDefault 100;
    };
  };
}
