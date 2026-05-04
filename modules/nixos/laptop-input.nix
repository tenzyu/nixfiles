{
  flake.modules.nixos.laptopInput = {
    services.libinput.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "suspend";
  };
}
