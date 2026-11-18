{
  lib,
  integrationModule,
}: let
  evaluate = steam: hyprland:
    (lib.evalModules {
      modules = [
        ({lib, ...}: {
          options.local.features.steam.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.local.features.hyprland-tenzyu.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          options.wayland.windowManager.hyprland.settings.window_rule = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [];
          };
          config.local.features = {
            steam.enable = steam;
            hyprland-tenzyu.enable = hyprland;
          };
        })
        integrationModule
      ];
    }).config.wayland.windowManager.hyprland.settings.window_rule;
in {
  testIntegrationNeitherEnabled = {
    expr = builtins.length (evaluate false false);
    expected = 0;
  };
  testIntegrationOnlySteam = {
    expr = builtins.length (evaluate true false);
    expected = 0;
  };
  testIntegrationOnlyHyprland = {
    expr = builtins.length (evaluate false true);
    expected = 0;
  };
  testIntegrationBothEnabled = {
    expr = evaluate true true;
    expected = [
      {match.class = "^(steam_app_.*)$"; immediate = true;}
      {match.class = "^(steam_app_.*)$"; fullscreen = true;}
    ];
  };
}
