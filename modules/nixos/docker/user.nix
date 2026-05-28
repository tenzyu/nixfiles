{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.dockerUser = {
    users.users.${config.me.username}.extraGroups = lib.mkAfter ["docker"];
  };
}
