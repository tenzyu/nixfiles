{
  config,
  inputs,
  ...
}: let
  inherit (config.me) username;
in {
  flake.modules.nixos.wsl = {
    imports = [
      inputs.nixos-wsl.nixosModules.wsl
    ];

    security.sudo.wheelNeedsPassword = false;
    services.openssh.settings.LogLevel = "DEBUG";

    local.pkgs.useUnstable = true;

    users.users.${username}.extraGroups = ["wheel" "docker"];

    programs.nix-ld.enable = true;

    wsl = {
      enable = true;
      wslConf.automount.root = "/mnt";
      wslConf.interop.appendWindowsPath = false;
      wslConf.network.generateHosts = false;
      defaultUser = username;
      startMenuLaunchers = true;
      docker-desktop.enable = false;
    };

    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
    };

    nix.settings.access-tokens = [];
  };
}
