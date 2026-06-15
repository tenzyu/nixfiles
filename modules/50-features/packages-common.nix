{...}: {
  flake.modules.homeManager.packages-common = {pkgs, ...}: {
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
