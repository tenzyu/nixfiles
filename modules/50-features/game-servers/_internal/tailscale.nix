{
  lib,
  pkgs,
}: let
  mkTailscaleNodeModule = spec: {
    lib,
    pkgs,
    ...
  }: {
    networking.hostName = spec.tailscaleHostname;

    networking.useHostResolvConf = lib.mkForce false;
    networking.nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];

    # The upstream NixOS module owns authentication and service lifecycle.
    # The key remains an existing runtime file; never materialize its value in
    # an evaluated Nix string or in /nix/store.
    services.tailscale = {
      enable = true;
      authKeyFile = spec.authKeyFile or "${spec.home}/secrets/tailscale-authkey";
      extraUpFlags = [
        "--hostname=${spec.tailscaleHostname}"
        "--accept-dns=false"
      ];
      extraSetFlags = ["--netfilter-mode=nodivert"];
    };

    # Existing installations may not yet have a Tailscale auth key. Stay
    # inert rather than failing the host boot; provision separately.
    systemd.services.tailscaled-autoconnect = {
      after = ["network-online.target"];
      wants = ["network-online.target"];
      unitConfig.ConditionPathExists =
        spec.authKeyFile or "${spec.home}/secrets/tailscale-authkey";
    };

    networking.firewall.enable = true;
    networking.firewall.interfaces.tailscale0.allowedUDPPorts = spec.udpPorts;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = spec.tcpPorts;

    environment.systemPackages = with pkgs; [
      bind
      curl
      jq
      netcat
      tailscale
    ];
  };
in
  mkTailscaleNodeModule
