{
  lib,
  fpConfig,
}: rec {
  policyForFeatures = features: let
    enabledNames =
      lib.attrNames
      (lib.filterAttrs (_name: feature: feature.enable or false) features);

    policies =
      map (name: fpConfig.flake.local.featurePolicies.${name} or {}) enabledNames;
  in {
    unfree = lib.concatMap (policy: policy.unfree or []) policies;
    permittedInsecure = lib.concatMap (policy: policy.permittedInsecure or []) policies;
  };

  mergePolicies = policies: {
    unfree = lib.concatMap (policy: policy.unfree or []) policies;
    permittedInsecure = lib.concatMap (policy: policy.permittedInsecure or []) policies;
  };
}
