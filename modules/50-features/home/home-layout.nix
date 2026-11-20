{
  flake.modules.homeManager.home-layout = {
    config,
    lib,
    ...
  }: let
    home = config.home.homeDirectory;
    vars = config.home.sessionVariables;
    held = group: builtins.elem group config.local.homeMigration.legacyGroups;
    tools = [
      {
        group = "codex";
        variable = "CODEX_HOME";
        legacy = "${home}/.codex";
        intended = "${config.xdg.dataHome}/codex";
        processes = ["*codex*"];
        references = ["config.toml" "hooks.json"];
      }
      {
        group = "gemini";
        variable = "GEMINI_CLI_HOME";
        legacy = home;
        intended = "${config.xdg.dataHome}/gemini";
        suffix = "/.gemini";
        processes = ["*gemini*"];
      }
      {
        group = "bun";
        variable = "BUN_INSTALL_CACHE_DIR";
        legacy = "${home}/.bun/install/cache";
        intended = "${config.xdg.cacheHome}/bun/install";
        processes = ["bun" ".bun-wrapped"];
        links = true;
      }
      {
        group = "bun";
        variable = "BUN_INSTALL";
        legacy = "${home}/.bun";
        intended = "${config.xdg.dataHome}/bun";
        processes = ["bun" ".bun-wrapped"];
        links = true;
      }
      {
        group = "bash-history";
        variable = "HISTFILE";
        legacy = "${home}/.bash_history";
        intended = "${config.xdg.stateHome}/bash/history";
      }
      {
        group = "claude";
        variable = "CLAUDE_CONFIG_DIR";
        legacy = "${home}/.claude";
        intended = "${config.xdg.configHome}/claude";
        processes = ["*claude*"];
      }
    ];
    emitted = lib.filter (tool: tool.group != "claude" || !held "claude") tools;
    effective = tool: vars.${tool.variable} or tool.legacy;
  in {
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
        map (tool: let
          suffix = tool.suffix or "";
        in {
          inherit (tool) group;
          owner = "home-layout";
          source = tool.legacy + suffix;
          target = tool.intended + suffix;
          route = effective tool + suffix;
          consumers = lib.optionalAttrs (builtins.hasAttr tool.variable vars) {${tool.variable} = effective tool;};
          serviceVariables = lib.optional (tool.variable != "HISTFILE") tool.variable;
          processes = tool.processes or [];
          references = tool.references or [];
          repairAbsoluteLinks = tool.links or false;
        })
        tools
        ++ [
          {
            owner = "home-layout";
            group = "claude";
            source = "${home}/.claude.json";
            target = "${config.xdg.configHome}/claude/.claude.json";
            route =
              if held "claude"
              then "${home}/.claude.json"
              else "${vars.CLAUDE_CONFIG_DIR}/.claude.json";
            processes = ["*claude*"];
          }
        ];

      home.sessionVariables = builtins.listToAttrs (map (
          tool:
            lib.nameValuePair tool.variable (
              if held tool.group
              then tool.legacy
              else tool.intended
            )
        )
        emitted);
      home.sessionPath = ["${vars.BUN_INSTALL}/bin"];

      # GUI applications and user services inherit the same storage as shells.
      systemd.user.sessionVariables =
        builtins.intersectAttrs
        (lib.genAttrs (map (tool: tool.variable) (lib.filter (tool: tool.variable != "HISTFILE") emitted)) (_: null))
        vars;
    };
  };
}
