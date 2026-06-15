{
  # See features/codex.nix for why there is no NixOS aspect.
  flake.modules.homeManager.rtk = {pkgs, ...}: {home.packages = [pkgs.llm-agents.rtk];};
}
