# neko5 — append-only presentation research log

This is the single chronological research record for the desktop migration,
osu!lazer latency and Jay/Gamescope investigation. Append new dated entries
at EOF; never rewrite, squash, or silently correct old entries. Corrections
must cite the entry superseded. Keep implementation instructions in the
[runbook](../cookbook/neko5-slim-desktop.md); this file is evidence and decisions.
Initial import: 2026-11-24 JST, reconstructed from the conversation and PR #81.
It preserves available substantive observations, source references, parameters,
hypotheses, decisions and known counterexamples, not an exact transcript or
a complete archive of historical tool output. Where a prior source was not
pinned, the link is explicitly a moving upstream reference. No physical
measurement is inferred from a source-code property. Tags: OBS = operator
observation; SRC = source inspection; INF = inference; HYP = untested causal
hypothesis; DEC = decision; OPEN = unresolved.

## 2026-11-24 / 01 — hardware, scope, memory baseline

- OBS: neko5 is the local input/display client, Intel i5-10210U (4C/8T),
  Intel UHD iGPU/i915, 1366x768 eDP-1 (~60.003 Hz), ~15.38 GiB usable RAM.
  NixOS; neko7 is the remote build/compute host. Wacom CTL-472, embedded OTD;
  Sayodevice O3C 1000 Hz. The external OTD daemon is not desired.
- DEC: target <=600 MiB idle effective used (MemTotal - MemAvailable);
  400 MiB exploratory, not a promise. Rust-first if it improves the actual
  system, not a language quota. Keep kernel, Mesa, PipeWire, WirePlumber,
  systemd, dbus-broker, networking, SSH, Tailscale, thermal protection unless
  a concrete advantage justifies change. No watermark gaming, cache dropping,
  indiscriminate service removal, or unnecessary desktop workload.
- OBS: first sample with Firefox + Kitty: effective used ~2675 MiB; memory
  PSI zero; CPU some avg10 .14, io some .43/full .38. Firefox process PSS
  ~1601.6 MiB. Hyprland 100.7, Kitty family 92.7, tailscaled 54.6, Waybar
  32.2, hyprpaper 31.1, Xwayland 30.2, journald 28.9, nix-daemon 23.5,
  WirePlumber 17.7, PipeWire 6.9 MiB. Hyprland + bar + wallpaper + Xwayland
  ~194.2 MiB gross; bar/wallpaper ~63.3 MiB gross, not guaranteed savings.
- OBS: another active sample MemTotal 16131036 KiB, MemFree 10301448,
  MemAvailable 12872068, Buffers 732760, Cached 1456856, Unevictable 322348,
  AnonPages 2594612, Mapped 534132, Shmem 341680, Slab 746440,
  SReclaimable 588196, SUnreclaim 158244, KernelStack 11488, PageTables
  30736, SecPageTables 2056, Percpu 5600, SwapTotal=SwapFree=15877112.
  zram lz4 7.7G logical, DATA 4K, COMPR 69B, TOTAL 20K. No swap occupancy.
  system.slice anon 50245632 B, file 921829376, kernel 571215872,
  slab_reclaimable 561792208; user.slice anon 2602754048, file 1243459584,
  kernel 86257664, shmem 341405696, slab_reclaimable 36726576.
  ext4_inode_cache 419392 KiB (406286 objects), dentry 85864 KiB (450786),
  kmalloc-rcl-96 38288, buffer_head 20728; slab total 719756 KiB.
- OBS: 17 active system services (dbus-broker, getty, NM, nix-daemon,
  nsncd, polkit, rtkit, sshd, journald, logind, oomd, timesyncd, udevd,
  tailscaled, thermald, user@1000, wpa_supplicant). 12 user services
  (dbus-broker, hypridle, hyprpaper, mako, pipewire-pulse, pipewire,
  wireplumber, portals GTK/Hyprland/core/document/permission-store).
  Hyprland clients were native Wayland Firefox and Kitty.
- OBS: quieter sample: effective used 1016.72 MiB; AnonPages 219.48,
  Shmem 65.47, Unevictable 56.18, Mlocked 0, SReclaimable 579.28,
  SUnreclaim 156.89, KernelStack 5.36, PageTables 8.42 MiB.
  i915_gem_objects 108 shrinkable [0 free] objects 58966016 B; system
  capacity 0x3d88f7000, stolen-system 0x2000000. Same physical GPU exposed
  via three debugfs paths, not three allocations. user.slice unevictable
  58781696 B; system.slice 126976 B.
- INF: GEM bytes ~56.23 MiB align with unevictable ~56.18 and user.slice
  ~56.06, strengthening (not proving) i915 backing hypothesis. GEM shrinker
  and VM unevictable LRU are different accounting domains. Debugfs capacity
  values are not live allocation. ext4 inode/dentry may be Nix store traversal
  but unproven. SUnreclaim is not permanently unreleasable. PSS overlaps some
  kernel and shmem accounting; do not sum all /proc/meminfo fields.
- OBS: later active sample MemTotal 15752.96 MiB, MemFree 10415.27,
  MemAvailable 13106.89, AnonPages 1824.69, Shmem 346.31, Unevictable 328.49,
  SUnreclaim 159.93, KernelStack 10.77, PageTables 26.36, SecPageTables 2.01,
  Percpu 5.47, VmallocUsed 83.66, Hugetlb 0, File LRU 2448.97,
  zone low 82.62, estimated reserve 172.52, non-cache residual 2308.32,
  reconstructed/actual EffectiveUsed both 2646.08 MiB. Total process PSS
  2352.57. Largest PSS: Firefox isolated 847.04, main 487.90, WebExtensions
  212.80, Hyprland 100.72, isolated 73.27, privileged 71.26, Kitty 56.65,
  tailscaled 56.64, Waybar 32.16, hyprpaper 31.04, Xwayland 30.16, journald
  29.44, nix-daemon 23.35, portals 22.07/16.02/6.70, WirePlumber 17.55,
  kittens 17.48/16.97, web 15.52/15.30/15.19, NM 13.26, RDD 12.35,
  PipeWire 8.14 MiB. Active app sample is not idle acceptance.
