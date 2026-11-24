{
  flake.modules.nixos.fileman = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.fileman.enable {
      services.gvfs.enable = true;
      xdg.mime.enable = true;
      xdg.menus.enable = true;
    };
  };

  flake.modules.homeManager.fileman = {
    config,
    lib,
    pkgs,
    ...
  }: let
    fileman = pkgs.unstable.callPackage ../../../assets/packages/fileman.nix {};
  in {
    config = lib.mkIf config.local.features.fileman.enable {
      # Fileman does not open .osk archives directly yet. Keep the existing
      # Ark association rather than silently regressing skin management.
      home.packages = [fileman pkgs.kdePackages.ark];
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
          "inode/directory" = ["dev.fileman.Files.desktop"];
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
