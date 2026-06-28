{
  flake.features.git-tools.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = with pkgs; [
      gh
      lazygit
    ];
  };
}
