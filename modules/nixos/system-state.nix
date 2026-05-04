{config, ...}: {
  flake.modules.nixos.systemState = {
    system.stateVersion = config.me.stateVersion;
  };
}
