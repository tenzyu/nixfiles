{...}: {
  flake.features.resolvconf-blacklist-gateway.projections.nixos.payload = {...}: {
    networking.resolvconf.extraConfig = ''
      name_server_blacklist=172.16.0.1
    '';
  };
}
