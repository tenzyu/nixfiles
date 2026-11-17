# Host package overlays live with flake fundamentals, not in the
# framework's feature/user projection machinery.
{inputs, ...}: {
  flake.lib.nixfilesOverlays = [
    (final: prev: {
      # Use the upstream package outputs and their pinned signed-cache toolchain.
      llm-agents = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system};
    })
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = prev.stdenv.hostPlatform.system;
        config = prev.config;
      };
    })
  ];
}
