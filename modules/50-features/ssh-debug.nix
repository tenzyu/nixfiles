{config, ...}: {
  flake.modules.nixos.ssh-debug = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.ssh-debug.enable {
      services.openssh.settings.LogLevel = "DEBUG";
    };
  };
}
