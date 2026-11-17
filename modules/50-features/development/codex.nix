{...}: {
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
