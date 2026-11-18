{
  lib,
  traceLib,
}: let
  trace = traceLib {inherit lib;};
  evaluated = lib.evalModules {
    modules = [
      {
        options.local.features.beta.enable = lib.mkEnableOption "beta";
        config.local.features.beta.enable = lib.mkDefault true;
      }
      {
        _file = "/fixture-flake/modules/50-features/root.nix";
        config.local.features.beta.enable = false;
      }
    ];
  };
  fakeFlake = {
    outPath = "/fixture-flake";
    nixosConfigurations.testhost = {
      config = {
        local.features = {
          alpha.enable = true;
          beta.enable = false;
        };
        local.users.alice.features.bar.enable = true;
        home-manager.users.alice.local.features.bar.enable = true;
      };
      inherit (evaluated) options;
    };
  };
  base = {
    flake = fakeFlake;
    repo = ./fixtures/trace-repo;
    host = "testhost";
  };
  names = feature:
    map (row: row.name)
    (trace.traceHost (base
      // {
        scope = "system";
        inherit feature;
      })).system;
in {
  testEvaluatedDefinitionAndSourceHintAreSeparate = {
    expr = let
      record = builtins.head (trace.traceHost (base // {feature = "beta";})).system;
      why = trace.traceWhy (base // {option = "local.features.beta.enable";});
    in {
      inherit (record) status;
      evaluated = map (d: {inherit (d) source value origin;}) record.definitions;
      hints = map (d: {inherit (d) source value origin;}) record.source_hints;
      whyMatches = why.definitions == record.definitions && why.effective == "false";
    };
    expected = {
      status = "disabled";
      evaluated = [
        {
          source = "modules/50-features/root.nix";
          value = false;
          origin = "definitionsWithLocations";
        }
      ];
      hints = [
        {
          source = "modules/00-hosts/testhost/configuration.nix";
          value = true;
          origin = "text-scan";
        }
      ];
      whyMatches = true;
    };
  };

  testHomeTraceKeepsEffectiveStatusAndSourceHints = {
    expr = let
      record =
        builtins.head
        (trace.traceHost (base
          // {
            scope = "home";
            feature = "bar";
            user = "alice";
          })).home;
    in {
      inherit (record) user hm_enabled home_seed_enabled definitions;
      activationOrigin = (builtins.head record.activations).origin;
      hintSource = (builtins.head record.source_hints).source;
    };
    expected = {
      user = "alice";
      hm_enabled = true;
      home_seed_enabled = true;
      definitions = [];
      activationOrigin = "text-scan";
      hintSource = "modules/00-hosts/testhost/configuration.nix";
    };
  };

  testFilteredTraceIncludesExplicitlyDisabledFeature = {
    expr = names "beta";
    expected = ["beta"];
  };

  testUnfilteredTraceIncludesOnlyEnabledFeatures = {
    expr = names null;
    expected = ["alpha"];
  };

  testFeatureDiscoveryIsRecursiveAndSkipsPrivateDirectories = {
    expr = map (file: file.rel) (trace.featureFiles ./fixtures/trace-repo);
    expected = [
      "modules/50-features/root.nix"
      "modules/50-features/ui/bar.nix"
    ];
  };

  testFeatureDiscoveryKeepsLeafNames = {
    expr = map (file: file.featureName) (trace.featureFiles ./fixtures/trace-repo);
    expected = ["root" "bar"];
  };
}
