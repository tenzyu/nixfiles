{
  inputs,
  pkgs,
  config,
  ...
}: let
  pkgsUnstable = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit (config.nixpkgs) config;
  };
in {
  imports = [inputs.home-manager.nixosModules.home-manager];
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {inherit inputs pkgsUnstable;};

  home-manager.users = {
    tenzyu = import ./tenzyu.nix;
  };
}
