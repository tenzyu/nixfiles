{...}: {
  perSystem = {pkgs, ...}: {
    checks.instance-recipes = pkgs.runCommand "instance-recipes-check" {
      nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils];
    } ''
      cp ${../../justfile} justfile
      just --list > commands
      for cmd in images instances status lab lab-stop; do
        grep -E "^[[:space:]]+$cmd([[:space:]]|$)" commands
      done
      for cmd in new update backup delete lab-vm; do
        if grep -E "^[[:space:]]+$cmd([[:space:]]|$)" commands; then exit 1; fi
      done
      just --dry-run lab fixture
      just --dry-run lab-stop fixture
      touch "$out"
    '';
  };
}
