{lib}: let
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

  pkgsAmbient = {
    module = module:
      module;

    unstable = {
      local.pkgs.useUnstable = true;
    };

    unfree = names: {
      policy.pkgs.allowUnfreeNames = toList names;
    };

    unfreePredicate = predicate: {
      policy.pkgs.allowUnfreePredicates = [predicate];
    };

    insecure = names: {
      policy.pkgs.permittedInsecurePackages = toList names;
    };

    config = attrs: {
      nixpkgs.config = attrs;
    };

    overlay = overlay: {
      nixpkgs.overlays = [overlay];
    };

    overlayBefore = overlay: {
      nixpkgs.overlays = lib.mkBefore [overlay];
    };

    overlayAfter = overlay: {
      nixpkgs.overlays = lib.mkAfter [overlay];
    };
  };

  mkCrossModule = {
    name,
    ambient ? [],
    nixos ? null,
    home ? null,
  }: let
    ambientModules = toList ambient;
    nixosModules = normalizeNixos nixos;
    homeModules = normalizeHome home;

    crossToken = {
      __cross = true;

      nixosImports =
        ambientModules
        ++ nixosModules;

      homeImports =
        homeModules;
    };

    standaloneHomeManagerModule = {
      imports =
        ambientModules
        ++ [
          (crossArgModule "standalone")
        ]
        ++ homeModules;
    };
  in {
    config = {
      flake.modules.homeManager.${name} =
        standaloneHomeManagerModule;

      local.cross.modules.${name} =
        crossToken;
    };
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
  module = mkCrossModule;
  inherit user;

  pkgs = pkgsAmbient;
}
