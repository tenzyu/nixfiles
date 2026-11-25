{
  flake.modules.homeManager.osu-lazer = {config, lib, pkgs, ...}: {
    config = lib.mkIf ((config.local.features.fileman.enable || config.local.features.thunar.enable) && config.local.features.osu-lazer.enable) {
      # Keep the existing .osk archive association across file manager changes.
      # Preserve Ark rather than silently regressing skin management.
      home.packages = [pkgs.kdePackages.ark];
      xdg.dataFile."mime/packages/osu-skin.xml".text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
          <mime-type type="application/x-osu-skin">
            <comment>osu! skin archive</comment>
            <sub-class-of type="application/zip"/>
            <glob pattern="*.osk"/>
          </mime-type>
        </mime-info>
      '';
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "application/x-osu-skin" = ["org.kde.ark.desktop"];
        };
        associations.added."application/x-osu-skin" = ["org.kde.ark.desktop"];
      };
      home.activation.updateLocalMimeDatabase = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.shared-mime-info}/bin/update-mime-database "$HOME/.local/share/mime"
      '';
    };
  };
}
