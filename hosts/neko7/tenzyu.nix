let
  inherit (import ../../lib/default.nix) homeModules;
in
  {
    pkgs,
    config,
    inputs,
    ...
  }: {
    ### user programs {{{
    imports = with homeModules; [
      ### common {{{
      ../common/tenzyu.nix
      ### }}}

      ### shell {{{
      programs.zsh
      ### }}}

      ### cli {{{
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
    ];

    # NOTE: home-manager が option を持っていないパッケージはココで入れる.
    home.packages = with pkgs; [
      ### cli {{{
      bitwarden-cli
      dust # du + rust = dust. Like du but more intuitive
      xdg-ninja # A shell script which checks your $HOME for unwanted files and directories
      playerctl
      jq
      jqp
      glow
      xclip
      pay-respects
      ### }}}
    ];
    ### }}}
  }
