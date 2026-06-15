{
  flake.modules.nixos.intel-graphics = {
    lib,
    pkgs,
    ...
  }: {
    hardware = {
      enableRedistributableFirmware = lib.mkDefault true;

      cpu.intel.updateMicrocode = lib.mkDefault true;

      graphics = {
        enable = true;
        enable32Bit = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
        ];
        extraPackages32 = with pkgs.pkgsi686Linux; [
          intel-vaapi-driver
        ];
      };
    };

    environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";
  };
}
