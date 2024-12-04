{
  inputs,
  system,
  ...
}: {
  programs.hyprland = {
    enable = true;
  };
  programs.hyprlock = {
    enable = true;
  };
}