- SRC: Linux si_mem_available estimates free pages minus reserves plus
  discounted file LRU and reclaimable kernel memory; see
  https://github.com/torvalds/linux/blob/master/mm/page_alloc.c and
  https://docs.kernel.org/driver-api/dma-buf.html (moving references).
  For this snapshot reserve + two discounts = 337.76 MiB, not permanent
  allocation. A 600 MiB effective target at the same discounts/reserve
  leaves 262.24 MiB residual. Quieter sample's selected anon/shmem/
  SUnreclaim/PageTables/KernelStack sum ~455.62 MiB; avoid double counting
  unevictable. 600 MiB is not yet demonstrated.
- DEC: compare idle after 5 min, 3 samples 30 s apart via SSH; record
  effective used, non-cache residual, PSS, PSI, swap, not just free memory.
  VFS cache_pressure 50 vs 100 was a possible comparison, not a change.
  Watermark parameters min_free_kbytes, watermark_scale_factor,
  lowmem_reserve_ratio must not be adjusted simply to improve displayed RAM.
- DEC: retain mature stack; Jay's built-in bar/background replaces external
  polling/wallpaper. Native-only initially, on-demand portal services.
  Candidates considered: niri, ashell/Ironbar, Wayle, yami, awww, Wired,
  Anyrun, Alacritty, greetd/tuigreet, Nushell/Yazi. Do not replace working
  infrastructure solely because it is not Rust. Wired not selected (X11
  dependencies); Rofi retained. No verified idle target yet.

## 2026-11-24 / 02 — first Jay generation and configuration history

- DEC: PR https://github.com/tenzyu/nixfiles/pull/81 is the one experiment PR.
  Base fb6d01358f3328e5bdae13cef844eedd441b50d8; initial commit
  1ac02db5b2c00f05bf680aa8b8b47882d0a886b2. Pinned Jay v1.15.0 from unstable
  nixpkgs e21fec321d73511849707a7585e4ea155ee4bf40. Stable nixpkgs revision
  f68407657ad294471eb4b2e65d193df26edf729f used in source inspection.
  Separate specialisation originally preserved ordinary Hyprland.
  Built-in bar, solid background, no Xwayland, portal Jay + GTK, Alacritty,
  direct-scanout=true, user US XKB, JAY_NO_REALTIME=1, no idle/lock UI,
  no wallpaper/status/notification startup process. No kernel or HOME
  migration; system-side neko5-osu-first kept, Hyprland-specific user side
  disabled. Default Alt bindings replaced by logo/Super (30 bindings),
  commit 61879db0ee2599517f6ae75db4b1241fb08f0486; Ctrl+Alt+F1..3 retained.
- OBS: CI failed because typed host seed recursively evaluated mkForce false
  and lost override priority (hyprland-tenzyu true/false conflict).
  Fix b4f8e7b80573e7065d423f769fc21ab02c05cee4 moved specialisation
  definition behind native module import. CI later succeeded.
- OBS: booted Jay. Operator reported Hyprland latency gone, Quantum 64
  no audible collapse, tablet latency no longer felt. Direct scanout
  confirmed by operator; 1366x768 and Limit8x yield stable ~480 Hz Draw.
  One earlier ~40-minute Q64 session ~40 ERR (operator observation,
  not synchronized per-node measurement). Do not equate no audible
  distortion with zero XRUN.
- SRC: Jay control center Visualize Compositing (indicator disappears during
  scanout), jay randr device direct-scanout setting, fullscreen. Tearing
  is independent of scanout; actual async hardware flip not established.
  Diagnostic commands: jay randr; jay set-log-level debug; jay log -f;
  jay debugfs mount/unmount; restore info log level. Source:
  https://github.com/mahkoh/jay/blob/v1.15.0/book/src/cli.md
  https://github.com/mahkoh/jay/blob/v1.15.0/book/src/control-center.md
  https://github.com/mahkoh/jay/blob/v1.15.0/book/src/configuration/outputs.md
- SRC: PipeWire runtime force command pw-metadata -n settings 0
  clock.force-quantum 128 (or 64; 0 clears override). At 48k, Q1024 21.333 ms,
  Q512 10.667, Q256 5.333, Q128 2.667, Q64 1.333, Q32 0.667.
  Graph period is not total audio latency. ALSA integrated output
  period-size 128, period-num 3 retained.
- DEC: 1366x768, ~60 Hz, scale 1, native Wayland, fullscreen, same renderer,
  Limit8x (~480 draw, ~960 update upper limits), embedded OTD, Q64/48k,
  min/default/max=64, original ALSA 128x3, no VRR, same hardware/kernel/Mesa,
  same map/skin/mods/power/temperature/background workload. No overlays or
  capture during timing; diagnostics separately. Game settings remain
  user-managed and verified, not overwritten. Native mode and actual
  scanout/async evidence separate from permission.
