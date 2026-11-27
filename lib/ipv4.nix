{lib}: let
  # Canonical decimal syntax only. Parse once before rendering firewall rules.
  decimal = value: builtins.fromJSON value;
  parse = value: let
    parts = if builtins.isString value then builtins.match "(0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})/(0|[1-9][0-9]?)" value else null;
    octets = map decimal (lib.take 4 parts);
    prefix = decimal (builtins.elemAt parts 4);
    number = lib.foldl' (acc: octet: acc * 256 + octet) 0 octets;
    size = lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - prefix));
    first = builtins.div number size * size;
  in
    if parts == null || !lib.all (n: n <= 255) octets || prefix > 32 then null
    else {
      address = lib.concatMapStringsSep "." toString octets;
      inherit prefix number first;
      last = first + size - 1;
    };
  contains = outer: inner: outer.first <= inner.first && outer.last >= inner.last;
  overlaps = a: b: a.first <= b.last && b.first <= a.last;
  isNetwork = p: p != null && p.number == p.first;
  isPrivateHost = p: p != null && p.prefix <= 30 && p.number > p.first && p.number < p.last
    && lib.any (private: contains (parse private) p) ["10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16"];
  cidr = lib.types.addCheck lib.types.str (s: isNetwork (parse s));
  privateHostCidr = lib.types.addCheck lib.types.str (s: isPrivateHost (parse s));
in {
  inherit parse contains overlaps isNetwork isPrivateHost cidr privateHostCidr;
}
