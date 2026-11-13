# Graphics Lab: standalone diagnostics and independent KMS acceptance

This folder intentionally **does not enable SplitCast** or change the known-good osu! configuration. It consolidates the two prior DirectCast/Kernel-Stream labs and their duplicated Direct Scanout parsers.

## Tools

- `snapshot.sh`: read-only CPUFreq/i915/VA-API/Hyprland inventory. Logs may contain device identifiers; inspect before sharing.
- `scanout.py`: single shared Direct Scanout parser and CLI. Unknown state is not successful Direct Scanout.
- `directcast_lab.py`: optional KMS/GSR→RTMP→SSH→MediaMTX acceptance probe. Uses independent ports **11935/18554**, not SplitCast's 1935/8554. Uses process groups only for children it starts; never kills osu! or existing services.
- `mediamtx.yml`: isolated receiver on `neko7` (`127.0.0.1` only).
- `osu-gl-test.sh`: opt-in GL/native Wayland launcher, without banned Vulkan/X11 variants.
- `obs_stock_boundary.py`: observational local listener+nft rule check, plus independent remote reachability probe. No rule changes or service start; remote failure alone is inconclusive.
- `timerslack_exec.py`: optional isolated timer-slack experiment; **not** a proven optimization, never enabled by a NixOS default.
- `tests/`: parser and command-generation tests; these are not GPU or end-to-end tests.

## Game-only baseline on neko5

```sh
bash scripts/graphics-lab/snapshot.sh "$HOME/kernel-stream-snapshot"
python3 scripts/graphics-lab/scanout.py --monitor eDP-1 --seconds 90 --interval 1 --output "$HOME/ds-game-only.jsonl"
python3 -m unittest discover -s scripts/graphics-lab/tests -v
```

Substitute the actual monitor name from `hyprctl monitors -j`. Start the watcher, return to osu!, and use the already-proven game Fullscreen + Hyprland `Win+F` behavior. No new renderer or in-game resolution is requested.

## Isolated remote capture acceptance (optional; user-initiated)

On `neko7`, copy the **lab's** `mediamtx.yml` and run `mediamtx /path/to/mediamtx.yml`; confirm `ss -lnt` shows only `127.0.0.1:11935` and `127.0.0.1:18554` listeners. Do not stop or replace an existing SplitCast listener.

On `neko5`:

```sh
python3 scripts/graphics-lab/directcast_lab.py --monitor eDP-1 --ssh-host neko7 --dry-run
python3 scripts/graphics-lab/directcast_lab.py --monitor eDP-1 --ssh-host neko7
```

After launch, return to the game before baseline capture. The script refuses a GSR capture target that is not a physical named monitor, sends **hardware H.264 only** and stops its own subprocess groups if the reported Direct Scanout state degrades. It does not measure frame latency, prove zero-copy or automatically configure remote OBS. The physical monitor may show private windows; screen-wide capture is not game-only capture.

On `neko7`, verify feed separately: `ffprobe -v error -rtsp_transport tcp -show_streams rtsp://127.0.0.1:18554/game` during the short test.

For detailed comparison of GPU engine usage and frame p99, keep using the existing `scripts/splitcast/perf.py`; these scripts do not reimplement that collector. Review [system RFC](../../docs/graphics-streaming/SYSTEM-RFC.md) before enabling services or creating a dedicated KMS broker.

All diagnostics are **read-only unless capture is explicitly invoked**. No Nix generation, kernel parameters, permissions, or firewall are altered by these tools.

## Stock OBS WebSocket isolation (separate manual gate, neko7)

The stock OBS candidate is **never enabled by this patch**. Keep the legacy patched OBS active until security parity is proved. On an isolated test generation on neko7, after evaluating the optional nftables feature and starting the stock OBS with an authenticated WebSocket listener:

```sh
python3 scripts/graphics-lab/obs_stock_boundary.py local --output /tmp/obs-stock-local.json
# From neko5, while neko7 still reports local listener active:
python3 scripts/graphics-lab/obs_stock_boundary.py remote --host neko7 --output /tmp/obs-stock-remote.json
```

The local probe exits zero only if localhost TCP/4455 is reachable **and** the expected nftables drop chain is readable. The remote probe intentionally always exits nonzero, even if the connection is blocked: lack of connection could just mean OBS is down. Independently inspect both JSON reports, check that the local and remote probes overlapped, and attempt connections over other relevant interfaces. Verify OBS WebSocket authentication, SSH/Tailscale and reboot persistence before the stock switch. The firewall candidate enables nftables, which may affect existing networking; do not activate without a rollback console.