- DEC: Super+Q must close window rather than compositor; workspace 1..10
  with Super+number and move/follow with Shift; Super+F fullscreen,
  Enter terminal, Space launcher, B Firefox, O osu!, HJKL focus;
  Ctrl+Shift+Super+Q exit. Jay user config changes and comparison profiles:
  864177a32e68eb157dfd1eb61903e6dbcb319348,
  61872ac674fe9dc0408c303dc7ef0b0e4d76f25d (CI success).
- OBS: new Jay generation lost stable 480 Draw; old generation restored it.
  Differences: variant3 default -> explicit variant2, graph min/default/max
  Q64, explicit output mode, VRR never, keybindings/workspaces. Jay/Mesa/
  kernel versions unchanged per diff. Operator subsequently reported Draw
  480 stable again; exact causal runtime change not captured.
- HYP: variant2 forced async eligibility even where KMS async commit
  fails; Jay skips normal adaptive vblank scheduling on async attempt then
  falls back to sync. Potential buffer-release timing/backpressure regression.
  Q64 policy and output mode also possible. No proof that variant2 was cause.
  Runtime A/B: jay randr output eDP-1 tearing set-mode variant3; inspect
  jay randr show --modes and pw-metadata -n settings.
- DEC: restore variant3 as prior policy, retain scanout and Q64. A/B matrix
  scanout on/off x tearing permitted/never with rest fixed; no need to run
  all if a concrete problem already solved. Record actual hardware path.
  Source https://github.com/tenzyu/nixfiles/compare/b4f8e7b...61872ac.

## 2026-11-24 / 03 — compositor candidate space, gates and maturity

- SRC: independent: Jay (Rust, own Metal DRM backend), Hyprland (C++,
  Aquamarine), KWin (C++/Qt), Mutter (C/GLib); wlroots family Sway, labwc,
  dwl, Wayfire, MangoWC, river-classic, SwayFX, Cage; Smithay family niri,
  COSMIC, Pinnacle, Anvil; specialized Gamescope, Weston, Mir/Miracle-WM.
  Shared library != identical policy or performance.
- DEC: G0 native game, G1 feasible same-GPU direct scanout, G2 async flip
  capability for tearing-tolerant fixed-60Hz minimum latency, G3 no
  unnecessary FIFO, G4 no mandatory nested boundary, G5 stable audio/input
  deadlines. G0-G4 can partly be reasoned from code; G5 needs real hardware.
  G2 elimination only conditional on actual i915 async success. A feature
  checklist does not prove performance.
- SRC: Hyprland v0.57.2 CMonitor::isDSBlocked/attemptDirectScanout
  requires m_solitaryClient, rejects blocked effects, nonmatching buffer
  size/transform, mirroring, recording conditions, software cursor,
  missing surface/DMA-BUF, color mismatch, mode-specific fullscreen/game
  conditions. isTearingBlocked checks visible hardware cursor, candidate
  and canBeTorn. Prior CANDIDATE blocker reported; earlier 1280x720 vs
  1366x768 mismatch is a distinct plausible blocker, not proof of cause.
  Early rejection is cheap if solitary client is clear. Same-buffer
  presentation, VRR, FIFO unlock, rollback, multi-GPU synchronization exist.
  https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/output/Monitor.cpp#L1830-L2140
  https://github.com/hyprwm/Hyprland/blob/v0.57.2/src/render/Renderer.cpp
  https://github.com/hyprwm/aquamarine (moving)
- SRC: wlroots scene output state, scene_entry_try_direct_scanout,
  wlr_scene_output_build_state, wlr_output_test_state; SCANOUT_INELIGIBLE/
  CANDIDATE/SUCCESS; feedback debounce, source/dest rectangles, timeline
  sync. Sway uses output_can_tear, pending.tearing_page_flip, test fallback,
  max_render_time JIT prediction. Millisecond timer vs Jay nanosecond
  deadline does not establish actual wake latency.
  https://github.com/live-clones/wlroots/blob/master/types/scene/wlr_scene.c
  https://wlroots.pages.freedesktop.org/wlroots/wlr/types/wlr_scene.h.html
  https://github.com/swaywm/sway/blob/f916a0cdc726319f1e88338bb95fb4535a5bbf60/sway/desktop/output.c
- SRC: Smithay DrmCompositor render_frame/try_assign_element/
  try_assign_primary_plane/try_assign_cursor_plane/try_assign_overlay_plane/
  queue_frame. FrameFlags primary, primary-any, overlay, cursor, skip
  cursor-only updates. niri primary/cursor normal, overlay opt-in debug.
  Async issue niri #844 and Smithay PR #1948 unmerged in prior inspection;
  Intel format constraints discussed. COSMIC/Pinnacle not independently
  proven equivalent. niri conditionally eliminated for tearing; not blanket
  condemnation of Smithay.
  https://github.com/Smithay/smithay/blob/master/src/backend/drm/compositor/mod.rs
  https://github.com/niri-wm/niri/blob/main/src/backend/tty.rs
  https://github.com/niri-wm/niri/issues/844
  https://github.com/Smithay/smithay/pull/1948
- SRC: KWin prepareDirectScanout uses RenderView/layers, transforms,
  color pipeline, import and feedback, separate supportedAsyncDrmFormats
  vs supportedDrmFormats. RenderLoop Async/AdaptiveAsync targetTimestamp
  presentNotBefore; adaptive render time/RenderJournal, commit thread,
  plane assignment. Strong competitor on code, not dismissed for Qt.
  https://github.com/KDE/kwin/blob/22667836fb60d6f3a55880d4b1b0b67fb1a799de/src/core/renderloop.cpp
  https://github.com/KDE/kwin/blob/master/src/compositor.cpp
  https://github.com/KDE/kwin/blob/master/src/backends/drm/drm_pipeline.cpp
