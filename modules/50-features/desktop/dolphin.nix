{
  flake.modules.nixos.dolphin = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.dolphin.enable ({
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
  };

  flake.modules.homeManager.dolphin = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.dolphin.enable {
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
    } // import ./_internal/osu-skin-mime.nix {inherit lib pkgs;});
  };
}
