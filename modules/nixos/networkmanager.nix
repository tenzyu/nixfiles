{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.networkManager = {
    networking.networkmanager.enable = true;
    # TODO: cross か factory か、なんかしら user boundry をうまく表現して member を提供するか、user aspect をうまく使って groups を管理する.
    users.users.${config.me.username}.extraGroups = lib.mkAfter ["networkmanager"];
    networking.nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
      "8.8.4.4"
    ];
  };
}
