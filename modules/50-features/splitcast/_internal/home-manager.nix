{role}: {
  config,
  lib,
  pkgs,
  ...
}: let
  feature = "splitcast-${role}";
  cfg = config.local.features.${feature};
  json = pkgs.formats.json {};
  toml = pkgs.formats.toml {};
  gated = pkgs.writeShellScript "splitcast-migration-gated" ''
    echo 'SplitCast service is disabled pending Rust parity and explicit cutover approval.' >&2
    exit 1
  '';
  defaults = builtins.fromJSON (builtins.readFile cfg.package.example);
  roleDefaults =
    {
      inherit role;
      audio.rnnoise_plugin = "${cfg.package.rnnoise}/lib/ladspa/librnnoise_ladspa.so";
      obs.binary = "${cfg.package.obs}/bin/obs";
    }
    // lib.optionalAttrs (role == "production") {
      peer = {
        control_port = 17871;
        remote_control_port = 17870;
        forward_control_port = 17873;
        token_file = "~/.config/splitcast/production.token";
        remote_token_file = "~/.config/splitcast/control.token";
      };
    };
  settings = lib.recursiveUpdate (lib.recursiveUpdate defaults roleDefaults) cfg.settings;
  generated = toml.generate "${feature}.toml" settings;
in {
  options.local.features.${feature} = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../../packages/splitcast-rs {};
      description = "SplitCast package, including the authoritative example configuration.";
    };
    rustCandidate = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicit experimental Rust agent selection. False keeps the service migration-gated.";
    };
    rustPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../../packages/splitcast-rs {};
      description = "Unprivileged Rust replacement candidate, disabled unless rustCandidate=true.";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf json.type;
      default = {};
      description = "Nix attribute overrides merged into the role's generated TOML. Store credential paths here, never secrets.";
    };
    configFile = lib.mkOption {
      type = lib.types.str;
      default = "${generated}";
      defaultText = lib.literalExpression "generated TOML from package.example and settings";
      description = "Configuration path passed to the agent. Override with an absolute runtime path for mutable configuration.";
    };
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        DISPLAY = ":99";
        XAUTHORITY = "/run/splitcast-display/Xauthority";
      };
      description = "Agent environment, including DISPLAY and XAUTHORITY for a separately managed production display. Do not put secrets here.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.local.features.splitcast-capture.enable && config.local.features.splitcast-production.enable);
        message = "Enable only one SplitCast agent role per user.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.configFile;
        message = "SplitCast configFile must be an absolute path.";
      }
      {
        assertion = settings.role == role;
        message = "SplitCast settings.role must match the enabled feature.";
      }
    ];
    home.packages = [cfg.package] ++ lib.optional cfg.rustCandidate cfg.rustPackage;
    xdg.configFile."splitcast/${role}.toml".source = generated;
    systemd.user.services.${feature} = {
      Unit = {
        Description = "SplitCast ${role} control agent";
        After = ["network.target"];
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "simple";
        ExecStart = if cfg.rustCandidate then "${lib.getExe cfg.rustPackage} agent --config ${lib.escapeShellArg cfg.configFile}" else "${gated}";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") cfg.environment;
        Restart = "on-failure";
        RestartSec = 5;
        KillMode = "control-group";
        TimeoutStopSec = 20;
        ExecStopPost = "${lib.getExe cfg.rustPackage} cleanup --config ${lib.escapeShellArg cfg.configFile}";
        SendSIGKILL = true;
        UMask = "0077";
        WorkingDirectory = config.home.homeDirectory;
        CPUWeight = 25;
        Nice = 10;
        MemoryMax = "2G";
      };
      Install.WantedBy = [];
    };
  };
}
