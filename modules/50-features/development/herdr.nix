{...}: {
  flake.modules.homeManager.herdr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # Herdr 0.9.5 prefers wl-copy on local Wayland. Jay restricts data-control,
    # so use Herdr's existing OSC 52 writer in a native Jay session instead.
    # The focused outer terminal owns the selection; no privileged helper,
    # clipboard-read permission, or richclip history injection is needed.
    herdr =
      if config.local.features.jay.enable
      then
        pkgs.llm-agents.herdr.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace src/selection.rs \
                --replace-fail 'let prefer_osc52 = should_prefer_osc52();' \
                  'let prefer_osc52 = should_prefer_osc52() || (std::env::var_os("XDG_CURRENT_DESKTOP").as_deref() == Some(OsStr::new("jay")) && std::env::var_os("WAYLAND_DISPLAY").is_some());'
            '';
        })
      else pkgs.llm-agents.herdr;
  in {
    config = lib.mkIf config.local.features.herdr.enable {
      home.packages = [herdr];
    };
  };
}
