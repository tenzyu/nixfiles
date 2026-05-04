{
  flake.modules.homeManager.firefox = {pkgs, ...}: {
    programs.firefox = {
      enable = true;
      package = pkgs.unstable.firefox;
      profiles.default.extensions.force = true;
    };
  };
}
