{
  description = "tenzyu's configuration";

  outputs = inputs: let
    # deprecated {{{
    username = "tenzyu";
    hostname = "neko5";
    system = "x86_64-linux";
    specialArgs = {inherit inputs hostname username system;};
    # }}}

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
        # pkgs = nixpkgsWithOverlays system;
        modules =
          [
            (configurationDefaults specialArgs)
            inputs.home-manager.nixosModules.home-manager
          ]
          ++ modules;
      };
  in {
    formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.alejandra);

    nixosConfigurations.${hostname} = inputs.nixpkgs.lib.nixosSystem {
      inherit system specialArgs;

      modules = [
        ./profiles/neko5/hardware-configuration.nix
        ./profiles/neko5/configuration.nix
        ./profiles/neko5/home-configuration.nix
      ];
    };

    # wsl on neko3
    nixosConfigurations.neko6 = mkNixosConfiguration {
      hostname = "neko6";
      username = "tenzyu";
      modules = [
        ./configs/wsl.nix
        inputs.nixos-wsl.nixosModules.wsl
        inputs.vscode-server.nixosModules.default
        ({
          config,
          pkgs,
          ...
        }: {
          environment.systemPackages = with pkgs; [wget];
          services.vscode-server.enable = true;
        })
      ];
    };

    homeConfigurations.tenzyu = inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      extraSpecialArgs = specialArgs;

      modules = [
        ./user/home/tenzyu.nix
      ];
    };
  };

  inputs = {
    ### nix ecosystem {{{
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    ### }}}

    ### {{{
    # NOTE: make sure to enable cachix first
    hyprland.url = "github:hyprwm/Hyprland";

    catppuccin.url = "github:catppuccin/nix";
    ### }}}
  };
}
