{lib}: let
  inherit
    (lib)
    attrNames
    concatMap
    filterAttrs
    flatten
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

  mkDefaultPriority = (lib.mkDefault true).priority;

  cleanViaOption = s: let
    m = match "(.+), via option .*" s;
  in
    if m != null
    then head m
    else s;

  toRepoPath = repo: flake: path:
    removePrefix "${toString repo}/" (
      removePrefix "${toString (flake.outPath or repo)}/" (cleanViaOption path)
    );

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

        startsLocal = hasInfix "local = {" line && !hasInfix "local.features" line;
        startsSystem =
          (hasInfix "local.features" line && hasInfix "{" line && !hasInfix "local.users." line)
          || (state.mode == "local" && hasInfix "features = {" line);
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
            resumeLocal = state.mode == "local";
          }
          else if startsLocal
          then {
            mode = "local";
            user = null;
            baseDepth = state.depth;
            path = null;
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
            mode = if stateAfterEnter.resumeLocal or false then "local" else null;
            user = null;
            baseDepth = if stateAfterEnter.resumeLocal or false then stateAfterEnter.baseDepth - 1 else 0;
            path = null;
            depth = newDepth;
          }
          else if stateAfterEnter.mode == "local" && newDepth <= stateAfterEnter.baseDepth
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
    hostFile,
    hostLines,
    scope,
    user ? null,
    feature,
  }: let
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
    hostLines;
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
      source = hostFile;
      line = hit.line;
      value = true;
      origin = "text-scan";
      option =
        if scope == "system"
        then "local.features.${feature}.enable"
        else "local.users.${user}.features.${feature}.enable";
      raw = trim hit.text;
    };

  # Source discovery is recursive: import-tree registers nested aspects too.
  # Ignore _private helpers, just as import-tree does.
  featureFiles = repo: let
    walk = dir: relative: let
      entries =
        if builtins.pathExists dir
        then builtins.readDir dir
        else {};
      visit = name: let
        entry = entries.${name};
        path = dir + "/${name}";
        rel = relative + "/${name}";
      in
        if hasPrefix "_" name
        then []
        else if entry == "directory"
        then walk path rel
        else if entry == "regular" && hasSuffix ".nix" name
        then [
          {
            inherit name rel;
            featureName = lib.removeSuffix ".nix" name;
            text = readFileIfExists path;
          }
        ]
        else [];
    in
      concatMap visit (attrNames entries);
  in
    walk (toString repo + "/modules/50-features") "modules/50-features";

  findImplementation = {
    files,
    moduleClass,
    feature,
  }: let
    needle = "flake.modules.${moduleClass}.${feature}";
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
    files,
    feature,
  }: let
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
    flake,
    featureName,
    winningPriority,
  }: d: let
    rel = toRepoPath repo flake d.file;
    fName =
      if hasPrefix "modules/50-features/" rel && hasSuffix ".nix" rel
      then lib.removeSuffix ".nix" (lib.last (splitString "/" rel))
      else null;
  in {
    kind =
      if hasPrefix "modules/50-features/" rel
      then
        if winningPriority == mkDefaultPriority
        then "default"
        else if fName != null && fName != featureName
        then "bundle"
        else "direct"
      else if hasPrefix "modules/10-foundations" rel
      then "materialized"
      else "unknown";
    source = rel;
    line = d.line or null;
    value = d.value;
    renderedValue = serializeValue d.value;
    origin = "definitionsWithLocations";
    # Nixpkgs has stripped mkOverride and excluded losing definitions.
    winning_priority = winningPriority;
  };

  at = root: path: lib.attrByPath (splitString "." path) null root;

  optionDefinitions = context: options: option: let
    target = at options option;
    winningPriority = target.highestPrio or null;
  in
    map (normalizeDef (context // {inherit winningPriority;}))
    (target.definitionsWithLocations or []);

  mkFeatureRecord = {
    flake,
    repo,
    host,
    files,
    hostFile,
    hostLines,
  }: {
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
      else homeSeedEnabled || hmEnabled;

    enabledUserNames = enabledUsersFor cfg;

    directSeedActivation = findHostSeed {
      inherit hostFile hostLines feature scope user;
    };

    userSeedActivations =
      if scope == "system"
      then
        builtins.filter (x: x != null) (
          map (
            u: let
              hit = findHostSeed {
                inherit hostFile hostLines feature;
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

    getDefinitions =
      optionDefinitions {
        inherit repo flake;
        featureName = feature;
      }
      opts;
    optionDefActivations =
      if scope == "system"
      then getDefinitions "local.features.${feature}.enable"
      else [];

    scannedFeatureActivations =
      if seedActivations != [] || optionDefActivations != []
      then []
      else findFeatureModuleActivations {inherit files feature;};

    # Evaluated Nix definitions are authoritative; textual source inspection
    # remains only a separately labeled location hint.
    activations =
      if optionDefActivations != []
      then optionDefActivations
      else seedActivations;

    implClass =
      if scope == "system"
      then "nixos"
      else "homeManager";
    impl = findImplementation {
      inherit files feature;
      moduleClass = implClass;
    };
    implFallback =
      if impl == null && scope == "system"
      then
        findImplementation {
          inherit files feature;
          moduleClass = "homeManager";
        }
      else null;
    implementations = builtins.filter (x: x != null) [impl implFallback];

    effectDefs =
      if scope == "system"
      then getDefinitions "programs.${feature}.enable"
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
    source_hints = seedActivations ++ scannedFeatureActivations;
    implementations = implementations;
    effects = effectDefs;
    definitions = optionDefActivations;
    # Nested NixOS user/HM submodule option metadata has no stable access path.
    winning_priority =
      if scope == "system"
      then (at opts "local.features.${feature}.enable").highestPrio or null
      else null;
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
  inherit featureFiles;

  traceHost = {
    flake,
    repo,
    host,
    user ? null,
    scope ? "all",
    feature ? null,
  }: let
    cfg = flake.nixosConfigurations.${host}.config;
    hostFile = "modules/00-hosts/${host}/configuration.nix";
    record = mkFeatureRecord {
      inherit flake repo host hostFile;
      files = featureFiles repo;
      hostLines = scanHostSeedLines (readFileIfExists (toString repo + "/" + hostFile));
    };
    enabledSysNames = attrNames (filterAttrs (_: f: f.enable or false) (cfg.local.features or {}));
    users = homeUsersFor {
      cfg = cfg;
      explicitUser = user;
    };
    systemFeatureNames =
      if feature == null
      then enabledSysNames
      else [feature];
    homeFeatureNames = u:
      if feature == null
      then attrNames (filterAttrs (_: f: f.enable or false) (cfg.local.users.${u}.features or {}))
      else [feature];
  in {
    type = "host";
    inherit host scope;
    system =
      if scope == "home"
      then []
      else
        map (feature:
          record {
            inherit feature;
            scope = "system";
          })
        systemFeatureNames;
    home =
      if scope == "system"
      then []
      else
        flatten (map (u:
          map (feature:
            record {
              inherit feature;
              scope = "home";
              user = u;
            }) (homeFeatureNames u))
        users);
  };

  traceWhy = {
    flake,
    repo,
    host,
    option,
  }: let
    n = flake.nixosConfigurations.${host};
    effective = at n.config option;
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
    definitions = optionDefinitions {inherit repo flake featureName;} n.options option;
    winning_priority = (at n.options option).highestPrio or null;
  };
}
