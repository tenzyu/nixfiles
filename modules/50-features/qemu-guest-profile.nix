{
  inputs,
  lib,
  ...
}: {
  flake.modules.nixos.qemu-guest-profile = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/profiles/qemu-guest.nix")
    ];
  };
}
