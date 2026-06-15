{
  config,
  lib,
  ...
}: let
  nixosModules = config.flake.modules.nixos;
  homeModules = config.flake.modules.homeManager;
  effects = config.flake.effects;
  userFactory = config.flake.lib.userFactory;

  isKnownFeature = name:
    builtins.hasAttr name nixosModules
    || builtins.hasAttr name homeModules
    || builtins.hasAttr name effects;

  resolveClosure = context: requestedNames: let
    go = acc: name:
      if !(isKnownFeature name)
      then throw "${context}: unknown feature '${name}'"
      else if builtins.elem name acc
      then acc
      else builtins.foldl' go (acc ++ [name]) (effects.${name}.requires or []);
  in
    lib.naturalSort (lib.unique (builtins.foldl' go [] requestedNames));

  isSystemProjectable = name: let
    go = visited: n:
      if builtins.elem n visited
      then false
      else if builtins.hasAttr n nixosModules
      then true
      else if builtins.hasAttr n effects && effects.${n}.system != null
      then true
      else let
        reqs =
          if builtins.hasAttr n effects
          then (effects.${n}.requires or [])
          else [];
      in
        if reqs == []
        then false
        else lib.any (r: go (visited ++ [n]) r) reqs;
  in
    go [] name;

  isUserProjectable = name: let
    go = visited: n:
      if builtins.elem n visited
      then false
      else if builtins.hasAttr n homeModules
      then true
      else if builtins.hasAttr n effects && effects.${n}.user != null
      then true
      else let
        reqs =
          if builtins.hasAttr n effects
          then (effects.${n}.requires or [])
          else [];
      in
        if reqs == []
        then false
        else lib.any (r: go (visited ++ [n]) r) reqs;
  in
    go [] name;

  filterByClosure = classMap: names:
    lib.filterAttrs (name: _: builtins.elem name names) classMap;

  callProjection = args: projection:
    if projection == null
    then {
      config = {};
      collect = {};
    }
    else if builtins.isFunction projection
    then projection (builtins.intersectAttrs (builtins.functionArgs projection) args)
    else projection;

  evalSystem = name:
    callProjection {inherit lib;} (effects.${name}.system or null);

  evalUser = name: userRecord:
    callProjection {
      user = userRecord;
      inherit lib;
    } (effects.${name}.user or null);

  projectionToModule = p: {
    config = lib.mkMerge [
      (p.config or {})
      {local.effects = p.collect or {};}
    ];
  };

  buildSystemProjection = names: {
    imports =
      lib.attrValues (filterByClosure nixosModules names)
      ++ map (n: projectionToModule (evalSystem n)) names;
  };

  buildUserProjection = username: spec: closure: let
    homeModuleList = lib.attrValues (filterByClosure homeModules closure);

    userRecord = {
      name = username;
      fullName = spec.fullName or username;
      email = spec.email or "";
      isAdmin = spec.isAdmin or false;
      shell = spec.shell or null;
      homeStateVersion = spec.homeStateVersion or "26.05";
      homeDirectory = "/home/${username}";
      extraGroups = spec.extraGroups or [];
      imports = spec.imports or [];
      module = spec.module or {};
    };

    userProjections = map (n: evalUser n userRecord) closure;

    factoryModule = userFactory userRecord;
  in {
    imports =
      [factoryModule]
      ++ map projectionToModule userProjections;

    config = {
      home-manager.users.${username}.imports =
        homeModuleList
        ++ (spec.imports or [])
        ++ [spec.module or {}];
    };
  };

  assertEnabled = context: features: let
    enabled = lib.attrNames (lib.filterAttrs (_: v: v) features);
  in
    if enabled == []
    then throw "${context}: no enabled features"
    else enabled;

  assertSystemProjectable = context: requested:
    builtins.foldl' (
      acc: name:
        if !(isSystemProjectable name)
        then throw "${context}: feature '${name}' is not system-projectable"
        else acc
    ) []
    requested;

  assertUserProjectable = context: requested:
    builtins.foldl' (
      acc: name:
        if !(isUserProjectable name)
        then throw "${context}: feature '${name}' is not user-projectable"
        else acc
    ) []
    requested;
in {
  config.flake.lib.feature = {
    system = {
      stateVersion ? "26.05",
      features,
    }: let
      context = "feature.system";
      requested = assertEnabled context features;
      closure =
        builtins.seq (assertSystemProjectable context requested)
        (resolveClosure context requested);
      projection = buildSystemProjection closure;
    in {
      imports =
        [projection]
        ++ [{system.stateVersion = lib.mkDefault stateVersion;}];
    };

    users = users:
      if users == {}
      then throw "feature.users: users is empty"
      else let
        context = "feature.users";
        usernames = builtins.attrNames users;

        perUserClosure =
          lib.foldl' (
            acc: username: let
              spec = users.${username};
              feats = spec.features or {};
              userContext = "${context}.${username}";
              requested = assertEnabled userContext feats;
              closure =
                builtins.seq (assertUserProjectable userContext requested)
                (resolveClosure userContext requested);
            in
              acc // {${username} = closure;}
          ) {}
          usernames;

        systemClosure = lib.unique (lib.concatLists (lib.attrValues perUserClosure));
        systemProjection = buildSystemProjection systemClosure;
        userProjections =
          lib.mapAttrsToList
          (username: closure:
            buildUserProjection username users.${username} closure)
          perUserClosure;
      in {
        imports =
          [systemProjection]
          ++ userProjections;
      };
  };
}
