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

    home.sessionVariables.NIXOS_OZONE_WL = "1";
  }
