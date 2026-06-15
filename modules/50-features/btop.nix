{
  flake.modules.homeManager.btop = {config, lib, ...}: {
    config = lib.mkIf config.local.features.btop.enable {
      programs.btop = {
        enable = true;
        settings = {
          vim_keys = true;
          proc_sorting = "memory";
        };
      };
    };
  };
}
