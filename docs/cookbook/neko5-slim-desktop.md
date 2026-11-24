# neko5 compositor experiments

Keep the ordinary neko5 Hyprland generation as recovery. The five boot
specialisations share the physical host, canonical HOME routes, kernel,
Mesa/i915 system driver, official osu! package, HID, audio, thermal, network
and SSH policy. No new flake inputs, kernel watermark tuning or HOME migration.
Only one native DRM session runs at a time.

| Boot entry | Role | Desktop usability |
|---|---|---|
| neko5-slim | Jay 1.15.0 reference | Ten numbered workspaces, Super+Q close |
| neko5-sway | wlroots / Sway | Ten numbered workspaces, Super+Q close |
| neko5-kwin | Standalone KWin (no Plasma session) | Ten desktops, Super+Q close via KWin script; verify shortcut registration |
| neko5-weston | Weston 15.0.1 DRM desktop-shell probe | **Not eligible:** upstream has only one workspace; no equivalent Super+Q binding |
| neko5-gamescope | Gamescope 3.16.23 standalone DRM game probe | **Not eligible:** no desktop workspaces; internal Xwayland required even for native clients |

The two probes are bootable attempts to compare presentation behavior, not
accepted desktop candidates. Do not rank them as satisfying the common
usability contract. Gamescope uses its native xdg-shell client path
(`--expose-wayland`, unset DISPLAY for osu!, no nested compositor). It requires
an internal Xwayland server in the pinned source (main.cpp accesses server 0).
Weston 15.0.1 desktop-shell/shell.c uses a single workspace object. Do not
patch in missing desktop features just to qualify the probes.

## Fixed experimental contract

- Same internal panel eDP-1, **1366x768 native, approximately 60 Hz, scale 1**.
  Disconnect external displays. Verify actual mode using `wayland-info`,
  `jay randr`, `swaymsg -t get_outputs`, KScreen/DRM logs as applicable.
  KWin chooses the preferred mode; if not native, correct it before testing.
- Same official osu!lazer install and HOME data, embedded OTD, same renderer,
  fullscreen, 1366x768, **Frame limiter 8x** (`Limit8x`, approximately 480 Draw
  Hz at 60 Hz); do not change game config or renderer between profiles.
  Confirm the in-game settings on every boot. These mutable game settings
  are operator-verified, not overwritten by Nix.
- PipeWire **64 frames / 48000 Hz**, min/default/max 64 in every specialisation.
  Verify active output and osu! in `pw-top` while playing. ALSA period-size 128,
  count 3 retained from existing policy. If graph rate or quantum differs,
  invalidate the run. Do not silently lower constraints. Ordinary Hyprland
  fallback is untouched; manually match settings if used as an extra control.
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
for p in slim sway kwin weston gamescope; do
  nix eval --raw ".#nixosConfigurations.neko5.config.specialisation.neko5-$p.configuration.system.build.toplevel.drvPath"
done
# Choose one to build first, or build the entire generation to stage all entries.
nix build --no-link .#nixosConfigurations.neko5.config.specialisation.neko5-sway.configuration.system.build.toplevel
sudo nixos-rebuild boot --flake .#neko5
```

Staging the parent generation builds all five specialisations (extra closure
and build time). Only run the last command after reviewing CI, build and
existing HOME admission requirements. Do not switch during an active session.
Reboot into the desired systemd-boot entry; log in on the local VT and run
`exec neko5-slim-session` for **every** experiment. Gamescope starts osu!
directly; the other entries start their desktop. No nested sessions.
For the three desktop candidates:

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
| Super+Ctrl+Shift+Q | Explicit exit in Jay/Sway only |

KWin uses a native KWin script plus on-demand systemd user application units,
and an /etc/xdg/kwinrc default. Existing local KDE settings may override
defaults; verify ten desktops and every shortcut before counting a result.
KWin uses stacking rather than Jay/Sway tiling; launcher units allow one
running instance per app. For Weston use panel launchers and Super+Shift+F
(fullscreen); its titlebar close action, not Super+K (force kill).
For Gamescope exit the game; neither probe has equivalent workspace controls.

For recovery use another VT (Ctrl+Alt+F2) or SSH. `loginctl list-sessions`
and `loginctl terminate-session SESSION_ID` only for the experimental
local session after saving work; do not terminate SSH. Reboot into ordinary
neko5 or the previous known-good generation if needed. No automatic lock UI
in these trial sessions: do not leave them unattended. Portal/IME/lock/suspend
and authorization remain runtime acceptance checks; KWin/Weston/Gamescope
use generic GTK portal only in this trial (no promised screen sharing).

## Record comparable results

After five idle minutes, close foreground apps and collect three samples
30 seconds apart over neko7 SSH for each desktop candidate:

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
Visualize Compositing plus debug log; Sway: get_outputs and debug logs;
KWin: support information/DRM debug logs; Weston: DRM log/scopes;
Gamescope: DRM logs. Diagnostic overlays and verbose logging can perturb
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
parses evaluated Jay TOML and syntax-checks KWin JS. Physical KMS, audio,
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
Mozc-enabled package. Its tagged ordinary connection receives input-method
capability (plus normal desktop capabilities) rather than all privileged
protocols. Super+Ctrl+I restarts the tagged Fcitx instance if needed. Existing
user IME profile/dictionaries are retained; use fcitx5-configtool to select
Mozc if it is absent. Verify cursor in empty workspace and Firefox; verify
Ctrl+Space or the existing IME trigger, preedit and Japanese commit in Firefox
and other native clients. Some toolkits may need per-app IM module settings.
Recheck 480 Hz Draw, direct scanout, and Q64 with the new IME process resident.
No hardware-cursor, scheduler or kernel tuning is changed.
