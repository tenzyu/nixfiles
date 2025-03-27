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
        ./wsl.nix
        inputs.nixos-wsl.nixosModules.wsl
        inputs.vscode-server.nixosModules.default
        ({ config, pkgs, ... }: {
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
    # NOTE: This will require your git SSH access to the repo.
    #
    # WARNING:
    # Do NOT pin the `nixpkgs` input, as that will
    # declare the cache useless. If you do, you will have
    # to compile LLVM, Zig and Ghostty itself on your machine,
    # which will take a very very long time.
    #
    # Additionally, if you use NixOS, be sure to **NOT**
    # run `nixos-rebuild` as root! Root has a different Git config
    # that will ignore any SSH keys configured for the current user,
    # denying access to the repository.
    #
    # Instead, either run `nix flake update` or `nixos-rebuild build`
    # as the current user, and then run `sudo nixos-rebuild switch`.
    ghostty.url = "git+ssh://git@github.com/ghostty-org/ghostty";

    # NOTE: make sure to enable cachix first
    hyprland.url = "github:hyprwm/Hyprland";

    catppuccin.url = "github:catppuccin/nix";
    ### }}}
  };
}
