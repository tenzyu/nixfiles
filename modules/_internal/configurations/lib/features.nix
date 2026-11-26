{lib}: rec {
  actualFeatureOptions = featureNames:
    lib.genAttrs featureNames (featureName: {
      enable = lib.mkEnableOption featureName;
    });

  # Seed options are for the flake-parts-side host declaration surface.
  # Use null instead of false so "not specified" does not propagate as an explicit disabled feature.
  seedFeatureOptions = featureNames:
    lib.genAttrs featureNames (featureName: {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Seed activation for ${featureName}.

          null means "not specified in this seed module".
          true/false are emitted into the real module passed to the target module system.
        '';
      };
    });

  # A typed host seed is tri-state; the evaluated NixOS user option is bool.
  # Only an explicit seed choice OR a native effective true emits an HM definition.
  # In particular, a native false alone must not suppress HM mkDefault true.
  embeddedHomeFeatures = selectedFeatures: evaluatedFeatures:
    lib.mapAttrs (_name: feature: {inherit (feature) enable;}) (
      lib.filterAttrs
        (name: feature: (selectedFeatures.${name}.enable or null) != null || feature.enable)
        evaluatedFeatures
    );

  # Remove null seed values before handing the module to NixOS/Home Manager.
  # This preserves "unspecified" semantics and avoids seed defaults overriding real module defaults.
  compactFeatureSet = features:
    lib.mapAttrs (_name: feature: {enable = feature.enable;}) (lib.filterAttrs (_name: feature: (feature.enable or null) != null) features);
}
