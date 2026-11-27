{
  perSystem = {
    lib,
    pkgs,
    ...
  }: {
    validationChecks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      safety-python = pkgs.runCommand "check-safety-python" {
        nativeBuildInputs = [pkgs.python3];
        SAFETY_TEST_BASH = "${pkgs.bash}/bin/bash";
        SAFETY_TEST_SHELL = pkgs.callPackage ../../assets/safety/shell {};
        PYTHONPATH = pkgs.callPackage ../../assets/safety/python {};
        PYTHONDONTWRITEBYTECODE = "1";
      } ''
        python3 ${../../assets/safety/python/test_operations.py} -v
        touch "$out"
      '';
    };
  };
}
