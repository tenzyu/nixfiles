{...}: {
  flake.modules.homeManager.herdr = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.herdr.enable {
      home.packages = [pkgs.llm-agents.herdr];
    };
  };
}
