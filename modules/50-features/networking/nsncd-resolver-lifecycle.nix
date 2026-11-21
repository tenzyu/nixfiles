{
  flake.modules.nixos.nsncd-resolver-lifecycle = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.nsncd-resolver-lifecycle.enable {
      assertions = [{
        assertion =
          config.services.nscd.enable
          && config.services.nscd.enableNsncd
          && config.networking.resolvconf.enable;
        message = "nsncd-resolver-lifecycle requires enabled nsncd and resolvconf";
      }];

      # NixOS 26.05's resolvconf module invalidates the glibc nscd cache
      # on every DNS update. nsncd is a non-caching NSS proxy; restarting it
      # cannot invalidate a cache and can instead exhaust StartLimitBurst.
      # Keep the libc subscriber and /etc/resolv.conf updates intact.
      networking.resolvconf.extraConfig = lib.mkAfter ''
        libc_restart=':'
      '';
    };
  };
}
