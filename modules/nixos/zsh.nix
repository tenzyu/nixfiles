{lib, ...}: {
  flake.modules.nixos.zsh = {pkgs, ...}: {
    programs.zsh.enable = lib.mkDefault true;
    environment.pathsToLink = lib.mkDefault ["/share/zsh"];
    environment.shells = lib.mkDefault [pkgs.zsh];
    environment.enableAllTerminfo = lib.mkDefault true;
  };
}
