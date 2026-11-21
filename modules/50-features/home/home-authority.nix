{
  flake.modules.homeManager.home-authority = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkEnableOption mkOption types;
    cfg = config.local.homeAuthority;
    home = config.home.homeDirectory;
    xdg = config.xdg;
    quote = lib.escapeShellArg;
    stateType = types.submodule {
      options = {
        legacy = mkOption {
          type = types.str;
          description = "One direct entry name in the actual HOME (not a glob or nested path).";
        };
        canonical = mkOption {
          type = types.str;
          description = "One absolute authoritative mutable storage root under HOME.";
        };
        mode = mkOption {
          type = types.enum ["observe" "native" "boxxy"];
          default = "observe";
          description = "observe=read-only; native=export supported variables; boxxy=generate a rule for explicitly wrapped processes.";
        };
        nativeEnvironment = mkOption {
          type = types.attrsOf types.str;
          default = {};
          description = "Application-supported environment values, active only in native mode.";
        };
        kind = mkOption {
          type = types.enum ["directory" "file"];
          default = "directory";
        };
      };
    };
    routes = cfg.states;
    routeList = lib.mapAttrsToList (name: state: state // {inherit name;}) routes;
    activeNative = lib.filter (state: state.mode == "native") routeList;
    activeBoxxy = lib.filter (state: state.mode == "boxxy") routeList;
    envPieces = map (state: state.nativeEnvironment) activeNative;
    nativeVars = lib.foldl' (acc: piece: acc // piece) {} envPieces;
    allEnvNames = lib.concatMap builtins.attrNames envPieces;
    display = lib.concatMapStringsSep "\n" (state: let
      source = "${home}/${state.legacy}";
      target = state.canonical;
    in ''
      if [ -e ${quote source} ] || [ -L ${quote source} ]; then original=present; else original=absent; fi
      if [ -e ${quote target} ] || [ -L ${quote target} ]; then canonical=present; else canonical=absent; fi
      printf '%s\n' ${quote "[${state.name}] mode=${state.mode} legacy=${source} canonical=${target}"} "source=$original target=$canonical"
    '') routeList;
  in {
    options.local.homeAuthority = {
      enable = mkEnableOption "the native HOME authority contract and a read-only audit";
      root = {
        forbidden = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Prohibited direct names in the physical HOME, not just one sandbox view.";
        };
        enforce = mkOption {
          type = types.bool;
          default = false;
          description = "Reserved for a verified filesystem-level root policy. Unsupported until independently proven.";
        };
      };
      states = mkOption {
        type = types.attrsOf stateType;
        default = {};
        description = "Single authoritative mutable roots and opt-in native or sandboxed views.";
      };
      audit = mkOption {
        type = types.bool;
        default = true;
        description = "Print a read-only source/target inventory during Home Manager activation.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions =
        [{
          assertion = !cfg.root.enforce;
          message = "homeAuthority.root.enforce requires a filesystem-wide implementation covering all launch paths and existing FDs. No such backend is installed; audit is not enforcement.";
        } {
          assertion = builtins.length allEnvNames == builtins.length (lib.unique allEnvNames);
          message = "homeAuthority.states defines an environment variable more than once.";
        }]
        ++ map (state: {
          assertion =
            builtins.match "\\.[A-Za-z0-9][A-Za-z0-9._-]*" state.legacy != null
            && lib.hasPrefix "${home}/" state.canonical
            && !(lib.hasInfix "/../" state.canonical)
            && state.canonical != "${home}/${state.legacy}";
          message = "homeAuthority.states.${state.name} must use a direct dot-entry and a distinct absolute canonical path inside HOME.";
        }) routeList
        ++ map (name: {
          assertion = builtins.any (state: state.legacy == name) routeList;
          message = "homeAuthority.root.forbidden includes ${name}, which has no authoritative state declaration.";
        }) cfg.root.forbidden;

      home.sessionVariables = nativeVars;
      systemd.user.sessionVariables = builtins.intersectAttrs
        (lib.genAttrs (builtins.attrNames nativeVars) (_: null))
        config.home.sessionVariables;

      programs.boxxy = lib.mkIf (activeBoxxy != []) {
        enable = true;
        rules = map (state: {
          name = "home-authority: ${state.name}";
          target = "${home}/${state.legacy}";
          rewrite = state.canonical;
          mode = state.kind;
        }) activeBoxxy;
      };

      home.packages = lib.optional cfg.audit pkgs.xdg-ninja;

      # Declaring a native route is an explicit cutover, never a data-move request.
      # Refuse a cutover with a legacy name still present or an absent new root.
      home.activation.homeAuthorityCheckCutover = lib.mkIf (activeNative != [])
        (lib.hm.dag.entryBefore ["writeBoundary"] ''
          ${lib.concatMapStringsSep "\n" (state: let
            source = "${home}/${state.legacy}";
          in ''
            if [ -e ${quote source} ] || [ -L ${quote source} ]; then
              echo ${quote "HOME authority: ${state.name}: legacy path still present; keeping the current generation"} >&2
              exit 1
            fi
            if [ ! -e ${quote state.canonical} ]; then
              echo ${quote "HOME authority: ${state.name}: canonical state missing; refusing empty-state cutover"} >&2
              exit 1
            fi
          '') activeNative}
        '');

      home.activation.homeAuthorityAudit = lib.mkIf cfg.audit
        (lib.hm.dag.entryAfter ["writeBoundary"] ''
          echo "HOME authority audit (not physical-root enforcement)"
          ${display}
          echo "For unsupported applications: xdg-ninja --skip-unsupported"
        '');
    };
  };
}
