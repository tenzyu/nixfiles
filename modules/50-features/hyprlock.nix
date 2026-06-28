{...}: {
  flake.features.hyprlock.projections.nixos.payload = {...}: {
    programs.hyprlock.enable = true;
  };
}
