{lib, ...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.common.enable {
      local.homeMigration.paths = let
        home = config.home.homeDirectory;
        vars = config.home.sessionVariables;
        move = source: target: processes: {inherit source target processes;};
      in [
        (move "${home}/.cargo" vars.CARGO_HOME ["cargo" "rustc" "rustup"])
        (move "${home}/.rustup" vars.RUSTUP_HOME ["cargo" "rustc" "rustup"])
        (move "${home}/.nuget/packages" vars.NUGET_PACKAGES ["*dotnet*"])
        (move "${home}/.npm" vars.NPM_CONFIG_CACHE ["*npm*" "node"])
        (move "${home}/.npm-init.js" vars.NPM_CONFIG_INIT_MODULE ["*npm*"])
        (move "${home}/.node_repl_history" vars.NODE_REPL_HISTORY ["node"])
        (move "${home}/.gtkrc-2.0" vars.GTK2_RC_FILES [])
        (move "${home}/go" vars.GOPATH ["go" "gopls"])
        # DOTNET_CLI_HOME is a replacement HOME, not the .dotnet directory.
        (move "${home}/.dotnet" "${vars.DOTNET_CLI_HOME}/.dotnet" ["*dotnet*"])
      ];

      home.sessionVariables = {
        EDITOR = "nvim";
        MANPAGER = "nvim +Man!";

        RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
        CARGO_HOME = "${config.xdg.dataHome}/cargo";
        NUGET_PACKAGES = "${config.xdg.cacheHome}/NuGetPackages";
        NPM_CONFIG_INIT_MODULE = "${config.xdg.configHome}/npm/config/npm-init.js";
        NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
        NPM_CONFIG_TMP = "${config.xdg.stateHome}/npm-runtime";
        NODE_REPL_HISTORY = "${config.xdg.stateHome}/node_repl_history";
        GTK2_RC_FILES = "${config.xdg.configHome}/gtk-2.0/gtkrc";
        GOPATH = "${config.xdg.dataHome}/go";
        DOTNET_CLI_HOME = "${config.xdg.dataHome}/dotnet";
      };

      systemd.user.sessionVariables = lib.genAttrs [
        "RUSTUP_HOME"
        "CARGO_HOME"
        "NUGET_PACKAGES"
        "NPM_CONFIG_INIT_MODULE"
        "NPM_CONFIG_CACHE"
        "NPM_CONFIG_TMP"
        "NODE_REPL_HISTORY"
        "GTK2_RC_FILES"
        "GOPATH"
        "DOTNET_CLI_HOME"
      ] (name: config.home.sessionVariables.${name});

      home.sessionPath = [
        "${config.home.sessionVariables.CARGO_HOME}/bin"
      ];

      programs.git.settings.user = lib.mkDefault {
        name = config.local.user.name;
        email = config.local.user.email;
      };
    };
  };
}
