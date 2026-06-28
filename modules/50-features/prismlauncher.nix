{
  flake.local.featurePolicies.prismlauncher.unfree = [
    "prismlauncher"
  ];

  flake.features.prismlauncher.projections.homeManager.payload = {
    pkgs,
    ...
  }: {
    home.packages = [
      (pkgs.unstable.prismlauncher.override {jdks = [pkgs.unstable.jdk21];})
    ];
  };
}
