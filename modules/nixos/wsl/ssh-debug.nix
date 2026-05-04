{
  flake.modules.nixos.sshDebug = {
    services.openssh.settings.LogLevel = "DEBUG";
  };
}
