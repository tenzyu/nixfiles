# neko5 compositor experiments

Jay is the normal neko5 generation; Gamescope is the only specialisation.
The two boot profiles share the physical host, canonical HOME routes, kernel,
Mesa/i915 system driver, official osu! package, HID, audio, thermal, network
and SSH policy. No new flake inputs, kernel watermark tuning or HOME migration.
Only one native DRM session runs at a time.

| Boot entry | Role | Desktop usability |
|---|---|---|
| neko5 | Jay 1.15.0 reference | Ten numbered workspaces, Super+Q close |
| neko5-gamescope | Gamescope 3.16.23 standalone DRM game probe | **Not eligible:** no desktop workspaces; internal Xwayland required even for native clients |

Jay is the selected daily baseline and primary boot. Hyprland modules remain
in the repository but are disabled on neko5; no dedicated fallback entry. Sway, KWin and Weston were retired
by the operator; their experimental code remains in Git history, not in
new generations. Gamescope remains a standalone presentation research
probe, not an eligible desktop replacement. It uses native xdg-shell
(`--expose-wayland`, unset DISPLAY for osu!, no nested compositor) and
requires an internal Xwayland server in the pinned source (main.cpp
accesses server 0). Do not add desktop features merely to qualify it.

## Fixed experimental contract

- Same internal panel eDP-1, **1366x768 native, approximately 60 Hz, scale 1**.
  Disconnect external displays. Verify actual mode using `wayland-info`,
  `jay randr`, or Gamescope DRM logs as applicable.
- Same official osu!lazer install and HOME data, embedded OTD, same renderer,
  fullscreen, 1366x768, **Frame limiter 8x** (`Limit8x`, approximately 480 Draw
  Hz at 60 Hz); do not change game config or renderer between profiles.
  Confirm the in-game settings on every boot. These mutable game settings
  are operator-verified, not overwritten by Nix.
- PipeWire stays at 48 kHz. The observed `alsa_playback.osu!` stream has
  `node.max-latency = "64/48000"` via a Home Manager XDG client drop-in,
  capping normal graph negotiation at 64 frames while linked (Q64 expected,
  smaller negotiated values possible). Its native `node.latency = 441/44100`
  is untouched; `pw-top` should show driver Q64 and osu! follower 441.
  Independent driver graphs such as the USB mic negotiate normally; clients
  sharing the same playback driver share its cycle. No global quantum override.
  ALSA period-size 128/count 3 retained. Previous boot generations retained.
  Restart osu! after applying or rolling back the drop-in; no daemon restart
  is normally needed. Verify actual output/capture QUANT and ERR deltas in
  `pw-top` and the node properties in `pw-dump`.
- Direct scanout requested where supported, tearing permitted for fullscreen,
  no VRR requested, no overlays/capture during performance runs. Neither
  eligibility nor permission proves actual hardware scanout or async flips.
  Record each separately. Do not add forced composition or change the GPU.
- Same song/map, mods, skin, renderer, peripherals, power source, ambient
  conditions, initial thermal state and background apps. Record package and
  renderer versions; do not modify the app between boots.

Jay direct scanout and stable 480 Hz Draw were reported by the operator on the
earlier specialisation. This is the reference observation, not proof that the
new revision has passed.

## Start and rollback

Build from the PR checkout without activation first:

```sh
nix eval --raw .#nixosConfigurations.neko5.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.neko5.config.specialisation.neko5-gamescope.configuration.system.build.toplevel.drvPath
nix build --no-link .#nixosConfigurations.neko5.config.system.build.toplevel
sudo nixos-rebuild boot --flake .#neko5
```

Staging the parent generation builds Jay and the Gamescope specialisation (extra closure
and build time). Only run the last command after reviewing CI, build and
existing HOME admission requirements. Do not switch during an active session.
Reboot into the desired systemd-boot entry and log in on the local VT.
Run `start-jay` on normal neko5, or `start-gamescope` on neko5-gamescope
(which launches osu! directly). Independent modules and commands;
no nested compositor or shared launcher.
Jay shortcuts:

| Shortcut | Action |
|---|---|
| Super+Q | Close focused window (never exit session) |
| Super+1..9,0 | Switch workspace 1..10 |
| Super+Shift+1..9,0 | Move focused window to workspace and follow |
| Super+F | Fullscreen |
| Super+Enter | Alacritty |
| Super+Space | tofi application launcher |
| Super+V | Clipboard history via richclip/tofi |
| Super+Shift+S / Print | Copy area / full display screenshot |
| Super+Tab / Super+Shift+Tab | Cycle numbered workspaces forward / backward |
| Super+Shift+V | Vertical split |
| Super+B / Super+O | Firefox / osu! |
| Super+H/J/K/L | Directional focus |
| Super+Ctrl+Shift+Q | Explicit session exit |

