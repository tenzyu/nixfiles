{
  flake.modules.homeManager.home-layout = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.home-layout.enable {
      xdg.userDirs = {
        enable = true;
        createDirectories = true;
        documents = "${config.home.homeDirectory}/Documents";
        download = "${config.home.homeDirectory}/Downloads";
        music = "${config.home.homeDirectory}/Music";
        pictures = "${config.home.homeDirectory}/Pictures";
        videos = "${config.home.homeDirectory}/Videos";
        desktop = null;
        publicShare = null;
        templates = null;
      };

      local.homeMigration.paths =
        [
          {
            source = "${config.home.homeDirectory}/.codex";
            target = config.home.sessionVariables.CODEX_HOME;
            processes = ["*codex*"];
            references = ["config.toml" "hooks.json"];
          }
          {
            source = "${config.home.homeDirectory}/.gemini";
            target = "${config.home.sessionVariables.GEMINI_CLI_HOME}/.gemini";
            processes = ["*gemini*"];
          }
          {
            source = "${config.home.homeDirectory}/.bun/install/cache";
            target = config.home.sessionVariables.BUN_INSTALL_CACHE_DIR;
            processes = ["bun" ".bun-wrapped"];
          }
          {
            source = "${config.home.homeDirectory}/.bun";
            target = config.home.sessionVariables.BUN_INSTALL;
            processes = ["bun" ".bun-wrapped"];
          }
          {
            source = "${config.home.homeDirectory}/.bash_history";
            target = config.home.sessionVariables.HISTFILE;
          }
          {
            source = "${config.home.homeDirectory}/.claude";
            target = config.home.sessionVariables.CLAUDE_CONFIG_DIR;
            processes = ["*claude*"];
          }
          {
            source = "${config.home.homeDirectory}/.claude.json";
            target = "${config.home.sessionVariables.CLAUDE_CONFIG_DIR}/.claude.json";
            processes = ["*claude*"];
          }
        ]
        ++ lib.optional config.local.features.android-mic.enable {
          source = "${config.home.homeDirectory}/.android";
          target = "${config.home.sessionVariables.ANDROID_USER_HOME}/.android";
          processes = ["adb" ".adb-wrapped" "*android-mic*"];
        };

      home.sessionVariables = {
        ANDROID_USER_HOME = "${config.xdg.dataHome}/android";
        BUN_INSTALL = "${config.xdg.dataHome}/bun";
        BUN_INSTALL_CACHE_DIR = "${config.xdg.cacheHome}/bun/install";
        CLAUDE_CONFIG_DIR = "${config.xdg.configHome}/claude";
        CODEX_HOME = "${config.xdg.dataHome}/codex";
        # Gemini appends .gemini to this root; retain its existing credentials/history.
        GEMINI_CLI_HOME = "${config.xdg.dataHome}/gemini";
        HISTFILE = "${config.xdg.stateHome}/bash/history";
      };

      home.sessionPath = ["${config.home.sessionVariables.BUN_INSTALL}/bin"];

      # GUI applications and user services need the same locations as shells.
      systemd.user.sessionVariables = lib.filterAttrs (name: _:
        builtins.elem name [
          "ANDROID_USER_HOME"
          "BUN_INSTALL"
          "BUN_INSTALL_CACHE_DIR"
          "CLAUDE_CONFIG_DIR"
          "CODEX_HOME"
          "GEMINI_CLI_HOME"
          "DOTNET_CLI_HOME"
          "NPM_CONFIG_CACHE"
        ])
      config.home.sessionVariables;
    };
  };
}
