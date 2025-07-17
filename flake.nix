{
  description = "tenzyu's nixfiles";

  outputs = inputs: let
    forAllSystems = inputs.nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];

    configurationDefaults = args: {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-backup";
      home-manager.extraSpecialArgs = args;
    };

    mkNixosConfiguration = {
      system ? "x86_64-linux",
      hostname,
      username,
      args ? {},
      modules,
    }: let
      specialArgs = {inherit inputs hostname username;} // args;
    in
      inputs.nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules =
          [
            (configurationDefaults specialArgs)
            inputs.home-manager.nixosModules.home-manager
            ./lib/nix.nix
          ]
          ++ modules;
      };
  in {
    # Laptop
    nixosConfigurations.neko5 = mkNixosConfiguration {
      hostname = "neko5";
      username = "tenzyu";
      modules = [./profiles/desktop.nix];
    };

    # WSL on neko3
    nixosConfigurations.neko6 = mkNixosConfiguration {
      hostname = "neko6";
      username = "tenzyu";
      modules = [./profiles/wsl.nix];
    };

    # supported by Yuki
    nixosConfigurations.neko7 = mkNixosConfiguration {
      hostname = "neko7";
      username = "tenzyu";
      modules = [./profiles/server.nix];
    };

    formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.alejandra);
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
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

    hyprland.url = "github:hyprwm/Hyprland";
    catppuccin.url = "github:catppuccin/nix";
  };
}
