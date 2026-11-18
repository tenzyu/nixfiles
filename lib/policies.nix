{
  lib,
  features,
}: rec {
  mergePolicies = policies: {
    unfree = lib.concatMap (policy: policy.unfree or []) policies;
    permittedInsecure = lib.concatMap (policy: policy.permittedInsecure or []) policies;
  };

  policyForFeatures = flakeConfig: selectedFeatures:
    mergePolicies (
      map
      (name: flakeConfig.flake.local.featurePolicies.${name} or {})
      (features.enabledFeatureNames selectedFeatures)
    );
}
