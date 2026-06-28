{lib}: rec {
  publicFeatureAttrs = attrs:
    lib.filterAttrs (name: _value: !(lib.hasPrefix "_" name)) attrs;

  featureSettingOptions = feature: let
    schema = feature.options or {};
  in
    if builtins.isFunction schema
    then schema {inherit lib;}
    else schema;

  actualFeatureOptions = featureNames:
    lib.genAttrs featureNames (featureName: {
      enable = lib.mkEnableOption featureName;
    });

  actualFeatureOptionsWithSchemas = featureNames: nativeFeatures:
    lib.genAttrs featureNames (featureName:
      {
        enable = lib.mkEnableOption featureName;
      }
      // featureSettingOptions (nativeFeatures.${featureName} or {}));

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

  seedFeatureOptionsWithSchemas = featureNames: nativeFeatures:
    lib.genAttrs featureNames (featureName:
      {
        enable = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          description = ''
            Seed activation for ${featureName}.

            null means "not specified in this seed module".
            true/false are emitted into the real module passed to the target module system.
          '';
        };
      }
      // featureSettingOptions (nativeFeatures.${featureName} or {}));

  enabledFeatures = features:
    lib.mapAttrs (_name: feature: (removeAttrs feature ["_module"]) // {enable = true;}) (lib.filterAttrs (_name: feature: (feature.enable or false) == true) features);

  activationFact = {
    boundary,
    featureName,
    featureConfig,
  }: {
    boundary = boundary.id;
    feature = featureName;
    name = featureName;
    enable = featureConfig.enable or false;
    settings = removeAttrs featureConfig ["_module" "enable"];
  };

  # Remove null seed values before handing the module to NixOS/Home Manager.
  # This preserves "unspecified" semantics and avoids seed defaults overriding real module defaults.
  compactFeatureSet = features:
    lib.mapAttrs (_name: feature: removeAttrs feature ["_module"]) (lib.filterAttrs (_name: feature: (feature.enable or null) != null) features);
}
