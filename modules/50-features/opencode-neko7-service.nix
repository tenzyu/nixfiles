{inputs, ...}: {
  flake.modules.homeManager.opencode-neko7-service = {config, lib, pkgs, ...}: let
    opencode = inputs.nixpkgs-opencode.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opencode;
  in {
    # Review-only migration candidate. Do not enable while the existing
    # manually managed unit owns this name and port.
    config = lib.mkIf config.local.features.opencode-neko7-service.enable {
      assertions = [{
        assertion = opencode.version == "2.2.1";
        message = "opencode-neko7-service requires the reviewed OpenCode 2.2.1 package; see docs/opencode-neko7-migration.md";
      }];
      systemd.user.services.opencode-neko7-persistent = {
        Unit = {
          Description = "OpenCode v2 development server";
          After = ["network-online.target"];
        };
        Service = {
          WorkingDirectory = "/home/tenzyu/dev/tenzyudotcom";
          EnvironmentFile = "/home/tenzyu/dev/opencode-mission-20261102/server.env";
          Environment = ["PATH=/home/tenzyu/.local/state/nix/profile/bin:/run/current-system/sw/bin:/etc/profiles/per-user/tenzyu/bin:${lib.getBin pkgs.unstable.ripgrep}/bin"];
          ExecStart = "${lib.getExe opencode} serve --hostname 127.0.0.1 --port 4096";
          Restart = "on-failure";
          RestartSec = 5;
          MemoryAccounting = true;
          TasksAccounting = true;
          TasksMax = 38450;
          LimitNOFILE = 524288;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
