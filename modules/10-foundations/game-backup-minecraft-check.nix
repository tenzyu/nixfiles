{
  perSystem = {pkgs, ...}: let
    fixture = import ../50-features/game-servers/_internal/minecraft-backup/test.nix {inherit pkgs;};
  in {
    checks.game-backup-minecraft =
      pkgs.runCommand "game-backup-minecraft-tests" {
        nativeBuildInputs = [pkgs.coreutils];
      } ''
        timeout 70s ${fixture.runner}
        touch "$out"
      '';
  };
}
