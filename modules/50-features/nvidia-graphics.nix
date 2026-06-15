{
  flake.effects.nvidia-graphics = {
    system = {
      # nvidia-settings is an `unfreeRedistributable` binary built as part
      # of the nvidia-x11 driver graph in nixpkgs-26.05, so both must be
      # permitted by allowUnfreePredicate.
      collect.pkgs.unfreePackages = [
        "nvidia-x11"
        "nvidia-settings"
      ];
    };
  };

  flake.modules.nixos.nvidia-graphics = {pkgs, ...}: {
    hardware.graphics.enable = true;
    services.xserver.videoDrivers = ["nvidia"];
    hardware.nvidia.open = true;
  };
}
