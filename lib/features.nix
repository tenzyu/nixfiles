{lib}: rec {
  # A missing feature is disabled; explicit false remains disabled.
  featureEnabled = name: features: features.${name}.enable or false;

  enabledFeatureNames = features:
    lib.attrNames (lib.filterAttrs (_: feature: feature.enable or false) features);
}
