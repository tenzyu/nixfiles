{
  flake.modules.homeManager.opencode = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.opencode.enable {
      home.packages = [pkgs.llm-agents.opencode];
    };
  };
}
