{cross, ...}:
cross.module {
  name = "osu-lazer";

  ambient = [
    cross.pkgs.unstable
    (cross.pkgs.unfree "osu-lazer-bin")
    (cross.pkgs.insecure [
      "dotnet-sdk-6.0.428"
      "dotnet-sdk-wrapped-6.0.428"
      "dotnet-runtime-6.0.36"
    ])
  ];

  home.packages = pkgs: [
    pkgs.unstable.osu-lazer-bin
  ];
}
