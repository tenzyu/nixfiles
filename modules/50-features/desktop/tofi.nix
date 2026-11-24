{
  flake.modules.homeManager.tofi = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.tofi.enable {
      home.packages = [pkgs.tofi];
      xdg.configFile."tofi/config".text = ''
        font = FiraCode Nerd Font
        font-size = 11
        background-color = #1e1e2eff
        text-color = #cdd6f4ff
        selection-color = #89b4faff
        fuzzy-match = true
        require-match = true
      '';
    };
  };
}
