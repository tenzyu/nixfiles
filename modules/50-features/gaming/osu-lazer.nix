{
  flake.local.featurePolicies.osu-lazer.unfree = [
    "osu-lazer-bin"
  ];

  flake.local.featurePolicies.osu-lazer.permittedInsecure = [
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
  ];

  flake.modules.nixos.osu-lazer = {};

  flake.modules.homeManager.osu-lazer = {
    config,
    lib,
    pkgs,
    ...
  }: let
    osuLauncher = pkgs.writeShellScriptBin "osu-lazer" ''
      set -euo pipefail

      # Gen9 i915 rejects Y_TILED_CCS for async flips. Scope the opt-in to
      # this process tree, not the desktop or other Mesa clients.
      ${lib.optionalString config.local.osuLazer.disableIntelCcs ''
        export INTEL_DEBUG="''${INTEL_DEBUG:+$INTEL_DEBUG,}noccs"
      '' }

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

  in {
    options.local.osuLazer.disableIntelCcs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Disable Intel Mesa CCS only for the osu! launcher.";
    };

    config = lib.mkIf config.local.features.osu-lazer.enable {
      home.packages = [osuLauncher];

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
