{
  # NOTE: UNDER CONSTRUCTION
  description = "tenzyu configuration";

  inputs = {
    ### nix ecosystem {{{
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ### }}}

    ### {{{
    # NOTE: https://github.com/ghostty-org/ghostty?tab=readme-ov-file#nix-package
    ghostty.url = "git+ssh://git@github.com/ghostty-org/ghostty";
    catppuccin.url = "github:catppuccin/nix";
    hyprland.url = "github:hyprwm/Hyprland";
    ### }}}
  };

  outputs = inputs @ {home-manager, ...}: let
    username = "tenzyu";
    hostname = "neko5";
    system = "x86_64-linux";

    overlay-unstable = final: _: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (final) config;
      };
    };
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        overlay-unstable
        inputs.nixgl.overlay
      ];
    };

    specialArgs = {inherit inputs hostname username system;};
  in {
    formatter.${system} = pkgs.alejandra;

    nixosConfigurations.${hostname} = inputs.nixpkgs.lib.nixosSystem {
      inherit system specialArgs;

      modules = [
        ./profiles/neko5/hardware-configuration.nix
        ./profiles/neko5/configuration.nix
        ./profiles/neko5/home-configuration.nix
      ];
    };

    homeConfigurations.${username} = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = specialArgs;

      modules = [
        ./user/home/tenzyu.nix
      ];
    };
  };
}
