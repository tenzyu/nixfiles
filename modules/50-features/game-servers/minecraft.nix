{inputs, ...}: {
  flake.modules.nixos.game-minecraft = {
    config,
    lib,
    pkgs,
    ...
  }: let
    useSrv = config.local.features.game-srv.enable;
    useSops = config.local.features.game-secrets-sops.enable;
    layout = import ../../../lib/service-layout.nix {inherit lib;};
    spec = {
      key = "minecraft";
      user = "game-minecraft";
      uid = 27009;
      gid = 27009;
      home = if useSrv then "/var/lib/game-containers/minecraft" else "/home/game-minecraft";
      gameDir = if useSrv then "/srv/minecraft" else "/home/game-minecraft/minecraft";
      containerName = "neko7-mc";
      hostAddress = "10.77.30.1";
      localAddress = "10.77.30.2";
      tailscaleHostname = "neko7-minecraft";
      autoStart = true;
      udpPorts = [];
      tcpPorts = [25565];
      extraModules = [inputs.nix-minecraft.nixosModules.minecraft-servers];
    } // lib.optionalAttrs useSops {
      # TODO(sops-bootstrap): the encrypted manifest must be committed first.
      # NixOS host decrypts this file, and nspawn mounts it read-only.
      authKeyFile = "/run/host-game-secrets/minecraft-tailscale-authkey";
      hostAuthKeyFile = config.sops.secrets."game-minecraft-tailscale-authkey".path;
    };
    inherit (import ./_internal/container.nix {inherit lib pkgs;}) mkGame;
    mkMinecraftModule = spec: {
      pkgs,
      lib,
      ...
    }: let
      d = layout.mkGameDirectories spec;
    in {
      nixpkgs.overlays = [inputs.nix-minecraft.overlay];

      # TODO(srv-cutover): remove the legacy /home exception once
      # the host has completed the offline copy and enabled game-srv.
      systemd.services.minecraft-server-survival.serviceConfig.ProtectHome =
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
  in {
    config =
      lib.mkIf config.local.features.game-minecraft.enable
      (mkGame spec mkMinecraftModule);
  };
}
