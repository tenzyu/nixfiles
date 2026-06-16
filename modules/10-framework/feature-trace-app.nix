{...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    wrapper = pkgs.writeShellApplication {
      name = "feature-trace";
      runtimeInputs = [
        pkgs.gitMinimal
        pkgs.gawk
        pkgs.jq
        pkgs.nix
      ];
      # jq filters intentionally use jq variables/interpolation inside single-quoted
      # shell strings. ShellCheck SC2016 is correct for shell interpolation, but false
      # positive for these jq programs.
      excludeShellChecks = ["SC2016"];
      text = builtins.readFile ./tools/feature-trace.sh;
    };
  in {
    apps.feature-trace = {
      type = "app";
      program = lib.getExe wrapper;
    };
  };
}
