{
  lib,
  coreutils,
  gnutar,
  gzip,
  nixos-container,
  glibc,
  python3,
  systemd,
  util-linux,
  writeShellApplication,
  callPackage,
  policy,
  # Build-time substitutions for the isolated check. The host supplies only policy.
  fixture ? null,
}: let
  inherit (lib) escapeShellArg getExe;
  safety = if fixture == null then callPackage ../../../../../assets/safety/shell {} else fixture.safety;
  fixed = name: value: "readonly ${name}=${escapeShellArg (toString value)}";
  bindings = values: lib.concatStringsSep "\n" (lib.mapAttrsToList fixed values) + "\n";
  archiveIds =
    if fixture != null && fixture.mockIdentity
    then ''
      archiveGid=$(id -g)
      readonly archiveUid=$EUID archiveGid
    ''
    else bindings {inherit (policy) archiveUid archiveGid;};
  writer = writeShellApplication {
    name = "minecraft-archive-writer";
    runtimeInputs = [coreutils gnutar gzip];
    inheritPath = false;
    text = archiveIds + bindings {
      inherit (policy) sourceDir backupsDir;
      inherit safety;
      filesystem = "${python3}/bin/python3";
      checks = "${./archive-checks.py}";
      boundary = if fixture == null then "/" else fixture.boundary;
      producer = if fixture == null then "${gnutar}/bin/tar" else fixture.producer;
      producer_gzip = "${gzip}/bin/gzip";
    } + builtins.readFile ./writer.sh;
  };
in
  writeShellApplication {
    name = "minecraft-operator";
    runtimeInputs = [coreutils glibc.bin systemd util-linux];
    inheritPath = false;
    text = archiveIds + (if fixture == null then ''
      readonly host_uid=0
      lock_gid=$(getent group wheel | cut -d: -f3)
      readonly lock_gid
    '' else ''
      lock_gid=$(id -g)
      readonly host_uid=$EUID lock_gid
    '') + bindings {
      inherit (policy) lockPath containerName containerUnit guestUnit backupsDir;
      writer = getExe writer;
      container = if fixture == null then getExe nixos-container else fixture.container;
      host_systemctl = if fixture == null then "${systemd}/bin/systemctl" else fixture.hostSystemctl;
      guest_systemctl = "/run/current-system/sw/bin/systemctl";
      lock_boundary = if fixture == null then "/" else fixture.boundary;
      drop_privileges = if fixture == null then "${util-linux}/bin/setpriv" else fixture.setpriv;
      clock = if fixture == null then "${coreutils}/bin/date" else fixture.date;
    } + (if fixture != null && fixture.mockIdentity then ''
      lock_fs=$(stat -fLc '%T' -- "$lock_boundary")
      readonly lock_fs
    '' else ''
      readonly lock_fs=tmpfs
    '') + builtins.readFile ./operator.sh;
  }
