{
  flake.modules.homeManager.herdr = {config, lib, pkgs, ...}: {
    options.local.herdr.package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llm-agents.herdr;
      description = "Herdr package, including session-specific integration if selected.";
    };
    config = lib.mkIf config.local.features.herdr.enable {
      home.packages = [config.local.herdr.package];
    };
  };
}
