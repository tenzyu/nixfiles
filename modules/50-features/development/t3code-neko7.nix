{inputs, ...}: {
  perSystem = {system, lib, ...}: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      neko7-t3-runtime = let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        t3code = inputs.nixpkgs-unstable.legacyPackages.${system}.t3code.override {
          enableCodex = false;
          enableOpencode = false;
        };
        codex = inputs.llm-agents.packages.${system}.codex;
      in pkgs.buildEnv {
        name = "neko7-t3-runtime";
        paths = [t3code codex pkgs.git pkgs.gh pkgs.direnv pkgs.coreutils pkgs.bash];
        pathsToLink = ["/bin"];
      };
    };
  };

  flake.modules.homeManager.t3code-neko7 = {
    config,
    lib,
    ...
  }: let
    # This native Nix profile is updated independently of NixOS/HM. Keep
    # the incumbent unit identity, HOME, port and provider discovery.
    profile = "${config.xdg.stateHome}/nix/profiles/t3-runtime";
  in {
    config = lib.mkIf config.local.features.t3code-neko7.enable {
      home.sessionPath = ["${profile}/bin"];

      # A separate unit avoids overwriting T3's own t3code.service or the
      # existing, manually managed OpenCode service on neko7.
      systemd.user.services.t3code-neko7 = {
        Unit = {
          Description = "T3 Code control plane (neko7)";
          After = ["network-online.target"];
        };
        Service = {
          Type = "simple";
          WorkingDirectory = config.home.homeDirectory;
          ExecStart = "${profile}/bin/t3 serve";
          Environment = [
            "T3CODE_HOST=127.0.0.1"
            "T3CODE_PORT=3773"
            "T3CODE_TELEMETRY_ENABLED=false"
            # Provider discovery happens in the non-interactive systemd
            # environment, not the user's interactive shell.
            "PATH=${profile}/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin"
          ];
          UMask = "0077";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install.WantedBy = ["default.target"];
      };
    };
  };
}
