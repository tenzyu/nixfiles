{
  flake.modules.nixos.ssh-debug = {
    services.openssh.settings.LogLevel = "DEBUG";
  };
}
