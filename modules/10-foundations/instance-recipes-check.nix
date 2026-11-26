{...}: {
  perSystem = {pkgs, ...}: {
    checks.instance-recipes = pkgs.runCommand "instance-recipes-check" {
      nativeBuildInputs = [pkgs.just pkgs.bash pkgs.coreutils pkgs.jq];
    } ''
      cp ${../../justfile} justfile
      mkdir -p tools
      cp ${../../tools/instance-ops.sh} tools/instance-ops.sh
      cp ${../../tools/vm-resources.sh} tools/vm-resources.sh
      bash -n tools/instance-ops.sh
      bash -n tools/vm-resources.sh
      bash ${../50-features/development/_internal/execution-discovery-test.sh} ${../50-features/development/_internal/execution-discovery.sh}
      # Native resource response shapes, without contacting a runtime.
      bash -euo pipefail -c '
        source tools/vm-resources.sh
        mock_incus() {
          case "$*" in
            "query lab:/1.0/resources?project=lab") echo "{\"cpu\":{\"total\":16},\"memory\":{\"total\":34359738368}}" ;;
            "query lab:/1.0/storage-pools/default/resources?project=lab") echo "{\"space\":{\"total\":1000000000000}}" ;;
            *) return 42 ;;
          esac
        }
        vm_resources lab lab mock_incus
        test "''${vm_args[*]}" = "-c limits.cpu=16 -c limits.memory=32768MiB -d root,size=1000000000000B"
        bad_incus() { echo "{}"; }
        if vm_resources lab lab bad_incus; then exit 1; fi
        denied_incus() { return 42; }
        if vm_resources lab lab denied_incus; then exit 1; fi
      '
      just --list > commands
      for cmd in images instances status new update backup lab lab-vm lab-stop; do
        grep -E "^[[:space:]]+$cmd([[:space:]]|$)" commands
      done
      # Dry-runs must not contact any runtime or require operator credentials.
      just --dry-run new syncthing fixture
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
          new) set -- syncthing fixture ;;
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
