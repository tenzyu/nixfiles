{
  callPackage,
  python3,
  rsync,
  runCommand,
  writeShellScript,
}: let
  safety = callPackage ../safety/python {};
  source = runCommand "home-layout-python" {} ''
    mkdir -p "$out"
    cp ${./migrate.py} "$out/migrate.py"
    cp ${./move_boundary.py} "$out/move_boundary.py"
    ln -s ${safety}/safety_operations.py "$out/safety_operations.py"
  '';
in {
  inherit source;
  launcher = manifest:
    writeShellScript "home-layout-migrate" ''
      exec ${python3}/bin/python3 -E -s -B ${source}/migrate.py "$@" --manifest ${manifest} \
        --rsync ${rsync}/bin/rsync --launcher "$0"
    '';
}
