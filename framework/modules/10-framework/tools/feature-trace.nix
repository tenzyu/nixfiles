{lib}: let
  inherit
    (lib)
    attrNames
    concatMap
    filterAttrs
    flatten
    foldl'
    hasInfix
    hasPrefix
    hasSuffix
    head
    isAttrs
    isList
    isString
    match
    optionals
    removePrefix
    splitString
    ;

  serializeValue = v:
    if v == true
    then "true"
    else if v == false
    then "false"
    else if v == null
    then "null"
    else if isString v
    then "\"${v}\""
    else if isList v
    then "[list of ${toString (builtins.length v)}]"
    else if isAttrs v && v._type or null == "override"
    then "mkOverride ${toString (v.priority or 1000)}"
    else if isAttrs v
    then "{${toString (builtins.length (builtins.attrNames v))} keys}"
    else "<value>";

  isMkDefault = v:
    isAttrs v && v._type or null == "override" && v.priority or null == 1000;

  cleanViaOption = s: let
    m = match "(.+), via option .*" s;
  in
    if m != null
    then head m
    else s;

  toRepoPath = repo: absPath: let
    repoStr = toString repo;
    stripped = removePrefix "${repoStr}/" absPath;
  in
    if stripped != absPath
    then cleanViaOption stripped
    else let
      m = match "/nix/store/[^/]+-source/(.+)" absPath;
    in
      if m != null
      then cleanViaOption (head m)
      else cleanViaOption absPath;

  renderLocation = location: let
    line = location.line or null;
  in
    if line == null
    then location.source
    else "${location.source}:${toString line}";

  readHostConfig = repo: host: let
    path = toString repo + "/modules/00-hosts/${host}/configuration.nix";
  in
    if builtins.pathExists path
    then builtins.readFile path
    else "";

  readFileIfExists = path:
    if builtins.pathExists path
    then builtins.readFile path
    else "";

  linesWithNumbers = text: let
    lines = splitString "\n" text;
  in
    builtins.genList (i: {
      lineNo = i + 1;
      text = builtins.elemAt lines i;
    }) (builtins.length lines);

  countChar = char: s: let
    chars = lib.stringToCharacters s;
  in
    builtins.length (builtins.filter (c: c == char) chars);

  braceDelta = line: (countChar "{" line) - (countChar "}" line);

  trim = s: lib.strings.trim s;

  # The host configuration is intentionally regular:
  #   local.features = { ... };
  #   local.users.<name> = { features = { ... }; };
  # This scanner is not a Nix parser. It is an edit-provenance scanner for that
  # host seed surface. It tracks enough brace depth to avoid choosing the wrong
  # zsh.enable line when both system and user scopes contain zsh.
  scanHostSeedLines = text: let
    lines = linesWithNumbers text;

    userNameFromLine = line: let
      m = match ".*local\\.users\\.([^[:space:]=.]+)[[:space:]]*=.*" line;
    in
      if m != null
      then head m
      else null;

    go = state: remaining:
      if remaining == []
      then []
      else let
        item = head remaining;
        line = item.text;
        delta = braceDelta line;

        startsSystem = hasInfix "local.features" line && hasInfix "{" line && !hasInfix "local.users." line;
        startsUser = hasInfix "local.users." line && hasInfix "{" line && !hasInfix ".features" line;
        userFromLine = userNameFromLine line;
        startsUserFeatures = state.user != null && state.mode == "user" && hasInfix "features" line && hasInfix "{" line;

        userBefore = state.user;
        pathBefore = state.path;

        location = {
          line = item.lineNo;
          text = line;
          path = pathBefore;
          user = userBefore;
        };

        stateAfterEnter =
          if startsSystem
          then {
            mode = "system-features";
            user = null;
            baseDepth = state.depth;
            path = "system";
          }
          else if startsUser && userFromLine != null
          then {
            mode = "user";
            user = userFromLine;
            baseDepth = state.depth;
            path = "user";
          }
          else if startsUserFeatures
          then {
            mode = "user-features";
            user = state.user;
            baseDepth = state.depth;
            path = "home";
          }
          else state;

        newDepth = state.depth + delta;
        stateAfterClose =
          if stateAfterEnter.mode == "system-features" && newDepth <= stateAfterEnter.baseDepth
          then {
            mode = null;
            user = null;
            baseDepth = 0;
            path = null;
            depth = newDepth;
          }
          else if stateAfterEnter.mode == "user-features" && newDepth <= stateAfterEnter.baseDepth
          then {
            mode = "user";
            user = stateAfterEnter.user;
            baseDepth = stateAfterEnter.baseDepth - 1;
            path = "user";
            depth = newDepth;
          }
          else if stateAfterEnter.mode == "user" && newDepth <= stateAfterEnter.baseDepth
          then {
            mode = null;
            user = null;
            baseDepth = 0;
            path = null;
            depth = newDepth;
          }
          else stateAfterEnter // {depth = newDepth;};
      in
        [location] ++ go stateAfterClose (builtins.tail remaining);
  in
    go {
      mode = null;
      user = null;
      baseDepth = 0;
      path = null;
      depth = 0;
    }
    lines;

  findHostSeed = {
    repo,
    host,
    scope,
    user ? null,
    feature,
  }: let
    rel = "modules/00-hosts/${host}/configuration.nix";
    text = readHostConfig repo host;
    scanned = scanHostSeedLines text;
    wantedPath =
      if scope == "system"
      then "system"
      else "home";
    hits = builtins.filter (item:
      item.path
      == wantedPath
      && (
        if scope == "home"
        then item.user == user
        else true
      )
      && hasInfix "${feature}.enable" item.text
      && hasInfix "true" item.text)
    scanned;
  in
    if hits == []
    then null
    else let
      hit = head hits;
    in {
      kind =
        if scope == "system"
        then "host-seed"
        else "user-seed";
      source = rel;
      line = hit.line;
      value = true;
      origin = "text-scan";
      option =
        if scope == "system"
        then "local.features.${feature}.enable"
        else "local.users.${user}.features.${feature}.enable";
      raw = trim hit.text;
    };

  featureFiles = repo: let
    dir = toString repo + "/modules/50-features";
    entries =
      if builtins.pathExists dir
      then builtins.readDir dir
      else {};
  in
    map (name: {
      inherit name;
      rel = "modules/50-features/${name}";
      featureName = lib.removeSuffix ".nix" name;
      text = readFileIfExists (dir + "/${name}");
    })
    (builtins.filter (name: entries.${name} == "regular" && hasSuffix ".nix" name) (attrNames entries));

  findImplementation = {
    repo,
    moduleClass,
    feature,
  }: let
    needle = "flake.modules.${moduleClass}.${feature}";
    files = featureFiles repo;
    hits = builtins.filter (f: hasInfix needle f.text) files;
  in
    if hits == []
    then null
    else let
      f = head hits;
    in {
      kind = "feature-module";
      moduleClass = moduleClass;
      source = f.rel;
      line = null;
      optionPrefix = needle;
      origin = "module-registry-scan";
    };

  findFeatureModuleActivations = {
    repo,
    feature,
  }: let
    files = featureFiles repo;
    scanFile = f: let
      lines = linesWithNumbers f.text;
      hits = builtins.filter (item:
        (hasInfix "${feature}.enable" item.text || hasInfix "local.features.${feature}.enable" item.text)
        && hasInfix "=" item.text
        && !hasInfix "mkIf" item.text)
      lines;
      mk = item: {
        kind =
          if f.featureName != feature
          then "bundle"
          else if hasInfix "mkDefault" item.text
          then "implied"
          else "direct";
        source = f.rel;
        line = item.lineNo;
        value = hasInfix "true" item.text;
        origin = "text-scan";
        option = "local.features.${feature}.enable";
        by = f.featureName;
        raw = trim item.text;
      };
    in
      map mk hits;
  in
    concatMap scanFile files;

  normalizeDef = {
    repo,
    featureName,
  }: d: let
    rel = toRepoPath repo d.file;
    fName = let
      m = match "modules/50-features/([^/]+)\\.nix" rel;
    in
      if m != null
      then head m
      else null;
  in {
    kind =
      if hasPrefix "modules/50-features/" rel
      then
        if fName != null && fName != featureName
        then "bundle"
        else if isMkDefault d.value
        then "implied"
        else "direct"
      else if hasPrefix "modules/10-framework/" rel
      then "materialized"
      else "unknown";
    source = rel;
    line = d.line or null;
    value = d.value;
    renderedValue = serializeValue d.value;
    origin = "definitionsWithLocations";
  };

  optionByPath = root: path:
    foldl' (acc: p:
      if acc == null
      then null
      else acc.${p} or null)
    root (splitString "." path);

  configValueByPath = root: path:
    foldl' (acc: p:
      if acc == null
      then null
      else acc.${p} or null)
    root (splitString "." path);

  optionDefinitions = {
    repo,
    featureName,
    option,
    optionsRoot,
  }: let
    opt = optionByPath optionsRoot option;
    defs =
      if opt != null && opt ? definitionsWithLocations
      then opt.definitionsWithLocations
      else [];
  in
    map (normalizeDef {inherit repo featureName;}) defs;

  firstNonEmpty = lists:
    if lists == []
    then []
    else if head lists != []
    then head lists
    else firstNonEmpty (builtins.tail lists);

  mkFeatureRecord = {
    flake,
    repo,
    host,
    scope,
    user ? null,
    feature,
  }: let
    n = flake.nixosConfigurations.${host};
    cfg = n.config;
    opts = n.options;

    systemEnabled = (cfg.local.features.${feature}.enable or false) == true;
    homeSeedEnabled = user != null && (cfg.local.users.${user}.features.${feature}.enable or false) == true;
    hmEnabled = user != null && (cfg.home-manager.users.${user}.local.features.${feature}.enable or false) == true;

    enabled =
      if scope == "system"
      then systemEnabled
      else if scope == "home"
      then homeSeedEnabled || hmEnabled
      else systemEnabled || homeSeedEnabled || hmEnabled;

    enabledUserNames = enabledUsersFor cfg;

    directSeedActivation =
      if scope == "system"
      then
        findHostSeed {
          inherit repo host feature;
          scope = "system";
        }
      else
        findHostSeed {
          inherit repo host user feature;
          scope = "home";
        };

    userSeedActivations =
      if scope == "system"
      then
        builtins.filter (x: x != null) (
          map (
            u: let
              hit = findHostSeed {
                inherit repo host feature;
                scope = "home";
                user = u;
              };
            in
              if hit == null
              then null
              else
                hit
                // {
                  kind = "user-seeded";
                  option = "local.users.${u}.features.${feature}.enable";
                  user = u;
                }
          )
          enabledUserNames
        )
      else [];

    seedActivations = optionals (directSeedActivation != null) [directSeedActivation] ++ userSeedActivations;

    optionDefActivations =
      if scope == "system" && seedActivations == []
      then
        optionDefinitions {
          inherit repo;
          featureName = feature;
          option = "local.features.${feature}.enable";
          optionsRoot = opts;
        }
      else [];

    scannedFeatureActivations =
      if seedActivations != [] || optionDefActivations != []
      then []
      else findFeatureModuleActivations {inherit repo feature;};

    activations = seedActivations ++ optionDefActivations ++ scannedFeatureActivations;

    implClass =
      if scope == "system"
      then "nixos"
      else "homeManager";
    impl = findImplementation {
      inherit repo feature;
      moduleClass = implClass;
    };
    implFallback =
      if impl == null && scope == "system"
      then
        findImplementation {
          inherit repo feature;
          moduleClass = "homeManager";
        }
      else null;
    implementations = builtins.filter (x: x != null) [impl implFallback];

    effectDefs = let
      effectOption = "programs.${feature}.enable";
      effectOpt = optionByPath opts effectOption;
    in
      if scope == "system" && effectOpt != null
      then
        optionDefinitions {
          inherit repo;
          featureName = feature;
          option = effectOption;
          optionsRoot = opts;
        }
      else [];

    primaryKind =
      if activations == []
      then "unknown"
      else (head activations).kind or "unknown";
  in {
    name = feature;
    inherit scope;
    user =
      if scope == "home"
      then user
      else null;
    status =
      if enabled
      then "enabled"
      else "disabled";
    system_enabled = systemEnabled;
    home_seed_enabled = homeSeedEnabled;
    hm_enabled = hmEnabled;
    kind = primaryKind;
    activations = activations;
    implementations = implementations;
    effects = effectDefs;
    definitions = activations;
  };

  enabledUsersFor = cfg:
    attrNames (filterAttrs (_: u: u.enable or true) (cfg.local.users or {}));

  homeUsersFor = {
    cfg,
    explicitUser ? null,
  }: let
    enabled = enabledUsersFor cfg;
  in
    if explicitUser != null
    then [explicitUser]
    else enabled;
