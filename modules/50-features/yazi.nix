{
  flake.modules.homeManager.yazi = {config, lib, ...}: {
    config = lib.mkIf config.local.features.yazi.enable {
      programs.yazi = {
        enable = true;
        enableZshIntegration = true;

        settings = {
          mgr = {
            show_hidden = true;
          };
        };
      };
    };
  };
}
