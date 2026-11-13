{inputs, ...}: {
  flake.modules.nixos.splitcast-production = {config, lib, ...}: {
    imports = [inputs.splitcast.nixosModules.default];
    services.splitcast = lib.mkIf config.local.features.splitcast-production.enable {
      enable = true;
      role = "production";
    };
  };
  flake.modules.homeManager.splitcast-production = {config, lib, ...}: {
    imports = [inputs.splitcast.homeManagerModules.default];
    services.splitcast = lib.mkIf config.local.features.splitcast-production.enable {
      enable = true;
      role = "production";
      rustCandidate = lib.mkDefault false;
    };
  };
}
