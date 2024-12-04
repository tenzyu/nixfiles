{
  pkgs,
  lib,
  ...
}: {
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cloudflare-warp"
    ];
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
