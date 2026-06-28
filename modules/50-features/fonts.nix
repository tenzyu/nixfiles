{lib, ...}: {
  flake.features.fonts.projections.nixos.payload = {
    config,
    pkgs,
    ...
  }: {
    fonts = {
      enableDefaultPackages = lib.mkDefault true;
      packages = with pkgs; [
        fira-code
        fira-code-symbols
        nerd-fonts.fira-code
        font-awesome
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];
    };
  };
}
