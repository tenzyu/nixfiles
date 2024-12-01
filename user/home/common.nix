{
  pkgs,
  username,
  ...
}: {
  home.username = "${username}";
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;
  nix = {
    package = pkgs.nixVersions.stable;
    settings = {
      trusted-users = "${username}";
      use-xdg-base-directories = true;
      experimental-features = ["nix-command" "flakes"];

      # NOTE: ビルドする前に登録する必要があるから、初期化だとここにあってもアドバンテージがないかも.
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
  };
}
