{
  inputs,
  system,
  ...
}: {
  programs.hyprland = {
    enable = true;
    xwayland.enable = false;
  };
  programs.hyprlock = {
    enable = true;
  };
}
