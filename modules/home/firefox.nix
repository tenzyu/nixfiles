{
  flake.modules.homeManager.firefox = {pkgs, ...}: {
    local.pkgs.useUnstable = true;

    programs.firefox = {
      enable = true;
      package = pkgs.unstable.firefox;
      profiles.default.extensions.force = true;
    };
  };
}
