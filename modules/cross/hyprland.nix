{
  local.cross.definitions.hyprland = {
    ambient = [
      {
        local.pkgs.useUnstable = true;
      }
    ];

    nixos.module = {pkgs, ...}: {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
        package = pkgs.unstable.hyprland;
        portalPackage = pkgs.unstable.xdg-desktop-portal-hyprland;
      };
    };

    home.module = {
      cross,
      pkgs,
      ...
    }: {
      wayland.windowManager.hyprland = let
        mod = "SUPER";
      in {
        enable = true;

        package = cross.only.nixos null;
        portalPackage = cross.only.nixos null;

        systemd.enable = cross.select {
          nixos = false;
          standalone = true;
        };

        xwayland.enable = true;

        settings = {
          monitor = [
            ",preferred,auto,1"
          ];

          "exec-once" = [
            "hyprctl setcursor Adwaita 24"
            "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
            "systemctl --user start hypridle.service"
            "systemctl --user start mako.service"
            "waybar"
            "wl-paste --watch cliphist store"
            "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XCURSOR_THEME XCURSOR_SIZE"
          ];

          input = {
            kb_layout = "us";
            numlock_by_default = true;
            follow_mouse = 1;
            mouse_refocus = false;
            sensitivity = 0;
            touchpad = {
              natural_scroll = false;
              disable_while_typing = true;
              scroll_factor = 1.0;
            };
          };

          general = {
            gaps_in = 0;
            gaps_out = 0;
            border_size = 1;
            layout = "dwindle";
            resize_on_border = true;
            allow_tearing = true;
          };

          decoration = {
            rounding = 0;
            active_opacity = 1.0;
            inactive_opacity = 1.0;
            fullscreen_opacity = 1.0;
            blur = {
              enabled = false;
              size = 1;
              passes = 1;
              new_optimizations = true;
              ignore_opacity = false;
              xray = false;
            };
            shadow = {
              enabled = false;
              range = 4;
              color = "0x66000000";
            };
          };

          master = {};
          dwindle = {
            preserve_split = true;
            smart_split = false;
          };

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

          cursor = {
            inactive_timeout = 3;
            no_hardware_cursors = false;
          };

          misc = {
            animate_manual_resizes = false;
            animate_mouse_windowdragging = false;
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            force_default_wallpaper = 0;
            mouse_move_enables_dpms = true;
            key_press_enables_dpms = true;
            render_unfocused_fps = 15;
            vrr = 1;
          };

          render = {
            direct_scanout = true;
            new_render_scheduling = true;
          };

          debug.disable_logs = true;

          animations = {
            enabled = false;
            bezier = [
              "linear, 1, 1, 1, 1"
            ];
            animation = [
              "border, 0"
              "borderangle, 0"
              "fade, 0"
              "windows, 0"
              "workspaces, 0"
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
            "$mod, m, movetoworkspacesilent, special:minimized"
            "$mod shift, m, togglespecialworkspace, minimized"
            "$mod, f, fullscreenstate, 2 0"
            "$mod, t, togglefloating"
            "$mod shift, j, layoutmsg, togglesplit"
            "$mod, s, layoutmsg, swapsplit"
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
            "$mod shift, g, exec, hypr-gaming-mode on"
            "$mod ctrl shift, g, exec, hypr-gaming-mode off"
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
            "match:class ^(steam_app_.*)$, immediate on"
            "match:class ^(steam_app_.*)$, fullscreen on"
            "match:class ^(osu!)$, immediate on"
            "match:class ^(osu!)$, fullscreen on"
            "match:class ^(osu-lazer)$, immediate on"
            "match:class ^(osu-lazer)$, fullscreen on"
          ];
        };

        extraConfig = ''
          env = SDL_VIDEODRIVER,wayland
        '';
      };

      services.hypridle = {
        enable = true;
        settings = {
          general = {
            after_sleep_cmd = "hyprctl dispatch dpms on";
            before_sleep_cmd = "loginctl lock-session";
            ignore_dbus_inhibit = false;
            lock_cmd = "pidof hyprlock || hyprlock";
          };

          listener = [
            {
              timeout = 180;
              on-timeout = "loginctl lock-session";
            }
            {
              timeout = 210;
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ];
        };
      };
    };
  };
}
