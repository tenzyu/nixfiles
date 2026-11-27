{inputs, self, system, image, packages}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in pkgs.testers.runNixOSTest {
  name = "remote-execution-mcp";
  nodes.machine = {lib, ...}: {
    imports = [
      self.modules.nixos.incus
      self.modules.nixos.remote-execution-mcp-network
      ({lib, ...}: {
        options.local.features.incus.enable = lib.mkEnableOption "Incus fixture";
        options.local.features.remote-execution-mcp-network.enable = lib.mkEnableOption "MCP network fixture";
      })
    ];
    system.stateVersion = "26.05";
    local.features.incus.enable = true;
    local.features.remote-execution-mcp-network.enable = true;
    local.remoteExecutionMcp = {
      bridgeAddress = "10.77.42.1/24";
      protectedIPv4 = ["203.0.113.0/24"];
    };
    networking.nat.externalInterface = "test-uplink";
    networking.firewall.allowedTCPPorts = [18080];
    users.users.agent.isNormalUser = true;
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.iproute2 pkgs.util-linux pkgs.python3];
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      diskSize = 24 * 1024;
      writableStore = true;
    };
  };
  testScript = ''
    import json
    import shlex

    machine.start()
    machine.wait_for_unit("incus-preseed.service")
    machine.wait_for_unit("nftables.service")
    machine.succeed("incus network show incusmcp0")
    machine.succeed("incus project get lab restricted.networks.access | grep -Fx incuslab0")
    machine.succeed("incus profile show remote-execution-mcp")
    machine.succeed("touch /root/host-mcp-canary")
    machine.succeed(
        "ip netns add outside",
        "ip link add test-uplink type veth peer name outside0",
        "ip link set outside0 netns outside",
        "ip addr add 198.51.100.1/24 dev test-uplink",
        "ip addr add 192.168.50.1/24 dev test-uplink",
        "ip addr add 203.0.113.1/24 dev test-uplink",
        "ip link set test-uplink up",
        "ip -n outside link set lo up",
        "ip -n outside addr add 198.51.100.2/24 dev outside0",
        "ip -n outside addr add 192.168.50.2/24 dev outside0",
        "ip -n outside addr add 203.0.113.2/24 dev outside0",
        "ip -n outside link set outside0 up",
        "ip -n outside route add 10.77.42.0/24 via 198.51.100.1",
        "systemd-run --unit=host-canary ${pkgs.python3}/bin/python3 -m http.server 18080 --bind 0.0.0.0 --directory /tmp",
        "systemd-run --unit=outside-canary ${pkgs.iproute2}/bin/ip netns exec outside ${pkgs.python3}/bin/python3 -m http.server 18080 --bind 0.0.0.0 --directory /tmp",
    )
    curl = "curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "
    machine.wait_until_succeeds(curl + "http://198.51.100.2:18080/")
    machine.succeed(curl + "http://192.168.50.2:18080/")
    machine.succeed(curl + "http://203.0.113.2:18080/")
    machine.succeed(curl + "http://10.77.42.1:18080/")

    machine.succeed("incus image import ${image}/metadata.tar.xz ${image}/rootfs.squashfs --alias mcp-fixture")
    machine.succeed("incus launch mcp-fixture mcp-fixture --profile remote-execution-mcp")
    def guest(command):
        return "incus exec mcp-fixture --mode=non-interactive --disable-stdin --env PATH=/run/wrappers/bin:/run/current-system/sw/bin -- sh -c " + shlex.quote(command)

    try:
        machine.wait_until_succeeds(guest("systemctl is-active remote-execution-mcp.service"), timeout=300)
        state = json.loads(machine.succeed("incus list name=mcp-fixture --format=json"))[0]
        assert set(state["expanded_devices"]) == {"root", "eth0"}, state["expanded_devices"]
        assert state["expanded_config"]["security.privileged"] == "false"
        assert state["expanded_config"]["security.nesting"] == "false"
        ips = [a["address"] for nic in state["state"]["network"].values() for a in nic["addresses"] if a["family"] == "inet" and a["scope"] == "global"]
        assert len(ips) == 1, ips
        ip = ips[0]
        endpoint = "http://" + ip + ":18991/mcp"
        reach = "curl --noproxy '*' -sS --connect-timeout 2 --max-time 4 -o /dev/null "
        machine.wait_until_succeeds("runuser -u remote-mcp-tunnel -- " + reach + endpoint)
        machine.fail("runuser -u agent -- " + reach + endpoint)
        machine.fail("ip netns exec outside " + reach + endpoint)

        machine.succeed(guest("test ! -e /root/host-mcp-canary && test ! -e /var/lib/incus/unix.socket && test ! -e /var/lib/incus/unix.socket.user"))
        machine.succeed(guest(curl + "http://198.51.100.2:18080/"))
        machine.fail(guest(curl + "http://10.77.42.1:18080/"))
        machine.fail(guest(curl + "http://192.168.50.2:18080/"))
        machine.fail(guest(curl + "http://203.0.113.2:18080/"))
        machine.succeed("MCP_URL=" + endpoint + " MCP_CHECK_GUEST=1 MCP_NIX_BUILDER=${pkgs.bash} ${packages.supergateway}/bin/remote-execution-mcp-probe")
        machine.succeed(guest("systemctl stop remote-execution-mcp.service"))
        machine.fail(reach + endpoint)
        machine.succeed(guest("systemctl start remote-execution-mcp.service"))
        machine.wait_until_succeeds(reach + endpoint)
    except Exception:
        print(machine.execute("incus info mcp-fixture --show-log; incus exec mcp-fixture -- journalctl -u remote-execution-mcp --no-pager -n 100; nft list table inet remote_execution_mcp")[1])
        raise
    finally:
        machine.succeed("incus stop mcp-fixture --force")
        machine.succeed("incus delete mcp-fixture")
  '';
}
