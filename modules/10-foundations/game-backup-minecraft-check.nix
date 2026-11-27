{
  perSystem = {pkgs, ...}: let
    fixture = import ../50-features/game-servers/_internal/minecraft-backup/test.nix {inherit pkgs;};
  in {
    validationChecks.game-backup-minecraft =
      pkgs.runCommand "game-backup-minecraft-tests" {
        nativeBuildInputs = [pkgs.coreutils pkgs.python3];
      } ''
        python3 ${../50-features/game-servers/_internal/minecraft-backup}/test-archive-checks.py
        timeout 70s ${fixture.runner}
        touch "$out"
      '';
  };
}
