{
  config,
  lib,
  ...
}: {
  config.flake.modules.nixos.collector = {
    config,
    lib,
    ...
  }: {
    options.local = {
      effects = lib.mkOption {
        type = lib.types.submodule {
          options = {
            pkgs = {
              unfreePackages = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = ''
                  Package names allowed by `nixpkgs.config.allowUnfreePredicate`.
                  Features contribute through `flake.effects.<name>.system.collect`
                  or `flake.effects.<name>.user.collect`.
                '';
              };

              permittedInsecurePackages = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = ''
                  Insecure package versions explicitly permitted for this
                  configuration. Projected to `nixpkgs.config.permittedInsecurePackages`.
                '';
              };
            };
          };
        };
        default = {};
        description = ''
          Cross-cutting policy accumulator.
          Features contribute to this through `flake.effects.<name>.collect`.
          Each effect projection becomes a NixOS module that writes
          `local.effects = <collect>;`. The NixOS module system merges
          the submodule-shaped values (lists concat, attrsets deep merge).
          The collector aspect then deduplicates policy lists and
          projects to `nixpkgs.config` and other policy options.
          Future policy dimensions (substituters, trusted-public-keys,
          fonts, groups, xdg-portals, security exceptions, ...) only
          extend this schema, never the class surface.
        '';
      };
    };

    config = let
      unfree = lib.unique config.local.effects.pkgs.unfreePackages;
      insecure = lib.unique config.local.effects.pkgs.permittedInsecurePackages;
    in {
      nixpkgs.config = {
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) unfree;
        permittedInsecurePackages = insecure;
      };
    };
  };
}