- SRC: Mutter uses top window actor/paint geometry/effect/transition and
  KMS test update; prior native atomic backend lacked confirmed async
  path (not proof of total absence, verify version if reconsidered).
  https://github.com/GNOME/mutter/blob/main/src/compositor/meta-compositor-view-native.c
  https://github.com/GNOME/mutter/blob/main/src/backends/native/meta-onscreen-native.c
- SRC: Cage handle_output_frame uses wlr_scene_output_commit; no Sway-like
  async flag found in inspected path. Weston DRM has async and direct
  scanout, but Weston 15.0.1 desktop shell inspected single workspace.
  https://github.com/cage-kiosk/cage/blob/master/output.c
  https://github.com/microsoft/weston-mirror/blob/15.0.1/desktop-shell/shell.c
- SRC: Gamescope 3.16.23 native xdg client path with --expose-wayland still
  needs Xwayland server 0 internally; standalone not nested; no desktop
  workspaces. https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/main.cpp
- SRC: Jay release inspection reported repo creation 2022, ~3200 commits,
  733 stars, v1.15.1 released 2026-11-14 (llvmpipe Vulkan crash fix);
  historical snapshot, not current metrics. Integration tests and protocol
  coverage advanced; smaller maintainer ecosystem/hardware diversity
  than Sway/KWin, bus factor unresolved. Tests are not actual i915 validation.
  https://github.com/mahkoh/jay/releases
  https://github.com/mahkoh/jay/blob/v1.15.0/src/it/tests/t2024_04_03_scanout_feedback.rs
  https://wayland.app/
- DEC: trialed five boot profiles Jay/Sway/KWin/Weston/Gamescope; Weston
  and Gamescope already failed workspace usability gate. Operator says
  Gamescope felt best but too much desktop functionality sacrificed.
  Jay selected; Sway/KWin/Weston explicitly retired, f1de3bade1ab60fdc0a776d2a22774c43256849c.
  No fabricated physical test scores for the retired products. Gamescope
  retained only as research probe; nested Gamescope excluded by design,
  not proven universally slower. Hyprland no longer fallback after /08.

## 2026-11-24 / 04 — osu-framework and Mesa critical path

- SRC: framework source snapshot aca e8b2 (full
  acae8b2c7c5eb568b240833d49d23374ec6afd8d); actual installed framework
  revision not captured. Embedded OTD IAbsolutePointer.SetPosition enqueues
  MousePositionAbsoluteInputFromPen directly; does not require compositor
  tablet input. Wacom -> HID/embedded OTD -> framework input -> update;
  Sayo -> evdev/compositor/SDL -> input -> update. The improved tablet
  feel may primarily be downstream input-to-photon improvement.
  https://github.com/ppy/osu-framework/blob/acae8b2c7c5eb568b240833d49d23374ec6afd8d/osu.Framework/Input/Handlers/Tablet/OpenTabletDriverHandler.cs#L111-L121
- SRC: TripleBuffer<DrawNode> index exchange (Interlocked.Exchange) is SPSC
  latest-state handoff, not FIFO display of three old frames. UpdateFrame
  generates DrawNode tree, DrawFrame consumes latest. GPU swapchain queue
  is separate. GameHost AllowTearing fullscreen && !VSyncVRR; Limit8x
  draw 8*refresh, update 16*refresh, input nominal 1000 Hz. At 60 Hz:
  draw 2.083ms, update 1.042ms, input ~1ms, panel cycle 16.667ms.
  These are intervals, not additive latency measurements.
  https://github.com/ppy/osu-framework/blob/acae8b2c7c5eb568b240833d49d23374ec6afd8d/osu.Framework/Allocation/TripleBuffer.cs#L40-L116
  https://github.com/ppy/osu-framework/blob/acae8b2c7c5eb568b240833d49d23374ec6afd8d/osu.Framework/Platform/GameHost.cs
- SRC: Mesa WSI/EGL/SDL transforms frame sync choice into swapchain image
  acquisition, buffer release, Wayland commit, callbacks and tearing hint.
  Vulkan FIFO/FIFO_RELAXED maintain ordered presentation; MAILBOX allows
  replacement but vblank synchronized; IMMEDIATE allows tear. Actual
  renderer and selected WSI mode not measured. OpenGL EGL swap interval
  also affects blocking. Investigate exact installed library versions first.
  https://docs.vulkan.org/refpages/latest/refpages/source/VkPresentModeKHR.html
  https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/vulkan/wsi/wsi_common_wayland.c
  https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/egl/drivers/dri2/platform_wayland.c
  https://wayland.app/protocols/tearing-control-v1
  https://wayland.app/protocols/fifo-v1
  https://wayland.app/protocols/linux-drm-syncobj-v1
- INF: latency decomposition dispatch + commit + queue + fence + composition
  + KMS + physical presentation, overlapping in reality. Uniform ready
  phase relative to fixed 60 Hz vblank implies mean 8.33ms wait and
  max <16.67ms before next boundary, ignoring deadlines. Async avoids
  forced vblank wait but physical scan position/pixel response remain;
  480 Hz draw != 480 Hz physical display.
- DEC: objective is freshness/Age of Information, Delta(t)=t-u(t) where
  u is state-generation time of visible pixels. Average, p95/p99 age,
  jitter, Draw blocking, audio deadline misses. Preserve official game
  package and standard environment; no game modification presumed.

## 2026-11-24 / 05 — Jay v1.15.0 source architecture

