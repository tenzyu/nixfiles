{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.cloudflare-warp
  ];
  systemd.packages = [
    pkgs.cloudflare-warp
  ];
  systemd.targets.multi-user.wants = [
    "warp-svc.service"
  ];
}
