{
  lib,
  pkgs,
  ...
}:
with lib; {
  virtualisation.docker = {
    enable = mkDefault true;
    enableOnBoot = mkDefault true;
    autoPrune = {
      enable = mkDefault true;
      dates = mkDefault "weekly";
    };
  };

  # Reverse proxy with Traefik
  services.traefik = {
    enable = mkDefault true;
    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
        };
        websecure = {
          address = ":443";
        };
      };
      providers = {
        docker = {
          endpoint = "unix:///var/run/docker.sock";
          exposedByDefault = false;
        };
        file = {
          directory = "/etc/traefik/config";
          watch = true;
        };
      };
    };
  };

  # Server packages
  environment.systemPackages = with pkgs; [
    # Container tools
    docker-compose
    kubectl
    helm
    k9s
    kompose

    # Monitoring tools
    htop
    iotop
    iftop
    nload

    # Network tools
    nmap
    tcpdump
    wireshark
  ];

  # Security
  security = {
    acme = {
      acceptTerms = mkDefault true;
      defaults.email = mkDefault "admin@example.com";
    };
  };

  # Networking
  networking = {
    firewall = {
      enable = mkDefault true;
      allowedTCPPorts = [80 443];
    };
  };
}
