{config, ...}: {
  flake.modules.homeManager.waybar = {
    programs.waybar = {
      enable = true;

      settings = [
        {
          layer = "top";
          position = "top";

          modules-left = [
            "hyprland/workspaces"
          ];
          modules-center = [
            "custom/music"
          ];
          modules-right = [
            "pulseaudio"
            "backlight"
            "battery"
            "clock"
            "wlr/taskbar"
            "tray"
            "custom/lock"
            "custom/power"
          ];

          "hyprland/workspaces" = {
            on-scroll-up = "hyprctl dispatch workspace e-1";
            on-scroll-down = "hyprctl dispatch workspace e+1";
            on-click = "activate";
            active-only = false;
            all-outputs = true;
            format = "{}";
            format-icons = {
              urgent = "";
              active = "";
              default = "";
            };
            persistent-workspaces = {
              "*" = 5;
            };
          };
          "custom/music" = {
            format = "  {}";
            escape = true;
            interval = 5;
            tooltip = false;
            exec = "playerctl metadata --format='{{ title }}'";
            on-click = "playerctl play-pause";
            max-length = 50;
          };
          pulseaudio = {
            format = "{icon} {volume}%";
            format-muted = "";
            format-icons = {
              default = ["" "" " "];
            };
            on-click = "pavucontrol";
          };
          backlight = {
            device = "intel_backlight";
            format = "{icon}";
            format-icons = ["" "" "" "" "" "" "" "" ""];
          };
          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            format-plugged = " {capacity}%";
            format-alt = "{icon} {capacity}%";
            format-icons = ["" "" "" "" "" "" "" "" "" "" "" ""];
          };
          clock = {
            format = "{:%H:%M}";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          };
          tray = {
            icon-size = 21;
            spacing = 10;
          };
          "wlr/taskbar" = {
            format = "{icon}";
            icon-size = 21;
            tooltip-format = "{title}";
            on-click = "minimize-raise";
            on-click-middle = "close";
          };
          "custom/lock" = {
            tooltip = false;
            on-click = "hyprlock &";
            format = "";
          };
          "custom/power" = {
            tooltip = false;
            on-click = "wlogout &";
            format = "";
          };
        }
      ];

      style = ''
        * {
            font-family: FantasqueSansMono Nerd Font;
            font-size: 17px;
            min-height: 0;
        }

        #waybar {
            background: transparent;
            color: @text;
            margin: 5px 5px;
        }

        #workspaces {
            border-radius: 1rem;
            margin: 5px;
            background-color: @surface0;
            margin-left: 1rem;
        }

        #workspaces button {
            color: @lavender;
            border-radius: 1rem;
            padding: 0.4rem;
        }

        #workspaces button.active {
            color: @sky;
            border-radius: 1rem;
        }

        #workspaces button:hover {
            color: @sapphire;
            border-radius: 1rem;
        }

        #custom-music,
        #taskbar,
        #tray,
        #backlight,
        #clock,
        #battery,
        #pulseaudio,
        #custom-lock,
        #custom-power {
            background-color: @surface0;
            padding: 0.5rem 1rem;
            margin: 5px 0;
        }

        #clock {
            color: @blue;
            border-radius: 0;
        }

        #battery {
            color: @green;
            border-radius: 0;
        }

        #battery.charging {
            color: @green;
        }

        #battery.warning:not(.charging) {
            color: @red;
        }

        #backlight {
            color: @yellow;
            border-radius: 0;
        }

        #pulseaudio {
            color: @maroon;
            border-radius: 1rem 0px 0px 1rem;
            margin-left: 1rem;
        }

        #custom-music {
            color: @mauve;
            border-radius: 1rem;
        }

        #custom-lock {
            border-radius: 1rem 0px 0px 1rem;
            color: @lavender;
        }

        #custom-power {
            margin-right: 1rem;
            border-radius: 0px 1rem 1rem 0px;
            color: @red;
        }

        #tray {
            border-radius: 0px 1rem 1rem 0px;
            margin-right: 1rem;
        }

        #taskbar {
            color: @peach;
            border-radius: 0;
        }

        #taskbar button {
            padding: 0 0.35rem;
            border-radius: 0.7rem;
        }

        #taskbar button.minimized {
            color: @overlay0;
        }
      '';
    };
  };
}
