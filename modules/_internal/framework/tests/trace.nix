{lib, traceLib}: let
  trace = traceLib {inherit lib;};
  fakeFlake = {
    nixosConfigurations.testhost = {
      config = {
        local.features = {
          alpha.enable = true;
          beta.enable = false;
        };
        local.users = {};
      };
      options = {};
    };
  };
  names = feature: map (row: row.name) (trace.traceHost {
    flake = fakeFlake;
    repo = ./.;
    host = "testhost";
    scope = "system";
    inherit feature;
  }).system;
in {
  testFilteredTraceIncludesExplicitlyDisabledFeature = {
    expr = names "beta";
    expected = ["beta"];
  };

  testUnfilteredTraceIncludesOnlyEnabledFeatures = {
    expr = names null;
    expected = ["alpha"];
  };
}
