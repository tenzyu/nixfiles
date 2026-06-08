{
  flake.modules.nixos.stubLd = {
    environment.stub-ld.enable = true;
    programs.nix-ld.enable = true;
  };
}
