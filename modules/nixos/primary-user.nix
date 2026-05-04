{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.primaryUser = {pkgs, ...}: {
    users.users.${config.me.username} = {
      isNormalUser = lib.mkDefault true;
      shell = pkgs.zsh;
      extraGroups = lib.mkDefault ["wheel"];
    };
  };
}
