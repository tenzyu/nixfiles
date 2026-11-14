{
  flake.modules.homeManager.opencode-direnv = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.local.features.opencode-direnv.enable {
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
      xdg.configFile."opencode/plugins/direnv.ts".source = pkgs.replaceVars ../../assets/opencode/direnv.ts {
        direnv = lib.getExe pkgs.direnv;
      };
    };
  };

  perSystem = {pkgs, ...}: {
    checks.opencode-direnv =
      pkgs.runCommand "check-opencode-direnv" {
        nativeBuildInputs = [pkgs.bun pkgs.direnv];
      } ''
        cp ${../../assets/opencode/direnv.ts} direnv.ts
        cp ${../../assets/opencode/direnv.test.ts} direnv.test.ts
        bun test direnv.test.ts
        touch "$out"
      '';
  };
}
