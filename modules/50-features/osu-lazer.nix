{
  flake.local.featurePolicies.osu-lazer.unfree = [
    "osu-lazer-bin"
  ];

  flake.local.featurePolicies.osu-lazer.permittedInsecure = [
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
  ];

  flake.modules.nixos.osu-lazer = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.osu-lazer.enable {};
  };

  flake.modules.homeManager.osu-lazer = {
    config,
    lib,
    pkgs,
    ...
  }: let
    osuLauncher = pkgs.writeShellScriptBin "osu-lazer" ''
      set -euo pipefail

      for candidate in \
        "${pkgs.unstable.osu-lazer-bin}/bin/osu!" \
        "${pkgs.unstable.osu-lazer-bin}/bin/osu-lazer" \
        "${pkgs.unstable.osu-lazer-bin}/bin/osu"
      do
        if [ -x "$candidate" ]; then
          exec "$candidate" "$@"
        fi
      done

      echo "osu-lazer: executable not found in ${pkgs.unstable.osu-lazer-bin}/bin" >&2
      exit 127
    '';

    osuLaunchers = pkgs.runCommand "osu-lazer-launchers" {} ''
      mkdir -p "$out/bin"
      ln -s ${osuLauncher}/bin/osu-lazer "$out/bin/osu-lazer"
      ln -s ${osuLauncher}/bin/osu-lazer "$out/bin/osu-lazer-raw"
    '';
  in {
    config = lib.mkIf config.local.features.osu-lazer.enable {
      home.packages = [osuLaunchers];

      xdg.desktopEntries.osu-lazer = {
        name = "osu! lazer";
        genericName = "Rhythm Game";
        exec = "osu-lazer";
        terminal = false;
        categories = ["Game"];
        comment = "Launch osu! lazer directly.";
      };
    };
  };
}
