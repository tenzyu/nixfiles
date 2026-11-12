# Hyprland 0.57.2 × osu!lazer fullscreen regression (2026-11-12)

Source: `tenzyu/nixfiles` main `956dac3d3ba51f52af2d89109c5635f6d614ba94`.
The 2026-11-12 flake update changed Hyprland **0.56.2 → 0.57.2** while preserving osu!'s static window rule `fullscreen_state="2 0"`, `immediate=true`, and `Win+F` without an explicit action. The issue has been reported by the user after the update; **the root cause has not been confirmed on hardware**.

## Source-level causality

- `src/config/lua/bindings/LuaBindingsDispatchers.cpp::dsp_fullscreenState` in Hyprland v0.57.2 toggles the internal/client values **independently**. Thus current `2/2` with target `2/0` and action `toggle` produces `0/0`, rather than `2/0`. Current `2/0` with action `toggle` likewise becomes `0/0`.
- `src/config/lua/objects/LuaWindow.cpp` exposes `win.fullscreen` (internal integer) and `win.fullscreen_client` (client integer); use these to derive desired behavior instead of relying on the default toggle.
- The window rule `fullscreen_state="2 0"` is applied on map; SDL's own Wayland fullscreen request can alter state afterward. Enforcing at map duplicates fullscreen authority.
- `immediate = true` **allows tearing**, does not enable Direct Scanout. Hyprland's tearing documentation warns unsupported GPU/drivers can freeze games. The user's previous scanout samples showed active scanout without active tearing.
- In Hyprland 0.57.x upstream, fullscreen-specific fixes are documented (0.57.2, PR #16870); a regression with a tiled client fullscreen was reported for 0.57.0 (#16842). They support compatibility risk but do **not** demonstrate this specific failure mode for neko5.

## Patch behavior

1. Remove static fullscreen_state and immediate rule for osu only, keeping the module registration.
2. For osu only, `Win+F` operates as **an explicit state-aware set**: if currently `2/0`, exit with `0/0`; otherwise set `2/0`, including from SDL's `2/2` or `0/2`.
3. For all other windows, preserve the previous toggle behavior.
4. Keep `render.direct_scanout=1`, `general.allow_tearing=true` for other applications, native SDL3/Wayland/OpenGL, osu! 1280×720 and in-process OTD. No changes to BASS, PipeWire, Input, Update, Draw or SplitCast.

## Apply (no auto-push or switch)

Prefer `bash apply-safe.sh ~/.nixfiles` from the extracted ZIP. It checks HEAD, clean worktree, verifies the current architecture HTML Git blob, applies the patch, and updates the original `docs/graphics-streaming/architecture/index.html` with the revised complete 13-tab HTML. The raw `.patch` alone adds the code and docs but does not update the large HTML asset.

```bash
cd ~/.nixfiles
git rev-parse HEAD  # must equal 956dac3d3ba51f52af2d89109c5635f6d614ba94
git status --short
git apply --check /path/to/neko5-hyprland-0572-fullscreen.patch
git apply /path/to/neko5-hyprland-0572-fullscreen.patch
nix flake check --no-build
nh os build
```

`nh os build` does not activate the new Home Manager Lua config. Following build success, **the user must explicitly activate** using their usual NixOS/Home Manager workflow, then log out of Hyprland and log in again if a hot-reload does not install the new binding. Keep the previous generation as fallback. The patch itself never executes `switch`.

### Acceptance

- Open osu!; at desktop full monitor `eDP-1` stays 1366×768@60.003Hz. The game's internal resolution remains 1280×720.
- `Win+F` yields `fullscreen=2`, `fullscreenClient=0`, no compositor hang, game redraws and accepts input.
- A second `Win+F` exits to `0/0` intentionally; another returns to `2/0`.
- While osu! is focused, `hyprctl -j monitors` should show scanout candidate using the same field semantics as current Hyprland; **absence of Direct Scanout is not accepted** as the final fix. Verify that tearing is not accidentally required.
- DT custom, FUN mod and BASS -256 remain available. User reported strong improvement with -256 and no anomalies in those scenarios; this is positive acceptance for those configurations, not a guarantee for all versions or mod combinations.

### If it still freezes

Run the supplied read-only `fullscreen-observe.sh` before switching to osu. It captures snapshots for 15 seconds after a 7-second focus interval, with individual 2-second hyprctl deadlines and a local tarball. It never changes compositor or game settings. Capture a session that includes one `Win+F` transition. No new full machine inventory is needed.

If the problem remains, send the archive rather than disabling Direct Scanout as a permanent workaround. A temporary compositor-only isolation using `hyprctl eval` and reversible Lua config may be considered after the failure data is inspected. Disabling Direct Scanout violates the final acceptance contract. If the compositor freezes irrecoverably, boot an older NixOS generation from systemd-boot rather than committing unverified kernel/i915 settings.

### SplitCast invariants

Capture remains disabled on neko5. The renderer is not hooked. Production on neko7 does not become a dependency of native fullscreen. KMS/VAAPI proposals remain provisional and must not require turning off Direct Scanout. Existing SplitCast ADR continues to apply.

## Sources

- Repo module: `modules/50-features/osu-lazer-hyprland.nix` and `hyprland-tenzyu.nix`, both verified at above main SHA.
- Hyprland source `src/config/lua/bindings/LuaBindingsDispatchers.cpp`, `src/config/lua/objects/LuaWindow.cpp` at `v0.57.2`.
- https://wiki.hypr.land/0.57.0/configuring/core/dispatchers/
- https://wiki.hypr.land/configuring/core/rules/window-rules/
- https://wiki.hypr.land/0.54.0/Configuring/Tearing/
- https://github.com/hyprwm/Hyprland/releases/tag/v0.57.2
- https://github.com/hyprwm/Hyprland/discussions/16842
