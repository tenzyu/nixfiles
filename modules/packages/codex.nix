{
  cross,
  inputs,
  ...
}:
cross.module {
  name = "codex";

  home.packages = pkgs: [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex
  ];
}
