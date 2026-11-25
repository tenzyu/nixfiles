{inputs, self, system}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  udpEcho = pkgs.writeText "udp-echo.py" ''
    import socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("198.51.100.2", 18083))
    while True:
        data, peer = sock.recvfrom(2048)
        sock.sendto(data, peer)
  '';
  udpClient = pkgs.writeText "udp-client.py" ''
    import socket
    import sys
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((sys.argv[1], 18082))
    sock.settimeout(3)
    sock.sendto(b"outbound-session", ("198.51.100.2", 18083))
    data, peer = sock.recvfrom(2048)
    assert data == b"outbound-session" and peer == ("198.51.100.2", 18083)
  '';
in pkgs.testers.runNixOSTest {
  name = "tailnet-ingress";
  nodes.machine = {
    imports = [
      self.modules.nixos.tailnet-ingress
      ({lib, ...}: {
        options.local.features.tailnet-ingress.enable = lib.mkEnableOption "Tailnet ingress fixture";
      })
    ];
    local.features.tailnet-ingress.enable = true;
    networking.nat = {
      enable = true;
      externalInterface = "test-uplink";
      internalInterfaces = ["test-lan"];
    };
    # Intentionally allow a host TCP port in the ordinary firewall.
    # The separate ingress guard must override even this mistaken opening.
    networking.firewall.allowedTCPPorts = [18080];
    networking.firewall.allowedUDPPorts = [18082];
    environment.systemPackages = [pkgs.curl pkgs.jq pkgs.iproute2];
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    machine.start()
    machine.wait_for_unit("nftables.service")

    # Independent network stacks, not loopback probes.
    machine.succeed(
        "ip netns add outside",
        "ip netns add guest",
        "ip link add test-uplink type veth peer name outside0",
        "ip link add test-lan type veth peer name guest0",
        "ip link set outside0 netns outside",
        "ip link set guest0 netns guest",
        "ip addr add 198.51.100.1/24 dev test-uplink",
        "ip addr add 203.0.113.1/24 dev test-lan",
        "ip link set test-uplink up",
        "ip link set test-lan up",
        "ip -n outside link set lo up",
        "ip -n guest link set lo up",
        "ip -n outside addr add 198.51.100.2/24 dev outside0",
        "ip -n guest addr add 203.0.113.2/24 dev guest0",
        "ip -n outside link set outside0 up",
        "ip -n guest link set guest0 up",
        "ip -n outside route add 203.0.113.0/24 via 198.51.100.1",
        "ip -n guest route add default via 203.0.113.1",
    )
    machine.succeed("ip netns exec outside ping -c 1 -W 2 198.51.100.1")
    machine.succeed(
        "systemd-run --unit=fixture-host ${pkgs.python3}/bin/python3 -m http.server 18080 --bind 0.0.0.0 --directory /tmp",
        "systemd-run --unit=fixture-guest ${pkgs.iproute2}/bin/ip netns exec guest ${pkgs.python3}/bin/python3 -m http.server 8080 --bind 203.0.113.2 --directory /tmp",
        "systemd-run --unit=fixture-outside ${pkgs.iproute2}/bin/ip netns exec outside ${pkgs.python3}/bin/python3 -m http.server 8080 --bind 198.51.100.2 --directory /tmp",
    )
    curl = "curl --noproxy '*' -fsS --connect-timeout 2 --max-time 4 "
    machine.wait_until_succeeds(curl + "http://127.0.0.1:18080/")
    machine.wait_until_succeeds(curl + "http://203.0.113.2:8080/")
    machine.wait_until_succeeds("ip netns exec guest " + curl + "http://203.0.113.1:18080/")
    machine.wait_until_succeeds("ip netns exec guest " + curl + "http://198.51.100.2:8080/")

    def denied_counter(name):
        return int(machine.succeed("nft -j list counter inet tailnet_ingress " + name + " | jq -r '.nftables[] | .counter? | select(.) | .packets'").strip())

    with subtest("external host listener blocked despite ordinary firewall opening"):
        before = denied_counter("input_denied")
        machine.fail("ip netns exec outside " + curl + "http://198.51.100.1:18080/")
        assert denied_counter("input_denied") > before

    with subtest("direct routed guest ingress blocked"):
        before = denied_counter("forward_denied")
        machine.fail("ip netns exec outside " + curl + "http://203.0.113.2:8080/")
        assert denied_counter("forward_denied") > before

    with subtest("accidental runtime port forwarding cannot bypass guard"):
        machine.succeed(
            "nft add table ip ci_dnat",
            "nft 'add chain ip ci_dnat pre { type nat hook prerouting priority dstnat; policy accept; }'",
            "nft 'add rule ip ci_dnat pre iifname test-uplink tcp dport 18081 dnat to 203.0.113.2:8080'",
        )
        before = denied_counter("forward_denied")
        machine.fail("ip netns exec outside " + curl + "http://198.51.100.1:18081/")
        assert denied_counter("forward_denied") > before
        machine.succeed("nft delete table ip ci_dnat")

    with subtest("unsolicited UDP denied, outbound UDP reply allowed without opening a port"):
        before = denied_counter("input_denied")
        machine.succeed("ip netns exec outside ${pkgs.python3}/bin/python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b\"unsolicited\",(\"198.51.100.1\",18082))'")
        assert denied_counter("input_denied") > before
        machine.succeed("systemd-run --unit=udp-echo ${pkgs.iproute2}/bin/ip netns exec outside ${pkgs.python3}/bin/python3 ${udpEcho}")
        machine.wait_until_succeeds("ip netns exec outside ss -lun | grep -F ':18083'")
        machine.succeed("${pkgs.python3}/bin/python3 ${udpClient} 198.51.100.1")
        machine.succeed("ip netns exec guest ${pkgs.python3}/bin/python3 ${udpClient} 203.0.113.2")

    # Prove the intended positive paths still work after all negative probes.
    machine.succeed(curl + "http://203.0.113.2:8080/")
    machine.succeed("ip netns exec guest " + curl + "http://198.51.100.2:8080/")
    machine.succeed("ip netns exec guest " + curl + "http://203.0.113.1:18080/")
  '';
}
