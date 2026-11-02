{
  flake.modules.nixos.splitcast-production = import ./splitcast/_internal/nixos.nix {role = "production";};
  flake.modules.homeManager.splitcast-production = import ./splitcast/_internal/home-manager.nix {role = "production";};
}
