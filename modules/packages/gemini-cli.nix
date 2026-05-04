{
  cross,
  inputs,
  ...
}:
cross.module {
  name = "gemini-cli";

  home.packages = pkgs: [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli
  ];
}
