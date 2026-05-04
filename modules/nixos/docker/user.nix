{config, ...}: {
  flake.modules.nixos.dockerUser = {
    users.users.${config.me.username}.extraGroups = ["docker"];
  };
}
