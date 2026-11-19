{
  pkgs,
  root ? "/build/minecraft-fixture",
  mockIdentity ? true,
}: let
  policy = {
    lockPath = "${root}/run/minecraft.lock";
    containerName = "fixture-mc";
    containerUnit = "container@fixture-mc.service";
    guestUnit = "minecraft-server-survival.service";
    archiveUid = 27009;
    archiveGid = 27009;
    sourceDir = "${root}/data/survival";
    backupsDir = "${root}/data/backups";
  };
  mock = role: program: pkgs.writeShellScript "minecraft-fixture-${role}" ''
    exec ${pkgs.python3}/bin/python3 -I ${./test-mocks.py} ${role} ${pkgs.lib.escapeShellArg root} ${pkgs.lib.escapeShellArg program} "$@"
  '';
  native = mock "native" "${../../../../../assets/safety/shell/native.py}";
  nativeScript = pkgs.writeText "minecraft-test-native.py" ''
    import os, sys
    os.execv("${native}", ["${native}", *sys.argv[1:]])
  '';
  safety = pkgs.replaceVars ../../../../../assets/safety/shell/operations.sh {
    inherit (pkgs) coreutils python3 util-linux;
    native = nativeScript;
  };
  operator = pkgs.callPackage ./. {
    inherit policy;
    fixture = {
      inherit mockIdentity safety;
      boundary = root;
      container = mock "container" "";
      hostSystemctl = mock "host" "";
      producer = mock "producer" "${pkgs.gnutar}/bin/tar";
      setpriv = if mockIdentity then mock "setpriv" "" else "${pkgs.util-linux}/bin/setpriv";
      date = pkgs.writeShellScript "minecraft-fixture-date" "echo 20261119-113355";
    };
  };
  runner = pkgs.writeShellScript "minecraft-fixture-run" ''
    exec ${pkgs.python3}/bin/python3 -I ${./test-backup.py} \
      ${pkgs.lib.getExe operator} ${pkgs.lib.escapeShellArg root} \
      ${if mockIdentity then "mock" else "real"} ${pkgs.gnutar}/bin/tar
  '';
in {
  inherit operator runner;
}
