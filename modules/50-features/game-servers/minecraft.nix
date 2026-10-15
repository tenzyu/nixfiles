{ inputs, ... }: {
  flake.modules.nixos.game-server-containers = {config, lib, pkgs, ...}: let
    spec = {
      key = "minecraft";
      user = "game-minecraft";
      uid = 27009;
      gid = 27009;
      home = "/home/game-minecraft";
      containerName = "neko7-minecraft";
      hostAddress = "10.77.30.1";
      localAddress = "10.77.30.2";
      tailscaleHostname = "neko7-minecraft";
      autoStart = true;
      udpPorts = [];
      tcpPorts = [25565];
      extraModules = [ inputs.nix-minecraft.nixosModules.minecraft-servers ];
    };
    inherit (import ./_internal/container.nix { inherit lib pkgs; }) mkGame;
    mkMinecraftModule = spec: {pkgs, ...}: {
      nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
      users.users.minecraft.uid = spec.uid;
      users.groups.minecraft.gid = spec.gid;
      environment.systemPackages = [pkgs.tmux];
      services.minecraft-servers = {
        enable = true;
        eula = true; # Only if you have accepted Mojang's EULA.
        dataDir = "${spec.home}/minecraft";
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
            # "white-list" = true;
            # "enforce-whitelist" = true;
            "max-players" = 8;
            # "view-distance" = 16;
            # "simulation-distance" = 6;
            "enable-rcon" = false;
          };
        };
      };
    };
  in {
    config = lib.mkIf config.local.features.game-server-containers.enable
      (mkGame spec mkMinecraftModule);
  };
}
