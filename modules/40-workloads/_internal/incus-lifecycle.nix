{inputs, self, system, name, image, candidate, guestMemory, stateProbe}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in pkgs.testers.runNixOSTest {
  name = "incus-workload-${name}";
  nodes.neko7 = {
    imports = [
      self.modules.nixos.incus
      ({lib, ...}: {options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";})
    ];
    local.features.incus.enable = true;
    virtualisation = {
      cores = 4;
      memorySize = 7168;
      diskSize = 48 * 1024;
      additionalPaths = [image candidate];
    };
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.just pkgs.util-linux];
  };
  testScript = ''
    import shlex
    neko7.start()
    neko7.wait_for_unit("incus-preseed.service")
    neko7.succeed("test -c /dev/kvm; incus version; mkdir -p /root/fixture/tools; cp ${../../../justfile} /root/fixture/justfile; cp ${../../../tools/instance-ops.sh} /root/fixture/tools/instance-ops.sh")
    recipe = "cd /root/fixture && just "
    def guest(name, command):
        return "incus exec local:" + name + " --project default -- sh -ec " + shlex.quote(command)
    def run(name, command):
        return neko7.succeed(guest(name, command)).strip()
    def ready(name):
        neko7.wait_until_succeeds(guest(name, "/etc/neko7/readiness"), timeout=300)
    # Exact production image, no synthetic image substitution. The private
    # artifact entrypoints are precisely the steps used by the public recipes
    # after nix build; public build wrappers are tested separately.
    neko7.succeed(recipe + "_new-image ${name} original 16GiB 2 ${guestMemory} ${image}")
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
    neko7.succeed(recipe + "_new-image ${name} independent 16GiB 2 ${guestMemory} ${image}")
    ready("independent")
    assert run("independent", "cat /etc/machine-id") != original_id
    neko7.succeed("incus stop local:independent --project default")
    neko7.succeed("incus start local:original --project default")
    ready("original")
    assert run("original", ${builtins.toJSON stateProbe.verify}) == original_state
    # Update to a distinct test release with identical application version.
    neko7.succeed(recipe + "_update-system original /root/before-update ${name} " + uuid + " ${candidate}")
    assert run("original", "cat /etc/neko7/fixture-release") == "candidate"
    assert run("original", "readlink -e /run/current-system") == "${candidate}"
    assert run("original", ${builtins.toJSON stateProbe.verify}) == original_state
    neko7.succeed("cd /root/before-update && sha256sum -c SHA256SUMS && jq -e --arg uuid " + shlex.quote(uuid) + " '.name == \"original\" and .uuid == $uuid' identity.json")
    neko7.succeed(recipe + "backup original /root/after-update")
    neko7.succeed("incus list local: name=original --format json | jq -e 'length == 1 and .[0].status == \"Stopped\"'")
    # Incus import does not boot. Override the NIC before the first start,
    # then assert no expanded NIC exists; never start a cloned identity online.
    neko7.succeed("incus import /root/before-update/instance.tar.gz local:restore --project default")
    neko7.succeed("incus config set local:restore boot.autostart=false --project default")
    neko7.succeed("incus config device add local:restore eth0 none --project default")
    neko7.succeed("incus list local: name=restore --format json | jq -e 'length == 1 and .[0].status == \"Stopped\" and ([.[0].expanded_devices[] | select(.type == \"nic\")] | length == 0)'")
    neko7.succeed("incus start local:restore --project default")
    ready("restore")
    assert run("restore", "readlink -e /run/current-system") == original_generation
    assert run("restore", ${builtins.toJSON stateProbe.verify}) == original_state
    neko7.fail(guest("restore", "test -e /etc/neko7/fixture-release"))
    neko7.succeed("incus stop local:restore --project default")
  '';
}
