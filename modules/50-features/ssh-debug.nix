{...}: {
  flake.features.ssh-debug.projections.nixos.payload = {...}: {
    services.openssh.settings.LogLevel = "DEBUG";
  };
}
