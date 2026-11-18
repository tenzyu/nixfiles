{
  lib,
  featuresLib,
  usersLib,
  composition,
}: rec {
  dropNullFields = context:
    lib.filterAttrs (_: value: value != null) context;

  compactNixosSeedModule = (composition.namedPipeline {
    label = "nixos-seed-projection";
    steps = [
      {
        name = "read-typed-host-seed";
        run = module: {original = module; local = module.local or {};};
      }
      {
        name = "compact-feature-user-context";
        run = state: state // {
          projectedLocal = (composition.namedDisjoint {
            label = "nixos-seed.local";
            layers = [
              {
                name = "feature-and-user-selection";
                attrs = {
                  features = featuresLib.compactFeatureSet (state.local.features or {});
                  users = usersLib.compactNixosUsers (state.local.users or {});
                };
              }
              {
                name = "optional-host-context";
                attrs = lib.optionalAttrs (state.local ? context) {
                  context = dropNullFields state.local.context;
                };
              }
            ];
          }).merged;
        };
      }
      {
        name = "emit-native-nixos-module";
        run = state:
          (removeAttrs state.original ["_module" "local"])
          // {local = state.projectedLocal;};
      }
    ];
  }).run;

  compactHomeSeedModule = (composition.namedPipeline {
    label = "home-manager-seed-projection";
    steps = [
      {
        name = "read-typed-home-seed";
        run = module: {original = module; local = module.local or {};};
      }
      {
        name = "compact-nullable-user-and-context";
        run = state: let
          compactUser = dropNullFields (state.local.user or {});
          compactCtx = dropNullFields (state.local.context or {});
        in state // {
          projectedLocal = (composition.namedDisjoint {
            label = "home-manager-seed.local";
            layers = [
              {
                name = "feature-selection";
                attrs = lib.optionalAttrs (state.local ? features) {
                  features = featuresLib.compactFeatureSet state.local.features;
                };
              }
              {
                name = "optional-context";
                attrs = lib.optionalAttrs (compactCtx != {}) {context = compactCtx;};
              }
              {
                name = "optional-user";
                attrs = lib.optionalAttrs (compactUser != {}) {user = compactUser;};
              }
            ];
          }).merged;
        };
      }
      {
        name = "emit-native-home-manager-module";
        run = state:
          (removeAttrs state.original ["_module" "local"])
          // lib.optionalAttrs (state.original ? local) {
            local = state.projectedLocal;
          };
      }
    ];
  }).run;
}
