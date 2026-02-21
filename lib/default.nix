rec {
  # ── Module collections ──────────────────────────────────────────────────
  # Usage: let inherit (import ../../lib/default.nix) homeModules; in { imports = [ homeModules.programs.starship ]; }

  homeModules = {
    programs = collectModules ../modules/home/programs;
    addons = collectModules ../modules/home/addons;
  };

  nixosModules = {
    programs = collectModules ../modules/nixos/programs;
    overlays = collectModules ../modules/nixos/overlays;
  };

  profiles = collectModules ../modules/profiles;

  # ── Utility functions ───────────────────────────────────────────────────

  forAllSystems = pkgs:
    pkgs.lib.genAttrs [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];

  # Build an attrset of modules keyed by name from a directory.
  # e.g., collectModules ./modules/home/programs → { bat = <path>; btop = <path>; ... }
  collectModules = dir: let
    entries = builtins.readDir dir;
    isModule = name: type:
      (type == "regular" && builtins.match ".*\\.nix" name != null && name != "default.nix")
      || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"));
    moduleNames = builtins.filter (n: isModule n entries.${n}) (builtins.attrNames entries);
    stripNix = name: builtins.replaceStrings [".nix"] [""] name;
  in
    builtins.listToAttrs (map (name: {
        name =
          if entries.${name} == "directory"
          then name
          else stripNix name;
        value = dir + "/${name}";
      })
      moduleNames);

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
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.extraSpecialArgs = specialArgs;
          }
          inputs.home-manager.nixosModules.home-manager
        ]
        ++ modules;
    };
}
