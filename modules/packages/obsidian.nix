{cross, ...}:
cross.module {
  name = "obsidian";

  ambient = [
    (cross.pkgs.unfree "obsidian")
  ];

  home.packages = pkgs: [
    pkgs.obsidian
  ];
}
