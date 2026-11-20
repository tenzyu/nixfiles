{...}: {
  # System-provided bwrap stays outside agent-writable paths and is visible
  # to both interactive Codex and the T3 user service via /run/current-system/sw/bin.
  flake.modules.nixos.codex-sandbox = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.codex-sandbox.enable {
      environment.systemPackages = [pkgs.bubblewrap];
    };
  };

  flake.modules.homeManager.codex = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.codex.enable {
      home.packages = [pkgs.llm-agents.codex];
    };
  };
}
