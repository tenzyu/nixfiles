let
  get = side: builtins.getFlake ("git+file://" + builtins.getEnv (side + "_PATH") + "?rev=" + builtins.getEnv (side + "_REV"));
  old = get "BASE"; new = get "CAND";
  inherit (old.inputs.nixpkgs) lib;
  inherit (builtins) mapAttrs hashString toJSON attrNames;
  featureValues = mapAttrs (_: feature: feature.enable);
  digest = value: hashString "sha256" (toJSON value);
  packageDrvs = map (p: p.drvPath);
  home = c: {features = featureValues c.local.features; activationDrv = c.home.activationPackage.drvPath; packages = packageDrvs c.home.packages; userServices = digest c.systemd.user.services;};
  guest = container: let c = container.config; in {systemDrv = c.system.build.toplevel.drvPath; packages = packageDrvs c.environment.systemPackages; systemUnits = digest (mapAttrs (_: u: u.text or null) c.systemd.units); mounts = container.bindMounts;};
  os = c: {features = featureValues c.local.features; userFeatures = mapAttrs (_: u: featureValues u.features) c.local.users; policy = c.local.nixpkgsPolicy; systemDrv = c.system.build.toplevel.drvPath; packages = packageDrvs c.environment.systemPackages; systemUnits = digest (mapAttrs (_: u: u.text or null) c.systemd.units); homes = mapAttrs (_: u: home u) c.home-manager.users; gameOperations = c.local.gameOperations or {}; gameGuests = mapAttrs (_: v: guest v) c.containers;};
  allGames = f: f.nixosConfigurations.neko7.extendModules { modules = [{local.features = {game-ark.enable = lib.mkForce true; game-rust.enable = lib.mkForce true;};}]; };
  gamePkg = host: let found = lib.filter (p: lib.getName p == "game") host.config.environment.systemPackages; in assert builtins.length found == 1; builtins.head found;
  restore = a: b: b.extendModules {modules = [{environment.systemPackages = lib.mkForce (map (p: if lib.getName p == "game" then gamePkg a else p) b.config.environment.systemPackages);}];};
  snapshot = f: hosts: all: {nixos = mapAttrs (_: h: os h.config) hosts; standalone = mapAttrs (_: h: (home h.config) // {policy = h.config.local.nixpkgsPolicy;}) f.homeConfigurations; gamescope = os hosts.neko5.config.specialisation.neko5-gamescope.configuration; allGames = os all.config; helperKeys = attrNames f.lib.helpers; operatorFeatures = f.operator.features;};
  oldAll = allGames old; newAll = allGames new;
in {
  baseline = snapshot old old.nixosConfigurations oldAll;
  candidate = snapshot new new.nixosConfigurations newAll;
  control = snapshot new (new.nixosConfigurations // {neko7 = restore old.nixosConfigurations.neko7 new.nixosConfigurations.neko7;}) (restore oldAll newAll);
  gameDrvs = {baseline = (gamePkg old.nixosConfigurations.neko7).drvPath; candidate = (gamePkg new.nixosConfigurations.neko7).drvPath; baselineAll = (gamePkg oldAll).drvPath; candidateAll = (gamePkg newAll).drvPath;};
}
