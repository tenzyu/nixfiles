{inputs, self, ...}: {
  # Production placement belongs here, not in the generic execution platform.
  # Evaluate the original upstream module in isolation; take its native unit
  # and TOML as a single deployable profile. No second Home Manager activation.
  perSystem = {system, lib, ...}: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      neko7-splitcast-runtime = let
        pkgs = self.nixosConfigurations.neko7.pkgs;
        hm = inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            inputs.splitcast.homeManagerModules.default
            {
              home = {
                username = "tenzyu";
                homeDirectory = "/home/tenzyu";
                stateVersion = "26.05";
              };
              xdg.enable = true;
              services.splitcast = {
                enable = true;
                role = "production";
                rustCandidate = false;
                settings.peer.ssh_host = "neko5";
              };
            }
          ];
        };
        cfg = hm.config;
      in pkgs.runCommand "neko7-splitcast-runtime" {} ''
        mkdir -p "$out/share/systemd/user" "$out/share/splitcast"
        ln -s ${cfg.services.splitcast.package}/bin "$out/bin"
        ln -s ${cfg.xdg.configFile."systemd/user/splitcast-production.service".source} \
          "$out/share/systemd/user/splitcast-production.service"
        ln -s ${cfg.xdg.configFile."splitcast/production.toml".source} \
          "$out/share/splitcast/production.toml"
      '';
    };
  };
}
