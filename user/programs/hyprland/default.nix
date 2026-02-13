# Hyprland user config only. System (profiles/desktop.nix + system/programs/hyprland/default.nix)
# provides the binary, session entry, and xdg-desktop-portal. This module does not set
# wayland.windowManager.hyprland.package so the system Hyprland is used; it only generates
# ~/.config/hypr/hyprland.conf from the settings below.
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.hyprland.homeManagerModules.default
  ];

  wayland.windowManager.hyprland = let
    mod = "SUPER";
  in {
    # REF: https://wiki.hypr.land/Nix/Hyprland-on-Home-Manager/#using-the-home-manager-module-with-nixos
    enable = true;
    package = null;
    portalPackage = null;

    systemd.enable = false; # use uwsm

    settings = {
      # Monitor (default + optional override; use extraConfig for per-host monitor)
      monitor = [
        ",preferred,auto,1"
        "DP-1, 1920x1080@120, auto, 1"
      ];
      env = [
        "bitdepth,10"
      ];

      # Cursor
      "exec-once" = [
        "hyprctl setcursor Adwaita 24"
        # Autostart
        "fcitx5"
        "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
        "systemctl --user start hyprpaper"
        "dunst"
        "waybar"
        "hypridle"
        "wl-paste --watch cliphist store"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
      ];

      # Keyboard / Input
      input = {
        kb_layout = "us";
        kb_variant = "";
        kb_model = "";
        kb_options = "";
        numlock_by_default = true;
        follow_mouse = 1;
        mouse_refocus = false;
        sensitivity = 0;
        touchpad = {
          natural_scroll = false;
          scroll_factor = 1.0;
        };
      };

      # General / Window
      general = {
        gaps_in = 2;
        gaps_out = 4;
        border_size = 3;
        layout = "dwindle";
        resize_on_border = true;
      };

      # Decoration (current Hyprland schema: shadow as subblock, blur as subblock)
      decoration = {
        rounding = 6;
        active_opacity = 1.0;
        inactive_opacity = 0.8;
        fullscreen_opacity = 1.0;
        blur = {
          enabled = true;
          size = 6;
          passes = 2;
          new_optimizations = true;
          ignore_opacity = true;
          xray = true;
        };
        shadow = {
          enabled = true;
          range = 30;
          color = "0x66000000";
        };
      };

      # Layout: laptop (gestures enabled)
      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };
      master = {};
      gestures = {
        gesture = "3, horizontal, workspace";
        workspace_swipe_distance = 500;
        workspace_swipe_invert = true;
        workspace_swipe_min_speed_to_force = 30;
        workspace_swipe_cancel_ratio = 0.5;
        workspace_swipe_create_new = true;
        workspace_swipe_forever = true;
      };

      binds = {
        workspace_back_and_forth = true;
        allow_workspace_cycles = true;
        pass_mouse_when_bound = false;
      };

      misc = {
        force_default_wallpaper = 2;
      };

      # Animations (current schema: bezier and animation as repeated keys → use lists)
      animations = {
        enabled = true;
        bezier = [
          "wind, 0.05, 0.9, 0.1, 1.05"
          "winIn, 0.1, 1.1, 0.1, 1.1"
          "winOut, 0.3, -0.3, 0, 1"
          "liner, 1, 1, 1, 1"
        ];
        animation = [
          "windows, 1, 6, wind, slide"
          "windowsIn, 1, 6, winIn, slide"
          "windowsOut, 1, 5, winOut, slide"
          "windowsMove, 1, 5, wind, slide"
          "border, 1, 1, liner"
          "borderangle, 1, 30, liner, once"
          "fade, 1, 10, default"
          "workspaces, 1, 5, wind"
        ];
      };

      "$mod" = mod;

      bind = [
        "$mod, return, exec, kitty"
        "$mod, b, exec, firefox"
        "$mod, h, movefocus, l"
        "$mod, j, movefocus, d"
        "$mod, k, movefocus, u"
        "$mod, l, movefocus, r"
        "$mod shift, h, resizeactive, -100 0"
        "$mod shift, j, resizeactive, 0 100"
        "$mod shift, k, resizeactive, 0 -100"
        "$mod shift, l, resizeactive, 100 0"
        "$mod, q, killactive"
        "$mod, f, fullscreen"
        "$mod, t, togglefloating"
        "$mod shift, j, togglesplit"
        "$mod, s, swapsplit"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"
        "$mod, tab, workspace, m+1"
        "$mod shift, tab, workspace, m-1"
        "$mod, mouse_down, workspace, e+1"
        "$mod, mouse_up, workspace, e-1"
        "$mod ctrl, mouse_down, workspace, empty"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"
        "$mod shift, s, exec, grimblast copy area"
        "$mod ctrl, q, exec, wlogout"
        "$mod, space, exec, pkill rofi || rofi -show drun -replace -i"
        "$mod, v, exec, cliphist list | rofi -dmenu -replace | cliphist decode | wl-copy"
        ", XF86MonBrightnessUp, exec, brightnessctl -q s +10%"
        ", XF86MonBrightnessDown, exec, brightnessctl -q s 10%-"
        ", XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%"
        ", XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioPause, exec, playerctl pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl prev"
        ", XF86AudioMicMute, exec, pactl set-source-mute @DEFAULT_SOURCE@ toggle"
        ", XF86Lock, exec, hyprlock"
        ", code:238, exec, brightnessctl -d smc::kbd_backlight s +10"
        ", code:237, exec, brightnessctl -d smc::kbd_backlight s 10-"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];

      windowrule = [
        "match:class ^(Microsoft-edge)$, tile on"
        "match:class ^(Brave-browser)$, tile on"
        "match:class ^(Chromium)$, tile on"
        "match:class ^(pavucontrol)$, float on"
        "match:class ^(blueman-manager)$, float on"
        "match:class ^(nm-connection-editor)$, float on"
        "match:class ^(qalculate-gtk)$, float on"
        "match:title ^(Picture-in-Picture)$, float on"
        "match:title ^(Picture-in-Picture)$, pin on"
        "match:title ^(Picture-in-Picture)$, move 69.5% 4%"
      ];
    };

    # windowrulev2 and other raw lines. For Nvidia: add settings.env (LIBVA_DRIVER_NAME,nvidia etc.) and cursor.no_hardware_cursors in extraConfig per host. For KVM/software render: add WLR_RENDERER_ALLOW_SOFTWARE,1 and LIBGL_ALWAYS_SOFTWARE,1 to settings.env.
    extraConfig = ''
      # Browser Picture in Picture

      env = SDL_VIDEODRIVER,wayland
    '';
  };
}
