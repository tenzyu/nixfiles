{config, lib, pkgs, ...}: let
  cfg = config.services.remote-execution-mcp;
  packages = import ./packages.nix {inherit pkgs;};
  user = "remote-execution-mcp";
  home = "/var/lib/${user}";
  tools = with pkgs; [bash coreutils findutils git ripgrep jq nix rustc cargo bun tmux];
in {
  options.services.remote-execution-mcp = {
    enable = lib.mkEnableOption "private Remote Execution MCP guest service";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Gateway listen address inside the isolated guest, never the production host.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.listenAddress == "127.0.0.1" || cfg.listenAddress == "0.0.0.0";
      message = "Remote Execution MCP must use its private guest listener.";
    }];
    users.groups.${user} = {};
    users.users.${user} = {
      isSystemUser = true;
      group = user;
      inherit home;
      shell = pkgs.bash;
    };
    security.sudo.enable = false;
    services.openssh.enable = false;
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      accept-flake-config = false;
      trusted-users = ["root"];
      allowed-users = ["root" user];
      sandbox = true;
    };
    environment.systemPackages = tools;
    networking.firewall.enable = true;
    networking.firewall.allowedTCPPorts = lib.optional (cfg.listenAddress != "127.0.0.1") 18991;
    systemd.services.remote-execution-mcp = {
      description = "Private stateful MCP execution gateway";
      wantedBy = ["multi-user.target"];
      after = ["network.target" "nix-daemon.socket"];
      path = tools;
      environment = {
        HOME = home;
        DESKTOP_COMMANDER_DISABLE_TELEMETRY = "1";
      };
      preStart = ''
        mkdir -p "$HOME/.claude-server-commander"
        if [ ! -e "$HOME/.claude-server-commander/config.json" ]; then
          printf '%s\n' '{"telemetryEnabled":false,"allowedDirectories":[],"blockedCommands":[]}' \
            > "$HOME/.claude-server-commander/config.json"
        fi
      '';
      serviceConfig = {
        User = user;
        Group = user;
        StateDirectory = user;
        StateDirectoryMode = "0700";
        WorkingDirectory = home;
        UMask = "0077";
        ExecStart = "${lib.getExe packages.supergateway} --stdio '${lib.getExe packages.desktopCommander} --no-onboarding' --outputTransport streamableHttp --stateful --host ${cfg.listenAddress} --port 18991";
        Restart = "on-failure";
        KillMode = "control-group";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        CapabilityBoundingSet = "";
      };
    };
  };
}
