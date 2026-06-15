{
  flake.modules.nixos.disable-ipv6 = {
    boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
    boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
    networking.enableIPv6 = false;
    boot.kernelParams = ["ipv6.disable=1"];
  };
}
