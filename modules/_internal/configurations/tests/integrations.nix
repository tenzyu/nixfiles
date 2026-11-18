{
  lib,
  integrationModule,
}: let
  evaluate = parsec: hyprland:
    (lib.evalModules {
      modules = [
        ({lib, ...}: {
          options.local.features.parsec.enable = lib.mkOption {
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
            parsec.enable = parsec;
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
  testIntegrationOnlyParsec = {
    expr = builtins.length (evaluate true false);
    expected = 0;
  };
  testIntegrationOnlyHyprland = {
    expr = builtins.length (evaluate false true);
    expected = 0;
  };
  testIntegrationBothEnabled = {
    # Assert rule values and order, not just the number of rules.
    expr = evaluate true true;
    expected = [
      {match = {title = "^(Parsec)$"; xwayland = true;}; immediate = true;}
      {match = {title = "^(Parsec)$"; xwayland = true;}; fullscreen = true;}
      {match = {title = "^(Parsec)$"; xwayland = true;}; stay_focused = true;}
      {match = {title = "^(Parsec)$"; xwayland = true;}; no_initial_focus = true;}
      {match = {title = "^(Parsec)$"; xwayland = true;}; allows_input = true;}
      {match = {title = "^(Parsec)$"; xwayland = true;}; focus_on_activate = true;}
    ];
  };
}
