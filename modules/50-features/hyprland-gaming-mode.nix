{
  flake.effects.hyprland-gaming-mode.requires = [
    "gaming-core"
    "hyprland-core"
  ];

  flake.modules.nixos.hyprland-gaming-mode = {
    lib,
    pkgs,
    ...
  }: let
    hyprGamingStart = pkgs.writeShellScript "hypr-gaming-start" ''
      set -eu

      systemctl --user stop mako.service 2>/dev/null || true
      pkill -STOP -x waybar 2>/dev/null || true

      for socket in "''${XDG_RUNTIME_DIR:-/run/user/$UID}"/hypr/*/.socket.sock; do
        [ -S "$socket" ] || continue
        sig="''${socket%/.socket.sock}"
        sig="''${sig##*/}"
        HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl --batch "\
          keyword animations:enabled false ; \
          keyword decoration:blur:enabled false ; \
          keyword decoration:shadow:enabled false ; \
          keyword decoration:rounding 0 ; \
          keyword general:gaps_in 0 ; \
          keyword general:gaps_out 0 ; \
          keyword general:allow_tearing true ; \
          keyword misc:vrr 2 ; \
          keyword render:direct_scanout true" >/dev/null 2>&1 || true
      done
    '';

    hyprGamingEnd = pkgs.writeShellScript "hypr-gaming-end" ''
      set -eu

      pkill -CONT -x waybar 2>/dev/null || true
      systemctl --user start mako.service 2>/dev/null || true
    '';
  in {
    programs.gamemode.settings.custom = lib.mkForce {
      start = "${hyprGamingStart}";
      end = "${hyprGamingEnd}";
    };
  };

  flake.modules.homeManager.hyprland-gaming-mode = {pkgs, ...}: {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "hypr-gaming-mode";
        runtimeInputs = with pkgs; [
          hyprland
          procps
          systemd
        ];
        text = ''
          case "''${1:-}" in
            on)
              systemctl --user stop mako.service 2>/dev/null || true
              pkill -STOP -x waybar 2>/dev/null || true
              hyprctl --batch "keyword animations:enabled false ; keyword decoration:blur:enabled false ; keyword decoration:shadow:enabled false ; keyword decoration:rounding 0 ; keyword general:gaps_in 0 ; keyword general:gaps_out 0 ; keyword general:allow_tearing true ; keyword misc:vrr 2 ; keyword render:direct_scanout true"
              ;;
            off)
              pkill -CONT -x waybar 2>/dev/null || true
              systemctl --user start mako.service 2>/dev/null || true
              ;;
            *)
              echo "usage: hypr-gaming-mode on|off" >&2
              exit 2
              ;;
          esac
        '';
      })
    ];
  };
}
