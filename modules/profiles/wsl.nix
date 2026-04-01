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

  # NOTE: これちょっと境界の線引きが曖昧なのでは
  nixpkgs.overlays = [
    (import ../nixos/overlays/unstable.nix {inherit inputs;})
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

  nix.settings.access-tokens = [
    # "github.com=${secrets.github_token}"
  ];
}
