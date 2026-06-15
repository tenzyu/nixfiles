{
  flake.effects.obsidian = {
    system = {
      collect.pkgs.unfreePackages = [ "obsidian" ];
    };
  };

  flake.modules.homeManager.obsidian = { pkgs, ... }: { home.packages = [ pkgs.obsidian ]; };
}
