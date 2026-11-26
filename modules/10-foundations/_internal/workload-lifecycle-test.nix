{inputs, system}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  guest = version: (inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [{
      boot.isNspawnContainer = true;
      networking.useDHCP = false;
      system.stateVersion = "26.05";
      documentation.enable = false;
      environment.etc."workload-release".text = version;
      systemd.services.shutdown-blocker.serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        ExecStop = "${pkgs.coreutils}/bin/sleep infinity";
        TimeoutStopSec = "infinity";
      };
    }];
  }).config.system.build.toplevel;
  first = guest "v1";
  second = guest "v2";
  profile = "/nix/var/nix/profiles/per-container/fixture/system";
  switch = pkgs.writeText "nspawn-profile-switch.sh" (builtins.readFile ../../../tools/nspawn-profile-switch.sh);
in pkgs.testers.runNixOSTest {
  name = "workload-lifecycle";
  qemu.forceAccel = true;
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      additionalPaths = [first second switch];
    };
    environment.systemPackages = [pkgs.util-linux];
    containers.fixture = {
      autoStart = false;
      path = "/nix/var/nix/profiles/system";
    };
    systemd.services."container@fixture".unitConfig.ConditionPathExists = "${profile}/init";
    systemd.services.incumbent = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
  };
  testScript = ''
    import json
    spec = json.loads(${builtins.toJSON (builtins.toJSON {
      inherit profile;
      first = toString first;
      second = toString second;
      switch = toString switch;
    })})
  '' + builtins.readFile ./workload-lifecycle-test.py;
}
