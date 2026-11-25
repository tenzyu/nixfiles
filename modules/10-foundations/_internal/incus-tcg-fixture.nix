# Only imported by the explicitly named *-tcg machine tests.
# Incus 7.6 generates [machine] accel="kvm" and a host-dependent -cpu.
# Adapt only those launch parameters on the disposable test host.
# The ordinary KVM checks do not import this module.
{lib, pkgs, ...}: let
  qemu = pkgs.writeShellScriptBin "qemu-system-x86_64" ''
    set -euo pipefail
    args=("$@")
    config=""
    instance=""
    cpu=-1
    for ((i=0; i<$#; i++)); do
      case "''${args[i]}" in
        -readconfig) config="''${args[i+1]}" ;;
        -cpu) cpu=$((i+1)) ;;
        -name) instance="''${args[i+1]}" ;;
      esac
    done
    # Preserve upstream feature discovery; only an instance launch
    # has both a generated configuration and a name.
    if [[ -n "$config" && -n "$instance" ]]; then
      [[ "$config" == /* && -f "$config" && $cpu -ge 0 ]] || exit 1
      test "$(${pkgs.gnugrep}/bin/grep -Ec '^[[:space:]]*accel[[:space:]]*=[[:space:]]*"kvm"[[:space:]]*$' "$config")" = 1
      ${pkgs.gnused}/bin/sed -i -E 's/^([[:space:]]*accel[[:space:]]*=[[:space:]]*)"kvm"([[:space:]]*)$/\1"tcg"\2/' "$config"
      ${pkgs.gnugrep}/bin/grep -Eq '^[[:space:]]*accel[[:space:]]*=[[:space:]]*"tcg"[[:space:]]*$' "$config"
      args[cpu]=max
      printf '%s\n' "$instance" >> /run/incus-ci-tcg-launches
    fi
    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 "''${args[@]}"
  '';
in {
  systemd.services.incus.path = lib.mkBefore [qemu];
}
