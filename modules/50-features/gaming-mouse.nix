{
  flake.modules.nixos.gaming-mouse = {
    lib,
    config,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.gaming-mouse.enable {
      services.ratbagd.enable = true;
      environment.systemPackages = with pkgs; [
        piper
        libratbag
      ];
    };
  };
}
