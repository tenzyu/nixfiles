{inputs, ...}: {
  flake.modules.homeManager.onair = {config, lib, pkgs, ...}: {
    config = lib.mkIf config.local.features.onair.enable {
      home.packages = [
        inputs.onair.packages.${pkgs.system}.default
      ];
    };
  };
}
