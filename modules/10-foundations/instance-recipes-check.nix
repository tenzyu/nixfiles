{...}: {
  perSystem = {pkgs, ...}: {
    checks.instance-recipes = pkgs.runCommand "instance-recipes-check" {
      nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils];
    } ''
      cp ${../../justfile} justfile
      just --list > commands
      for cmd in images instances new update backup delete lab lab-vm lab-stop; do
        grep -E "^[[:space:]]+$cmd([[:space:]]|$)" commands
      done
      # Dry-runs must not contact any runtime or require operator credentials.
      just --dry-run new syncthing fixture 20GiB
      just --dry-run update fixture /tmp/fixture-backup.tar.gz
      just --dry-run delete fixture /tmp/fixture-backup.tar.gz
      mkdir -p mock
      printf '#!%s\necho not-neko7\n' "${pkgs.runtimeShell}" > mock/hostname
      printf '#!%s\nexit 99\n' "${pkgs.runtimeShell}" > mock/sudo
      chmod +x mock/*
      export PATH="$PWD/mock:$PATH"
      for cmd in new update backup delete; do
        case "$cmd" in
          new) set -- syncthing fixture 20GiB ;;
          *) set -- fixture /tmp/fixture-backup.tar.gz ;;
        esac
        if just "$cmd" "$@"; then
          echo "$cmd did not reject execution on the wrong host" >&2
          exit 1
        fi
      done
      touch "$out"
    '';
  };
}