Jay's native named-action cycle tracks the last workspace selected by its
keyboard bindings (1–10, including empty workspaces); mouse/bar changes
are not reflected in this state. Numbered keys resynchronize the cycle.
The single richclipd Wayland capture process starts on Jay's privileged socket;
the tofi picker runs on the ordinary socket and restores an item by UUID via
richclip IPC. Screenshots still use grim/slurp and wl-copy, not Hyprland's
grimblast. Selection cancellation leaves the clipboard unchanged. Existing
cliphist data is untouched and its CLI remains available for legacy history.

For Gamescope exit the game; it does not have desktop workspace controls.

For recovery use another VT (Ctrl+Alt+F2) or SSH. `loginctl list-sessions`
and `loginctl terminate-session SESSION_ID` only for the experimental
local session after saving work; do not terminate SSH. Reboot into the previous known-good generation if needed. No Hyprland
fallback specialisation is generated. No automatic lock UI
in these trial sessions: do not leave them unattended. Portal/IME/lock/suspend
and authorization remain runtime acceptance checks; Gamescope
uses generic GTK portal only in this trial (no promised screen sharing).

## Record comparable results

After five idle minutes, close foreground apps and collect three samples
30 seconds apart over neko7 SSH for Jay:

```sh
ssh neko5 'python3 /home/tenzyu/.nixfiles/scripts/desktop/slim-memory.py'
```

Use the actual PR checkout path if different. The Gamescope game-only probe
cannot supply an equivalent empty desktop idle reading. The script is
read-only; PSS is limited to readable processes unless run with sudo.
Use effective used and non-cache residual separately. Target 600 MiB
effective used, no cache dropping or VM reserve tuning.

For every valid game run record actual resolution/rate/scale, graphics API,
native Wayland confirmation, actual quantum/rate, scanout and async flip
evidence, Draw/Update frequencies, p95/p99 frame times, audio ERR delta by
node (not just total), session length, thermal state and input feel. Prefer
the same 40-minute play workload where feasible. Record an actual
input-to-photon measurement only if instrumented. Jay: Control Center
Visualize Compositing plus debug log; Gamescope: DRM logs. Diagnostic overlays and verbose logging can perturb
performance: collect eligibility separately, turn diagnostics off for the
timing run. A missing telemetry channel is unknown, not a pass.

Reject a candidate for missing workspaces or unsafe close/exit behavior,
failure of native fullscreen / input / audio or any material frame pacing
regression. Direct scanout and 64-frame operation are acceptance criteria,
not presumed from configuration. Do not tune one candidate's game or
audio settings to hide failures. Only after these experiments, decide
whether a dedicated osu!-specific end-to-end presentation implementation
is worthwhile; this PR does not start that project.

CI evaluates each specialisation and the shared audio/identity invariants,
and parses evaluated Jay TOML. Physical KMS, audio,
keybinding delivery, package build and game performance are not proven by
Nix evaluation alone.

## Baseline selection and desktop integration

The operator reports Gamescope felt best but sacrifices too much desktop
functionality; Jay is the selected daily baseline. Restore Jay upstream
`variant3` tearing policy (the previous configuration used this default).
Keep all other performance settings unchanged: native mode, direct scanout,
Limit8x and Q64. The operator reported recovery of stable 480 Hz Draw after
the regression discussion; the exact runtime settings were not captured.

Jay's Xcursor loader uses explicit Adwaita 24 and a store-backed search path
before compositor startup; do not disable hardware cursor as a workaround.
Fcitx5 is started from Jay's graphics-initialized hook using the existing
Mozc-enabled package. The tagged ordinary-socket attempt did not restore Japanese input. Start only
the trusted Nix-packaged Fcitx5 with Jay's documented privileged socket
(`privileged = true`); this grants all Jay protocol capabilities to that
process, not root. Super+Ctrl+I restarts Fcitx5, Super+I toggles its active
state via fcitx5-remote. QT_IM_MODULE=fcitx is scoped to Jay session apps;
GTK native text-input-v3 remains the first path. Existing
user IME profile/dictionaries are retained; use fcitx5-configtool to select
Mozc if it is absent. Verify cursor in empty workspace and Firefox; verify
Ctrl+Space or the existing IME trigger, preedit and Japanese commit in Firefox
and other native clients. For GTK fallback, launch a new GTK app with GTK_IM_MODULE=fcitx and test.
Run fcitx5-diagnose, fcitx5-remote and fcitx5-remote -n if still broken.
Do not replace existing dictionaries or force user profile changes.
Recheck 480 Hz Draw, direct scanout, and Q64 with the new IME process resident.
No hardware-cursor, scheduler or kernel tuning is changed.

## Research record

