{
  config,
  lib,
  ...
}: {
  flake.modules.nixos.time = {
    time.timeZone = lib.mkDefault config.me.timeZone;
  };
}
