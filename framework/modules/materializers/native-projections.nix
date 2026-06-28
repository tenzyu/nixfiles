{
  lib,
  featuresLib,
  modulesLib,
  usersLib,
  nativeFeatures,
  nixosModules,
}: let
  nativeFeatureList =
    lib.mapAttrsToList (name: feature: {
      inherit name feature;
    })
    nativeFeatures;

  hasPayload = path: feature:
    lib.attrByPath (path ++ ["payload"]) null feature != null;

  isConfigFragment = result:
    builtins.isAttrs result
    && !(builtins.hasAttr "imports" result)
    && !(builtins.hasAttr "options" result)
    && !(builtins.hasAttr "config" result)
    && !(builtins.hasAttr "_module" result);

  payloadAssertion = name: result: {
    assertion = isConfigFragment result;
    message = "native feature ${name} payload must return a config fragment, not a Nix module.";
  };

  boundaryId = boundary: "${boundary.kind}:${boundary.name}";

  wrapPayload = {
    name,
    payload,
    activation,
    boundary,
    active ? ((activation.enable or false) == true),
    imports ? [],
    extraContext ? {},
  }: moduleArgs @ {
    config,
    lib,
    options,
    pkgs,
    ...
  }: let
    boundaryWithId = boundary // {id = boundaryId boundary;};
    feature = featuresLib.activationFact {
      boundary = boundaryWithId;
      featureName = name;
      featureConfig = activation;
    };
    result = payload (moduleArgs
      // {
        inherit config lib options pkgs;
      }
      // extraContext
      // {
        boundary = boundaryWithId;
        inherit feature;
      });
    valid = isConfigFragment result;
  in {
    inherit imports;

    config = lib.mkMerge [
      {
        assertions = lib.optionals active [
          (payloadAssertion name result)
        ];
      }
      (lib.mkIf (active && valid) result)
    ];
  };

  hostBoundary = config: {
    class = "nixos";
    kind = config.local.context.boundaryKind or "nixos";
    name = config.local.context.nixosConfigurationName or config.networking.hostName or "host";
  };

  homeBoundary = config: {
    class = "homeManager";
    kind = "homeManager";
    name = config.local.context.homeConfigurationName;
  };