SRC: Jay independent Rust compositor, own native DRM backend named Metal.
Core sources:
- https://github.com/mahkoh/jay/blob/v1.15.0/src/renderer.rs
- https://github.com/mahkoh/jay/blob/v1.15.0/src/gfx_api.rs#L1490-L1617
- https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/present.rs
- https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/video.rs
- https://github.com/mahkoh/jay/blob/v1.15.0/src/dmabuf_feedback.rs
- https://github.com/mahkoh/jay/tree/v1.15.0/src/gfx_apis/vulkan
- https://github.com/mahkoh/jay/blob/v1.15.0/src/video/drm.rs

1. Render-pass-centric scanout: GfxRenderPass::prepare_direct_scanout walks
   draw ops in reverse, identifies top texture, validates alpha/blend space,
   background visibility, acquire sync, viewport, transforms, geometry,
   scaling. Errors TopmostTexture, NotPremultipliedElectrical,
   AlphaWithIncompatibleBlendSpace, AlphaFactor, TextureVisible, FillVisible,
   BackgroundVisible, ImplicitSync, RotationOrMirroring, Viewport,
   OutsideScreen, Scaling. Can ignore fully occluded background and
   equivalent black fill; hardware scaling if geometry/KMS allow. Contrast
   Hyprland solitary-window prefilter. Primary framebuffer plus hardware
   cursor; no general multi-overlay allocator claimed.
2. MetalConnector::prepare_direct_scanout checks format/modifier,
   device, lazy work, color state. scanout_impossible_cache negative key
   includes dmabuf ID, plane/CRTC, src/dst, intent, gamma LUT, cursor plane,
   plane color pipeline. Avoid repeated known-invalid commits; on failure
   try composition and record bad combination if fallback succeeds.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/present.rs#L721-L880
3. Phase-aware cooperative runtime: EventHandling -> Layout -> PostLayout
   -> Present. Dispatcher drains current phase, including newly queued work
   before advancing; does not preempt running later-phase task and can
   suffer starvation. io_uring reactor dispatches runnable tasks and CQEs,
   submits SQEs, awaits FD/timeouts. libinput, Wayland sockets, DMA-BUF/
   syncobj, DRM events and deadlines share the model. No claim io_uring
   inherently beats epoll; scheduler wakeup and runtime work differ.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/async_engine.rs
   https://github.com/mahkoh/jay/blob/v1.15.0/src/io_uring.rs
4. CommitTimeline tracks acquire points/files, SHM upload, PRIME copies,
   FIFO barriers, commit time, subsurface transaction dependencies. No
   dependencies and empty timeline -> apply immediately. FIFO-wait and
   Mailbox differentiated; mailbox does not require FIFO barrier, but
   flush_list stops at first unresolved dependency. Potential HoL blocking
   on same timeline; cannot skip arbitrary state deltas. Jay is not a
   general latest-only compositor.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/ifs/wl_surface/commit_timeline.rs
5. present_loop: use_frame_scheduling = !try_async_flip(); synchronized
   start/latch near predicted vblank minus pre/post margins. before_latch
   allows latest state before presentation. Pre margin tracks measured
   duration maxima with geometric decay; post margin uses expected vs
   actual page-flip sequence, increases on miss and decays to configured
   minimum. Configured flip-margin-ms default 1.5 per prior inspection;
   1.0 experimental only; avoid increasing missed vblank for sub-ms gain.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/present.rs#L179-L249
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/video.rs#L2449-L2479
6. Bounded in-flight KMS: present_once gates buffers_idle and crtc_idle;
   next_framebuffer becomes active on DRM flip completion. Retain buffer
   until hardware done. Avoid deep submission queue, but pipelining
   throughput may be limited. This is independent of upstream surface
   queue depth.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/present.rs#L250-L273
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/video.rs#L2370-L2446
7. Atomic NONBLOCK/PAGE_FLIP_EVENT; try PAGE_FLIP_ASYNC when output policy
   and hardware support allow; fallback to synchronous. Scanout and
   async are orthogonal: direct+async, direct+sync, composited+async,
   composited+sync. Real KMS flags and hardware support must be observed,
   not inferred from config.
   https://github.com/mahkoh/jay/blob/v1.15.0/src/backends/metal/present.rs#L565-L596
8. Tearing modes never/always/variant1 (fullscreen exists)/variant2
   (single fullscreen app)/variant3 (single app requests tear, default).
   Actual async constraints are DRM/i915 format/modifier/plane/CRTC
   state. Kernel's intel_async_flip_check_hw is part of this boundary;
   no specific successful async flip demonstrated in operator report.
   https://github.com/torvalds/linux/tree/master/drivers/gpu/drm/i915/display
9. JAY_NO_REALTIME=1 explicit initial decision, retained. CAP_SYS_NICE,
   SCHED_RR and Vulkan queue priority may be explored separately, not
   assumed beneficial; could hurt PipeWire RT. Vulkan vs GL, fence wait,
   libinput/cursor, memory lifetime, thermal budget remain research.
   https://github.com/mahkoh/jay/blob/v1.15.0/book/src/environment-variables.md
10. HYP: lower composition, wakeup and memory-bandwidth contention may
    leave CPU/GPU package-power and thermal headroom, reducing tail
    scheduling latency and Q64 XRUN. Not an established causal chain.

## 2026-11-24 / 06 — Gamescope 3.16.23 source and comparison

SRC: Gamescope is frame-centric gaming policy around Wayland, X11/Xwayland,
Steam focus/overlays, Vulkan composition, multi-threaded waiters, DRM
backend. Do not equate absence of a desktop with a specific latency win.

