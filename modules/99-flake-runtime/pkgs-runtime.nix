{inputs, ...}: {
  config.flake.modules.nixos.pkgs-runtime = {
    nixpkgs.overlays = [
      inputs.llm-agents.overlays.default

      (final: prev: {
        unstable = import inputs.nixpkgs-unstable {
          system = prev.stdenv.hostPlatform.system;
          config = prev.config;
        };
      })
    ];
  };
}
