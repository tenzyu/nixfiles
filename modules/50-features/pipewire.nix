{lib, ...}: {
  flake.modules.nixos.pipewire = {config, lib, ...}: {
    config = lib.mkIf config.local.features.pipewire.enable {
      security.rtkit.enable = lib.mkDefault true;

      services.pipewire = {
        enable = lib.mkDefault true;
        alsa = {
          enable = lib.mkDefault true;
          support32Bit = lib.mkDefault true;
        };
        pulse.enable = lib.mkDefault true;
        wireplumber.enable = lib.mkDefault true;
      };
    };
  };
}
