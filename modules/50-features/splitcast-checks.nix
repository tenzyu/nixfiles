{inputs, self, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    package = self.packages.${system}.splitcast;
    capture = self.nixosConfigurations.neko5.config.home-manager.users.tenzyu.local.features.splitcast-capture.configFile;
    production = self.nixosConfigurations.neko7.config.home-manager.users.tenzyu.local.features.splitcast-production.configFile;
  in {
    checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      splitcast-configs = pkgs.runCommand "splitcast-host-configs-check" {} ''
        ${package}/bin/splitcast validate --config ${capture}
        ${package}/bin/splitcast validate --config ${production}
        touch "$out"
      '';
    };
  };
}
