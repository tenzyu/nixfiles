{lib, ...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: let
    home = config.home.homeDirectory;
    vars = config.home.sessionVariables;
    held = group: builtins.elem group config.local.homeMigration.legacyGroups;
    tools = [
      {
        group = "rust";
        variable = "CARGO_HOME";
        legacy = "${home}/.cargo";
        intended = "${config.xdg.dataHome}/cargo";
        processes = ["cargo" "rustc" "rustup"];
      }
      {
        group = "rust";
        variable = "RUSTUP_HOME";
        legacy = "${home}/.rustup";
        intended = "${config.xdg.dataHome}/rustup";
        processes = ["cargo" "rustc" "rustup"];
      }
      {
        group = "dotnet";
        variable = "NUGET_PACKAGES";
        legacy = "${home}/.nuget/packages";
        intended = "${config.xdg.cacheHome}/NuGetPackages";
        processes = ["*dotnet*"];
      }
      {
        group = "dotnet";
        variable = "DOTNET_CLI_HOME";
        legacy = home;
        intended = "${config.xdg.dataHome}/dotnet";
        suffix = "/.dotnet";
        processes = ["*dotnet*"];
      }
      {
        group = "npm";
        variable = "NPM_CONFIG_CACHE";
        legacy = "${home}/.npm";
        intended = "${config.xdg.cacheHome}/npm";
        processes = ["*npm*" "node"];
      }
      {
        group = "npm";
        variable = "NPM_CONFIG_INIT_MODULE";
        legacy = "${home}/.npm-init.js";
        intended = "${config.xdg.configHome}/npm/config/npm-init.js";
        processes = ["*npm*"];
      }
      {
        group = "node-history";
        variable = "NODE_REPL_HISTORY";
        legacy = "${home}/.node_repl_history";
        intended = "${config.xdg.stateHome}/node_repl_history";
        processes = ["node"];
      }
      {
        group = "gtk2";
        variable = "GTK2_RC_FILES";
        legacy = "${home}/.gtkrc-2.0";
        intended = "${config.xdg.configHome}/gtk-2.0/gtkrc";
      }
      {
        group = "go";
        variable = "GOPATH";
        legacy = "${home}/go";
        intended = "${config.xdg.dataHome}/go";
        processes = ["go" "gopls"];
      }
    ];
    selected = tool:
      if held tool.group
      then tool.legacy
      else tool.intended;
    goBin = vars.GOBIN or "${vars.GOPATH}/bin";
  in {
    config = lib.mkIf config.local.features.common.enable {
      local.homeMigration.paths =
        map (tool: let
          suffix = tool.suffix or "";
        in {
          inherit (tool) group;
          owner = "common";
          source = tool.legacy + suffix;
          target = tool.intended + suffix;
          route = vars.${tool.variable} + suffix;
          processes = tool.processes or [];
          consumers =
            {${tool.variable} = vars.${tool.variable};}
            // lib.optionalAttrs (tool.variable == "GOPATH") {
              GOBIN = goBin;
              GOMODCACHE = vars.GOMODCACHE or "${vars.GOPATH}/pkg/mod";
            };
          serviceVariables = [tool.variable];
          independentRoutes =
            lib.optionalAttrs (tool.variable == "GOPATH")
            (builtins.intersectAttrs {
                GOBIN = null;
                GOMODCACHE = null;
              }
              vars);
        })
        tools;

      home.sessionVariables =
        builtins.listToAttrs (map (tool: lib.nameValuePair tool.variable (selected tool)) tools)
        // {
          EDITOR = "nvim";
          MANPAGER = "nvim +Man!";
          # Scratch has no durable migration root.
          NPM_CONFIG_TMP =
            if held "npm"
            then "${home}/.npm/_tmp"
            else "${config.xdg.stateHome}/npm-runtime";
        };

      systemd.user.sessionVariables =
        builtins.intersectAttrs
        (lib.genAttrs (map (tool: tool.variable) tools ++ ["NPM_CONFIG_TMP" "GOBIN" "GOMODCACHE"]) (_: null))
        vars;

      home.sessionPath = ["${vars.CARGO_HOME}/bin" goBin];

      programs.git.settings.user = lib.mkDefault {
        name = config.local.user.name;
        email = config.local.user.email;
      };
    };
  };
}
