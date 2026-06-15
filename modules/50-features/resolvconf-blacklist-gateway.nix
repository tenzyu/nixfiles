{
  flake.modules.nixos.resolvconf-blacklist-gateway = {
    networking.resolvconf.extraConfig = ''
      name_server_blacklist=172.16.0.1
    '';
  };
}
