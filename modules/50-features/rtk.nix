{inputs, ...}: let
  settings.hooks.exclude_commands = [
    "biome"
    "bunx biome"
    "bun x biome"
    "npm run lint"
    "pnpm lint"
    "pnpm run lint"
    "yarn lint"
    "bun lint"
    "bun run lint"
  ];
in {
  flake.modules.homeManager.rtk = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.rtk.enable {
      home.packages = [pkgs.llm-agents.rtk];
      xdg.configFile."rtk/config.toml".source = (pkgs.formats.toml {}).generate "rtk.toml" settings;
    };
  };

  perSystem = {pkgs, ...}: {
    checks.rtk-rewrites =
      pkgs.runCommand "check-rtk-rewrites" {
        nativeBuildInputs = [pkgs.python3 inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.rtk];
      } ''
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export CLAUDE_CONFIG_DIR="$TMPDIR/claude"
        mkdir -p "$XDG_CONFIG_HOME/rtk"
        cp ${(pkgs.formats.toml {}).generate "rtk.toml" settings} "$XDG_CONFIG_HOME/rtk/config.toml"
        python3 ${../../assets/rtk/test_rewrites.py}
        touch "$out"
      '';
  };
}
