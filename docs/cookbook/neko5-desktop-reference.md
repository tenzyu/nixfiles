# neko5 desktop configuration reference

## Source ownership and fixed settings

- Host choices and eDP-1 mode: [configuration](../../modules/00-hosts/neko5/configuration.nix);
  [independent specialisation](../../modules/00-hosts/neko5/specialisations.nix);
  [physical performance policy](../../modules/00-hosts/neko5/performance.nix).
- Jay owns session, portal, native workspace actions and screenshots.
  Selected Alacritty, Rofi, cclip, Fcitx5 and Herdr integrations compose its
  TOML or scoped package settings; no implicit alternate launcher or cliphist fallback.
- [PipeWire host policy](../../modules/60-integrations/audio/neko5-pipewire.nix):
  48 kHz, ALC257 analog sink periods 128 × 3, headroom 0, suspend timeout 5 s;
  direct RTKit for PipeWire-Pulse. Keep RTKit limits and thermal protection.
- [osu! client integration](../../modules/60-integrations/audio/neko5-pipewire-osu-lazer.nix):
  XDG drop-in visible in the AppImage FHS namespace; match
  `alsa_playback.osu!` and cap graph negotiation at `64/48000`. Keep
  native `node.latency = 441/44100`. Q64 expected, smaller possible.
  Shared playback clients share quantum; independent USB capture is not
  forced. The XDG RTKit drop-in is client-context-wide, not stream-specific.
  No global quantum override or manual RT promotion.
- Native 1366×768 (~60 Hz), scale 1, Jay direct scanout requested,
  tearing `variant2` on eDP-1 only (generic default `variant3`), VRR never,
  XWayland disabled. Keep official osu! fullscreen, OpenGL, embedded OTD,
  `Limit8x` (~480 Draw Hz). The normal neko5 osu! launcher exports
  `INTEL_DEBUG=noccs` only to its process tree; the Gamescope probe and other
  hosts retain defaults. Nix does not overwrite mutable in-game settings.
  Keep the default 1.5 ms flip margin and i915 FBC/PSR/DC/DDB policies.
  See [dated presentation evidence](https://github.com/tenzyu/nixfiles/blob/050bd373eaa20e65134b33d79888d77c784a9371/docs/research/neko5-presentation-log.md).
- Fileman v0.5.2 uses pinned official x86_64 binary; Ark remains for .osk
  because Fileman cannot handle that archive path. GTK FileChooser portal
  unchanged. cclip 3.3.1 builds pinned C/Meson source (no official binary
  found). Alacritty, dua-cli and GitUI replace Kitty, ncdu and Lazygit.
  Restore stock Rofi 2.0 (native Wayland) after the operator observed slow
  or missing Tofi launches; cclip/Herdr capture remains unchanged. QDirStat and dust remain available.

See the [desktop operation and measurement procedure](neko5-desktop.md).
