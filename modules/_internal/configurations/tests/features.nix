{lib}: let
  featuresLib = import ../lib/features.nix {inherit lib;};
in {
  testEmbeddedHomeProjectsNativeEnabledFeatures = {
    expr = let
      evaluated = lib.evalModules {
        modules = [
          {options.features = featuresLib.actualFeatureOptions ["alpha" "beta" "gamma"];}
          {config.features = {alpha.enable = true; beta.enable = false;};}
        ];
      };
    in featuresLib.embeddedHomeFeatures {} evaluated.config.features;
    expected = {
      alpha = {enable = true;};
    };
  };

  testCompactFeatureSetDropsNullAndMissing = {
    expr = featuresLib.compactFeatureSet {
      alpha = {enable = true;};
      beta = {enable = false;};
      gamma = {enable = null;};
      delta = {};
    };
    expected = {
      alpha = {enable = true;};
      beta = {enable = false;};
    };
  };

  testCompactFeatureSetPreservesExplicitFalse = {
    expr = featuresLib.compactFeatureSet {
      alpha = {enable = false;};
    };
    expected = {
      alpha = {enable = false;};
    };
  };

  testActualFeatureOptionsKeys = {
    expr = lib.attrNames (featuresLib.actualFeatureOptions ["alpha" "beta"]);
    expected = ["alpha" "beta"];
  };

  testActualFeatureOptionsEnableShape = let
    opt = (featuresLib.actualFeatureOptions ["alpha"]).alpha.enable;
  in {
    expr = {
      optionType = opt._type;
      default = opt.default;
      example = opt.example;
      description = opt.description;
      typeName = opt.type.name;
    };
    expected = {
      optionType = "option";
      default = false;
      example = true;
      description = "Whether to enable alpha.";
      typeName = "bool";
    };
  };

  testSeedFeatureOptionsKeys = {
    expr = lib.attrNames (featuresLib.seedFeatureOptions ["alpha" "beta"]);
    expected = ["alpha" "beta"];
  };

  testSeedFeatureOptionsEnableShape = let
    opt = (featuresLib.seedFeatureOptions ["alpha"]).alpha.enable;
  in {
    expr = {
      optionType = opt._type;
      default = opt.default;
      typeName = opt.type.name;
    };
    expected = {
      optionType = "option";
      default = null;
      typeName = "nullOr";
    };
  };

  testEmbeddedHomePreservesExplicitSelectionsAndNativeTrue = {
    expr = featuresLib.embeddedHomeFeatures {
      alpha.enable = null;
      beta.enable = false;
      gamma.enable = true;
      delta.enable = null;
      epsilon.enable = false;
      zeta.enable = true;
    } {
      alpha.enable = false;
      beta.enable = false;
      gamma.enable = true;
      delta.enable = true;
      epsilon.enable = true;
      zeta.enable = false;
      eta.enable = false;
    };
    expected = {
      beta.enable = false;
      gamma.enable = true;
      delta.enable = true;
      epsilon.enable = true;
      zeta.enable = false;
    };
  };

  testEmbeddedHomeDoesNotForwardImplicitFalse = {
    expr = featuresLib.embeddedHomeFeatures {} {
      implicit.enable = false;
      nativeDefault.enable = true;
    };
    expected = {nativeDefault.enable = true;};
  };
}
