{...}: {
  flake.modules = {
    nixos.dolphin = {
      xdg.menus.enable = true;
      xdg.mime.enable = true;

      environment.etc."xdg/menus/applications.menu".text = ''
        <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
          "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
        <Menu>
          <Name>Applications</Name>
          <DefaultAppDirs/>
          <DefaultDirectoryDirs/>
          <DefaultMergeDirs/>
          <Include>
            <All/>
          </Include>
          <DefaultLayout>
            <Merge type="menus"/>
            <Merge type="files"/>
          </DefaultLayout>
        </Menu>
      '';
    };

    homeManager.dolphin = {
      lib,
      pkgs,
      ...
    }: {
      home.packages = with pkgs; [
        kdePackages.ark
        kdePackages.dolphin
        kdePackages.ffmpegthumbs
        kdePackages.kdegraphics-thumbnailers
        kdePackages.kimageformats
        kdePackages.kio-extras
        kdePackages.kservice
        libheif
        qt6.qtimageformats
      ];

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
        associations.added."application/x-osu-skin" = ["org.kde.ark.desktop"];
        defaultApplications."application/x-osu-skin" = ["org.kde.ark.desktop"];
      };

      home.activation.updateLocalMimeDatabase = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.shared-mime-info}/bin/update-mime-database "$HOME/.local/share/mime"
      '';
    };
  };
}
