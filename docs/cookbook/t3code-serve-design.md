# Why T3 Code uses the Tailscale node CLI

The pinned NixOS option
`services.tailscale.serve` exists. In a test evaluation,
`services.tailscale.serve.services.t3code.endpoints."tcp:8445"` generated
a `svc:t3code` entry and a unit running `tailscale serve set-config --all`.
The `configFile` option feeds the same command. Tailscale 1.104.5 applies
named Services with that command and ignores legacy node-level TCP/Web fields.
On neko7, `tailscale serve get-config --all` returned zero named Services,
while `tailscale serve status --json` showed the working node-level 8445
proxy. Moving clients to a named Service would require a separately approved
endpoint migration. [Pinned NixOS module](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/nixos/modules/services/networking/tailscale-serve.nix)
· [Tailscale CLI implementation](https://github.com/tailscale/tailscale/blob/v1.104.5/cmd/tailscale/cli/serve_v2.go#L825-L918).

See the [remote access procedure](t3code-neko7.md#remote-access).
