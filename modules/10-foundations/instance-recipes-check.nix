{...}: {
  perSystem = {pkgs, ...}: {
    checks.instance-recipes = pkgs.runCommand "instance-recipes-check" {
      nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils];
    } ''
      cp ${../../justfile} justfile
      mkdir -p tools
      cp ${../../tools/instance-ops.sh} tools/instance-ops.sh
      bash -n tools/instance-ops.sh
      just --list > commands
      for cmd in images instances status new update backup lab lab-vm lab-stop; do
        grep -E "^[[:space:]]+$cmd([[:space:]]|$)" commands
      done
      # Dry-runs must not contact any runtime or require operator credentials.
      just --dry-run new syncthing fixture 20GiB
      just --dry-run update fixture /tmp/fixture-backup.tar.gz
      if just --list | grep -E "^[[:space:]]+delete([[:space:]]|$)"; then exit 1; fi
      mkdir -p mock
      printf '#!%s\necho not-neko7\n' "${pkgs.runtimeShell}" > mock/hostname
      printf '#!%s\ntouch "$PWD/runtime-called"\nexit 99\n' "${pkgs.runtimeShell}" > mock/sudo
      cp mock/sudo mock/nix
      chmod +x mock/*
      export PATH="$PWD/mock:$PATH"
      for cmd in new update backup; do
        case "$cmd" in
          new) set -- syncthing fixture 20GiB ;;
          *) set -- fixture /tmp/fixture-backup.tar.gz ;;
        esac
        status=0
        just "$cmd" "$@" || status=$?
        case "$status" in 1|2) ;; *) echo "Unexpected guard status $status" >&2; exit 1 ;; esac
        test ! -e runtime-called
      done
      touch "$out"
    '';
  };
}
