{
  lib,
  fpConfig,
}: rec {
  policyForFeatures = features: let
    enabledNames =
      lib.attrNames
      (lib.filterAttrs (_name: feature: (feature.enable or false) == true) features);

    policies = map (name:
      mergePolicies [
        (fpConfig.flake.local.featurePolicies.${name} or {})
        (fpConfig.flake.features.${name}.policy or {})
      ])
    enabledNames;
  in {
    unfree = lib.concatMap (policy: policy.unfree or []) policies;
    permittedInsecure = lib.concatMap (policy: policy.permittedInsecure or []) policies;
  };

  mergePolicies = policies: {
    unfree = lib.concatMap (policy: policy.unfree or []) policies;
    permittedInsecure = lib.concatMap (policy: policy.permittedInsecure or []) policies;
  };
}
