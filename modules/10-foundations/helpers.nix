{lib, ...}: let
  features = import ../../lib/features.nix {inherit lib;};
  users = import ../../lib/users.nix {inherit lib features;};
in {
  # Preserve the exported flake.lib.helpers and specialArgs.helpers API.
  config.flake.lib.helpers = features // users // {
    composition = import ../../lib/composition.nix {inherit lib;};
  };
}
