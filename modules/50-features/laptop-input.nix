{
  flake.modules.nixos.laptop-input = {
    services.libinput.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "suspend";
  };
}
