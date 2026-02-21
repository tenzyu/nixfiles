let
  inherit (import ../../lib/default.nix) homeModules;
in
  {
    pkgs,
    config,
    inputs,
    ...
  }: {
    imports = with homeModules; [
      ../common/tenzyu.nix

      addons.catppuccin

      ### cli {{{
      programs.zsh
      programs.bat # A cat(1) clone with syntax highlighting and Git integration
      programs.btop # A monitor of resources
      programs.eza # A modern, maintained replacement for ls
      programs.fastfetch
      programs.fd # A simple, fast and user-friendly alternative to find
      programs.fzf # Command-line fuzzy finder written in Go
      programs.git # Distributed version control system
      programs.neovim
      programs.ripgrep
      programs.starship # A minimal, blazing fast, and extremely customizable prompt for any shell
      programs.tealdeer
      programs.tmux
      programs.yazi
      programs.zoxide
      ### }}}

      ### DE {{{
      programs.hyprland
      programs.hyprpaper
      programs.wlogout
      ### }}}

      ### gui {{{
      programs.kitty # A modern, hackable, featureful, OpenGL based terminal emulator
      programs.firefox
      programs.waybar
      programs.rofi
      programs.zed-editor
      programs.obs-studio
      ../../modules/home/programs/obsidian/wayland.nix # no default.nix
      ### }}}
    ];

    # NOTE: home-manager が option を持っていないパッケージはココで入れる.
    home.packages = with pkgs; [
      ### cli {{{
      bitwarden-cli
      brightnessctl
      dust # du + rust = dust. Like du but more intuitive
      pavucontrol # PulseAudio Volume Control
      xdg-ninja # A shell script which checks your $HOME for unwanted files and directories
      playerctl
      jq
      jqp
      glow
      xclip
      pay-respects
      ### }}}

      ### DE {{{
      grimblast
      wl-clipboard
      dunst
      cliphist
      ### }}}

      ### GUI {{{
      obsidian
      parsec-bin
      unstable.discord
      unstable.osu-lazer-bin
      unstable.prismlauncher
      unstable.code-cursor
      unstable.antigravity
      unstable.claude-code
      unstable.windsurf
      unstable.codex
      ### }}}
    ];
  }
