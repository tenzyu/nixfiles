{inputs, self, system, vm}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  inherit (pkgs) lib;
  # Use the pinned upstream image builders, not external mutable image aliases.
  releases = import "${inputs.nixpkgs}/nixos/release.nix" {
    configuration = {lib, pkgs, ...}: {
      documentation.enable = lib.mkForce false;
      documentation.nixos.enable = lib.mkForce false;
      system.installer.channel.enable = lib.mkForce false;
      virtualisation.incus.package = pkgs.incus;
      users.users.developer = {
        isNormalUser = true;
        uid = 1234;
      };
      environment.etc."compute-fixture/index.html".text = "compute-host-fixture";
      systemd.services.fixture-http = {
        wantedBy = ["multi-user.target"];
        serviceConfig = {
          User = "developer";
          ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --directory /etc/compute-fixture";
        };
      };
      networking.firewall.allowedTCPPorts = [8080];
    };
  };
  metadata = if vm
    then "${releases.incusVirtualMachineImageMeta.${system}}/*/*.tar.xz"
    else "${releases.incusContainerMeta.${system}}/tarball/nixos-image-lxc-*-${system}.tar.xz";
  image = if vm
    then "${releases.incusVirtualMachineImage.${system}}/nixos.qcow2"
    else "${releases.incusContainerImage.${system}}/nixos-lxc-image-${system}.squashfs";
  vmFlag = lib.optionalString vm " --vm -c security.secureboot=false -c limits.memory=1024MiB -c limits.cpu=2";
in pkgs.testers.runNixOSTest {
  name = if vm then "compute-host-vm" else "compute-host-container";
  nodes.machine = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {
        options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";
      })
    ];
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      memorySize = 4096;
      diskSize = 24 * 1024;
    };
    users.users.agent = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [pkgs.curl pkgs.jq];
    # Co-resident native service should not be restarted by lab operations.
    systemd.services.incumbent = {
      wantedBy = ["multi-user.target"];
      serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
  };
  testScript = ''
    import json
    import shlex

    def agent(command):
        return "su - agent -c " + shlex.quote(command)

    machine.start()
    machine.wait_for_unit("incus-preseed.service")
    machine.wait_for_unit("incumbent.service")
    incumbent = machine.succeed("systemctl show -p MainPID --value incumbent.service").strip()
    machine.succeed("incus project get lab restricted | grep -x true")
    machine.succeed("incus project get lab restricted.devices.disk | grep -x managed")
    machine.succeed("incus network show incuslab0")
    machine.succeed("ss -ltn | grep -F '127.0.0.1:8443'")
    machine.succeed("curl -fkLs https://127.0.0.1:8443/ui/ | grep -i incus")
    machine.fail(agent("test -w /var/lib/incus/unix.socket"))
    machine.fail(agent("test -w /var/lib/incus/unix.socket.user"))

    # Enrollment is an explicit operator action. CI uses disposable credentials.
    machine.succeed(agent("incus remote get-client-certificate > /home/agent/client.pem"))
    machine.succeed("incus config trust add-certificate /home/agent/client.pem --projects lab --restricted")
    machine.succeed(agent("incus remote add lab https://127.0.0.1:8443 --accept-certificate --project lab"))
    machine.succeed(agent("incus list lab:"))
    machine.fail(agent("incus project set lab:lab restricted=false"))
    machine.fail(agent("incus network create lab:escape --project default"))
    machine.fail(agent("incus config set lab: core.https_address=:8443"))

    machine.succeed("incus image import ${metadata} ${image} --alias fixture --project lab")
    machine.succeed("incus image import ${metadata} ${image} --alias fixture --project default")
    machine.succeed("incus create fixture operator-owned${vmFlag}")
    machine.fail(agent("incus delete lab:operator-owned --project default --force"))
    machine.succeed("incus info operator-owned")
    ${lib.optionalString vm ''
      # Real nested KVM is mandatory for this test: no empty-VM substitute.
      machine.succeed("test -c /dev/kvm")
    ''}
    machine.succeed(agent("incus launch lab:fixture lab:persistent${vmFlag}"))
    machine.succeed(agent("incus launch lab:fixture lab:experiment${vmFlag} --ephemeral"))
    machine.wait_until_succeeds(agent("incus exec lab:experiment -- systemctl is-active fixture-http"), timeout=240)
    machine.wait_until_succeeds(agent("incus exec lab:persistent -- systemctl is-active fixture-http"), timeout=240)
    machine.succeed(agent("incus exec lab:experiment -- su - developer -c 'id -un' | grep -x developer"))
    machine.succeed(agent("incus exec lab:experiment -- touch /tmp/experiment-marker"))
    machine.fail(agent("incus exec lab:persistent -- test -e /tmp/experiment-marker"))
    machine.fail(agent("incus config device add lab:experiment host-etc disk source=/etc path=/host-etc"))
    ${lib.optionalString (!vm) ''
      machine.fail(agent("incus config set lab:experiment security.privileged=true"))
    ''}
    ${lib.optionalString vm ''
      machine.fail(agent("incus config set lab:experiment raw.qemu=-nographic"))
    ''}
    # A real HTTP preview is reachable from the host without a public listener.
    data = json.loads(machine.succeed(agent("incus list lab:experiment --format=json")))
    ips = [a["address"] for nic in data[0]["state"]["network"].values() for a in nic["addresses"] if a["family"] == "inet" and a["scope"] == "global"]
    assert len(ips) >= 1, data
    machine.wait_until_succeeds("curl -fsS http://" + ips[0] + ":8080/ | grep -F compute-host-fixture")
    machine.succeed(agent("incus stop lab:experiment --force"))
    machine.wait_until_fails(agent("incus info lab:experiment"))
    machine.succeed(agent("incus exec lab:persistent -- systemctl is-active fixture-http"))

    # The management daemon can restart without restarting the workload.
    before = machine.succeed(agent("incus exec lab:persistent -- cat /proc/sys/kernel/random/boot_id")).strip()
    pid = machine.succeed("incus info persistent --project lab | grep '^PID:'").strip()
    machine.succeed("systemctl restart incus.service")
    machine.wait_for_unit("incus-preseed.service")
    machine.wait_until_succeeds(agent("incus exec lab:persistent -- systemctl is-active fixture-http"))
    assert machine.succeed(agent("incus exec lab:persistent -- cat /proc/sys/kernel/random/boot_id")).strip() == before
    assert machine.succeed("incus info persistent --project lab | grep '^PID:'").strip() == pid
    assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == incumbent
    machine.succeed(agent("incus delete lab:persistent --force"))
    machine.succeed("incus delete operator-owned")
    machine.succeed(agent("incus list lab: --format=json | jq -e 'length == 0'"))
  '';
}
