{
  flake.features.rtk.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = [pkgs.llm-agents.rtk];
  };
}
