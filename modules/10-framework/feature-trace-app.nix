{...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    wrapper = pkgs.writeShellApplication {
      name = "feature-trace";
      runtimeInputs = [pkgs.jq pkgs.gawk];
      text = builtins.readFile ./tools/feature-trace.sh;
    };
  in {
    apps.feature-trace = {
      type = "app";
      program = lib.getExe wrapper;
    };
  };
}
