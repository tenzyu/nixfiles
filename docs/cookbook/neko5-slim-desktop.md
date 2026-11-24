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
- PipeWire **64 frames / 48000 Hz**, min/default/max 64 in both profiles.
  Verify active output and osu! in `pw-top` while playing. ALSA period-size 128,
  count 3 retained from existing policy. If graph rate or quantum differs,
  invalidate the run. Do not silently lower constraints. Previous boot generations remain available until the operator deletes them.
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
Reboot into the desired systemd-boot entry; log in on the local VT and run
`exec neko5-slim-session` for **every** experiment. Gamescope starts osu!
directly; Jay starts the desktop. No nested sessions.
Jay shortcuts:

| Shortcut | Action |
|---|---|
| Super+Q | Close focused window (never exit session) |
| Super+1..9,0 | Switch workspace 1..10 |
| Super+Shift+1..9,0 | Move focused window to workspace and follow |
| Super+F | Fullscreen |
| Super+Enter | Alacritty |
| Super+Space | Application launcher |
| Super+B / Super+O | Firefox / osu! |
| Super+H/J/K/L | Directional focus |
| Super+Ctrl+Shift+Q | Explicit session exit |

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
Discord VC + osu! at Q64 is an open stability issue; do not change quantum,
RT priorities, kernel or ALSA policy in the primary migration commit.
