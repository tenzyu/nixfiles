{
  description = "tenzyu's nixfiles";

  outputs = inputs: let
    lib = import ./lib/default.nix;
  in {
    # Laptop
    nixosConfigurations.neko5 = lib.mkNixosConfiguration {
      hostname = "neko5";
      username = "tenzyu";
      modules = [./modules/profiles/desktop.nix];
      inherit inputs;
    };

    # WSL on neko3
    nixosConfigurations.neko6 = lib.mkNixosConfiguration {
      hostname = "neko6";
      username = "tenzyu";
      modules = [./modules/profiles/wsl.nix];
      inherit inputs;
    };

    # supported by Yuki
    nixosConfigurations.neko7 = lib.mkNixosConfiguration {
      hostname = "neko7";
      username = "tenzyu";
      modules = [./modules/profiles/server.nix];
      inherit inputs;
    };

    formatter = import ./formatter.nix {inherit inputs;};
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland.url = "github:hyprwm/Hyprland";
  };
}
