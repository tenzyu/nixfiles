{
  flake.modules.homeManager.disk-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.disk-tools.enable {
      home.packages = with pkgs; [
        qdirstat
      ];
    };
  };
}
