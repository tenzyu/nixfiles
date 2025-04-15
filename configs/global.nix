{
  lib,
  name,
  outputs,
  ...
}:
with lib; {
  nix.settings.extra-experimental-features = mkDefault ["nix-command" "flakes"];
  nixpkgs.config.allowUnfree = mkDefault true;

  networking.hostName = mkDefault name;
}
