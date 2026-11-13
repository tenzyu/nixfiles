{inputs, ...}: {
  flake.modules.nixos.splitcast-capture = {config, lib, ...}: {
    imports = [inputs.splitcast.nixosModules.default];
    services.splitcast = lib.mkIf config.local.features.splitcast-capture.enable {
      enable = true;
      role = "capture";
    };
  };
  flake.modules.homeManager.splitcast-capture = {config, lib, ...}: {
    imports = [inputs.splitcast.homeManagerModules.default];
    services.splitcast = lib.mkIf config.local.features.splitcast-capture.enable {
      enable = true;
      role = "capture";
      rustCandidate = lib.mkDefault false;
    };
  };
}