- steamcompmgr.cpp window_last_done_commit_index scans queue and selects
  latest done index; handle_done_commit marks done, records earliest
  present/latch time and held base commit, erases prefix before j.
  Potential latest-ready supersession; FIFO/due time still honored.
  Native xdg handle_done_commits_xdg uses FIFO one-per-window-per-vblank
  and desiredPresentTime gating; code has a break for not-yet-due entry.
  Not unconditional latest-only. Completion reorder in osu! workload
  unproven; same GPU execution may complete in order. State vs image
  transaction semantics differ from Jay; do not blindly transplant.
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/steamcompmgr.cpp#L1427-L1472
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/steamcompmgr.cpp#L6665-L6920
- update_wayland_res imports buffer, records acquire/release timeline or
  implicit dma-buf FD/memory fence; CAsyncWaiter tracks readiness. Known
  ready -> Signal immediately; otherwise wait FD. commit_t::OnPollIn
  closes/removes fence, Signal appends DoneList entry under mutex, nudges
  steamcompmgr. Destructor discards remaining presentation feedback and
  unlocks wlr_buffer; release point/buffer lifetime tied to backend FB.
  Distinct waiter thread, epoll/poll vs Jay's cooperative io_uring runtime;
  locks/cache coherence/wakeups are costs. Preemptive upscaling only FIFO,
  not high-frequency non-FIFO content; native resolution avoids this path.
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/commit.cpp
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/steamcompmgr.cpp#L7050-L7276
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/waitable.h
- FlipType Normal: vblank && (base repaint || nonbase repaint || forced
  sync). Async: base hasRepaint; overlay-only repaint may be postponed.
  VRR: repaint-driven, overlay handling, in-flight guard. Steam/perf overlay,
  prior compositing, fades and forced repaint can force normal sync.
  Game-centric rather than generic desktop responsiveness. Do not claim
  --immediate-flips alone establishes actual async KMS.
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/steamcompmgr.cpp#L8850-L8956
- CVBlankTimer::CalcNextWakeupTime: predicted vblank minus rolling draw
  time and red zone. Fast response to spikes, gradual decay, refresh-cycle
  clamp, compositing minimum, distinct VRR behavior. timerfd if backend
  does not need frame sync; otherwise nudge thread. Jay separates pre/post
  margins and tracks missed sequences. Neither guaranteed lower tail.
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/vblankmanager.cpp#L28-L173
- DRM drm_prepare_liftoff: state negative cache cleared on modeset, single
  plane optimization, FB_ID/IN_FENCE_FD/zpos and layer geometry. Vulkan
  composition fallback, partial composite where feasible, full composite
  if single-plane flip fails, scaling/filter/color/cursor/reshade conditions.
  DMA-BUF import via drmPrimeFDToHandle, drmModeAddFB2WithModifiers.
  Atomic nonblock/event/async flags, rollback on failure. Prior composition
  path explicitly waits on Vulkan completion, so not all rendering async.
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/Backends/DRMBackend.cpp#L2566-L2605
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/Backends/DRMBackend.cpp#L2917-L3055
  https://github.com/ValveSoftware/gamescope/blob/3.16.23/src/Backends/DRMBackend.cpp#L3490-L3715
- DEC: research priorities latest-ready selection and game-driven repaint
  (P0), fence completion fast path and lifetime (P1), hardware plane
  assignment for overlays (P2; unnecessary for solitary native osu!).
  Jay has a simpler single-texture fast path, protocol transaction
  correctness, desktop input/IME/workspaces and separate adaptive margins.
  No measured component-level causal attribution of Gamescope feel.
- DEC: keep standalone command unchanged for reproducibility:
  gamescope --backend drm --expose-wayland --immediate-flips
  --prefer-output eDP-1 -W 1366 -H 768 -w 1366 -h 768 -r 60
  --framerate-limit 0 -- gameProbe (unset DISPLAY, SDL_VIDEODRIVER=wayland,
  require WAYLAND_DISPLAY, exec osu-lazer). No nested session.

## 2026-11-24 / 07 — coexistence without writing a desktop compositor

- SRC: DRM render node permits concurrent rendering; DRM primary card
  normally has one current master; lease delegates subset of connectors,
  CRTC, planes. Same physical scanout resource cannot have two independent
  owners at once. Direct scanout retains compositor control, only bypasses
  GPU composition. Nested compositor adds scheduling boundary but not
  necessarily copy. 
  https://docs.kernel.org/gpu/drm-uapi.html
  https://wayland.app/protocols/drm-lease-v1
- Options: existing Jay direct scanout/policy patch; separate VT/session
  handoff; DRM leasing (usually non-desktop HMD, eDP dynamic lease not
  automatic, requires compositor policy; input separate); in-process
  SDL KMSDRM; direct Vulkan display WSI; minimal Wayland server only if
  unmodified application requires it. Do not develop full WM/workspaces/
  clipboard/IME/notifications to solve game presentation.
- SRC: logind TakeControl/TakeDevice/PauseDevice/ResumeDevice/ReleaseDevice;
  libseat; normal local login and correct seat ownership. Never run game
  root or broadly chmod devices. Same-UID sessions share runtime dir/
  systemd --user/PipeWire sockets and audio graph; Discord process/VC can
  survive VT handoff in principle, but actual ALSA/ACL/policy/resume gaps
  must be tested. Inactive compositor input absent -> PTT needs routing;
  overlay/screen share need separate capture, simultaneous single-panel
  display needs composition.
  https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html
