{inputs, ...}: {
  flake.features.onair.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = [
      inputs.onair.packages.${pkgs.system}.default
    ];
  };
}
