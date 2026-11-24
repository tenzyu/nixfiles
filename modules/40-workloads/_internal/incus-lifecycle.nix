{inputs, self, system, name, image, candidate, guestMemory, stateProbe, tcg ? false}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in pkgs.testers.runNixOSTest {
  name = "incus-workload-${name}${pkgs.lib.optionalString tcg "-tcg"}";
  qemu.forceAccel = true;
  globalTimeout = 75 * 60;
  nodes.neko7 = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";})
    ] ++ pkgs.lib.optional tcg ../../10-foundations/_internal/incus-tcg-fixture.nix;
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      # Native local store image instead of nested QEMU/image I/O over 9p.
      useNixStoreImage = true;
      writableStore = true;
      memorySize = 7168;
      diskSize = 48 * 1024;
      additionalPaths = [image candidate];
    };
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.just pkgs.util-linux];
  };
  testScript = ''
    import shlex
    neko7.start()
    neko7.wait_for_unit("register-nix-paths.service")
    neko7.wait_for_unit("incus-preseed.service")
    neko7.succeed("test -c /dev/kvm; incus version; mkdir -p /root/fixture/tools; cp ${../../../justfile} /root/fixture/justfile; cp ${../../../tools/instance-ops.sh} /root/fixture/tools/instance-ops.sh")
    recipe = "cd /root/fixture && NEKO7_READINESS_TIMEOUT=900 just "
    def guest(name, command):
        return "incus exec local:" + name + " --project default --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- /run/current-system/sw/bin/bash -ec " + shlex.quote(command)
    def run(name, command):
        return neko7.succeed(guest(name, command)).strip()
    def diagnose(name):
        print(neko7.execute("timeout -k 5s 20s incus info local:" + name + " --project default --show-log 2>&1; timeout -k 5s 20s incus console local:" + name + " --project default --show-log 2>&1; free -m; cat /proc/pressure/{cpu,memory,io}; journalctl -k --no-pager | tail -100; ps -eLo pid,tid,stat,pcpu,wchan:32,comm | grep -E 'qemu|incus'")[1])
    def ready(name):
        try:
            neko7.wait_until_succeeds("timeout -k 5s 30s " + guest(name, "/etc/neko7/readiness"), timeout=900)
        except Exception:
            diagnose(name)
            raise
    def new_instance(name):
        status, output = neko7.execute(recipe + "_new-image ${name} " + name + " 16GiB 1 ${guestMemory} ${image} 2>&1")
        if status != 0:
            print(output)
            diagnose(name)
            raise Exception("exact-image instance creation/readiness failed")
        ${pkgs.lib.optionalString tcg ''
          neko7.succeed("grep -Fx " + shlex.quote(name) + " /run/incus-ci-tcg-launches")
        ''}
    # Exact production image, no synthetic image substitution. The private
    # artifact entrypoints are precisely the steps used by the public recipes
    # after nix build; public build wrappers are tested separately.
    # One vCPU in CI only: the hosted runner adds an extra virtualization
    # layer. Production sizing and all exact-image/state tests are unchanged.
    new_instance("original")
    ready("original")
    original_id = run("original", "cat /etc/machine-id")
    run("original", ${builtins.toJSON stateProbe.seed})
    original_state = run("original", ${builtins.toJSON stateProbe.verify})
    original_generation = run("original", "readlink -e /run/current-system")
    uuid = neko7.succeed("incus config get local:original volatile.uuid --project default").strip()
    assert uuid
    # Concurrency and destination collision fail before stop or mutation.
    neko7.succeed("flock /run/lock/neko7-instances/original.lock -c 'touch /tmp/lock-held; sleep 20' >/tmp/lock-log 2>&1 &")
    neko7.wait_until_succeeds("test -f /tmp/lock-held")
    neko7.fail(recipe + "backup original /root/locked-bundle")
    neko7.succeed("test ! -e /root/locked-bundle")
    neko7.wait_until_succeeds("flock -n /run/lock/neko7-instances/original.lock true")
    neko7.succeed("mkdir -m 0700 /root/collision")
    neko7.fail(recipe + "backup original /root/collision")
    ready("original")
    neko7.fail(recipe + "_update-system original /root/wrong-id ${name} wrong-uuid ${candidate}")
    neko7.succeed("test ! -e /root/wrong-id")
    # Separate instance identity without copying state, one running VM at a time.
    neko7.succeed("incus stop local:original --project default")
    new_instance("independent")
    ready("independent")
    assert run("independent", "cat /etc/machine-id") != original_id
    neko7.succeed("incus stop local:independent --project default")
    neko7.succeed("incus start local:original --project default")
    ready("original")
    assert run("original", ${builtins.toJSON stateProbe.verify}) == original_state
    # Update to a distinct test release with identical application version.
    ${pkgs.lib.optionalString (name == "syncthing") ''
      # Fixture-only fault injection: preserve native calls except for the
      # activation boundary after the real profile mutation has completed.
      neko7.succeed("mkdir -p /root/fault-bin")
      neko7.succeed("cat >/root/fault-bin/sudo <<'EOF'\n#!${pkgs.runtimeShell}\nfor arg in \"$@\"; do\n  case \"$arg\" in */bin/switch-to-configuration) exit 77;; esac\ndone\nexec /run/wrappers/bin/sudo \"$@\"\nEOF\nchmod 0700 /root/fault-bin/sudo")
      neko7.fail("cd /root/fixture && PATH=/root/fault-bin:$PATH NEKO7_READINESS_TIMEOUT=900 just _update-system original /root/interrupted ${name} " + uuid + " ${candidate}")
      neko7.succeed("cd /root/interrupted && sha256sum -c SHA256SUMS")
      assert run("original", "readlink -e /nix/var/nix/profiles/system") == "${candidate}"
      assert run("original", "readlink -e /run/current-system") == original_generation
      assert run("original", ${builtins.toJSON stateProbe.verify}) == original_state
      # No activation ran; the fixture may safely reset only the release
      # pointer. This is not a general schema rollback procedure.
      run("original", "nix-env -p /nix/var/nix/profiles/system --set " + original_generation)
      ready("original")
    ''}
    neko7.succeed(recipe + "_update-system original /root/before-update ${name} " + uuid + " ${candidate}")
    assert run("original", "cat /etc/neko7/fixture-release") == "candidate"
    assert run("original", "readlink -e /run/current-system") == "${candidate}"
    assert run("original", ${builtins.toJSON stateProbe.verify}) == original_state
    neko7.succeed("cd /root/before-update && sha256sum -c SHA256SUMS && jq -e --arg uuid " + shlex.quote(uuid) + " '.name == \"original\" and .uuid == $uuid' identity.json")
    neko7.succeed(recipe + "backup original /root/after-update")
    neko7.succeed("incus list local: name=original --format json | jq -e 'length == 1 and .[0].status == \"Stopped\"'")
    # Incus import does not boot. Override the NIC before the first start,
    # then assert no expanded NIC exists; never start a cloned identity online.
    neko7.succeed("incus import local: /root/before-update/instance.tar.gz restore --project default -c boot.autostart=false")
    neko7.succeed("incus config get local:restore boot.autostart --project default | grep -Fx false")
    neko7.succeed("incus config device add local:restore eth0 none --project default")
    neko7.succeed("incus list local: name=restore --format json | jq -e 'length == 1 and .[0].status == \"Stopped\" and ([.[0].expanded_devices[] | select(.type == \"nic\")] | length == 0)'")
    neko7.succeed("incus start local:restore --project default")
    ready("restore")
    ${pkgs.lib.optionalString tcg ''
      neko7.succeed("grep -Fx restore /run/incus-ci-tcg-launches")
    ''}
    assert run("restore", "readlink -e /run/current-system") == original_generation
    assert run("restore", ${builtins.toJSON stateProbe.verify}) == original_state
    neko7.fail(guest("restore", "test -e /etc/neko7/fixture-release"))
    neko7.succeed("incus stop local:restore --project default")
  '';
}
