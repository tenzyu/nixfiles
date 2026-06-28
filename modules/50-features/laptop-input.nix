{...}: {
  flake.features.laptop-input.projections.nixos.payload = {...}: {
    services.libinput.enable = true;
    services.logind.settings.Login.HandleLidSwitch = "suspend";
  };
}