in rec {
  nixosProjectionModules =
    map
    ({
      name,
      feature,
    }: moduleArgs @ {
      config,
      options,
      pkgs,
      ...
    }:
        (wrapPayload {
          inherit name;
          imports = feature.projections.nixos.imports or [];
          payload = feature.projections.nixos.payload;
          activation = config.local.features.${name};
          boundary = hostBoundary config;
        }
        moduleArgs)
      // {
        _file = "flake.features.${name}.projections.nixos.payload";
      })
    (lib.filter ({feature, ...}: hasPayload ["projections" "nixos"] feature) nativeFeatureList);

  homeProjectionModules =
    map
    ({
      name,
      feature,
    }: moduleArgs @ {
      config,
      options,
      pkgs,
      ...
    }:
        (wrapPayload {
          inherit name;
          imports = feature.projections.homeManager.imports or [];
          payload = feature.projections.homeManager.payload;
          activation = config.local.features.${name};
          boundary = homeBoundary config;
          extraContext = {
            user = config.local.user // {name = config.local.user.name;};
          };
        }
        moduleArgs)
      // {
        _file = "flake.features.${name}.projections.homeManager.payload";
      })
    (lib.filter ({feature, ...}: hasPayload ["projections" "homeManager"] feature) nativeFeatureList);

  homeContributionModules =
    lib.concatMap (
      {
        name,
        feature,
      }:
        lib.mapAttrsToList (
          collectorName: contribution: moduleArgs @ {
            config,
            options,
            pkgs,
            ...
          }: let
            requiredFeatures = contribution.when.sameBoundary.features or [];
            requiredActive = lib.all (featureName: (config.local.features.${featureName}.enable or false) == true) requiredFeatures;
            contributorActive = (config.local.features.${name}.enable or false) == true;
            collectorActive = (config.local.features.${collectorName}.enable or false) == true;
          in
            (wrapPayload {
                inherit name;
                payload = contribution.payload;
                activation = config.local.features.${name};
                boundary = homeBoundary config;
                active = contributorActive && collectorActive && requiredActive;
                extraContext = {
                  collector = {
                    name = collectorName;
                    activation = featuresLib.activationFact {
                      boundary = homeBoundary config // {id = boundaryId (homeBoundary config);};
                      featureName = collectorName;
                      featureConfig = config.local.features.${collectorName};
                    };
                  };
                  user = config.local.user // {name = config.local.user.name;};
                };
              }
              moduleArgs)
            // {
              _file = "flake.features.${name}.contributions.homeManager.${collectorName}.payload";
            }
        )
        (lib.filterAttrs (_collectorName: contribution: (contribution.payload or null) != null) (feature.contributions.homeManager or {}))
    )
    nativeFeatureList;

  seededUserToNixosJoinModules = {
    hostName,
    seedModule,
  }: let
    users = usersLib.enabledUsers (seedModule.local.users or {});
    boundary = {
      class = "nixos";
      kind = "nixos";
      name = hostName;
    };
  in
    lib.concatMap (
      userName: let
        rawUser = users.${userName};
        user = removeAttrs rawUser ["_module" "features"] // {name = userName;};
        enabledFeatureNames = lib.attrNames (lib.filterAttrs (_name: featureConfig: (featureConfig.enable or false) == true) (rawUser.features or {}));
      in
        lib.concatMap (
          featureName: let
            feature = nativeFeatures.${featureName} or {};
          in
            lib.optionals (hasPayload ["joins" "userToNixos"] feature) [
              (moduleArgs @ {
                config,
                options,
                pkgs,
                ...
              }:
                (wrapPayload {
                    name = featureName;
                    payload = feature.joins.userToNixos.payload;
                    activation = rawUser.features.${featureName};
                    inherit boundary;
                    extraContext = {
                      inherit user;
                    };
                  }
                  moduleArgs)
                // {
                  _file = "flake.features.${featureName}.joins.userToNixos.payload:${userName}@${hostName}";
                })
            ]
        )
        enabledFeatureNames
    )
    (lib.attrNames users);

  seededNixosContainerModules = {
    hostName,
    seedModule,
    containerModules,
  }: let
    containers = seedModule.local.containers or {};
  in
    lib.mapAttrsToList (
      containerName: container: let
        containerConfig =
          {
            autoStart = container.autoStart or false;
            privateNetwork = container.privateNetwork or false;
            enableTun = container.enableTun or false;
            bindMounts = container.bindMounts or {};
            config = {lib, ...}: {
              imports = let
                activeFeatureNames = lib.attrNames (lib.filterAttrs (_name: featureConfig: (featureConfig.enable or false) == true) (container.features or {}));
                legacyModuleNames = lib.filter (featureName: builtins.hasAttr featureName nixosModules) activeFeatureNames;
                legacyModules = map (featureName: modulesLib.tagNixosModule featureName nixosModules.${featureName}) legacyModuleNames;
              in
                containerModules
                ++ legacyModules
                ++ [
                  {
                    networking.hostName = lib.mkDefault containerName;
                    system.stateVersion = lib.mkDefault "26.05";

                    local = {
                      features = featuresLib.compactFeatureSet (container.features or {});
                      users = {};
                      containers = {};
                      context = {
                        hostName = containerName;
                        nixosConfigurationName = containerName;
                        boundaryKind = "nixosContainer";
                      };
                    };
                  }
                ];
            };
          }
          // lib.optionalAttrs ((container.hostAddress or null) != null) {
            hostAddress = container.hostAddress;
          }
          // lib.optionalAttrs ((container.localAddress or null) != null) {
            localAddress = container.localAddress;
          };
        module = {
          config = {
            containers.${containerName} = containerConfig;

            networking.nat = lib.mkIf (container.nat.enable or false) ({
                enable = true;
                internalInterfaces = ["ve-${containerName}"];
              }
              // lib.optionalAttrs ((container.nat.externalInterface or null) != null) {
                externalInterface = container.nat.externalInterface;
              });
          };
        };
      in
        module
    )
    containers;

  seededNixosContainerToHostJoinModules = {
    hostName,
    seedModule,
  }: let
    containers = seedModule.local.containers or {};
    boundary = {
      class = "nixos";
      kind = "nixos";
      name = hostName;
    };
  in
    lib.concatMap (
      containerName: let
        container =
          containers.${containerName}
          // {
            name = containerName;
            parent = hostName;
          };
        enabledFeatureNames = lib.attrNames (lib.filterAttrs (_name: featureConfig: (featureConfig.enable or false) == true) (container.features or {}));
        fragments = lib.flatten (map (
            featureName: let
              feature = nativeFeatures.${featureName} or {};
            joinModule = moduleArgs @ {
              config,
              options,
              pkgs,
              ...
            }: let
                module =
                  wrapPayload {
                    name = featureName;
                    payload = feature.joins.nixosContainerToHost.payload;
                    activation = container.features.${featureName};
                    inherit boundary;
                    extraContext = {
                      inherit container;
                    };
                  }
                  moduleArgs;
              in
                module
                // {
                  _file = "flake.features.${featureName}.joins.nixosContainerToHost.payload:${containerName}@${hostName}";
                };
            in
              lib.optionals (hasPayload ["joins" "nixosContainerToHost"] feature) [joinModule]
          )
          enabledFeatureNames);
      in
        fragments
    )
    (lib.attrNames containers);
}
