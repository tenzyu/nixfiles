{...}: {
  flake.modules.homeManager.packagesCommon = {pkgs, ...}: {
    home.packages = with pkgs; [
      bat
      bitwarden-cli
      dust
      eza
      fd
      glow
      pay-respects
      ripgrep
      tealdeer
      xclip
      xdg-ninja
    ];
  };
}
