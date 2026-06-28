{
  flake.features.disk-tools.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = with pkgs; [
      qdirstat
    ];
  };
}
