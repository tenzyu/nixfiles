{
  flake.effects.prismlauncher = {
    system = {
      collect.pkgs.unfreePackages = [ "prismlauncher" ];
    };
  };

  flake.modules.homeManager.prismlauncher = { pkgs, ... }: {
    home.packages = [ (pkgs.unstable.prismlauncher.override { jdks = [ pkgs.unstable.jdk21 ]; }) ];
  };
}
