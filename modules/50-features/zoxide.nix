{
  flake.modules.homeManager.zoxide = {config, lib, ...}: {
    config = lib.mkIf config.local.features.zoxide.enable {
      programs.zoxide = {
        enable = true;
      };
    };
  };
}
