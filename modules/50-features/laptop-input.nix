{
  config,
  ...
}: {
  flake.modules.nixos.laptop-input = {config, lib, ...}: {
    config = lib.mkIf config.local.features.laptop-input.enable {
      services.libinput.enable = true;
      services.logind.settings.Login.HandleLidSwitch = "suspend";
    };
  };
}
