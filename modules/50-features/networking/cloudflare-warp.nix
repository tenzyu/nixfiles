{lib, ...}: {
  flake.modules.nixos.cloudflare-warp = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.cloudflare-warp.enable {
      environment.systemPackages = [
        pkgs.cloudflare-warp
      ];
      systemd.packages = [
        pkgs.cloudflare-warp
      ];
      systemd.targets.multi-user.wants = [
        "warp-svc.service"
      ];
    };
  };
}
