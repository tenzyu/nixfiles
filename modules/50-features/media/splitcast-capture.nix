{inputs, ...}: {
  flake.modules.nixos.splitcast-capture = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.splitcast.nixosModules.default];
    config = lib.mkIf config.local.features.splitcast-capture.enable {
      services.splitcast = {
        enable = true;
        role = "capture";
      };
      nix.settings = import ./_internal/cache.nix;
    };
  };
  flake.modules.homeManager.splitcast-capture = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.splitcast.homeManagerModules.default];
    services.splitcast = lib.mkIf config.local.features.splitcast-capture.enable {
      enable = true;
      role = "capture";
      rustCandidate = lib.mkDefault false;
    };
  };
}
