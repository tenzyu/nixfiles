# neko5 osu! eDP async-presentation experiment

**Default OFF; not benchmark-validated.** This is the executable companion to the separately maintained 2026-11-13 osu! LLM Wiki (`wiki/DRAW.md`, `wiki/DECISIONS.md`). Do not copy that Wiki's research and raw logs into nixfiles.

The user's 2026-11-13 11:10 JST observation showed 25/25 DSO selection in known-good `fullscreen=2/fullscreenClient=0` samples. `activelyTearing` was false in 30/30. This experiment changes only the compositor's **named, disabled-by-default** `immediate` rule and does not patch osu!, SDL, KMS or i915.

Usage in the active Hyprland session, with osu! **foreground** and DSO working:

```sh
osu-display status
osu-display try 12   # automatically returns to OFF; refuses 2/2 or missing DSO
osu-display on       # requires >=2 tearing-positive samples in a completed short trial
osu-display off      # works even when another app is focused
```

Hotkeys: `Super+Shift+F11` temporary 12s; `Super+Ctrl+F11` gated sustained; `Super+Shift+F12` OFF. Successful status sampling does **not** measure physical optical latency or prove i915 accepted every asynchronous page flip. `NOT_TORN` can be a transient state. A frozen compositor cannot be recovered by IPC timeout; use another TTY or an earlier NixOS generation.

Verify this code without a live desktop: `bash scripts/osu-performance/test-osu-display.sh`. Full Nix evaluation, real asynchronous page-flip and light-onset timing remain outstanding.

Source: [Hyprland v0.57.2 Monitor](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/output/Monitor.cpp), [named Lua window rule](https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/config/lua/bindings/LuaBindingsConfigRules.cpp), [Linux i915 async flip](https://docs.kernel.org/gpu/intel-display/async-flip.html).
