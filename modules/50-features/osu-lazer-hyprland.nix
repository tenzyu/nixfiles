{
  # Hyprland 0.57.2 regression isolation (2026-11-12):
  # Do not force fullscreen_state on window creation: osu!/SDL can request it
  # itself, and the Win+F binding handles compositor/client state explicitly.
  # Do not set immediate=true: this is a tearing permission, not a requirement
  # for direct scanout. render.direct_scanout=1 remains configured separately.
  # Retain the module name so existing module references do not break.
  flake.modules.homeManager.osu-lazer-hyprland = _: {};
}
