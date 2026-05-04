{
  config,
  lib,
  ...
}: let
  inherit (config.me) stateVersion timeZone username;
  module = {pkgs, ...}: {
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
          "https://cache.numtide.com"
        ];
        extra-trusted-public-keys = [
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
        ];
      };
      gc = {
        automatic = true;
        options = "--delete-older-than 7d";
      };
    };

    users.users.${username} = {
      isNormalUser = lib.mkDefault true;
      shell = pkgs.zsh;
      extraGroups = lib.mkDefault ["wheel"];
    };

    home-manager.users.${username} = {
      programs.home-manager.enable = lib.mkDefault true;
      xdg.enable = lib.mkDefault true;
      home.preferXdgDirectories = lib.mkDefault true;
      home.username = lib.mkDefault username;
      home.homeDirectory = lib.mkDefault "/home/${username}";
      home.stateVersion = stateVersion;
    };

    programs.zsh.enable = lib.mkDefault true;
    environment.pathsToLink = lib.mkDefault ["/share/zsh"];
    environment.shells = lib.mkDefault [pkgs.zsh];
    environment.enableAllTerminfo = lib.mkDefault true;

    time.timeZone = lib.mkDefault timeZone;
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };

    i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
    console.font = lib.mkDefault "Lat2-Terminus16";

    system.stateVersion = stateVersion;
  };
in {
  flake.modules.nixos.common = module;
}
