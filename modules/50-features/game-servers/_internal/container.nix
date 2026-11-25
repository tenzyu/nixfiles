{
  config,
  lib,
  pkgs,
}: let
  inherit (lib) mkMerge mkIf;
  # NOTE: これ伝播するわけじゃないから別途必要
  steamUnfreeNames = [
    "steamcmd"
    "steam"
    "steam-run"
    "steam-original"
    "steam-unwrapped"
  ];
  mkSteamUnfreePolicy = spec: {lib, ...}: {
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem
      (lib.getName pkg)
      (
        steamUnfreeNames
        ++ lib.optionals (spec.key == "minecraft") [
          "minecraft-server"
        ]
      );
  };

  serviceLayout = import ../../../../lib/service-layout.nix {inherit lib;};

  mkHostUser = _name: spec: serviceLayout.mkStaticServiceAccount pkgs spec;

  mkHostTmpfiles = _name: spec: let
    d = serviceLayout.mkGameDirectories spec;
  in [
    "d ${d.home} 0750 ${spec.user} ${spec.user} - -"

    # Service-owned data and backups at the canonical /srv root.
    "d ${d.gameDir} 0750 ${spec.user} ${spec.user} - -"
    "d ${d.serverDir} 0750 ${spec.user} ${spec.user} - -"
    "d ${d.backupsDir} 0750 ${spec.user} ${spec.user} - -"

    # Authentication and Tailscale node identity remain host root-owned.
    "d ${d.secretsDir} 0700 root root - -"
    "d ${d.stateDir} 0750 root root - -"
    "d ${d.tailscaleDir} 0700 root root - -"
  ];

  mkContainerUserModule = spec: {pkgs, ...}:
    serviceLayout.mkStaticServiceAccount pkgs spec;

  mkTailscaleNodeModule = import ./tailscale.nix {inherit lib pkgs;};

  mkBaseContainerModule = spec: args:
    mkMerge [
      {
        system.stateVersion = "26.05";

        systemd.tmpfiles.rules =
          lib.optionals (spec.key != "minecraft")
          (mkHostTmpfiles spec.key spec);
      }

      (mkSteamUnfreePolicy spec args)
      (mkIf (spec.key != "minecraft") (mkContainerUserModule spec args))
      (mkTailscaleNodeModule spec args)
    ];

  mkContainer = spec: gameModule: let
    d = serviceLayout.mkGameDirectories spec;
  in {
    containers.${spec.containerName} = {
      autoStart = spec.autoStart or false;
      privateNetwork = true;
      enableTun = true;

      hostAddress = spec.hostAddress;
      localAddress = spec.localAddress;

      bindMounts =
        {
          "${d.home}" = {
            hostPath = d.home;
            isReadOnly = false;
          };
          "/var/lib/tailscale" = {
            hostPath = d.tailscaleDir;
            isReadOnly = false;
          };
          "${d.gameDir}" = {
            hostPath = d.gameDir;
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
  mkGame = spec: gameModule: let
    enabled = config.local.features."game-${spec.key}".enable;
    hasOperations = enabled && config.local.features.game-server-tools.enable;
    policy = serviceLayout.mkGameOperation spec;
    archiveUser = config.users.users.${policy.archiveUser};
    lockAccess = {user = "root"; group = "wheel";};
  in {
    options.local.gameOperations.${spec.key} = lib.mkOption {
      internal = true;
      readOnly = true;
      default = if hasOperations then policy else null;
      type = with lib.types; nullOr (submodule {
        options = {
          lockPath = lib.mkOption {type = str;};
          containerName = lib.mkOption {type = str;};
          containerUnit = lib.mkOption {type = str;};
          guestUnit = lib.mkOption {type = str;};
          archiveUser = lib.mkOption {type = str;};
          archiveUid = lib.mkOption {type = ints.positive;};
          archiveGid = lib.mkOption {type = ints.positive;};
          sourceDir = lib.mkOption {type = str;};
          backupsDir = lib.mkOption {type = str;};
        };
      });
      description = "Fixed host operation identities for the selected game and operator tools.";
    };

    config = mkMerge [
      (mkIf enabled (mkMerge [
        (mkHostUser spec.key spec)
        {
          systemd.tmpfiles.rules = mkHostTmpfiles spec.key spec;
          networking.nat.internalInterfaces = ["ve-${spec.containerName}"];
        }
        (mkContainer spec gameModule)
      ]))
      (mkIf hasOperations {
        assertions = [{
          assertion =
            archiveUser.name == policy.archiveUser
            && archiveUser.uid == policy.archiveUid
            && config.users.groups.${archiveUser.group}.gid == policy.archiveGid
            && archiveUser.group != "wheel"
            && !(lib.elem "wheel" archiveUser.extraGroups)
            && !(lib.elem policy.archiveUser config.users.groups.wheel.members);
          message = "The ${spec.key} archive account must keep its fixed name and UID/GID and stay outside the wheel operator group.";
        }];

        # Shared host inode, independent of guest-unit and data lifetimes.
        systemd.tmpfiles.settings.nixfiles-game-locks = {
          ${serviceLayout.gameLockDirectory}.d = lockAccess // {mode = "0750";};
          ${policy.lockPath}.f = lockAccess // {mode = "0440";};
        };
      })
    ];
  };
}
