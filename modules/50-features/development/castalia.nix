{inputs, ...}: {
  flake.modules.homeManager.castalia = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.castalia.enable {
      home.packages = [
        inputs.castalia.packages.${pkgs.system}.castalia
      ];
    };
  };
}
