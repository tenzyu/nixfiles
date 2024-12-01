{
  description = "tenzyu's nix home-manager configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";
    hyprland.url = "github:hyprwm/Hyprland";
    ghostty.url = "git+ssh://git@github.com/ghostty-org/ghostty";
  };

  outputs = inputs: let
    username = "tenzyu";
    system = "x86_64-linux";
    pkgs = import inputs.nixpkgs {
      inherit system;
      overlays = [
        inputs.nixgl.overlay
      ];
      config = {
        permittedInsecurePackages = [
          ### NOTE: for pkgs.opentabletdriver {{{
          "dotnet-sdk-6.0.428"
          "dotnet-sdk-wrapped-6.0.428"
          "dotnet-runtime-6.0.36"
          ### }}}
        ];
      };
    };
    extraSpecialArgs = {
      inherit inputs;
      inherit username;
      inherit system;
    };
  in {
    formatter.${system} = pkgs.alejandra;

    homeConfigurations.${username} = inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      inherit extraSpecialArgs;

      modules = [
        ./user/home/tenzyu.nix
      ];
    };
  };
}
