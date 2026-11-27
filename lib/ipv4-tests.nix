{lib}: let
  ip = import ./ipv4.nix {inherit lib;};
  invalid = ["999.1.2.3/24" "10.1.2.3/33" "10.1.2.3/-1" "010.1.2.3/24" "10.1.2.3/024" "10..2.3/24" "10.1.2.3/24; accept" "10.1.2.3" "2001:db8::/32"];
in {
  testInvalid = {expr = map ip.parse invalid; expected = map (_: null) invalid;};
  testHost = {
    expr = map (s: ip.isPrivateHost (ip.parse s)) ["10.77.42.1/24" "10.77.42.0/24" "10.77.42.255/24" "10.77.42.1/31" "10.77.42.1/0" "8.8.8.8/24" "172.16.0.1/12" "192.168.0.1/16"];
    expected = [true false false false false false true true];
  };
  testNetwork = {
    expr = map (s: ip.isNetwork (ip.parse s)) ["0.0.0.0/0" "255.255.255.255/32" "192.168.0.1/24" "203.0.113.0/24"];
    expected = [true true false true];
  };
  testOverlap = {
    expr = map (s: ip.overlaps (ip.parse "10.77.42.1/24") (ip.parse s)) ["10.77.41.1/24" "10.77.42.128/25" "10.77.0.0/16" "10.77.43.0/24" "0.0.0.0/0"];
    expected = [false true true false true];
  };
}
