# Shared base profile for all host types (desktop, server, wsl).
# Each profile imports this and adds its own specializations.
{
  lib,
  pkgs,
  hostname,
  username,
  ...
}:
with lib; {
  # Nix
  nix = {
    package = pkgs.nixVersions.stable;
    settings = {
      use-xdg-base-directories = true;
      extra-experimental-features = ["nix-command" "flakes"];
      extra-trusted-users = [username];
      accept-flake-config = true;
      auto-optimise-store = true;

      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
        "https://ghostty.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="
      ];
    };
    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
    };
  };

  # User
  users.users.${username} = {
    isNormalUser = mkDefault true;
    shell = pkgs.zsh;
    extraGroups = mkDefault ["wheel"];
  };

  # Home Manager defaults
  home-manager.users.${username} = {
    imports = [
      ../../hosts/${hostname}/${username}.nix
      {
        programs.home-manager.enable = mkDefault true;
        xdg.enable = mkDefault true;
        home.preferXdgDirectories = mkDefault true;
        home.username = mkDefault "${username}";
        home.homeDirectory = mkDefault "/home/${username}";
        home.stateVersion = "25.11";
      }
    ];
  };

  # Shell
  programs.zsh.enable = mkDefault true;
  environment.pathsToLink = mkDefault ["/share/zsh"];
  environment.shells = mkDefault [pkgs.zsh];
  environment.enableAllTerminfo = mkDefault true;

  # Network
  time.timeZone = mkDefault "Asia/Tokyo";
  networking.hostName = mkDefault "${hostname}";
  services.openssh = {
    enable = mkDefault true;
    settings = {
      PasswordAuthentication = mkDefault false;
      KbdInteractiveAuthentication = mkDefault false;
      GatewayPorts = mkDefault "yes";
    };
  };

  # i18n
  i18n.defaultLocale = mkDefault "en_US.UTF-8";
  console.font = mkDefault "Lat2-Terminus16";

  system.stateVersion = "25.11";
}
