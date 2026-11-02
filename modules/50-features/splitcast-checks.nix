{
  inputs,
  self,
  ...
}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs.legacyPackages.${system};
    package = self.packages.${system}.splitcast;
    capture = self.nixosConfigurations.neko5.config.home-manager.users.tenzyu.local.features.splitcast-capture.configFile;
    production = self.nixosConfigurations.neko7.config.home-manager.users.tenzyu.local.features.splitcast-production.configFile;
  in {
    checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      splitcast-configs = pkgs.runCommand "splitcast-host-configs-check" {} ''
        export PYTHONPATH=${package}/lib/splitcast
        ${package.python}/bin/python - <<'PY'
        from pathlib import Path
        from splitcast.config import Config

        for filename, role, port, remote, host in [
            ("${capture}", "capture", 17870, 17871, "neko7"),
            ("${production}", "production", 17871, 17870, "neko5"),
        ]:
            config = Config.load(filename)
            assert config["role"] == role
            assert config["peer"]["control_port"] == port
            assert config["peer"]["remote_control_port"] == remote
            assert config["peer"]["ssh_host"] == host
            assert Path(config["audio"]["rnnoise_plugin"]).is_file()
            assert Path(config["obs"]["binary"]).is_file()
        PY
        touch "$out"
      '';
    };
  };
}
