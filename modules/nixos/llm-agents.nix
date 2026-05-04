{inputs, ...}: {
  flake.modules.nixos.llmAgents = {
    nixpkgs.overlays = [
      inputs.llm-agents.overlays.default
    ];
  };
}
