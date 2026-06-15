{
  flake.modules.nixos.stub-ld = {
    environment.stub-ld.enable = true;
    programs.nix-ld.enable = true;
  };
}
