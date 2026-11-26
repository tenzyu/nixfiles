# Why the Parsec settings exist

The first Parsec module declared `decoder_software=0` (hardware decoding),
`client_decoder_h265=1` (try HEVC with H.264 fallback), `client_vsync=0`, and
`client_overlay_warnings=1` (show network and hardware warnings). The source
records the values. Hardware decoding and disabled VSync suggest a preference for lower client latency.
Parsec documents the tradeoff between latency and tearing. The commit supplies no benchmark or reason for each choice.
[Original client settings](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L13-L24)
· [Parsec advanced options](https://support.parsec.app/hc/en-us/articles/32381443626516-All-Advanced-Configuration-Options)

The same source identifies the neko5 Dynabook touchpad as `HID Controller #14`
(`06CB/83D7`) and describes a constantly active fake gamepad. It uses an
all-unmapped row for that one ID and separately sets SDL environment variables
in the XWayland launcher to limit false controller detection. Parsec documents
per-controller mapping and unmapping in the Gamepad section of Settings. The on-disk
`_00` row and the effect of the SDL flags on this device come from repository
history. Current behavior on neko5 and the effect on real controllers remain
unverified here.
[Original launcher](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L50-L66)
· [Original mapping hook](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L90-L112)
· [Parsec Linux Gamepad settings](https://support.parsec.app/hc/en-us/articles/32381494397332-Parsec-App-for-Linux#gamepad)
· [Parsec stuck inputs guidance](https://support.parsec.app/hc/en-us/articles/32361336267412-Parsec-Constantly-Pressing-or-Scrolling-Up-Down)

The original module records an `EROFS` error when a Home Manager store
symlink was used for `config.txt`. Parsec documents that, since `150-89`, it
imports legacy assignments into `~/.parsec/config.json` on restart and clears
the imported settings from `config.txt`. The committed Linux package version
is `150_104a`. Parsec documents editing `config.json` directly with settings
stored in `{"value": …}` objects, then restarting the app. The first-run seed
uses that native format. First-launch behavior remains a host acceptance check.
[Original write rationale](https://github.com/tenzyu/nixfiles/blob/c64bff27a0ee472f9c3fa508452d9dadc0154818/modules/50-features/parsec.nix#L71-L87)
· [Current package and seed](../../modules/50-features/services/parsec.nix)
· [Parsec configuration and migration](https://support.parsec.app/hc/en-us/articles/32381346632596-Accessing-Your-Advanced-Settings)

See the [settings review procedure](README.md).
