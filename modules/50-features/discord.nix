{
  flake.effects.discord = {
    system = {
      collect.pkgs.unfreePackages = ["discord"];
    };
  };

  flake.modules.homeManager.discord = {pkgs, ...}: {home.packages = [pkgs.unstable.discord];};
}
