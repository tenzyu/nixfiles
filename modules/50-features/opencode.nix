{
  flake.features.opencode.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = [pkgs.llm-agents.opencode];
  };
}
