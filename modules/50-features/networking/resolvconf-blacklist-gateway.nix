{config, ...}: {
  flake.modules.nixos.resolvconf-blacklist-gateway = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.resolvconf-blacklist-gateway.enable {
      networking.resolvconf.extraConfig = ''
        name_server_blacklist=172.16.0.1
      '';
    };
  };
}