- SRC: SDL KMSDRM backend, SDL_VIDEODRIVER=kmsdrm, EGL/GBM and Vulkan,
  evdev, VT release/acquire (version-dependent). Legacy swap waits for
  preceding flip; double-buffer atomic may block; fenced nonblocking path
  available in SDL 3.4+ subject to build/driver. Removing IPC is no
  guarantee of lower latency if Draw blocks. Official AppImage bundled
  backend and exact renderer support unknown; test separate local VT:
  env -u WAYLAND_DISPLAY -u DISPLAY SDL_VIDEODRIVER=kmsdrm osu-lazer
  (not executed). Vulkan VK_KHR_display/VK_KHR_display_swapchain/
  VK_EXT_direct_mode_display/VK_EXT_acquire_drm_display; vkAcquireDrmDisplayEXT.
  https://github.com/libsdl-org/SDL/tree/main/src/video/kmsdrm
  https://docs.vulkan.org/refpages/latest/refpages/source/vkAcquireDrmDisplayEXT.html
- HYP: Session Broker + Presentation Engine + Resource Governor may be
  sufficient; handoff dark interval, modeset, resource retention,
  suspend/resume, input exclusivity, portal env, failure recovery, background
  GPU/CPU contention and VC continuity are actual costs. Earlier proposed
  (not adopted/verified) targets p95 switch <=100ms, zero VC reconnect/
  transition XRUN/game restart, 100 successful switches, 480 Draw, zero
  extra GPU composition, automatic recovery. Jay single session avoids
  these handoff costs. No independent product needed unless evidence
  establishes a residual problem unsolvable by smaller changes.

## 2026-11-24 / 08 — cursor, IME, primary migration

- OBS: mouse cursor missing outside osu!, Japanese input switching failed.
  Jay cursor.rs uses XCURSOR_PATH default ~/.icons:/usr/share/icons:
  /usr/share/pixmaps:/usr/X11R6/lib/X11/icons, excludes Nix store paths;
  failed load returns 1x1 transparent texture. Old Hyprland used Adwaita24.
  Explicit packaged Adwaita cursor search path, size/theme before Jay start,
  keep hardware cursor enabled. Cause plausible, runtime cursor status
  after fix not explicitly reported. Source:
  https://github.com/mahkoh/jay/blob/v1.15.0/src/cursor.rs#L237-L299
  https://github.com/mahkoh/jay/blob/v1.15.0/book/src/environment-variables.md
- SRC: existing Fcitx5 + Mozc UT, native Wayland frontend; no Fcitx startup
  in initial Jay hook. Jay text-input-v3 to zwp_input_method_v2 with
  CAP_INPUT_METHOD; focus/activate/preedit/commit/popup/grab. Default
  ordinary socket not privileged. d197a143d64df1800a960ee53fa5db5023a5f2c3
  added tagged Fcitx startup, per-client input-method capability,
  restart shortcut; operator reports Mozc present but Japanese still
  cannot switch. No confirmed reason why tag-based path failed.
  https://github.com/mahkoh/jay/blob/v1.15.0/src/ifs/wl_seat/text_input/zwp_input_method_manager_v2.rs
  https://github.com/mahkoh/jay/blob/v1.15.0/src/ifs/wl_seat/text_input.rs
  https://github.com/mahkoh/jay/blob/v1.15.0/toml-spec/spec/spec.generated.md
- DEC: 01b8782980d6aaa2c18e4b3c1576bdf5b3d6743a promotes Jay to normal
  neko5, removes neko5-slim specialisation, keeps only neko5-gamescope
  as native probe, disables Hyprland on neko5 without deleting feature
  modules, old generations retained. Same TTY login and
  exec neko5-slim-session, no autologin. CI validates primary/probe and
  audio/HOME identity plus evaluated Jay TOML; hardware acceptance pending.
- DEC: switch from tagged normal socket to documented privileged=true
  exclusively for packaged Fcitx5 -r. Source Command::privileged sets
  WAYLAND_DISPLAY to socket path + .jay; secure acceptor grants ALL Jay
  protocol capabilities, not OS root. Explicit tradeoff to restore IME;
  later reduce to input-method only if tested. Super+Ctrl+I restart;
  Super+I fcitx5-remote -t; keep user trigger/profile/dictionary, use
  QT_IM_MODULE=fcitx in Jay session; GTK native v3 first. If still broken,
  test fcitx5-remote / -n, fcitx5-diagnose, configtool group/Mozc, GTK
  per-app fallback GTK_IM_MODULE=fcitx, Chromium/Electron text-input-v3
  flags only on affected app after version check. No global SDL IME
  or Xwayland enable; do not claim fix works before user test.
  https://github.com/mahkoh/jay/blob/v1.15.0/jay-config/src/exec.rs#L89-L101
  https://github.com/mahkoh/jay/blob/v1.15.0/src/client.rs#L273-L277
  https://github.com/mahkoh/jay/blob/v1.15.0/book/src/configuration/startup.md
  https://fcitx-im.org/wiki/Using_Fcitx_5_on_Wayland/en
- OPEN: test empty workspace/Firefox cursor, Firefox native preedit and
  commit, Discord input, ten workspace shortcuts, direct scanout and 480
  with Fcitx present, portal authorization, suspend/lock. No auto lock
  currently; do not leave unattended. No additional kernel/audio changes.

## 2026-11-24 / 09 — Discord VC + osu! Q64 error evidence

OBS (operator report; raw pw-top excerpt, line breaks normalized only):

