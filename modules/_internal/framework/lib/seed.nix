{
  lib,
  featuresLib,
  usersLib,
}: rec {
  compactContext = context:
    lib.filterAttrs (_name: value: value != null) context;

  # Convert the typed flake-parts host seed back into a plain NixOS module.
  # This keeps editor-visible seed options while preventing null/default seed state from leaking downstream.
  compactNixosSeedModule = module: let
    local = module.local or {};
    rest = removeAttrs module ["_module" "local"];
  in
    rest
    // {
      local =
        {
          features = featuresLib.compactFeatureSet (local.features or {});
          users = usersLib.compactNixosUsers (local.users or {});
        }
        // lib.optionalAttrs (local ? context) {
          context = compactContext local.context;
        };
    };

  # Convert the typed flake-parts Home Manager seed back into a plain HM module.
  # Filter null fields inside local.user / local.context and skip the wrapper when the filtered value is empty,
  # so that "unspecified" semantics are preserved and default-null seed values do not leak downstream.
  compactHomeSeedModule = module: let
    local = module.local or {};
    rest = removeAttrs module ["_module" "local"];

    compactUser =
      if (local ? user)
      then lib.filterAttrs (_n: v: v != null) local.user
      else {};

    compactCtx =
      if (local ? context)
      then lib.filterAttrs (_n: v: v != null) local.context
      else {};
  in
    rest
    // lib.optionalAttrs (module ? local) {
      local =
        lib.optionalAttrs (local ? features) {
          features = featuresLib.compactFeatureSet local.features;
        }
        // lib.optionalAttrs (compactCtx != {}) {
          context = compactCtx;
        }
        // lib.optionalAttrs (compactUser != {}) {
          user = compactUser;
        };
    };
}
