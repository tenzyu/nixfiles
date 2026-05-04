{
  config,
  inputs,
  ...
}: {
  flake.modules.nixos.wslIntegration = {
    imports = [
      inputs.nixos-wsl.nixosModules.wsl
    ];

    wsl = {
      enable = true;
      wslConf.automount.root = "/mnt";
      wslConf.interop.appendWindowsPath = false;
      wslConf.network.generateHosts = false;
      defaultUser = config.me.username;
      startMenuLaunchers = true;
      docker-desktop.enable = false;
    };
  };
}
