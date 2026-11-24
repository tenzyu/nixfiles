# neko5 Slim Desktop experiment

This is a reversible NixOS boot specialisation, not the new default. It uses the
same physical machine, existing home, kernel, Intel driver, audio, thermal
policy, Nix, Tailscale and SSH. No kernel watermark, data migration, power
protection or secrets changes are proposed.

The initial native-Wayland profile uses Jay 1.15.0 from the already locked
unstable input, its built-in bar and solid background, Alacritty, and the
existing on-demand Rofi and D-Bus-activatable Mako. It deliberately does not
start Hyprland, Waybar, hyprpaper, Xwayland, a tray bridge or a status script.
Wired is not selected because it requires X11. No new flake inputs.

## Trial procedure

From the PR checkout, on neko5:

```sh
nix eval --raw .#nixosConfigurations.neko5.config.specialisation.neko5-slim.configuration.system.build.toplevel.drvPath
nix build --no-link .#nixosConfigurations.neko5.config.specialisation.neko5-slim.configuration.system.build.toplevel
```

Only after reviewing the build and existing HOME admission requirements, install
the boot menu generation from the PR checkout on neko5:

```sh
sudo nixos-rebuild boot --flake .#neko5
```

This stages the normal Hyprland generation and its neko5-slim specialisation.
Do not use switch during an active desktop session. Save work, reboot when
ready, and select the neko5-slim entry in systemd-boot. Log in on the local
text VT as the usual user and run:

```sh
exec neko5-slim-session
```

Use Alt+Enter (Alacritty), Alt+P (Rofi), Alt+B (Firefox), Alt+O (raw osu!),
Alt+U (fullscreen), Alt+1 is not bound; Alt+F1 through Alt+F5 select workspaces,
Alt+Shift+C closes a window and Alt+Q exits. If graphics fails, use another VT
(Ctrl+Alt+F2) or SSH. Do not start both compositors at once.

This native-only experiment deliberately omits X11/Parsec compatibility, the
Hyprland-specific osu-first launcher, idle/lock UI and tray widgets.
Notifications, IME, portals/screen sharing, suspend, and native osu! are
runtime acceptance items, not guaranteed by evaluation. Do not leave an
unlocked experimental session unattended. If any required application needs
Xwayland, use the ordinary Hyprland generation rather than quietly changing
the experimental baseline.

## Measurement and decision

Compare the same booted hardware, display mode and network connection, after
five minutes idle with no foreground apps or measurement terminal. Collect
three samples 30 seconds apart from neko7 over SSH, using the same checked-out
script for both profiles:

```sh
ssh neko5 'python3 /home/tenzyu/.nixfiles/scripts/desktop/slim-memory.py'
```

If that checkout is not the PR checkout, substitute its actual path.
The script is read-only. Its PSS list covers only readable processes; run
locally via sudo if a whole-process inventory is needed. The JSON reports
effective used, non-cache residual, estimated reserve, pressure and process
PSS separately. Do not add these accounting categories together.

* Effective used (MemTotal minus MemAvailable): 600 MiB target, not claimed.
* Non-cache residual: report separately; no cache dropping or VM reserve tuning.
* Check expected absence of Hyprland, Waybar, hyprpaper and Xwayland.
* Verify network/Tailscale/SSH, native Firefox, O3C and CTL-472, PipeWire
  and Japanese input; verify screen sharing and authorization prompts if needed.
* Compare osu! p95/p99 frame timing, audio XRUNs, Direct Scanout and tearing
  with the ordinary Hyprland generation. Do not claim input-to-photon results
  from compositor telemetry alone. Reject regressions or missing required
  functionality even if memory is lower.

No real-device or VM graphics measurement has been performed by this PR.

## Rollback

Exit Jay (Alt+Q), save all work and reboot into the ordinary neko5 entry.
If the new boot generation fails, select the previous known-good NixOS
generation in systemd-boot. Do not bypass HOME admission or delete user
data; if activation reports a conflict, stop and inspect it. No HOME path
changes are part of the experiment.
