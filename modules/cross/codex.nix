{moduleWithSystem, ...}: {
  local.cross.definitions.codex.home.module = moduleWithSystem ({inputs', ...}: {
    home.packages = [
      inputs'.llm-agents.packages.codex
    ];
  });
}
