{
  flake.modules.nixos.gamescope = {
    config,
    lib,
    pkgs,
    ...
  }: let
    game = pkgs.writeShellScript "gamescope-osu" ''
      unset DISPLAY
      export SDL_VIDEODRIVER=wayland
      : "''${WAYLAND_DISPLAY:?Gamescope did not expose a native Wayland display}"
      exec osu-lazer
    '';
    startGamescope = pkgs.writeShellScriptBin "start-gamescope" ((import ../../../lib/local-vt-guard.nix) "Gamescope" + ''
      export XDG_CURRENT_DESKTOP=gamescope
      export XDG_SESSION_DESKTOP=gamescope
      export XDG_SESSION_TYPE=wayland
      exec gamescope --backend drm --expose-wayland --immediate-flips --prefer-output eDP-1 -W 1366 -H 768 -w 1366 -h 768 -r 60 --framerate-limit 0 -- ${game}
    '');
  in {
    config = lib.mkIf config.local.features.gamescope.enable {
      programs.gamescope.enable = true;
      environment.systemPackages = [startGamescope pkgs.xwayland pkgs.wayland-utils];
      xdg.portal = {
        enable = true;
        extraPortals = [pkgs.xdg-desktop-portal-gtk];
        config.gamescope.default = ["gtk"];
      };
    };
  };
}
