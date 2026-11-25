# neko5 — NixOS + Jay: purpose-built personal workstation

Status: candidate source policy, 2026-11-25. No host activation, benchmark result,
or 400 MiB attainment is claimed. The parent is PR #81 at
[a8461262](https://github.com/tenzyu/nixfiles/commit/a846126222f8f0053903861a49ac429f45597ed0).
The normal workstation is the product; there is no Slim Edition, new desktop
supervisor, alternative init, kernel fork, or always-resident measurement agent.

## Decision and non-regression boundary

Minimize the resource cost of the capabilities the operator actually needs,
not the number of processes or an accounting counter in isolation. The
successful Jay/official osu! pairing is a protected capability, not a target
for compositor replacement or allocator experimentation. Keep native Wayland,
the eDP-1 1366x768 mode, Direct Scanout, variant2 and scoped noccs, independent
Gamescope reference, embedded OTD, PipeWire/RTKit and ALC257 policy, thermal
safety, SSH/Tailscale and remote Nix builder, Japanese input, clipboard,
screenshots, files, notifications, HOME route authority and generation
rollback. See [presentation evidence](neko5-presentation-log.md) and
[desktop runbook](../cookbook/neko5-desktop.md). Use stock binary/substitute
eligible packages unless measured benefit justifies a separate exception.

## Research: transfer mechanisms rather than distro branding

| Evidence (primary unless noted) | Transfer to NixOS | Reject / limit |
| --- | --- | --- |
| [Alpine design](https://www.alpinelinux.org/about/) | Small base, split binary packages, explicit additions | Its disk/container sizes are not physical laptop idle RAM; musl/BusyBox/OpenRC migration changes ABI and session behavior |
| [Void service handbook](https://docs.voidlinux.org/config/services/index.html) | Installing software and enabling its service are separate decisions; use native systemd units and activation | Do not replace systemd/logind or equate fewer processes with fewer allocated pages |
| [Gentoo USE flags](https://devmanual.gentoo.org/general-concepts/use-flags/) | Separate significant optional functionality; prefer native switches | Gentoo itself warns against recompiling for insignificant optional files or proliferating flags; no custom rebuild just to trim an installed package |
| [DietPi stats and methods](https://dietpi.com/stats.html) | Optimize a conventional distribution's userland and record commands/hardware | Its free -tm output, RAM-backed logging and SBC/VM conditions are not identical to neko5; keep persistent diagnostics |
| [Pinned NixOS minimal profile](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/nixos/modules/profiles/minimal.nix) | Audit defaults selectively, not a wholesale profile import | Profile disables docs, optional system packages, XDG MIME/icons/autostart and UDisks; those are different capability/cost decisions |
| [Pinned NixOS default packages](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/nixos/modules/config/system-path.nix#L52-L65) | Understand direct installation vs transitive references | Default Perl, rsync, strace are not three resident daemons; retain until a concrete closure/compatibility tradeoff is accepted |
| [EveryByteCounts](https://everybytecounts.org/) and [Sway community example](https://www.reddit.com/r/unixporn/comments/1qrxbo4/sway_under_300mb_idle_finally_achieved_it/) (secondary) | Hypothesis generation: a light Linux desktop is possible, investigate included services and measurement definition | No matched kernel, GPU, RAM, application set, cache history or evidence of Jay/IME/remote access parity; do not transfer the claimed totals |
| [wcbench](https://github.com/grigio/wayland-compositor-bench) | Separate compositor/core and support stack, measure working set, wakeups and post-close drift; at least three independent runs | Its compatibility with Jay and async flips is not established; do not add it to the default closure |
| [systemd graphical-session.target](https://freedesktop.org/software/systemd/man/latest/systemd.special.html#graphical-session.target) and [daemon activation](https://www.freedesktop.org/software/systemd/man/latest/daemon.html) | One lifecycle owner per capability; activation does not imply idle exit | Never stop an active provider to achieve an idle screenshot; do not add a second supervisor |
| [Kernel /proc accounting](https://docs.kernel.org/filesystems/proc.html) and [allocation profiling](https://www.kernel.org/doc/html/latest/mm/allocation-profiling.html) | Compare Effective Used, residual, PSS partitions and allocation tags on identical hardware | Reserve/discount is an estimate, not allocated memory; no watermarks, drop_caches, artificial memory pressure or swap tricks |

Jay v1.15.0 [release notes](https://github.com/mahkoh/jay/blob/v1.15.0/release-notes.md)
already describe ownership of graphical-session.target; do not introduce a
second target manager on the assumption that a direct VT launcher has no
session lifecycle. Verify its actual status and activation environment
after login/logout and restart. The [GVFS module at the pinned revision](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/nixos/modules/services/desktops/gvfs.nix)
registers D-Bus and systemd providers, enables UDisks2, and exposes GIO
modules. Fileman selects it explicitly. Installing udiskie does not prove a
running automounter. Do not disable GVFS backends or UDisks on package-name
evidence alone; FileChooser, trash, removable storage, network shares and
the .osk/Ark route are separate acceptance surfaces.

## Architecture: ownership and time of consumption

| Capability | Selected owner | Lifetime / rule |
| --- | --- | --- |
| Presentation, input, workspace, screenshots | Jay + grim/slurp/wl-clipboard | Session / operation; immutable tested presentation contract |
| Audio and real-time admission | PipeWire, WirePlumber, RTKit, ALSA | Preserve socket/graph semantics; no global quantum override |
| Launching and clipboard | Stock Rofi, cclip, Jay native binding, Herdr OSC 52 | Rofi operation; capture session; no Tofi, no new daemon |
| Japanese input | Fcitx5 + Mozc | Session, narrow privileged boundary as before |
| Files and portal | Fileman, UDisks2, GVFS, GTK portal, Jay portal, dconf | Session / bus activation; keep successful provider, verify idle exit separately |
| Notifications | Existing systemd-owned Mako D-Bus provider | Native activation; no duplicate notification owner |
| Connectivity / authority | NetworkManager, wpa_supplicant, logind, polkit, Tailscale, SSH | Maintain connectivity, login, removable media and recovery authority |
| Build and agent execution | Nix client/daemon, SSH remote builder, Herdr | Remote execution when available; preserve local admission and recovery |
| Desktop controls | desktop-tools | User selection, installed commands, no new daemon |
| Recording | obs-studio | Independent app selection; no automatic capture |
| Effects | easyeffects | Independent app selection; preserve SplitCast exclusion |
| Browser, games, editing, communications | Existing explicit host selections | Operator-launched; not part of idle baseline |

The old desktop bundle is retained as an inactive compatibility choice;
neko5 no longer selects it. OBS and EasyEffects remain selected, not
silently removed from the user's normal environment. They can be disabled
independently if the operator decides their capabilities are unnecessary.
Installed tools, activated providers, and resident memory are different
costs. No feature requires a new config DSL or a special boot profile.

## Implemented candidate: kernel-first allocation policy

The operator's post-workload idle capture reported Effective Used
1073.90 MiB and non-cache residual 769.48 MiB; the estimated reserve and
reclaimability discount were 304.42 MiB. Earlier lighter-session capture
was 920.30 MiB; an active Firefox sample was 4623.42 MiB. They are not
controlled A/B runs. Root PSS in the post-workload sample was approximately
569 MiB, of which about 252 MiB anonymous. PSS, shmem, DRM resident and
unevictable memory overlap. No sum of those categories is a physical
footprint. Memory PSI and swap use were zero in the supplied snapshots.

| Direct operator evidence | Candidate policy | Estimate, not result |
| --- | --- | --- |
| zram 8,258,580,480 bytes at 50%, LZ4, priority 100; no used swap; physical swap remains | zswap/LZ4 over existing physical swap; zram disabled | ~30.83 MiB gross metadata opportunity, not net savings |
| alloc_page_ext ~29.75 MiB; profiling 1, compression 0, PAGE_OWNER disabled | compile out allocation profiling | Up to ~29.75 MiB if the page extension is no longer needed |
| unnecessary mapped Asahi/DZN libraries ~3.26 MiB PSS combined | Leave ICDs unchanged | Reclaimable mappings, insufficient benefit to add loader policy |
| Jay DRM client resident ~140 MiB after workload | Protect stock Jay and Mesa | No allocation shrinkage claim |

Implementation: [host resource policy](../../modules/00-hosts/neko5/resources.nix).
zram capacity is not allocated compressed data; the kernel maintains
per-slot metadata even while empty. See [kernel zram documentation](https://docs.kernel.org/admin-guide/blockdev/zram.html)
and [pinned NixOS option](https://github.com/NixOS/nixpkgs/blob/f68407657ad294471eb4b2e65d193df26edf729f/nixos/modules/config/zram.nix).
The normal kernel is configured for eight logical CPUs and allocation profiling is compiled out. The stock kernel generation remains the diagnostic and rollback route. The selected zswap compressor is LZ4. No savings from the smaller CPU limit or slab extensions are counted without measurement. Do not change min_free_kbytes,
watermark_scale_factor, overcommit, swap priority, driver buffers or
runtime cache policy to make a number look smaller.

The estimated fixed-allocation opportunity is ~61 MiB gross, not a verified
Effective Used delta, and not a path to 400 MiB on its own. Other candidates
require evidence before configuration changes: the separately retained interaction candidate (foot, Thunar, native Firefox picker);
portal teardown and stale D-Bus environment; GVFS optional backend
activation; lock/PAM/suspend/resume; system package and closure attribution.
Retain current providers until replacement is proven. No arbitrary daemon
disable, custom Mesa/Jay build, tmpfs logs or blanket default-package removal.

## Admission: comparable baseline without a second production profile

Use the same physical host, kernel source version, panel mode, package pins, power source,
network/SSH policy, user identity and workload. On three independent boots
of each reviewed generation, collect five read-only snapshots 10 seconds
apart after at least 120 seconds of settled idle. Label each phase:
1. Normal VT, before starting Jay (system + user login foundation).
2. Normal Jay, no operator-launched application (support stack).
3. Normal terminal + Herdr and typical active workload, then close only
   the apps opened for the trial (post-workload drift).

From the checkout, each snapshot is
`sudo python3 scripts/desktop/memory-snapshot.py`. Retain JSON locally
with boot ID, exact generation (`readlink -f /run/current-system`), phase
and timestamp. Compare medians across boots, within-boot range and
post-close drift. Do not drop caches, kill agents, alter services, or
manufacture a low-memory screenshot. Report missing process PSS separately.
For resident userspace, also use Pss_Anon/Pss_File/Pss_Shmem in
/proc/PID/smaps_rollup and deduplicated DRM client accounting; never sum
overlapping categories. Root collection is observation, not root activation.

For a research-only QEMU reference on neko7, boot the same pinned NixOS
minimal and ordinary base with identical kernel configuration, vCPU count
and 4/8/16 GiB RAM, separate disposable guests, no physical HOME or secrets.
Report the harness overhead and VM-specific devices; this can investigate
RAM-dependent accounting, not physical i915 or Jay. No VM benchmark has
been executed and no infrastructure or new production profile is included
in this change.

After separate approval to stage and boot, check the running kernel config, all eight online CPUs, zswap enabled/LZ4 and the existing physical swap. No zram device or allocation profiling should be active. Compare residual and Effective Used at matched workload. Reject if swap capacity/pressure, major faults or any protected performance or integration acceptance regresses. See the desktop runbook for build,
activation and rollback boundaries.

### Integration acceptance

Verify 100 launcher/clipboard open-cancel cycles and exact paste content,
screenshot/restore, Japanese GTK and Qt input, Herdr local and remote OSC 52,
GTK file selection and dconf persistence, mount/unmount and trash,
notification ownership, graphical-session.target and portal reactivation
after Jay exit/re-entry, lock/authentication/suspend/resume (currently
unaccepted), and no new lingering daemon or privileged client. Keep the
existing 40-minute osu!/Discord playback acceptance, Q64 ceiling, RR/20,
ALSA H0 and steady async flip evidence. Zero new regressions; numerical
latency claims require the corresponding live measurement, not CI.

Closure inspection: after explicitly approved non-activating builds,
`nix path-info -Sh /run/current-system` and
`nix store diff-closures /run/current-system ./result`. For a suspected
dependency use `nix why-depends ./result /nix/store/<exact-path>`. Closure
size is not uniquely occupied disk bytes; historical generations, sharing
and mutable data remain separate. No GC is part of this work.

## CI and evidence tier

The normal host and Gamescope reference must evaluate with the new resource
policy and all existing audio/desktop assertions. The stack-parent gate
compares the full parsed Jay TOML, native protected policy, and direct home
package names and derivations against the PR base; only the explicit zswap kernel arguments are permitted. It does not prove equal closure size or
runtime behavior. The parent a8461262 CI was red: the concrete Home feature
fixture still expected Tofi, and its historical one-time refactor comparator
rejected the intentional Rofi shortcut transition. This stack corrects the
current feature fixture; the parent branch is not modified. The old PR #81
one-time comparator still requires a separate parent correction before
parent merge. GitHub CI and physical admission remain distinct.
