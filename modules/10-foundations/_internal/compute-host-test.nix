{inputs, self, system, vm, tcg ? false}: let
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
  # Test-only single-vCPU guests remove one nested-SMP variable while
  # preserving real KVM, two simultaneous guests, and production limits.
  # Controlled mitigation, not a proven root-cause fix.
  vmFlag = lib.optionalString vm " --vm -c security.secureboot=false -c limits.memory=2048MiB -c limits.cpu=1";
in pkgs.testers.runNixOSTest {
  name = if vm then "compute-host-vm${lib.optionalString tcg "-tcg"}" else "compute-host-container";
  qemu.forceAccel = true;
  nodes.machine = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {
        options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";
      })
    ] ++ lib.optional tcg ./incus-tcg-fixture.nix;
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      # The nested QEMU process and image reads must not traverse the
      # outer test driver's 9p Nix store. Native block-backed EROFS store.
      useNixStoreImage = vm;
      writableStore = true;
      memorySize = if vm then 7168 else 4096;
      diskSize = 24 * 1024;
    };
    users.users.agent = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.time pkgs.qemu pkgs.util-linux];
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
        if command.startswith("incus exec lab:"):
            command = command.replace(" -- ", " --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- ", 1)
        return "su - agent -c " + shlex.quote(command)

    def guest_ready(name):
        try:
            machine.wait_until_succeeds("timeout -k 5s 30s " + agent("incus exec lab:" + name + " -- systemctl is-active fixture-http"), timeout=900 if ${if vm then "True" else "False"} else 300)
        except Exception:
            # A present /dev/kvm is not evidence that an inner guest booted.
            # Collect firmware/kernel/agent console before fixture cleanup.
            print(machine.execute("timeout -k 5s 20s incus info " + name + " --project lab --show-log 2>&1; timeout -k 5s 20s incus console " + name + " --project lab --show-log 2>&1; free -m; cat /proc/pressure/{cpu,memory,io}; journalctl -k --no-pager | tail -100; ps -eLo pid,tid,stat,pcpu,wchan:32,comm | grep -E 'qemu|incus'")[1])
            raise

    machine.start()
    machine.wait_for_unit("register-nix-paths.service")
    machine.wait_for_unit("incus-preseed.service")
    machine.wait_for_unit("incumbent.service")
    incumbent = machine.succeed("systemctl show -p MainPID --value incumbent.service").strip()
    machine.succeed("incus version; incus project get lab limits.instances | grep -x 8; incus project get lab limits.virtual-machines | grep -x 3")
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
      # Incus feature probing requires /dev/kvm in both variants; the
      # unsuffixed KVM check also verifies hardware-accelerated guest execution.
      machine.succeed("test -c /dev/kvm")
    ''}
    machine.succeed(agent("incus launch lab:fixture lab:persistent${vmFlag}"))
    guest_ready("persistent")
    ${lib.optionalString vm ''
      # Preserve the upstream inspection limits. Capture headroom, CPU time
      # and peak RSS before launching the second concurrent guest.
      machine.succeed("free -m; cat /proc/pressure/{cpu,memory,io}; incus version")
      machine.execute("for image in /var/lib/incus/images/*.rootfs; do ${pkgs.time}/bin/time -v prlimit --cpu=2 --as=1073741824 qemu-img info -f qcow2 --output=json \"$image\"; done")
    ''}
    status, output = machine.execute(agent("incus launch lab:fixture lab:experiment${vmFlag} --ephemeral") + " 2>&1")
    if status != 0:
        print(output)
        print(machine.succeed("free -m; cat /proc/pressure/{cpu,memory,io}; journalctl -k --no-pager | tail -100; journalctl -u incus --no-pager | tail -100"))
        raise Exception("second instance launch failed; see diagnostics above")
    guest_ready("experiment")
    guest_ready("persistent")
    ${lib.optionalString tcg ''
      machine.succeed("grep -Fx persistent /run/incus-ci-tcg-launches; grep -Fx experiment /run/incus-ci-tcg-launches")
    ''}
    machine.succeed(agent("incus exec lab:experiment -- su - developer -c 'id -un' | grep -x developer"))
    machine.succeed(agent("incus exec lab:experiment -- touch /tmp/experiment-marker"))
    machine.fail(agent("incus exec lab:persistent -- test -e /tmp/experiment-marker"))
    def denied(command, reason):
        # Test Driver captures stdout; Incus diagnostics go to stderr.
        status, output = machine.execute(agent(command) + " 2>&1")
        assert status != 0 and reason.lower() in output.lower(), (command, output)
    before_config = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))[0]
    denied("incus config device add lab:experiment host-etc disk source=/etc path=/host-etc", "not backed by a pool")
    denied("incus config device add lab:experiment gpu gpu", "GPU devices are forbidden")
    denied("incus config set lab:experiment limits.memory=9GiB", "maximum aggregate value")
    denied("incus config set lab:experiment limits.cpu=9", "maximum aggregate value")
    denied("incus create lab:fixture lab:over-budget${lib.optionalString vm " --vm -c security.secureboot=false"} -c limits.cpu=9", "maximum aggregate value")
    after_config = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))[0]
    # Volatile config keys may change asynchronously (e.g. NIC state).
    assert {k: v for k, v in after_config["config"].items() if not k.startswith("volatile.")} == {k: v for k, v in before_config["config"].items() if not k.startswith("volatile.")}
    assert after_config["devices"] == before_config["devices"]
    denied("incus config device add lab:experiment external nic nictype=physical parent=eth0 name=eth1", "Only managed network devices")
    denied("incus network forward create lab:incuslab0 192.0.2.99", "permission for project")
    ${lib.optionalString (!vm) ''
      denied("incus config set lab:experiment security.privileged=true", "Privileged containers are forbidden")
      denied("incus config device add lab:experiment public proxy listen=tcp:0.0.0.0:18080 connect=tcp:127.0.0.1:8080", "Proxy devices are forbidden")
    ''}
    ${lib.optionalString vm ''
      machine.fail(agent("incus config set lab:experiment raw.qemu=-nographic"))
    ''}
    # A real HTTP preview is reachable from the host without a public listener.
    data = json.loads(machine.succeed(agent("incus list lab: name=experiment --format=json")))
    assert len(data) == 1 and data[0]["name"] == "experiment", data
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
    guest_ready("persistent")
    assert machine.succeed(agent("incus exec lab:persistent -- cat /proc/sys/kernel/random/boot_id")).strip() == before
    assert machine.succeed("incus info persistent --project lab | grep '^PID:'").strip() == pid
    assert machine.succeed("systemctl show -p MainPID --value incumbent.service").strip() == incumbent
    denied("incus config device add lab:persistent host-etc disk source=/etc path=/host-etc", "not backed by a pool")
    machine.fail(agent("incus info lab:operator-owned --project default"))
    machine.succeed(agent("incus delete lab:persistent --force"))
    machine.succeed("incus delete operator-owned")
    machine.succeed(agent("incus list lab: --format=json | jq -e 'length == 0'"))
  '';
}
