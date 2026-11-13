# User-approved integration decisions

Base: `tenzyu/nixfiles` main `d373e872031eb6c4a9839d1ef234ae803647ff9d`. This patch is offline and does **not** deploy either host.

| Area | Selected change | Boundary / remaining risk |
|---|---|---|
| osu!lazer | OpenGL, SDL3 native Wayland, existing 1280×720/fullscreen config | Never add Vulkan/Zink; known-good manual Win+F continues working |
| Hyprland | Add static `fullscreen_state = "2 0"` to existing `immediate` rule | Unverified SDL fullscreen race; if failed, remove only this line and keep manual Win+F |
| Tablet | `hardware.opentabletdriver.daemon.enable = false` | Retain OTD udev rules and blacklist; desktop tablet use may require daemon, restore by reverting |
| Local OBS | Remove obs-vkcapture plugin from managed packages | EGL `eglExportDMABUFImageQueryMESA` SIGSEGV prevents adoption; retain regular OBS |
| Remote OBS | Add stock OBS candidate + disabled nftables guard on port 4455 | Existing patched OBS **remains active** until effective listener/network tests prove isolation and media acceptance |
| SplitCast | Select full Python→Rust rewrite as migration destination | Only a Rust lifecycle and best-effort process-group foundation is implemented; full descendant cleanup requires a cgroup owner; all other functions require feature parity and test gates. Python remains authoritative |
| Kernel/i915 | No unmeasured parameters added | Collect CPUFreq, i915, VAAPI, Direct Scanout and perf counter evidence before edits |
| Capture | GSR KMS/VAAPI lab as baseline; alternatives in RFC | No proof of true zero-copy or Direct Scanout preservation without hardware trials |

## Stock OBS security test contract

The stock candidate is built separately (`nix build .#splitcast-obs-stock-candidate`). The optional `splitcast-stock-obs-firewall` module is **disabled** on all hosts and must not be enabled without inspecting the effect of switching `networking.nftables.enable` (firewall backend) on networking, SSH/Tailscale, VM services and existing firewall rules.

If enabled on a dedicated evaluation generation of neko7, nftables creates an independent `inet splitcast-obs-websocket-guard` input hook at priority -150 to drop inbound TCP/4455 unless the interface is loopback, including tailscale0. The rule is IPv4/IPv6 and does not block local OBS→MediaMTX or outbound Twitch. The OBS WebSocket itself must still require a private password. Host-side `ss`, nft introspection and **independent remote probes from neko5 and other reachable networks** must verify ingress denial and local OBS WebSocket success. Include reboot persistence. **No automatic selection of stock OBS is made in this patch.**

The existing `packages/splitcast/default.nix` and `modules/50-features/splitcast/_internal/obs.nix` remain unchanged. `nix build .#splitcast-obs` still builds the patched legacy OBS.

## Application / rollback

1. `git apply --check` the patch against the exact base revision, then `git apply`. Build before switching.
2. Review `nix diff-closures`/`nh os build`; test `nix eval` and new Rust package build separately, before applying on host.
3. `nh os switch` only for the approved OTD/Fullscreen/local OBS removals. Stop any previously running OTD daemon explicitly after activation; reboot if required for udev/group/kernel module changes.
4. If the tablet no longer moves as required, re-enable daemon; if fullscreen changes 1280×720 input mapping, revert `fullscreen_state` and use Win+F; if OBS workflows require the removed plugin, revert the one Nix module and rebuild.
5. Do not enable SplitCast capture, the Rust agent, or the stock OBS firewall candidate automatically. Perform acceptance and security verification first.
