{
  config,
  inputs,
  ...
}: let
  inherit (config.me) username;
  unstableOverlay = final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final.stdenv.hostPlatform) system;
      inherit (final) config;
    };
  };
in {
  flake.modules.nixos.wsl = {
    imports = [
      inputs.nixos-wsl.nixosModules.wsl
    ];

    security.sudo.wheelNeedsPassword = false;
    services.openssh.settings.LogLevel = "DEBUG";

    users.users.${username}.extraGroups = ["wheel" "docker"];

    nixpkgs.overlays = [
      unstableOverlay
    ];

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
