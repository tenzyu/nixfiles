{
  flake.modules.homeManager.git-tools = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.git-tools.enable {
      home.packages = with pkgs; [
        gh
        lazygit
      ];
    };
  };
}
