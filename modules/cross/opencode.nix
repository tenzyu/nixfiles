{moduleWithSystem, ...}: {
  local.cross.definitions.opencode.home.module = moduleWithSystem ({inputs', ...}: {
    home.packages = [
      inputs'.llm-agents.packages.opencode
    ];
  });
}
