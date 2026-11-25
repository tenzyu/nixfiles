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
    }];
  }).config.system.build.toplevel;
  first = guest "v1";
  second = guest "v2";
  profile = "/nix/var/nix/profiles/per-container/fixture/system";
in pkgs.testers.runNixOSTest {
  name = "workload-lifecycle";
  nodes.machine = {
    virtualisation = {
      memorySize = 2048;
      additionalPaths = [first second];
    };
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
    machine.start()
    machine.wait_for_unit("incumbent.service")
    system = machine.succeed("readlink -e /run/current-system").strip()
    pid = machine.succeed("systemctl show -p MainPID --value incumbent.service").strip()

    # Missing profile fails closed; no attempt to boot an unseeded guest.
    machine.succeed("systemctl start container@fixture.service")
    machine.fail("systemctl is-active --quiet container@fixture.service")
    machine.succeed("mkdir -p /nix/var/nix/profiles/per-container/fixture")
    machine.succeed("nix-env --profile ${profile} --set ${first}")
    machine.succeed("systemctl start container@fixture.service")
    machine.wait_until_succeeds("nixos-container run fixture -- grep -x v1 /etc/workload-release")
    machine.succeed("nixos-container run fixture -- sh -c 'echo persisted > /var/lib/workload-state'")

    # Native profile update changes only this workload and retains its state.
    machine.succeed("systemctl stop container@fixture.service")
    machine.succeed("nix-env --profile ${profile} --set ${second}")
    machine.succeed("systemctl start container@fixture.service")
    machine.wait_until_succeeds("nixos-container run fixture -- grep -x v2 /etc/workload-release")
    machine.succeed("nixos-container run fixture -- grep -x persisted /var/lib/workload-state")
    assert machine.succeed("readlink -e /run/current-system").strip() == system
    assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == pid

    # Exercise actual native generation rollback; mutable data is not rolled back.
    machine.succeed("systemctl stop container@fixture.service")
    machine.succeed("nix-env --profile ${profile} --rollback")
    machine.succeed("systemctl start container@fixture.service")
    machine.wait_until_succeeds("nixos-container run fixture -- grep -x v1 /etc/workload-release")
    machine.succeed("nixos-container run fixture -- grep -x persisted /var/lib/workload-state")
    assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == pid
  '';
}
