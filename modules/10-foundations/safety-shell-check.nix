{
  perSystem = {pkgs, ...}: let
    library = pkgs.callPackage ../../assets/safety/shell {};
    fixtures = ../../assets/safety/shell/test-operations.sh;
    native = ../../assets/safety/shell/native.py;
  in {
    checks.safety-shell =
      pkgs.runCommand "safety-shell-tests" {
        nativeBuildInputs = [pkgs.coreutils pkgs.python3 pkgs.shellcheck pkgs.util-linux];
      } ''
        ln -s ${library} operations.sh
        shellcheck --external-sources --source-path . --shell=bash ${library} ${fixtures}
        timeout 45s ${pkgs.bash}/bin/bash ${fixtures} ${library} ${native}
        touch "$out"
      '';
  };
}
