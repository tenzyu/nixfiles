{cross, ...}:
cross.module {
  name = "discord";

  ambient = [
    cross.pkgs.unstable
    (cross.pkgs.unfree "discord")
  ];

  home.packages = pkgs: [
    pkgs.unstable.discord
  ];
}
