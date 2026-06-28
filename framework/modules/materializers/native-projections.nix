{
  lib,
  featuresLib,
  usersLib,
  nativeFeatures,
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
    extraContext ? {},
  }: moduleArgs @ {lib, ...}: let
    active = activation.enable or false;
    boundaryWithId = boundary // {id = boundaryId boundary;};
    feature = featuresLib.activationFact {
      boundary = boundaryWithId;
      featureName = name;
      featureConfig = activation;
    };
    result = payload (moduleArgs
      // extraContext
      // {
        boundary = boundaryWithId;
        inherit feature;
      });
    valid = isConfigFragment result;
  in {
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
    kind = "nixos";
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
    }: moduleArgs @ {config, ...}:
      (wrapPayload {
          inherit name;
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
    }: moduleArgs @ {config, ...}:
      (wrapPayload {
          inherit name;
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
              (moduleArgs:
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
}