in {
  inherit toRepoPath renderLocation;

  traceHost = {
    flake,
    repo,
    host,
    user ? null,
    scope ? "all",
  }: let
    cfg = flake.nixosConfigurations.${host}.config;
    enabledSysNames = attrNames (filterAttrs (_: f: f.enable or false) (cfg.local.features or {}));
    users = homeUsersFor {
      cfg = cfg;
      explicitUser = user;
    };
    homeFeatureNames = u:
      attrNames (filterAttrs (_: f: f.enable or false) (cfg.local.users.${u}.features or {}));
  in {
    type = "host";
    inherit host scope;
    system =
      if scope == "home"
      then []
      else
        map (feature:
          mkFeatureRecord {
            inherit flake repo host feature;
            scope = "system";
          })
        enabledSysNames;
    home =
      if scope == "system"
      then []
      else
        flatten (map (u:
          map (feature:
            mkFeatureRecord {
              inherit flake repo host feature;
              scope = "home";
              user = u;
            }) (homeFeatureNames u))
        users);
  };

  traceFeature = {
    flake,
    repo,
    host,
    user ? null,
    scope ? "system",
    feature,
  }:
    if scope == "all"
    then {
      type = "feature";
      name = feature;
      scope = "all";
      system = mkFeatureRecord {
        inherit flake repo host feature;
        scope = "system";
      };
      home =
        if user == null
        then []
        else [
          (mkFeatureRecord {
            inherit flake repo host user feature;
            scope = "home";
          })
        ];
    }
    else mkFeatureRecord {inherit flake repo host user feature scope;};

  traceWhy = {
    flake,
    repo,
    host,
    option,
  }: let
    n = flake.nixosConfigurations.${host};
    opt = optionByPath n.options option;
    defs =
      if opt != null && opt ? definitionsWithLocations
      then opt.definitionsWithLocations
      else [];
    effective = configValueByPath n.config option;
    featureName = let
      m = match "local\\.features\\.([^.]+)\\..*" option;
    in
      if m != null
      then head m
      else let
        m2 = match "local\\.users\\.[^.]+\\.features\\.([^.]+)\\..*" option;
      in
        if m2 != null
        then head m2
        else option;
  in {
    type = "why";
    path = option;
    effective = serializeValue effective;
    definitions =
      map (normalizeDef {
        inherit repo;
        featureName = featureName;
      })
      defs;
  };
}
