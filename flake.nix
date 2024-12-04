{
  # NOTE: UNDER CONSTRUCTION
  description = "tenzyu configuration";

  inputs = {
    ### nix ecosystem {{{
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
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

  outputs = inputs: let
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        inputs.nixgl.overlay
      ];
    };
  in {
    formatter.${system} = pkgs.alejandra;

    nixosConfigurations."neko5" = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ./profiles/neko5/home-configuration.nix
          ./profiles/neko5/configuration.nix
          ./profiles/neko5/hardware-configuration.nix
        ];
      };

    homeConfigurations.tenzyu = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs system;
        username = "tenzyu";
      };
      modules = [
        ./profiles/tenzyu.nix
      ];
    };
  };
}
