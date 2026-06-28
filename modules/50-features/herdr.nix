{...}: {
  flake.features.herdr.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = [pkgs.llm-agents.herdr];
  };
}
