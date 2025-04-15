{
  pkgs,
  username,
  ...
}: {
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
}
