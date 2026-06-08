{moduleWithSystem, ...}: {
  local.cross.definitions.rtk.home.module = moduleWithSystem ({inputs', ...}: {
    home.packages = [
      inputs'.llm-agents.packages.rtk
    ];
  });
}
