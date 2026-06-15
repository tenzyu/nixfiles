{config, ...}: {
  flake.modules.nixos.passwordless-sudo = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.passwordless-sudo.enable {
      security.sudo.wheelNeedsPassword = false;
    };
  };
}
