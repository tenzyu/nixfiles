{cross, ...}:
cross.module {
  name = "prismlauncher";

  ambient = [
    cross.pkgs.unstable
    (cross.pkgs.unfree "prismlauncher")
  ];

  home.packages = pkgs: [
    pkgs.unstable.prismlauncher
  ];
}
