{...}: {
  flake.features.open-tablet-driver.projections.nixos.payload = {...}: {
    hardware.opentabletdriver.enable = true;
  };
}
