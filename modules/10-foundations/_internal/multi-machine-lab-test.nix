{inputs, system}: let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
in pkgs.testers.runNixOSTest {
  name = "multi-machine-lab";
  nodes = {
    server = {
      networking.firewall.allowedTCPPorts = [8080];
      environment.etc."lab/index.html".text = "generic-lab";
      systemd.services.fixture = {
        wantedBy = ["multi-user.target"];
        serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 8080 --directory /etc/lab";
      };
    };
    client = {environment.systemPackages = [pkgs.curl pkgs.iproute2];};
    observer = {environment.systemPackages = [pkgs.curl];};
  };
  testScript = ''
    start_all()
    server.wait_for_unit("fixture.service")
    request = "curl -fsS --connect-timeout 2 --max-time 4 http://server:8080/ | grep -Fx generic-lab"
    client.wait_until_succeeds(request)
    observer.wait_until_succeeds(request)
    # Inject a link-local egress blackhole on one machine only.
    interface = client.succeed("ip -4 route get $(getent ahostsv4 server | head -n1 | cut -d' ' -f1) | sed -n 's/.* dev \\([^ ]*\\).*/\\1/p' | head -n1").strip()
    assert interface and interface != "lo", interface
    pid = server.succeed("systemctl show -p MainPID --value fixture.service").strip()
    client.succeed("tc qdisc replace dev " + interface + " root netem loss 100%")
    client.fail(request)
    observer.succeed(request)
    client.succeed("tc qdisc del dev " + interface + " root")
    client.wait_until_succeeds(request)
    assert server.succeed("systemctl show -p MainPID --value fixture.service").strip() == pid
  '';
}