```text
S   30      0      0    ---     ---   ---   ---     0                  Dummy-Driver
S   31      0      0    ---     ---   ---   ---     0                  Freewheel-Driver
S   45      0      0    ---     ---   ---   ---     0                  Midi-Bridge
S   50      0      0    ---     ---   ---   ---     0                  bluez_midi.server
R   54     64  48000  14.3us   0.7us  0.01  0.00   23    S24LE 2 48000 alsa_input.usb-HP__Inc_HyperX_SoloCast-00.analog-stereo
R   91   1440  48000   5.5us   5.6us  0.00  0.00   58    S16LE 2 48000  + WEBRTC VoiceEngine
R   55     64  48000  19.1us   5.6us  0.01  0.00    4    S32LE 2 48000 alsa_output.pci-0000_00_1f.3.analog-stereo
R   69    441  44100   5.8us   8.5us  0.00  0.01   26    F32LE 2 44100  + alsa_playback.osu!
R   86    360  48000   6.0us   3.7us  0.00  0.00   56    S16LE 2 48000  + WEBRTC VoiceEngine
S   56      0      0    ---     ---   ---   ---     0                  alsa_input.pci-0000_00_1f.3.analog-stereo
S   66      0      0    ---     ---   ---   ---     0                  v4l2_input.pci-0000_00_14.0-usb-0_7_1.0
```

- SRC: https://docs.pipewire.org/page_man_pw-top_1.html : driver QUANT
  is active quantum, follower QUANT is suggestion; RATE stream/graph
  semantics; ERR cumulative XRUNs/errors. Driver cycle deadline or
  follower processing deadline may contribute to same event.
- INF: physical capture ID54 and output ID55 at 64/48k = 1.333ms.
  Mic driver ERR23, output4, WebRTC followers 58/56, osu!26. Follower
  request 1440/48k=30ms, 360/48k=7.5ms, 441/44.1k=10ms, not physical
  graph cadence or proof of a 30ms render delay. 44.1->48k resampling
  on output graph; independent USB mic vs integrated codec clocks may
  require rate adaptation when linked, exact graph not inspected.
  WAIT/BUSY ~microseconds in this snapshot, W/Q low; not proof of good
  p99 scheduling. Do not add ERR across nodes or infer per-second rate
  without elapsed interval or reset. Higher WebRTC errors do not prove
  Discord root cause; startup, device graph transition, scheduling jitter,
  resampling/clock drift, voice processing and thermal contention possible.
- DEC: no change to Q64 min/default/max or ALSA/RT/kernel policy now.
  First compare idle VC / osu only / VC+osu after warmup, same map,
  5min or 40min equal intervals; pw-top interactive c resets local
  counters only, or batch pw-top -b -n N and per-node delta.
  Record active physical driver QUANT/RATE, node IDs across reconnect,
  errors/time, audible issue, frame times, thermal and VC status.
  Inspect pw-dump, pw-metadata -n settings, pw-profiler --help,
  journalctl --user -u pipewire -u wireplumber --since ...; do not
  collect voice content. If sustained new errors, isolate capture vs
  playback, device clock and scheduler; consider separate graph quantum
  policy for USB capture only after evidence and consent to relax fixed
  experiment. Do not set global 128 as a silent workaround.
- OPEN: Discord usability and Q64 simultaneous stability are production
  gates; source research is not a substitute for this result.

## 2026-11-24 / 10 — how to advance without owning a fork

DEC: production is unmodified packaged Jay with declarative config.
Gamescope is reference/probe, not daily desktop. No new compositor
or permanent fork authorized yet. First inspect/measure the exact
osu-framework/Mesa/Jay/i915 pipeline and isolate one necessary improvement.

Proposed research sequence (not implemented):
1. Reproduce primary Jay success including Discord, Japanese input and
   cursor. Capture installed revisions, renderer, surface buffer format/
   modifier, actual sync and KMS mode. Preserve baseline generation.
2. Instrument frame IDs / timestamps without changing algorithm:
   input/update/draw/swap entry/exit, wl_surface.commit, acquire readiness,
   timeline apply, latch, scanout rejection, DRM submit/errno/flags, flip
   sequence/time, release. All on MONOTONIC clock or calibrated mapping.
   Trace observer overhead bounded; no per-frame stderr logging in benchmark.
   AoI at flip is not physical input-to-photon; use sensor if claiming it.
3. Identify avoidable waits and whether they are on actual critical path.
   If all fences finish in order and no backlog, latest-ready selection
   has no material gain. If actual scanout already active, additional
   overlay allocator has no solitary-game benefit. If async fallback
   happens, distinguish eligibility vs KMS hardware constraints.
4. Minimal experiment patch to Jay (Nix overrideAttrs patches or separate
   pinned source revision, no production change), with testable invariant
   and rollback. Fork only for branch hosting/contribution if necessary;
   not a permanent downstream product. Prototype pure scheduling logic
   outside compositor if useful, but Wayland state and KMS lifetime must
   stay integrated.
5. For supersession: only replace provably redundant buffer-only state
   within compatible transaction epoch; never cross FIFO/timed/synchronized
   subsurface/configure/geometry/color/input constraints or unsatisfied
   dependencies that later state needs. Preserve feedback discard,
   release fence and active scanout references, no premature reuse.
   Compare latest-ready vs ordered under synthetic blocked/out-of-order
   fences, state changes, resize, mode changes, teardown, output handoff,
   overlays, IME/Discord, no regression ordinary clients. KMS failed
   async fallback and negative cache context invalidation tests.
6. If improvement exists, upstream report/PR preferred; maintain small
   downstream patch temporarily only if needed. If no demonstrable gain,
   discard experimental change. Only consider independent presentation
   runtime after proven limitation and user decision; do not replicate
   Wayland desktop. User plans to involve 6.2 Astra / Sol if all trials
   unsatisfactory, but current decision is Jay baseline.
