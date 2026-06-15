{inputs, ...}: {
  flake.modules.nixos.wsl-integration = {
    imports = [inputs.nixos-wsl.nixosModules.wsl];

    wsl = {
      enable = true;
      wslConf.automount.root = "/mnt";
      wslConf.interop.appendWindowsPath = false;
      wslConf.network.generateHosts = false;
      startMenuLaunchers = true;
      docker-desktop.enable = false;
    };
  };
}
