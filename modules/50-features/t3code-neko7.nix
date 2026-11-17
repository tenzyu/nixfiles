{...}: {
  flake.modules.homeManager.t3code-neko7 = {
    config,
    lib,
    pkgs,
    ...
  }: let
    codex = pkgs.llm-agents.codex;
    # Codex is pinned by llm-agents.nix in flake.lock. Avoid bringing in
    # a second Codex binary from the unstable nixpkgs T3 wrapper.
    t3code = pkgs.unstable.t3code.override {
      enableCodex = false;
      enableOpencode = false;
    };
  in {
    config = lib.mkIf config.local.features.t3code-neko7.enable {
      home.packages = [t3code];

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
          ExecStart = "${lib.getExe' t3code "t3"} serve";
          Environment = [
            "T3CODE_HOST=127.0.0.1"
            "T3CODE_PORT=3773"
            "T3CODE_TELEMETRY_ENABLED=false"
            # Provider discovery happens in the non-interactive systemd
            # environment, not the user's interactive shell.
            "PATH=${lib.makeBinPath [codex pkgs.git pkgs.gh pkgs.direnv pkgs.coreutils pkgs.bash]}:/run/current-system/sw/bin:/etc/profiles/per-user/${config.home.username}/bin"
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
