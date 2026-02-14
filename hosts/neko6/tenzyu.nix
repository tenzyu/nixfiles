{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    ../../modules/home/programs/zsh
    ../../modules/home/programs/bat # A cat(1) clone with syntax highlighting and Git integration
    ../../modules/home/programs/btop # A monitor of resources
    ../../modules/home/programs/eza # A modern, maintained replacement for ls
    ../../modules/home/programs/fastfetch
    ../../modules/home/programs/fd # A simple, fast and user-friendly alternative to find
    ../../modules/home/programs/fzf # Command-line fuzzy finder written in Go
    ../../modules/home/programs/git # Distributed version control system
    ../../modules/home/programs/neovim
    ../../modules/home/programs/ripgrep
    ../../modules/home/programs/starship # A minimal, blazing fast, and extremely customizable prompt for any shell
    ../../modules/home/programs/tealdeer
    ../../modules/home/programs/tmux
    ../../modules/home/programs/yazi
    ../../modules/home/programs/zoxide
  ];

  home.packages = [
    pkgs.bitwarden-cli
    pkgs.dust # du + rust = dust. Like du but more intuitive
    pkgs.devbox
    pkgs.xdg-ninja # A shell script which checks your $HOME for unwanted files and directories
    pkgs.glow
    pkgs.xclip
    pkgs.pay-respects
  ];

  programs.git.settings.user = {
    name = "tenzyu";
    email = "tenzyu.on@gmail.com";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    MANPAGER = "nvim +Man!";
    NIXOS_OZONE_WL = "1";

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
