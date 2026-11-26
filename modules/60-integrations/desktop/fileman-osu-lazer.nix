{
  flake.modules.homeManager.fileman = {config, lib, pkgs, ...}: {
    config = lib.mkIf (config.local.features.fileman.enable && config.local.features.osu-lazer.enable) ({
      # Fileman does not open .osk archives directly yet. Keep the existing
      # Ark association rather than silently regressing skin management.
      home.packages = [pkgs.kdePackages.ark];
    } // import ../../50-features/desktop/_internal/osu-skin-mime.nix {inherit lib pkgs;});
  };
}
