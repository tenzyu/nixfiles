{
  username,
  hostname,
  pkgs,
  inputs,
  lib,
  ...
}:
with lib; {
  imports = [inputs.nixos-wsl.nixosModules.wsl];

  time.timeZone = mkDefault "Asia/Tokyo";
  networking.hostName = "${hostname}";

  programs.zsh.enable = true;
  environment.pathsToLink = ["/share/zsh"];
  environment.shells = [pkgs.zsh];
  environment.enableAllTerminfo = true;

  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "docker"
    ];
    # FIXME: add your own hashed password
    # hashedPassword = "";
    # FIXME: add your own ssh public key
    # openssh.authorizedKeys.keys = [
    #   "ssh-rsa ..."
    # ];
  };
  programs.nix-ld.enable = true;

  system.stateVersion = "24.11";

  wsl = {
    enable = true;
    wslConf.automount.root = "/mnt";
    wslConf.interop.appendWindowsPath = false;
    wslConf.network.generateHosts = false;
    defaultUser = username;
    startMenuLaunchers = true;

    # Enable integration with Docker Desktop (needs to be installed)
    docker-desktop.enable = false;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  home-manager.users.${username} = {
    imports = [
      ../hosts/${hostname}/${username}.nix

      {
        programs.home-manager.enable = mkDefault true;
        xdg.enable = mkDefault true;
        home.preferXdgDirectories = mkDefault true;
        home.username = mkDefault "${username}";
        home.homeDirectory = mkDefault "/home/${username}";
        home.stateVersion = "24.11";
      }
    ];
  };

  nix = {
    settings = {
      access-tokens = [
        # "github.com=${secrets.github_token}"
      ];
    };
  };
}
