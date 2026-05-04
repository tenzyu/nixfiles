{config, ...}: {
  flake.modules.nixos.nix = {pkgs, ...}: {
    nix = {
      package = pkgs.nixVersions.stable;
      settings = {
        use-xdg-base-directories = true;
        extra-experimental-features = ["nix-command" "flakes"];
        extra-trusted-users = [config.me.username];
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
  };
}
