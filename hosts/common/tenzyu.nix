{
  config,
  lib,
  ...
}: {
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

  programs.git.settings.user = lib.mkDefault {
    name = "tenzyu";
    email = "tenzyu.on@gmail.com";
  };
}
