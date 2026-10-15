{lib, pkgs}: let
  inherit (lib) mkMerge mkIf;
    # NOTE: これ伝播するわけじゃないから別途必要
    steamUnfreeNames = [
      "steamcmd"
      "steam"
      "steam-run"
      "steam-original"
      "steam-unwrapped"
    ];
    mkSteamUnfreePolicy = {lib, ...}: {
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (lib.getName pkg) steamUnfreeNames;
    };

    mkHostUser = _name: spec: {
      users.groups.${spec.user}.gid = spec.gid;

      users.users.${spec.user} = {
        isNormalUser = true;
        uid = spec.uid;
        group = spec.user;
        home = spec.home;
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        description = "${spec.containerName} service account";
      };
    };

    mkHostTmpfiles = _name: spec: [
      "d ${spec.home} 0750 ${spec.user} ${spec.user} - -"

      # Human-maintained runtime root.
      "d ${spec.home}/${spec.key} 0750 ${spec.user} ${spec.user} - -"
      "d ${spec.home}/${spec.key}/server 0750 ${spec.user} ${spec.user} - -"
      "d ${spec.home}/${spec.key}/backups 0750 ${spec.user} ${spec.user} - -"

      # Root-owned secrets. Game processes should not be able to read auth keys.
      "d ${spec.home}/secrets 0700 root root - -"

      # Tailscale node identity. Persist this, or the container becomes a new node.
      "d ${spec.home}/.state 0750 root root - -"
      "d ${spec.home}/.state/tailscale 0700 root root - -"
    ];

    mkContainerUserModule = spec: {
      lib,
      pkgs,
      ...
    }: {
      users.groups.${spec.user}.gid = spec.gid;

      users.users.${spec.user} = {
        isNormalUser = true;
        uid = spec.uid;
        group = spec.user;
        home = spec.home;
        createHome = true;
        shell = pkgs.bashInteractive;
        hashedPassword = "!";
        description = "${spec.containerName} service account";
      };
    };

    mkTailscaleNodeModule = import ./tailscale.nix { inherit lib pkgs; };

    mkBaseContainerModule = spec: args:
      mkMerge [
        {
          system.stateVersion = "26.05";

          systemd.tmpfiles.rules = mkHostTmpfiles spec.key spec;
        }

        (mkSteamUnfreePolicy args)
        (mkIf (spec.key != "minecraft") (mkContainerUserModule spec args))
        (mkTailscaleNodeModule spec args)
      ];

    mkContainer = spec: gameModule: {
      containers.${spec.containerName} = {
        autoStart = spec.autoStart or false;
        privateNetwork = true;
        enableTun = true;

        hostAddress = spec.hostAddress;
        localAddress = spec.localAddress;

        bindMounts = {
          "${spec.home}" = {
            hostPath = spec.home;
            isReadOnly = false;
          };

          "/var/lib/tailscale" = {
            hostPath = "${spec.home}/.state/tailscale";
            isReadOnly = false;
          };
        };

        config = containerArgs @ {
          lib,
          pkgs,
          ...
        }: {
          imports = spec.extraModules or [];
          config = mkMerge [
            (mkBaseContainerModule spec containerArgs)
            (gameModule spec containerArgs)
          ];
        };
      };
    };
in {
  mkGame = spec: gameModule: mkMerge [
    (mkHostUser spec.key spec)
    {
      systemd.tmpfiles.rules = mkHostTmpfiles spec.key spec;
      networking.nat.internalInterfaces = [ "ve-${spec.containerName}" ];
    }
    (mkContainer spec gameModule)
  ];
}
