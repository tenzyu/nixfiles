{inputs, self, ...}: {
  perSystem = {pkgs, system, ...}: let
    inherit (inputs.nixpkgs) lib;
    root = ../_internal/configurations;
    shared = ../../lib;
    suites = {
      shared = import (shared + "/tests.nix") {inherit lib;};
      features = import (root + "/tests/features.nix") {inherit lib;};
      users = import (root + "/tests/users.nix") {inherit lib;};
      policies = import (root + "/tests/policies.nix") {inherit lib;};
      seed = import (root + "/tests/seed.nix") {
        inherit lib;
        composition = import (shared + "/composition.nix") {inherit lib;};
      };
      modules = import (root + "/tests/modules.nix") {inherit lib;};
      steam = import (root + "/tests/integrations-steam.nix") {
        inherit lib;
        integrationModule = (import ../60-integrations/desktop/steam-hyprland.nix).flake.modules.homeManager.steam;
      };
      parsec = import (root + "/tests/integrations.nix") {
        inherit lib;
        integrationModule = (import ../60-integrations/desktop/parsec-hyprland.nix).flake.modules.homeManager.parsec;
      };
    };
    unitFailures = lib.concatLists (lib.mapAttrsToList
      (suite: tests: map (failure: suite + "." + failure.name) (lib.runTests tests))
      suites);
    adapterFailures = map (failure: failure.name)
      (import (root + "/tests/configurations.nix") {flake = self;}).failures;
    types = let
      inherit (self.debug.options.configurations) nixos homeManager;
      localOptions = kind: name: (((kind.type.getSubOptions [name]).module.type.getSubOptions []).local);
      os = localOptions nixos "neko7";
      user = os.users.type.getSubOptions ["tenzyu"];
      hm = localOptions homeManager "standalone";
    in [
      nixos.type.name
      homeManager.type.name
      os.features.ssh.enable.type.name
      user.features.steam.enable.type.name
      hm.features.steam.enable.type.name
    ];
    failures = unitFailures ++ adapterFailures ++ lib.optional
      (types != ["attrsOf" "attrsOf" "nullOr" "nullOr" "nullOr"])
      "typed host and user feature options";
  in {
    validationChecks = lib.optionalAttrs (system == "x86_64-linux") {
      framework =
      assert lib.assertMsg (failures == []) ("Nix configuration regressions: " + builtins.toJSON failures);
      pkgs.runCommand "framework-check" {} "touch $out";
    };
  };
}