See [append-only presentation research log](../research/neko5-presentation-log.md).
Discord VC + osu! ERR remains unresolved. The former global Q64 and
osu!-scoped forced quantum are superseded by a playback-scoped negotiation
ceiling. Operator reports the transient max-latency trial matches the expected
driver Q64 / follower 441. Verify the deployed XDG rule, Discord-only and
combined graphs, quantum restoration after osu! exits, and steady-state
40-minute ERR deltas, audible continuity and frame pacing. Keep RT priorities,
kernel and ALSA policy unchanged. Do not use the legacy global-quantum lab
for this acceptance test.

## Daily software replacements

The normal neko5 generation selects Alacritty, Fileman, tofi, dua-cli,
richclip and GitUI. Kitty, Dolphin, Rofi, ncdu and Lazygit are no longer
selected on this host. Ark and the existing osu! skin MIME association remain:
Fileman does not handle opening an arbitrary archive on its command line or
recognize .osk as an archive in this upstream revision. QDirStat and dust
remain available for treemap and summary use. The GTK FileChooser portal is
unchanged. No historical clipboard migration or deletion is performed.

Fileman v0.5.2 and richclip v0.1.3 use the official x86_64 Linux release
archives, pinned by SHA-256. Nix repackages the ELF binaries using
autoPatchelfHook; no Rust compilation, Cargo tests or upstream shell installer
runs locally. Fileman matches the previous source revision; richclip uses the
release tag instead of the two later main-branch commits, so post-release
history deduplication and restore-ordering changes are not included.
The previous source packages remain available in Git history.
CI builds the repackaged derivations and checks the installed binaries;
actual Wayland behavior still requires a local smoke test.
Richclip's upstream capture policy skips token-like runs of 30 or more ASCII
characters (including some commit hashes), caps each format at 4 MiB and
expires items after 30 days by default. Direct clipboard copy/paste remains
independent of history. If richclipd survives a compositor shutdown, stop the
old instance before starting Jay again; its single-instance socket rejects
duplicate daemons. No cloud labelling worker is installed.

Smoke test after building and booting: Super+Enter, Super+Space,
Super+V (text, HTML and screenshot restore, cancel), Fileman copy/move/trash,
archive extraction, .osk association, USB/network share, `dua i` and `lg`.
Check Japanese input and Herdr clipboard as before. Keep existing generation
for rollback. No full performance A/B is required for this selection;
actual game/audio/Wayland behavior still needs a local smoke test.

## Herdr clipboard

The Jay-enabled Herdr launcher reuses the unmodified llm-agents Herdr
package (v0.9.5 at the current lock). A private PATH prefix makes only the
exact native wl-copy call from the stock Herdr executable on Jay fail,
selecting Herdr's existing OSC 52 fallback. Ordinary wl-copy calls,
including pane commands, still invoke the real wl-copy. There is no Rust
source patch or new clipboard transport, and the existing Numtide
substituter can serve the unchanged stock derivation if cached.
See upstream herdrdev/herdr #6035 for a first-class clipboard backend
selector request. Remove the launcher adapter once an upstream release
provides that option. SSH already prefers OSC 52 upstream; neko7 and
non-Jay packages remain unmodified. Alacritty allows OSC 52 writes only;
its focused window owns the Wayland selection. Richclipd observes normal
selections, preserving its capture filters.

Super+V reads at most 129 history records initially, displays the newest
128, and offers "Show all history" if older entries exist. No records are
deleted. Recent-list timeout is 2 seconds (plus up to 1 second to kill),
full-list timeout is 10 seconds, restore timeout is 5 seconds. Empty
history and CLI failures produce a notification. The picker has its own
nonblocking lock, independent of tofi-drun's shared lock; its menu does
not persist a second history. These are bounded-work mitigations, not a
measured diagnosis of the operator's intermittent launch failure.
To compare history-load costs without displaying clipboard contents:

```sh
time richclip list --json --limit 129 >/dev/null
time richclip list --json >/dev/null
```

Test repeated Super+V (20 opens/cancels), older history, text and screenshot
restoration, Super+Space, and an ordinary wl-copy from a Herdr pane.
An actual cache hit and live Wayland acceptance remain operator checks.

After building and activating, open a fresh Alacritty via Super+Enter and
attach with the new Herdr client (do not terminate running agents just to
test clipboard). First run this outside Herdr, then inside its pane:

```sh
printf '\033]52;c;%s\a' "$(printf 'Herdr clipboard 日本語\nsecond line' | base64 -w0)"
```

With the terminal focused during execution, paste into Firefox and compare
both lines exactly. Repeat using Herdr mouse selection and keyboard copy
mode, locally and via the actual remote route; test multiline JSON, then
Super+V history restore and both screenshot shortcuts. A long token-like
string may paste correctly but be intentionally absent from richclip history.
Do not treat a Herdr success toast as delivery confirmation. If direct OSC 52
fails, inspect Alacritty focus/policy and Jay selection before altering
privileges. Nested terminal multiplexers require independent OSC 52
forwarding support. This is a source-level routing fix, not a demonstrated
runtime root cause; physical acceptance is pending.
