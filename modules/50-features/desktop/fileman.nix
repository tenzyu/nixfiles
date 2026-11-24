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
      home.packages = [fileman];
      xdg.mimeApps = {
        enable = true;
        defaultApplications."inode/directory" = ["dev.fileman.Files.desktop"];
      };
    };
  };
}
