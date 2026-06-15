{
  # See features/codex.nix for why there is no NixOS aspect.
  flake.modules.homeManager.opencode = {pkgs, ...}: {
    home.packages = [pkgs.llm-agents.opencode];
  };
}
