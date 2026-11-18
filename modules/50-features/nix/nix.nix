{...}: {
  flake.modules.nixos.nix = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.nix.enable {
      nix = {
        package = pkgs.nixVersions.stable;
        settings = {
          use-xdg-base-directories = true;
          extra-experimental-features = [
            "nix-command"
            "flakes"
          ];
          # Do not trust arbitrary flake nixConfig (including command-bearing
          # trusted settings) merely because a user evaluates a repository.
          # Required caches and public keys are declared below instead.
          accept-flake-config = false;
          auto-optimise-store = true;

          # Configure Catppuccin on the system daemon, not only in Home Manager.
          # HM-only nix.settings may not apply to privileged NixOS rebuilds.
          extra-substituters = [
            "https://catppuccin.cachix.org"
            "https://nix-community.cachix.org"
            "https://cache.nixos-cuda.org"
            "https://cache.numtide.com"
          ];
          extra-trusted-public-keys = [
            "catppuccin.cachix.org-1:noG/4HkbhJb+lUAdKrph6LaozJvAeEEZj4N732IysmU="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          ];
        };
        gc = {
          automatic = true;
          options = "--delete-older-than 7d";
        };
      };
    };
  };
}
