# Operate and verify the neko5 desktop and Gamescope

Jay is the daily desktop. Gamescope is a separate native DRM research
specialisation. Hyprland remains selectable in
source but disabled on neko5, with no dedicated fallback. Sway, KWin and
Weston are retired. Both boot entries preserve HOME, kernel, Mesa/i915,
official osu! package, HID, audio, thermal, network and SSH policy.

The workstation selects desktop tools, OBS Studio, and EasyEffects independently.
The kernel/resource experiment is intentionally outside this integration.

## Source ownership and fixed settings

Use the [neko5 desktop configuration reference](neko5-desktop-reference.md#source-ownership-and-fixed-settings) to check the expected settings before a build or activation.

## Build, enter and recover

Build without activation from the PR checkout:

```sh
nix eval --raw .#nixosConfigurations.neko5.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.neko5.config.specialisation.neko5-gamescope.configuration.system.build.toplevel.drvPath
nix build --no-link .#nixosConfigurations.neko5.config.system.build.toplevel
```

Wait for CI, the build, HOME admission review, and separate operator approval.
Then run `sudo nixos-rebuild boot --flake .#neko5` to stage both profiles.
Do not switch during a session. After reboot, log in on a local text VT.
Run `start-jay` on normal neko5 or `start-gamescope` on the research specialisation.
`start-gamescope` launches osu! directly. No nested compositor or shared launcher. Gamescope exits with the
game, uses native xdg-shell, unsets DISPLAY for osu!, and still needs its
internal Xwayland server (pinned source accesses server 0). It has no
desktop workspaces or promised screen sharing.

To recover, open another VT with **Ctrl+Alt+F2** or connect over SSH.
Save your work before you run `loginctl terminate-session SESSION_ID`.
Never terminate the SSH session. Reboot to the previous known-good generation if necessary.
Rollback does not reverse mutable data. No automatic lock UI is promised:
do not leave sessions unattended. Lock/suspend/authorization are live
acceptance checks.

## Daily interaction

| Shortcut | Action |
| --- | --- |
| Super+Enter / Super+Space | Alacritty / Rofi application launcher |
| Super+V | cclip history via Rofi |
| Super+R / Super+Shift+R | Native Rofi run / custom actions |
| Super+Shift+Space / Super+Ctrl+Shift+R | Desktop actions / native Jay reload |
| Super+Shift+S / Print | Copy area / full screenshot |
| Super+1..9,0 / Super+Shift+1..9,0 | Select workspace / move and follow |
| Super+Tab / Super+Shift+Tab | Cycle forward or backward through workspaces 1 to 10 |
| Super+H/J/K/L / Super+Shift+V | Focus / vertical split |
| Super+B / Super+O | Firefox / osu! |
| Super+F / Super+Q / Super+Ctrl+Shift+Q | Fullscreen / close window / exit session |
| Super+Ctrl+I / Super+I | Restart Fcitx5 / toggle IME |

The native workspace cycle tracks keyboard selections only.
Changes made with the mouse or bar do not update its state.
Use a numbered workspace key to resynchronise. Run mode uses Rofi's stock command runner; use an explicit shell or
terminal for shell operators. Custom and desktop action menus use fixed allowlists.

## Clipboard, cursor and Japanese input

Only trusted capture/restore, screenshots and Fcitx5 use the privileged
Wayland socket (all Jay protocol capabilities, not root). Rofi runs on the
ordinary socket. cclipd uses a private 0700 directory and singleton flock;
regular clipboard only, 512-entry retention target, 160-byte previews.
One MIME representation is retained; grouped HTML/file semantics are not
preserved. Upstream password-manager hints are honoured, but unmarked
secrets can be captured; upstream payload/queue sizes are not hard-bounded.
The picker queries previews with a two-second deadline, validates the
numeric ID against its snapshot, releases the lock FD before restore and
leaves clipboard unchanged on cancel. No old history migration/deletion.

Herdr 0.9.5 lacks a first-class OSC 52 preference (upstream #6035).
A private PATH shim rejects only the exact stock Herdr native wl-copy call
on Jay; normal pane callers are unaffected. Herdr then uses its built-in
OSC 52 fallback. Alacritty permits writes only, with no terminal-initiated
reads. Keep stock derivation/substitution; remove the shim when upstream
supports backend selection. SSH already prefers OSC 52 upstream.

Jay loads Adwaita 24 from a store-backed Xcursor path before launch;
do not disable hardware cursor. Fcitx5 uses the existing Mozc package,
privileged startup hook after D-Bus environment import and clipboard.
QT_IM_MODULE=fcitx is scoped to Jay; native GTK text-input-v3 is preferred.
The tagged ordinary-socket trial failed Japanese input. Keep dictionaries;
if needed, check fcitx5-configtool, fcitx5-diagnose, fcitx5-remote and
fcitx5-remote -n. Test GTK fallback with GTK_IM_MODULE=fcitx on a new app.

After approved boot, smoke-test launcher modes and reload, 20 clipboard
open/cancel cycles, multiline Japanese/JSON, long SHA, screenshot restore,
Fileman copy/move/trash, archive/.osk, USB/network shares, dua i and lg.
In a focused fresh Alacritty, outside then inside a Herdr pane:

```sh
printf '\033]52;c;%s\a' "$(printf 'Herdr clipboard 日本語\nsecond line' | base64 -w0)"
```

Paste into Firefox; compare both lines, repeat Herdr mouse/keyboard copy
locally and through the real remote route, then restore via Super+V.
A success toast is not delivery proof. Do not terminate existing agents;
inspect focus/policy and selection before changing privileges. Nested
multiplexers must independently support OSC 52 forwarding.

## Audio transition and live acceptance

Portal realtime PID-namespace lookup failed with ENOTDIR; direct RTKit
restored both data-loops to RR/20. H0 trial observed zero ERR across 299
valid playback samples with Discord VC/video. See the [dated research
log](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/research/neko5-presentation-log.md); these are not fresh runtime
receipts. No new daemon, RT limit or app patch.

Before approved switch, stop osu!/VC/video. Review and remove only the
temporary trial drop-ins if present, using the actual XDG directory:
`pipewire/client.conf.d/99-neko5-rtkit-probe.*.conf`,
`pipewire/pipewire-pulse.conf.d/99-neko5-rtkit-probe.conf`,
`wireplumber/wireplumber.conf.d/99-neko5-headroom-probe.conf`.
After applying the configuration, restart PipeWire-Pulse.
Relaunch affected clients. During play, verify data loops at RR/20,
sink H0, driver Q64, and follower 441.
Test Discord-only / osu! exit / restart graph lifecycle, capture graph,
40-minute ERR deltas, audible continuity and pacing. Roll back generation
and restart affected processes on regression. Do not invoke the old global
quantum lab for this test. The portal remains available for other uses.

## Presentation acceptance and rollback

After separately approved activation, relaunch osu! through `osu-lazer`.
Verify effective eDP-1 variant2, the process environment, XRGB8888 Y_TILED
(without CCS), actual Direct Scanout and steady ~480 successful async flips/s
(DRM flags 0x203). The setting and Draw count alone are insufficient. Use the same
fullscreen map, native mode, OpenGL and Limit8x. Verify ordinary desktop,
other fullscreen clients, Discord/IME, audio and thermal behaviour; variant2
can attempt unsupported async flips and fall back to sync. Reject material
regressions, EINVAL loops for osu!, or loss of Direct Scanout. Restore
`tearingMode = null` and `disableIntelCcs = false` together (or use the
previous generation) and relaunch/reload; for immediate session rollback use
`jay randr output eDP-1 tearing set-mode variant3` and restart osu! without
`noccs` using the prior launcher. Do not disable synchronization or change
kernel parameters. Host activation is not implied by Git or CI.

## Measurement procedure

For A/B: disconnect external displays; verify actual mode, renderer and
native Wayland, same map/mods/skin/peripherals/power/thermal/background
apps, no capture or overlays. Record actual rate/quantum, Direct Scanout
and async flip separately, Draw/Update frequency, p95/p99 frame times,
per-node ERR delta, input feel and temperature. Jay Control Center
Visualize Compositing/debug log; Gamescope DRM logs. Disable instrumentation
during timing runs. Physical latency requires independent instrumentation.
Record missing telemetry as unknown rather than PASS. Reject missing workspaces for daily
desktop, unsafe close/exit, native fullscreen/input/audio failure or material
pacing regression. Gamescope is a probe only.

For the idle-memory measurement, close foreground applications after five minutes.
Take three samples at 30-second intervals over SSH from neko7:

```sh
ssh neko5 'python3 /home/tenzyu/.nixfiles/scripts/desktop/memory-snapshot.py'
```

Use actual checkout path. PSS covers readable processes only; distinguish
effective used (MemTotal − MemAvailable) from non-cache residual.
600 MiB is the historical target, 400 MiB exploratory; no cache dropping or
watermark manipulation. Gamescope lacks an equivalent empty desktop idle
state. Jay's earlier 480 Hz Draw and direct scanout are dated observations.

CI checks both profiles, parsed TOML, audio and identity invariants,
selected package builds and offline routing. It does not prove KMS,
physical latency, audio, IME, permission delivery, memory or host acceptance.
