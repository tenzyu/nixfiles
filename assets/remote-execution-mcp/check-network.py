import argparse
import ipaddress
import json
import subprocess
import sys


def inventory(ip, *args):
    result = subprocess.run([ip, "-j", "-4", *args], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def conflicts(expected, bridge, addresses, routes):
    network = expected.network
    for link in addresses:
        name = link["ifname"]
        for info in link["addr_info"]:
            address = ipaddress.IPv4Interface(f'{info["local"]}/{info["prefixlen"]}')
            if name == bridge:
                if address != expected:
                    yield f"{name}: unexpected address {address}"
            elif network.overlaps(address.network):
                yield f"{name}: overlapping address {address}"
    for route in routes:
        destination = route["dst"]
        prefix = ipaddress.IPv4Network("0.0.0.0/0" if destination == "default" else destination, strict=True)
        device = route.get("dev")
        if prefix.prefixlen == 0:
            if device == bridge or any(hop.get("dev") == bridge for hop in route.get("nexthops", [])):
                yield f"{bridge}: unexpected default route"
            continue
        if not network.overlaps(prefix):
            continue
        if device == bridge and (
            (prefix == network and route.get("protocol") == "kernel" and not route.get("gateway"))
            or (prefix.prefixlen == 32 and prefix.network_address in (
                expected.ip, network.network_address, network.broadcast_address
            ) and route.get("type") in ("local", "broadcast"))
        ):
            continue
        yield f"overlapping route: {json.dumps(route, sort_keys=True)}"


def main():
    parser = argparse.ArgumentParser(description="Read-only admission check for a dedicated IPv4 bridge.")
    parser.add_argument("--ip", required=True)
    parser.add_argument("--bridge", required=True)
    parser.add_argument("--address", type=ipaddress.IPv4Interface, required=True)
    args = parser.parse_args()
    failures = list(conflicts(
        args.address, args.bridge,
        inventory(args.ip, "address", "show"),
        inventory(args.ip, "route", "show", "table", "all"),
    ))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"No conflicting IPv4 address or route for {args.bridge} ({args.address}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
