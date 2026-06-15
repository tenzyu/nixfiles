{
  flake.modules.homeManager.rtk = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.rtk.enable {
      home.packages = [pkgs.llm-agents.rtk];
    };
  };
}
