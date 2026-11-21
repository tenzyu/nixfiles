{
  # NVMe SMART inspection needs a root-capable command in the system profile:
  # a Home Manager-only binary may be absent from sudo's secure PATH.
  # User selection projects this system aspect via native mkDefault semantics.
  flake.modules.nixos.disk-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.disk-tools.enable {
      environment.systemPackages = [pkgs.smartmontools];
    };
  };

  flake.modules.homeManager.disk-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.disk-tools.enable {
      home.packages = with pkgs; [
        qdirstat
      ];
    };
  };
}
