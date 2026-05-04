{
  config,
  lib,
  ...
}: let
  toList = value:
    if value == null
    then []
    else if builtins.isList value
    then value
    else [value];

  isCrossModule = value:
    builtins.isAttrs value
    && value ? __cross
    && value.__cross == true;

  mkCrossArg = env: {
    inherit env;

    is = {
      nixos = env == "nixos";
      standalone = env == "standalone";
    };

    select = choices:
      if builtins.hasAttr env choices
      then choices.${env}
      else if choices ? default
      then choices.default
      else
        builtins.throw ''
          cross.select: missing value for environment `${env}`.
          Provide `${env}` or `default`.
        '';

    only = {
      nixos = value:
        lib.mkIf (env == "nixos") value;

      standalone = value:
        lib.mkIf (env == "standalone") value;
    };
  };

  crossArgModule = env: {
    _module.args.cross = mkCrossArg env;
  };

  resolvePackages = packages: pkgs:
    if builtins.isFunction packages
    then packages pkgs
    else toList packages;

  packagesModule = packages: {pkgs, ...}: {
    home.packages = resolvePackages packages pkgs;
  };

  sectionHasDslKeys = section:
    builtins.isAttrs section
    && (
      section ? module
      || section ? modules
      || section ? packages
    );

  normalizeNixos = nixos:
    if nixos == null
    then []
    else if sectionHasDslKeys nixos
    then
      (toList (nixos.modules or []))
      ++ (toList (nixos.module or null))
    else toList nixos;

  normalizeHome = home:
    if home == null
    then []
    else if sectionHasDslKeys home
    then
      (toList (home.modules or []))
      ++ (toList (home.module or null))
      ++ lib.optionals (home ? packages) [
        (packagesModule home.packages)
      ]
    else toList home;

  normalizeDefinition = definition: {
    ambientModules = toList (definition.ambient or []);
    nixosModules = normalizeNixos (definition.nixos or null);
    homeModules = normalizeHome (definition.home or null);
  };

  mkCrossToken = _: definition: let
    normalized = normalizeDefinition definition;
  in {
    __cross = true;

    nixosImports =
      normalized.ambientModules
      ++ normalized.nixosModules;

    homeImports =
      normalized.homeModules;
  };

  mkStandaloneHomeManagerModule = _: definition: let
    normalized = normalizeDefinition definition;
  in {
    imports =
      normalized.ambientModules
      ++ [
        (crossArgModule "standalone")
      ]
      ++ normalized.homeModules;
  };

  normalizeCrossItem = item:
    if isCrossModule item
    then {
      nixosImports = item.nixosImports or [];
      homeImports = item.homeImports or [];
    }
    else {
      nixosImports = [];
      homeImports = [item];
    };

  collectCrossItems = items: let
    normalized = map normalizeCrossItem items;
  in {
    nixosImports =
      lib.concatMap (item: item.nixosImports) normalized;

    homeImports =
      lib.concatMap (item: item.homeImports) normalized;
  };

  user = username: items: let
    collected = collectCrossItems items;
  in {
    imports =
      collected.nixosImports;

    home-manager.users.${username}.imports =
      [
        (crossArgModule "nixos")
      ]
      ++ collected.homeImports;
  };
in {
  options.local.cross = {
    definitions = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = {};
      description = "Cross-environment module definitions for NixOS and standalone Home Manager.";
    };

    modules = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      default = {};
      description = "Collected cross modules for NixOS + Home Manager user boundaries.";
    };
  };

  config = {
    flake.modules.homeManager =
      lib.mapAttrs mkStandaloneHomeManagerModule config.local.cross.definitions;

    local.cross.modules =
      lib.mapAttrs mkCrossToken config.local.cross.definitions;

    flake.lib.cross = {
      inherit user;
      modules = config.local.cross.modules;
    };
  };
}
