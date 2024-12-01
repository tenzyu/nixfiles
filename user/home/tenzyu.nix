{
  pkgs,
  config,
  ...
}: {
  imports = [
    ### chore {{{
    ./common.nix
    ../addons/nixgl.nix
    ../addons/catppuccin.nix
    ### }}}

    ### shell {{{
    ../programs/zsh
    ### }}}

    ### cli {{{
    ../programs/bat # A cat(1) clone with syntax highlighting and Git integration
    ../programs/btop # A monitor of resources
    ../programs/eza # A modern, maintained replacement for ls
    ../programs/fastfetch
    ../programs/fd # A simple, fast and user-friendly alternative to find
    ../programs/fzf # Command-line fuzzy finder written in Go
    ../programs/git # Distributed version control system
    ../programs/neovim
    ../programs/ripgrep
    ../programs/starship # A minimal, blazing fast, and extremely customizable prompt for any shell
    ../programs/tealdeer
    ../programs/thefuck
    ../programs/yazi
    ../programs/zoxide
    ### }}}

    ### DE {{{
    ../wayland/hyprland/configure-only.nix
    ../services/hyprpaper
    ../programs/wlogout
    ### }}}

    ### gui {{{
    ../addons/ghostty.nix
    ../programs/kitty # A modern, hackable, featureful, OpenGL based terminal emulator
    ../programs/waybar
    ../programs/rofi-wayland
    ../programs/zed-editor
    ../programs/obs-studio
    ### }}}
  ];

  # home-manager が option を持っていないパッケージはココで入れる.
  home.packages = [
    ### cli {{{
    pkgs.bitwarden-cli
    pkgs.brightnessctl
    pkgs.dust # du + rust = dust. Like du but more intuitive
    pkgs.pavucontrol # PulseAudio Volume Control
    pkgs.xdg-ninja # A shell script which checks your $HOME for unwanted files and directories
    pkgs.playerctl
    pkgs.jq
    pkgs.jqp
    pkgs.glow
    pkgs.xclip
    ### }}}

    ### DE {{{
    pkgs.grimblast
    pkgs.wl-clipboard
    pkgs.dunst
    pkgs.cliphist
    ### }}}

    ### gui {{{
    pkgs.opentabletdriver
    ### }}}

    ### font {{{
    pkgs.fira-code
    pkgs.fira-code-symbols
    pkgs.fira-code-nerdfont
    pkgs.font-awesome
    pkgs.noto-fonts
    pkgs.noto-fonts-color-emoji
    ### }}}
  ];

  ### user variables {{{
  programs.git = {
    userEmail = "tenzyu.on@gmail.com";
    userName = "tenzyu";
  };
  ### }}}

  fonts.fontconfig = {
    enable = true;
  };

  # Prefer XDG Base Directories
  xdg.enable = true;
  home.preferXdgDirectories = true;

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

    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive"; # https://nixos.wiki/wiki/Locales
    __HM_SESS_VARS_SOURCED = ""; # TODO: remove this workaround
  };

  home.sessionPath = [
    "/usr/lib/ccache/bin/:$PATH"
    "${config.home.sessionVariables.CARGO_HOME}/bin"
  ];
}
