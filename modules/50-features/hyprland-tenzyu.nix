{
  flake.modules.nixos.hyprland-tenzyu = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.hyprland-tenzyu.enable {
      local.features.hyprland-core.enable = lib.mkDefault true;
    };
  };

  flake.modules.homeManager.hyprland-tenzyu = {
    config,
    lib,
    pkgs,
    ...
  }: let
    lua = lib.generators.mkLuaInline;

    luaExec = command: lua "hl.dsp.exec_cmd(${builtins.toJSON command})";
    focus = direction: lua "hl.dsp.focus({ direction = ${builtins.toJSON direction} })";
    focusWorkspace = workspace: lua "hl.dsp.focus({ workspace = ${builtins.toJSON workspace} })";
    moveWorkspace = workspace: lua "hl.dsp.window.move({ workspace = ${builtins.toJSON workspace}, follow = true })";
    moveWorkspaceSilent = workspace: lua "hl.dsp.window.move({ workspace = ${builtins.toJSON workspace}, follow = false })";
    resize = x: y: lua "hl.dsp.window.resize({ x = ${toString x}, y = ${toString y}, relative = true })";
    layout = message: lua "hl.dsp.layout(${builtins.toJSON message})";

    bind = key: dispatcher: {
      _args = [
        key
        dispatcher
      ];
    };

    bindWithFlags = key: dispatcher: flags: {
      _args = [
        key
        dispatcher
        flags
      ];
    };

    modBind = key: dispatcher: bind (lua ''mod .. " + ${key}"'') dispatcher;

    modBindWithFlags = key: dispatcher: flags:
      bindWithFlags (lua ''mod .. " + ${key}"'') dispatcher flags;
  in {
    config = lib.mkIf config.local.features.hyprland-tenzyu.enable {
      local.features.hyprland-core.enable = lib.mkDefault true;

      wayland.windowManager.hyprland = {
        configType = "lua";

        package = lib.mkIf config.local.context.embeddedInNixOS null;
        portalPackage = lib.mkIf config.local.context.embeddedInNixOS null;

        systemd.enable = lib.mkIf (!config.local.context.embeddedInNixOS) true;

        settings = {
          mod = {
            _var = "SUPER";
          };

          config = {
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
                color = "#00000066";
              };
            };

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

            xwayland = {
              enabled = true;
              force_zero_scaling = true;
            };

            master = {};
            dwindle = {
              preserve_split = true;
              smart_split = false;
            };

            binds = {
              workspace_back_and_forth = true;
              allow_workspace_cycles = true;
              pass_mouse_when_bound = false;
            };

            cursor = {
              inactive_timeout = 3;
              no_hardware_cursors = 0;
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
              direct_scanout = 1;
              new_render_scheduling = true;
            };

            debug.disable_logs = true;

            animations.enabled = false;
          };

          monitor = {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = 1;
          };

          env = {
            _args = [
              "SDL_VIDEODRIVER"
              "wayland"
            ];
          };

          on = {
            _args = [
              "hyprland.start"
              (lua ''
                function()
                  hl.exec_cmd("hyprctl setcursor Adwaita 24")
                  hl.exec_cmd("${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1")
                  hl.exec_cmd("systemctl --user start hypridle.service")
                  hl.exec_cmd("systemctl --user start mako.service")
                  hl.exec_cmd("waybar")
                  hl.exec_cmd("wl-paste --watch cliphist store")
                  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XCURSOR_THEME XCURSOR_SIZE")
                end
              '')
            ];
          };

          gesture = {
            fingers = 3;
            direction = "horizontal";
            action = "workspace";
          };

          curve = {
            _args = [
              "linear"
              {
                type = "bezier";
                points = [
                  [
                    1
                    1
                  ]
                  [
                    1
                    1
                  ]
                ];
              }
            ];
          };

          animation = [
            {
              leaf = "border";
              enabled = false;
            }
            {
              leaf = "borderangle";
              enabled = false;
            }
            {
              leaf = "fade";
              enabled = false;
            }
            {
              leaf = "windows";
              enabled = false;
            }
            {
              leaf = "workspaces";
              enabled = false;
            }
          ];

          bind = [
            (modBind "Return" (luaExec "kitty"))
            (modBind "b" (luaExec "firefox"))
            (modBind "h" (focus "left"))
            (modBind "j" (focus "down"))
            (modBind "k" (focus "up"))
            (modBind "l" (focus "right"))
            (modBind "SHIFT + h" (resize (-100) 0))
            (modBind "SHIFT + j" (resize 0 100))
            (modBind "SHIFT + k" (resize 0 (-100)))
            (modBind "SHIFT + l" (resize 100 0))
            (modBind "q" (lua "hl.dsp.window.close()"))
            (modBind "m" (moveWorkspaceSilent "special:minimized"))
            (modBind "SHIFT + m" (lua ''hl.dsp.workspace.toggle_special("minimized")''))
            (modBind "f" (lua "hl.dsp.window.fullscreen_state({ internal = 2, client = 0 })"))
            (modBind "t" (lua ''hl.dsp.window.float({ action = "toggle" })''))
            (modBind "SHIFT + j" (layout "togglesplit"))
            (modBind "s" (layout "swapsplit"))
            (modBind "1" (focusWorkspace 1))
            (modBind "2" (focusWorkspace 2))
            (modBind "3" (focusWorkspace 3))
            (modBind "4" (focusWorkspace 4))
            (modBind "5" (focusWorkspace 5))
            (modBind "6" (focusWorkspace 6))
            (modBind "7" (focusWorkspace 7))
            (modBind "8" (focusWorkspace 8))
            (modBind "9" (focusWorkspace 9))
            (modBind "0" (focusWorkspace 10))
            (modBind "Tab" (focusWorkspace "m+1"))
            (modBind "SHIFT + Tab" (focusWorkspace "m-1"))
            (modBind "mouse_down" (focusWorkspace "e+1"))
            (modBind "mouse_up" (focusWorkspace "e-1"))
            (modBind "CTRL + mouse_down" (focusWorkspace "empty"))
            (modBind "SHIFT + 1" (moveWorkspace 1))
            (modBind "SHIFT + 2" (moveWorkspace 2))
            (modBind "SHIFT + 3" (moveWorkspace 3))
            (modBind "SHIFT + 4" (moveWorkspace 4))
            (modBind "SHIFT + 5" (moveWorkspace 5))
            (modBind "SHIFT + 6" (moveWorkspace 6))
            (modBind "SHIFT + 7" (moveWorkspace 7))
            (modBind "SHIFT + 8" (moveWorkspace 8))
            (modBind "SHIFT + 9" (moveWorkspace 9))
            (modBind "SHIFT + 0" (moveWorkspace 10))
            (modBind "SHIFT + s" (luaExec "grimblast copy area"))
            (modBind "CTRL + q" (luaExec "wlogout"))
            (modBind "Space" (luaExec "pkill rofi || rofi -show drun -replace -i"))
            (modBind "v" (luaExec "cliphist list | rofi -dmenu -replace | cliphist decode | wl-copy"))
            (modBind "p" (luaExec "pkill castalia || castalia launch"))
            (modBind "SHIFT + g" (luaExec "hypr-gaming-mode on"))
            (modBind "CTRL + SHIFT + g" (luaExec "hypr-gaming-mode off"))
            (bind "XF86MonBrightnessUp" (luaExec "brightnessctl -q s +10%"))
            (bind "XF86MonBrightnessDown" (luaExec "brightnessctl -q s 10%-"))
            (bind "XF86AudioRaiseVolume" (luaExec "pactl set-sink-volume @DEFAULT_SINK@ +5%"))
            (bind "XF86AudioLowerVolume" (luaExec "pactl set-sink-volume @DEFAULT_SINK@ -5%"))
            (bind "XF86AudioMute" (luaExec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
            (bind "XF86AudioPlay" (luaExec "playerctl play-pause"))
            (bind "XF86AudioPause" (luaExec "playerctl pause"))
            (bind "XF86AudioNext" (luaExec "playerctl next"))
            (bind "XF86AudioPrev" (luaExec "playerctl prev"))
            (bind "XF86AudioMicMute" (luaExec "pactl set-source-mute @DEFAULT_SOURCE@ toggle"))
            (bind "XF86ScreenSaver" (luaExec "hyprlock"))
            (bind "code:238" (luaExec "brightnessctl -d smc::kbd_backlight s +10"))
            (bind "code:237" (luaExec "brightnessctl -d smc::kbd_backlight s 10-"))
            (modBindWithFlags "mouse:272" (lua "hl.dsp.window.drag()") {mouse = true;})
            (modBindWithFlags "mouse:273" (lua "hl.dsp.window.resize()") {mouse = true;})
          ];

          window_rule = [
            {
              match = {class = "^(Microsoft-edge)$";};
              tile = true;
            }
            {
              match = {class = "^(Brave-browser)$";};
              tile = true;
            }
            {
              match = {class = "^(Chromium)$";};
              tile = true;
            }
            {
              match = {class = "^(pavucontrol)$";};
              float = true;
            }
            {
              match = {class = "^(blueman-manager)$";};
              float = true;
            }
            {
              match = {class = "^(nm-connection-editor)$";};
              float = true;
            }
            {
              match = {class = "^(qalculate-gtk)$";};
              float = true;
            }
            {
              match = {title = "^(Picture-in-Picture)$";};
              float = true;
            }
            {
              match = {title = "^(Picture-in-Picture)$";};
              pin = true;
            }
            {
              match = {title = "^(Picture-in-Picture)$";};
              move = "69.5% 4%";
            }
          ];
        };
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
