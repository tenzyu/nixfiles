{
  flake.modules.homeManager.waybar = {config, lib, ...}: {
    config = lib.mkIf config.local.features.waybar.enable {
      programs.waybar = {
        enable = true;

        settings = [
          {
            layer = "top";
            position = "top";
            height = 28;
            spacing = 8;

            modules-left = [
              "hyprland/workspaces"
            ];
            modules-center = [];
            modules-right = [
              "pulseaudio"
              "backlight"
              "battery"
              "clock"
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
              persistent-workspaces = {
                "*" = 5;
              };
            };

            pulseaudio = {
              format = "{icon} {volume}%";
              format-muted = "";
              format-icons.default = [""  ""  ""];
              on-click = "pavucontrol";
            };

            backlight = {
              device = "intel_backlight";
              format = "{icon}";
              format-icons = [""  ""  ""  ""  ""  ""  ""  ""  ""];
            };

            battery = {
              states = {
                warning = 30;
                critical = 15;
              };
              format = "{icon} {capacity}%";
              format-charging = " {capacity}%";
              format-plugged = " {capacity}%";
              format-alt = "{icon} {capacity}%";
              format-icons = [""  ""  ""  ""  ""  ""  ""  ""  ""  ""  ""  ""];
            };

            clock = {
              format = "{:%H:%M}";
              tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            };

            tray = {
              icon-size = 18;
              spacing = 8;
            };

            "custom/lock" = {
              tooltip = false;
              on-click = "hyprlock &";
              format = "";
            };

            "custom/power" = {
              tooltip = false;
              on-click = "wlogout &";
              format = "";
            };
          }
        ];

        style = ''
          * {
            font-family: FantasqueSansMono Nerd Font;
            font-size: 15px;
            min-height: 0;
            border: none;
            box-shadow: none;
            text-shadow: none;
          }

          #waybar {
            background: transparent;
            color: @text;
          }

          #workspaces,
          #tray,
          #backlight,
          #clock,
          #battery,
          #pulseaudio,
          #custom-lock,
          #custom-power {
            background-color: @surface0;
            padding: 0.25rem 0.65rem;
            margin: 3px 0;
          }

          #workspaces {
            border-radius: 0.7rem;
            margin-left: 0.6rem;
          }

          #workspaces button {
            color: @lavender;
            border-radius: 0.55rem;
            padding: 0 0.45rem;
          }

          #workspaces button.active {
            color: @sky;
          }

          #pulseaudio {
            color: @maroon;
            border-radius: 0.7rem 0 0 0.7rem;
            margin-left: 0.6rem;
          }

          #backlight { color: @yellow; }
          #battery { color: @green; }
          #battery.warning:not(.charging) { color: @red; }
          #clock { color: @blue; }
          #tray { border-radius: 0 0.7rem 0.7rem 0; }
          #custom-lock { color: @lavender; border-radius: 0.7rem 0 0 0.7rem; }
          #custom-power { color: @red; border-radius: 0 0.7rem 0.7rem 0; margin-right: 0.6rem; }
        '';
      };
    };
  };
}
