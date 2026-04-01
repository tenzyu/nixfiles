{
  description = "tenzyu's nixfiles";

  outputs = inputs: let
    lib = import ./lib/default.nix;
  in {
    # Laptop
    nixosConfigurations.neko5 = lib.mkNixosConfiguration {
      hostname = "neko5";
      username = "tenzyu";
      modules = [lib.profiles.desktop];
      inherit inputs;
    };

    # WSL on neko3
    nixosConfigurations.neko6 = lib.mkNixosConfiguration {
      hostname = "neko6";
      username = "tenzyu";
      modules = [lib.profiles.wsl];
      inherit inputs;
    };

    # supported by Yuki
    nixosConfigurations.neko7 = lib.mkNixosConfiguration {
      hostname = "neko7";
      username = "tenzyu";
      modules = [lib.profiles.server];
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
    systems.url = "github:nix-systems/default";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
    lazyvim = {
      url = "github:pfassina/lazyvim-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-compat.follows = "flake-compat";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    catppuccin = {
      url = "github:catppuccin/nix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Auto-updating {{{
    antigravity-nix = {
      url = "github:jacopone/antigravity-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.flake-utils.follows = "flake-utils";
    };
    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.flake-utils.follows = "flake-utils";
    };
    # }}}
  };
}
