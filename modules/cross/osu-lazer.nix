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

    home.module = {pkgs, ...}: let
      osuLazer = pkgs.unstable.osu-lazer-bin;
    in {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "osu-lazer";
          runtimeInputs = with pkgs; [coreutils gamemode gamescope];
          text = ''
            set -euo pipefail

            osu_exe=""
            for candidate in \
              "${osuLazer}/bin/osu!" \
              "${osuLazer}/bin/osu-lazer" \
              "${osuLazer}/bin/osu"
            do
              if [ -x "$candidate" ]; then
                osu_exe="$candidate"
                break
              fi
            done

            if [ -z "$osu_exe" ]; then
              echo "osu-lazer: executable not found in ${osuLazer}/bin" >&2
              exit 127
            fi

            if command -v hypr-gaming-mode >/dev/null 2>&1; then
              hypr-gaming-mode on || true
              trap 'hypr-gaming-mode off || true' EXIT INT TERM
            fi

            exec gamemoderun "$osu_exe" "$@"
          '';
        })

        (pkgs.writeShellApplication {
          name = "osu-lazer-raw";
          runtimeInputs = [pkgs.coreutils];
          text = ''
            set -euo pipefail

            osu_exe=""
            for candidate in \
              "${osuLazer}/bin/osu!" \
              "${osuLazer}/bin/osu-lazer" \
              "${osuLazer}/bin/osu"
            do
              if [ -x "$candidate" ]; then
                osu_exe="$candidate"
                break
              fi
            done

            if [ -z "$osu_exe" ]; then
              echo "osu-lazer-raw: executable not found in ${osuLazer}/bin" >&2
              exit 127
            fi

            exec "$osu_exe" "$@"
          '';
        })
      ];

      xdg.desktopEntries.osu-lazer = {
        name = "osu! lazer";
        genericName = "Rhythm Game";
        exec = "osu-lazer";
        terminal = false;
        categories = ["Game"];
        comment = "Run osu! lazer through GameMode and Gamescope.";
      };

      xdg.desktopEntries.osu-lazer-raw = {
        name = "osu! lazer Raw";
        genericName = "Rhythm Game";
        exec = "osu-lazer-raw";
        terminal = false;
        categories = ["Game"];
        comment = "Run osu! lazer without GameMode or Gamescope.";
      };
    };
  };
}
