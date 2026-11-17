{
  flake.local.featurePolicies.nvidia-graphics.unfree = [
    "nvidia-x11"
    "nvidia-settings"
  ];

  flake.modules.nixos.nvidia-graphics = {
    config,
    lib,
    ...
  }: {
    config = lib.mkIf config.local.features.nvidia-graphics.enable {
      # nvidia-settings is an `unfreeRedistributable` binary built as part
      # of the nvidia-x11 driver graph in nixpkgs-26.05, so both must be
      # permitted by allowUnfreePredicate.
      hardware.graphics.enable = true;
      services.xserver.videoDrivers = ["nvidia"];
      hardware.nvidia.open = true;
    };
  };
}
