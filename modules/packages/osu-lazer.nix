{
  local.cross.definitions.osu-lazer = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
      {
        policy.pkgs.allowUnfreeNames = ["osu-lazer-bin"];
      }
      {
        policy.pkgs.permittedInsecurePackages = [
          "dotnet-sdk-6.0.428"
          "dotnet-sdk-wrapped-6.0.428"
          "dotnet-runtime-6.0.36"
        ];
      }
    ];

    home.packages = pkgs: [
      pkgs.unstable.osu-lazer-bin
    ];
  };
}
