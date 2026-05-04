{moduleWithSystem, ...}: {
  local.cross.definitions.gemini-cli.home.module = moduleWithSystem ({inputs', ...}: {
    home.packages = [
      inputs'.llm-agents.packages.gemini-cli
    ];
  });
}
