{
  pkgs,
  config,
  inputs,
  ...
}: {
  ### user programs {{{
  imports = [
    ### chore {{{
    ../../user/addons/catppuccin.nix
    ### }}}

    ### shell {{{
    ../../user/programs/zsh
    ### }}}

    ### cli {{{
    ../../user/programs/bat # A cat(1) clone with syntax highlighting and Git integration
    ../../user/programs/btop # A monitor of resources
    ../../user/programs/eza # A modern, maintained replacement for ls
    ../../user/programs/fastfetch
    ../../user/programs/fd # A simple, fast and user-friendly alternative to find
    ../../user/programs/fzf # Command-line fuzzy finder written in Go
    ../../user/programs/git # Distributed version control system
    ../../user/programs/neovim
    ../../user/programs/ripgrep
    ../../user/programs/starship # A minimal, blazing fast, and extremely customizable prompt for any shell
    ../../user/programs/tealdeer
    ../../user/programs/thefuck
    ../../user/programs/tmux
    ../../user/programs/yazi
    ../../user/programs/zoxide
    ### }}}

    ### DE {{{
    ../../user/programs/hyprland/configure-only.nix
    ../../user/programs/hyprpaper
    ../../user/programs/wlogout
    ### }}}

    ### gui {{{
    ../../user/programs/kitty # A modern, hackable, featureful, OpenGL based terminal emulator
    ../../user/programs/firefox
    ../../user/programs/waybar
    ../../user/programs/rofi-wayland
    ../../user/programs/zed-editor
    ../../user/programs/obs-studio
    ../../user/programs/obsidian/wayland.nix
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
    ### }}}

    ### DE {{{
    grimblast
    wl-clipboard
    dunst
    cliphist
    ### }}}

    ### GUI {{{
    parsec-bin
    unstable.discord
    unstable.discord-ptb
    unstable.osu-lazer-bin
    unstable.prismlauncher
    unstable.code-cursor
    ### }}}
  ];
  ### }}}

  programs.git = {
    userEmail = "tenzyu.on@gmail.com";
    userName = "tenzyu";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";

    ### follow xdg base directories {{{
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    NUGET_PACKAGES = "${config.xdg.cacheHome}/NuGetPackages";
    NPM_CONFIG_INIT_MODULE = "${config.xdg.configHome}/npm/config/npm-init.js";
    NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
    NPM_CONFIG_TMP = "${config.xdg.stateHome}/npm-runtime"; # NOTE: RUNTIME_DIR is impure
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
    GTK2_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
    GOPATH = "${config.xdg.dataHome}/go";
    DOTNET_CLI_HOME = "${config.xdg.dataHome}/dotnet";
    ### }}}
  };

  home.sessionPath = [
    "${config.home.sessionVariables.CARGO_HOME}/bin"
  ];
}
