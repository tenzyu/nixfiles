# Supporting subdomain: read-only projection of the real configuration/module
# definitions. No stored registry, feature evaluator or precedence simulation.
{lib}: {
  flake,
  hostDefinitions,
  homeDefinitions,
  moduleDefinitions,
}: let
  root = toString flake.outPath + "/";
  localFile = file: let
    clean = builtins.head (lib.splitString "#" (toString file));
    relative = lib.removePrefix root clean;
  in if lib.hasPrefix root clean && lib.hasPrefix "modules/" relative
    then relative else null;
  localFiles = locations: lib.unique (builtins.filter (p: p != null) (map localFile locations));
  definedAt = definitions: path:
    localFiles (map (d: d.file) (builtins.filter
      (d: builtins.isAttrs d.value && lib.hasAttrByPath path d.value)
      definitions));
  nativeOrigins = opts: lib.mapAttrs (_: option: let
    locations = lib.unique (map (d: toString d.file) option.enable.definitionsWithLocations);
  in {
    inherit locations;
    files = localFiles locations;
  }) opts;

  # Embedded HM submodule options are not exposed as an evaluated options tree
  # by the outer NixOS config. Extend only the inspection evaluation, never
  # the deployed host, to read the real HM option definitions.
  homeProbe = {lib, options, ...}: {
    options.local.operatorFeatureOrigins = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.raw;
      internal = true;
      readOnly = true;
    };
    config.local.operatorFeatureOrigins = nativeOrigins options.local.features;
  };

  rowsFor = {configuration, user, scope, features, selections, moduleClass}:
    lib.mapAttrsToList (feature: value: {
      inherit configuration user scope feature moduleClass;
      enabled = value.enable;
      sources = {
        selection = lib.unique (lib.concatMap (s:
          definedAt s.definitions (s.path ++ [feature "enable"])) selections);
        registration = definedAt moduleDefinitions [moduleClass feature];
      };
    }) features;

  hostRows = lib.mapAttrsToList (configuration: host: let
    inherit (host) config;
    seed = path: {definitions = hostDefinitions; path = [configuration "module"] ++ path;};
  in rowsFor {
    inherit configuration;
    user = null;
    scope = "system";
    features = config.local.features;
    selections = [ (seed ["local" "features"]) ];
    moduleClass = "nixos";
  } ++ lib.concatLists (lib.mapAttrsToList (user: home: rowsFor {
    inherit configuration user;
    scope = "home";
    features = home.local.features;
    selections = [
      (seed ["local" "users" user "features"])
      (seed ["home-manager" "users" user "local" "features"])
    ];
    moduleClass = "homeManager";
  }) config.home-manager.users)) flake.nixosConfigurations;

  standaloneRows = lib.mapAttrsToList (configuration: home: rowsFor {
    inherit configuration;
    user = home.config.home.username;
    scope = "standalone";
    features = home.config.local.features;
    selections = [{definitions = homeDefinitions; path = [configuration "module" "local" "features"];}];
    moduleClass = "homeManager";
  }) flake.homeConfigurations;
in {
  features = lib.concatLists (hostRows ++ standaloneRows);
  # Lazy per-scope lookup; the browser requests origins only for a selected row.
  origins = {
    nixos = lib.mapAttrs (_: host: {
      system = nativeOrigins host.options.local.features;
      home = let
        probed = host.extendModules {modules = [{home-manager.sharedModules = [homeProbe];}];};
      in lib.mapAttrs (_: home: home.local.operatorFeatureOrigins) probed.config.home-manager.users;
    }) flake.nixosConfigurations;
    standalone = lib.mapAttrs (_: home: nativeOrigins home.options.local.features) flake.homeConfigurations;
  };
}
