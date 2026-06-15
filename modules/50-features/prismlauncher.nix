{
  flake.local.featurePolicies.prismlauncher.unfree = [
    "prismlauncher"
  ];

  flake.modules.nixos.prismlauncher = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.prismlauncher.enable {};
  };

  flake.modules.homeManager.prismlauncher = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.prismlauncher.enable {
      home.packages = [
        (pkgs.unstable.prismlauncher.override {jdks = [pkgs.unstable.jdk21];})
      ];
    };
  };
}
