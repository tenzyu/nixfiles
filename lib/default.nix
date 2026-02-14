rec {
  # Library functions for NixOS configurations

  forAllSystems = pkgs:
    pkgs.lib.genAttrs [
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
    inputs,
  }: let
    specialArgs = {inherit inputs hostname username;} // args;
  in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules =
        [
          (configurationDefaults specialArgs)
          inputs.home-manager.nixosModules.home-manager
          ../modules/nix.nix
        ]
        ++ modules;
    };
}
