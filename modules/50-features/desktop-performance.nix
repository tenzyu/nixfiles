{lib, ...}: {
  flake.modules.nixos.desktop-performance = {
    powerManagement = {
      enable = true;
      # The target machine is a small Intel laptop used as a graphical workstation.
      # Keep the desktop deterministic; GameMode handles per-game process priority.
      cpuFreqGovernor = lib.mkDefault "performance";
    };

    services = {
      fstrim.enable = lib.mkDefault true;
      power-profiles-daemon.enable = lib.mkDefault false;
      thermald.enable = lib.mkDefault true;
    };

    systemd.oomd.enable = lib.mkDefault true;

    services.journald.extraConfig = ''
      SystemMaxUse=256M
      RuntimeMaxUse=64M
    '';

    boot.kernel.sysctl = {
      "vm.swappiness" = lib.mkDefault 10;
      "vm.vfs_cache_pressure" = lib.mkDefault 50;
      "vm.page-cluster" = lib.mkDefault 0;
    };

    zramSwap = {
      enable = lib.mkDefault true;
      # lz4 is chosen for latency. zstd compresses better; lz4 burns less CPU on swap bursts.
      algorithm = lib.mkDefault "lz4";
      memoryPercent = lib.mkDefault 50;
      priority = lib.mkDefault 100;
    };
  };
}
