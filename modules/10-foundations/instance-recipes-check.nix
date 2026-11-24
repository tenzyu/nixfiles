{...}: {
  perSystem = {pkgs, ...}: {
    checks.instance-recipes = pkgs.runCommand "instance-recipes-check" {
      nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils];
    } ''
      cp ${../../justfile} justfile
      chmod u+w justfile
      # In the Nix build sandbox /usr/bin/env need not exist.
      substituteInPlace justfile --replace-fail '#!/usr/bin/env bash' '#!${pkgs.runtimeShell}'
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
      printf '#!%s\ntouch "$PWD/runtime-called"\nexit 99\n' "${pkgs.runtimeShell}" > mock/sudo
      cp mock/sudo mock/nix
      chmod +x mock/*
      export PATH="$PWD/mock:$PATH"
      for cmd in new update backup delete; do
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
