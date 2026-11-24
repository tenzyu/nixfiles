{
  configurations.nixos.neko7.module = {config, lib, ...}: let
    home = config.home-manager.users.tenzyu;
    profiles = "${home.xdg.stateHome}/nix/profiles";
  in {
    # Admission only, not a deployment script. An unseeded profile must
    # never silently replace the working user service during host activation.
    system.preSwitchChecks.neko7-workload-profiles = ''
      ${lib.optionalString home.local.features.t3code-neko7.enable ''
        if ! test -L ${lib.escapeShellArg "${profiles}/t3-runtime"} ||
           ! test -x ${lib.escapeShellArg "${profiles}/t3-runtime/bin/t3"} ||
           ! test -x ${lib.escapeShellArg "${profiles}/t3-runtime/bin/codex"}; then
          echo "Seed the T3 runtime profile as the service user before activation." >&2
          exit 1
        fi
      ''}
      ${lib.optionalString home.local.features.splitcast-production-profile.enable ''
        if ! test -L ${lib.escapeShellArg "${profiles}/splitcast-production"} ||
           ! test -r ${lib.escapeShellArg "${profiles}/splitcast-production/share/systemd/user/splitcast-production.service"} ||
           ! test -r ${lib.escapeShellArg "${profiles}/splitcast-production/share/splitcast/production.toml"}; then
          echo "Seed the gated SplitCast production profile before activation." >&2
          exit 1
        fi
      ''}
      true
    '';
  };
}
