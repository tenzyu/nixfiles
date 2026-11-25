{inputs, self, ...}: {
  perSystem = {system, lib, ...}: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      # Build independently; never make the host generation a GC root for
      # the current application release.
      neko7-minecraft-system =
        self.nixosConfigurations.neko7.config.containers.neko7-mc.config.system.build.toplevel;
    };
  };

  flake.modules.nixos.game-minecraft = {
    config,
    lib,
    pkgs,
    ...
  }: let
    useSrv = config.local.features.game-srv.enable;
    layout = import ../../../lib/service-layout.nix {inherit lib;};
    spec = {
      key = "minecraft";
      user = "game-minecraft";
      uid = 27009;
      gid = 27009;
      home = if useSrv then "/var/lib/game-containers/minecraft" else "/home/game-minecraft";
      gameDir = if useSrv then "/srv/minecraft" else "/home/game-minecraft/minecraft";
      containerName = "neko7-mc";
      guestService = "minecraft-server-survival";
      backupSource = "survival";
      hostAddress = "10.77.30.1";
      localAddress = "10.77.30.2";
      tailscaleHostname = "neko7-minecraft";
      autoStart = true;
      udpPorts = [];
      tcpPorts = [25565];
      extraModules = [inputs.nix-minecraft.nixosModules.minecraft-servers];
    };
    inherit (import ./_internal/container.nix {inherit config lib pkgs;}) mkGame;
    mkMinecraftModule = spec: {
      pkgs,
      lib,
      ...
    }: let
      d = layout.mkGameDirectories spec;
    in {
      nixpkgs.overlays = [inputs.nix-minecraft.overlay];

      # The legacy layout keeps Minecraft data under /home.
      systemd.services.${spec.guestService}.serviceConfig.ProtectHome =
        lib.mkIf (!useSrv) (lib.mkForce false);

      users.users.minecraft.uid = spec.uid;
      users.groups.minecraft.gid = spec.gid;
      environment.systemPackages = [pkgs.tmux];
      services.minecraft-servers = {
        enable = true;
        eula = true; # Only if you have accepted Mojang's EULA.
        dataDir = d.gameDir;
        servers.survival = {
          enable = true;
          package = pkgs.fabricServers.fabric-26_3.override {
            jre_headless = pkgs.openjdk25_headless;
          };
          jvmOpts = "-Xms1G -Xmx4G";
          openFirewall = false;
          serverProperties = {
            "level-name" = "world";
            "server-ip" = "";
            "server-port" = 25565;
            "online-mode" = true;
            "white-list" = false;
            "max-players" = 8;
            "enable-rcon" = false;
          };
        };
      };
    };
    game = mkGame spec mkMinecraftModule;
    profile = "/nix/var/nix/profiles/per-container/${spec.containerName}/system";
  in
    game // {
      config = lib.mkMerge [
        game.config
        (lib.mkIf config.local.features.game-minecraft.enable {
          # NixOS nspawn binds the host per-container profiles directory over
          # /nix/var/nix/profiles inside the guest. SYSTEM_PATH is resolved
          # there, not at the host's own /nix/var/nix/profiles/system.
          # Keep config as the build input, but deploy through a native Nix
          # generation profile (the explicit path wins over the derived path).
          containers.${spec.containerName}.path = lib.mkForce "/nix/var/nix/profiles/system";
          systemd.services."container@${spec.containerName}".unitConfig.ConditionPathExists = "${profile}/init";
          system.preSwitchChecks.minecraft-workload-profile = ''
            if ! test -L ${profile} || ! test -x ${profile}/init; then
              echo "Seed the Minecraft workload profile from the incumbent guest before activation." >&2
              exit 1
            fi
          '';
        })
      ];
    };
}
