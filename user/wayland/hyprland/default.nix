{
  inputs,
  config,
  system,
  pkgs,
  ...
}: {
  imports = [
    inputs.hyprland.homeManagerModules.default
  ];

  home.pointerCursor = {
    gtk.enable = true;
    # x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 16;
  };

  gtk = {
    enable = true;
    gtk2.configLocation = "${config.xdg.configHome}/gtk-2.0/gtkrc";

    theme = {
      package = pkgs.flat-remix-gtk;
      name = "Flat-Remix-GTK-Grey-Darkest";
    };

    iconTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "Adwaita";
    };

    font = {
      name = "Sans";
      size = 11;
    };
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
    ];
    config.common.default = "*";
  };

  programs.zsh.profileExtra = ''
    if uwsm check may-start && uwsm select; then
      exec systemd-cat -t uwsm_start start default
    fi
  '';

  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${system}.hyprland;

    xwayland.enable = false;
    systemd.enable = false; # use uwsm
    # systemd.variables = [ "--all" ];

    #    settings = {
    #      misc = {
    #        force_default_wallpaper = 2;
    #      };
    #
    #      debug = {
    #        disable_logs = false;
    #        enable_stdout_logs = true;
    #      };
    #
    #      ### autostart {{{
    #      ### }}}
    #
    #      ### animations {{{
    #      ### }}}
    #      ### decorations {{{
    #      ### }}}
    #      ### environments {{{
    #      ### }}}
    #
    #      ### keybindings {{{
    #      "$mod" = "super";
    #      bindm = [
    #        ### window {{{
    #        "$mod, mouse:272, movewindow"
    #        "$mod, mouse:273, resizewindow"
    #        ### }}}
    #      ];
    #      bind = [
    #        ### gui application {{{
    #        "$mod, return, exec, kitty"
    #        "$mod, b, exec, firefox"
    #        ### }}}
    #
    #        ### window {{{
    #        "$mod, h, movefocus, l" # left
    #        "$mod, j, movefocus, d" # down
    #        "$mod, k, movefocus, u" # up
    #        "$mod, l, movefocus, r" # right
    #        "$mod shift, h, resizeactive, -100 0"
    #        "$mod shift, j, resizeactive, 0 100"
    #        "$mod shift, k, resizeactive, 0 -100"
    #        "$mod shift, l, resizeactive, 100 0"
    #        "$mod, q, killactive"
    #        "$mod, f, fullscreen"
    #        "$mod, t, togglefloating"
    #        "$mod shift, j, togglesplit"
    #        "$mod, s, swapsplit"
    #        ### }}}
    #
    #        ### workspace {{{
    #        "$mod, 1, workspace, 1"
    #        "$mod, 2, workspace, 2"
    #        "$mod, 3, workspace, 3"
    #        "$mod, 4, workspace, 4"
    #        "$mod, 5, workspace, 5"
    #        "$mod, 6, workspace, 6"
    #        "$mod, 7, workspace, 7"
    #        "$mod, 8, workspace, 8"
    #        "$mod, 9, workspace, 9"
    #        "$mod, 0, workspace, 10"
    #        "$mod, tab, workspace, m+1"
    #        "$mod shift, tab, workspace, m-1"
    #        "$mod, mouse_down, workspace, e+1"
    #        "$mod, mouse_up, workspace, e-1"
    #        "$mod ctrl, mouse_down, workspace, empty"
    #        ### }}}
    #
    #        ### action {{{
    #        # todo: selective screenshoi
    #        "$mod shift, s, exec, grimblast copy area"
    #        "$mod ctrl, q, exec, wlogout"
    #        "$mod, space, exec, pkill rofi || rofi -show drun -replace -i"
    #        "$mod, v, exec, cliphist list | rofi -dmenu -replace | cliphist decode | wl-copy"
    #        ### }}}
    #
    #        ### function key {{{
    #        ", xf86monbrightnessup, exec, brightnessctl -q s +10%"
    #        ", xf86monbrightnessdown, exec, brightnessctl -q s 10%-"
    #        ", xf86audioraisevolume, exec, pactl set-sink-volume @default_sink@ +5%"
    #        ", xf86audiolowervolume, exec, pactl set-sink-volume @default_sink@ -5%"
    #        ", xf86audiomute, exec, wpctl set-mute @default_audio_sink@ toggle"
    #        ", xf86audioplay, exec, playerctl play-pause"
    #        ", xf86audiopause, exec, playerctl pause"
    #        ", xf86audionext, exec, playerctl next"
    #        ", xf86audioprev, exec, playerctl prev"
    #        ", xf86audiomicmute, exec, pactl set-source-mute @default_source@ toggle"
    #        ", xf86lock, exec, hyprlock"
    #        ### }}}
    #      ];
    #      ### }}}
    #
    #      ### layouts {{{
    #      ### }}}
    #      ### monitors {{{
    #      ### }}}
    #      ### windowrules {{{
    #      ### }}}
    #      ### windows {{{
    #      ### }}}
    #    };
  };
}
