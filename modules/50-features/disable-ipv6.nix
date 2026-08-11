{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.disable-ipv6 = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.disable-ipv6.enable {
      boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 1;
      boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 1;
      networking.enableIPv6 = false;
      # Do NOT use:
      # boot.kernelParams = ["ipv6.disable=1"];
      #
      # Rust/.NET may still need AF_INET6 socket support even when
      # this host intentionally has no usable IPv6 connectivity.
    };
  };
}
