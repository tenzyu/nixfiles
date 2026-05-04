{
  flake.modules.nixos.disableIpv6 = {
    boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
    boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
  };
}
