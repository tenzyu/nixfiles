{cross, ...}:
cross.module {
  name = "parsec";

  ambient = [
    (cross.pkgs.unfree "parsec-bin")
  ];

  home.packages = pkgs: [
    pkgs.parsec-bin
  ];
}
