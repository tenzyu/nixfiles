{lib, ...}: {
  flake.modules.nixos.pipewire = {
    services.pipewire = {
      enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
    };
  };
}
