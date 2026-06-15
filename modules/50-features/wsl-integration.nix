{inputs, ...}: {
  flake.modules.nixos.wsl-integration = {config, lib, ...}: {
    imports = [
      inputs.nixos-wsl.nixosModules.wsl
    ];

    config = lib.mkIf config.local.features.wsl-integration.enable {
      wsl = {
        enable = true;
        wslConf.automount.root = "/mnt";
        wslConf.interop.appendWindowsPath = false;
        wslConf.network.generateHosts = false;
        startMenuLaunchers = true;
        docker-desktop.enable = false;
      };
    };
  };
}
