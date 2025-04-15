{
  pkgs,
  config,
  ...
}: {
  home.username = "tenzyu";
  home.homeDirectory = "/home/tenzyu";
  home.stateVersion = "24.11";
  programs.home-manager.enable = true;

  nixpkgs.overlays = [
    (import ../lib/overlays/wayland.nix)
    (import ../lib/overlays/unstable.nix)
  ];

  nixpkgs.config.permittedInsecurePackages = [
    ### NOTE: for pkgs.opentabletdriver {{{
    "dotnet-sdk-6.0.428"
    "dotnet-sdk-wrapped-6.0.428"
    "dotnet-runtime-6.0.36"
    ### }}}
  ];

  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = ["en_US.UTF-8/UTF-8"];
  };
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = [
      pkgs.fcitx5-mozc-ut
    ];
  };

  imports = [
    ### chore {{{
    ./_core-home-manager.nix
    ./_nix.nix
    ../user/addons/nixgl.nix
    ../user/addons/catppuccin.nix
    ### }}}

    ### shell {{{
    ../user/programs/zsh
    ### }}}

    ### cli {{{
    ../user/programs/bat # A cat(1) clone with syntax highlighting and Git integration
    ../user/programs/btop # A monitor of resources
    ../user/programs/eza # A modern, maintained replacement for ls
    ../user/programs/fastfetch
    ../user/programs/fd # A simple, fast and user-friendly alternative to find
    ../user/programs/fzf # Command-line fuzzy finder written in Go
    ../user/programs/git # Distributed version control system
    ../user/programs/neovim
    ../user/programs/ripgrep
    ../user/programs/starship # A minimal, blazing fast, and extremely customizable prompt for any shell
    ../user/programs/tealdeer
    ../user/programs/thefuck
    ../user/programs/yazi
    ../user/programs/zoxide
    ### }}}

    ### DE {{{
    ../user/programs/hyprland/configure-only.nix
    ../user/programs/hyprpaper
    ../user/programs/wlogout
    ### }}}

    ### gui {{{
    ../user/addons/ghostty.nix
    ../user/programs/kitty # A modern, hackable, featureful, OpenGL based terminal emulator
    ../user/programs/waybar
    ../user/programs/rofi-wayland
    ../user/programs/zed-editor
    ../user/programs/obs-studio
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

    __HM_SESS_VARS_SOURCED = ""; # TODO: remove this workaround
  };

  home.sessionPath = [
    "/usr/lib/ccache/bin/:$PATH"
    "${config.home.sessionVariables.CARGO_HOME}/bin"
  ];
}
