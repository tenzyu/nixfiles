{inputs, ...}: {
  local.cross.definitions.codex.home.packages = pkgs: [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
  ];
}
