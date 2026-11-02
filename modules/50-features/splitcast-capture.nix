{
  flake.modules.nixos.splitcast-capture = import ./splitcast/_internal/nixos.nix {role = "capture";};
  flake.modules.homeManager.splitcast-capture = import ./splitcast/_internal/home-manager.nix {role = "capture";};
}
