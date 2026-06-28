{
  flake.features.nix-tools.projections.homeManager.payload = {pkgs, ...}: {
    home.packages = with pkgs; [
      nh
      jq
      jqp
      zip
      ncdu
      crosspipe
    ];
  };
}
