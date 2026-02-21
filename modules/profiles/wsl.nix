# WSL profile — inherits shared base, adds WSL-specific config.
{
  username,
  hostname,
  pkgs,
  inputs,
  lib,
  ...
}:
with lib; {
  imports = [
    ./shared.nix
    inputs.nixos-wsl.nixosModules.wsl
  ];

  security.sudo.wheelNeedsPassword = false;

  services.openssh.settings.LogLevel = "DEBUG";

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

  nix.settings.access-tokens = [
    # "github.com=${secrets.github_token}"
  ];
}
