{
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

    # Service-owned data and backups, whether under /home or /srv.
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
  mkGame = spec: gameModule:
    mkMerge [
      (mkHostUser spec.key spec)
      {
        systemd.tmpfiles.rules = mkHostTmpfiles spec.key spec;
        networking.nat.internalInterfaces = ["ve-${spec.containerName}"];
      }
      (mkContainer spec gameModule)
    ];
}
