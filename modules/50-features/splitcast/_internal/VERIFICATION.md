# Nix integration verification

The Nix worker started from `3cf330792d31df0721289d91e5643aa5fdee8f77` in `/tmp/opencode/splitcast-nix`.
Files were published with `apply_patch` into `/home/tenzyu/.nixfiles` after syntax and option inspection.
The application worker published the app before the package and generated-configuration checks ran.
All results below were observed on 2026-11-01.

| Check | Status | Evidence |
| --- | --- | --- |
| Nix syntax | PASS | `nix-instantiate --parse` accepted all 12 changed Nix files |
| Nix formatting | PASS | Alejandra 4.0.0 `--check` accepted all 12 changed Nix files |
| Whitespace | PASS | `git diff --check` |
| Feature registration | PASS | NixOS and Home Manager expose both role names through `flake.modules` |
| Unit configuration | PASS | Evaluated both real host user units. `Install.WantedBy=[]`, `KillMode=control-group`, `Restart=on-failure`, `RestartSec=5`, `StartLimitBurst=3`, `StartLimitIntervalSec=60`, and `TimeoutStopSec=20` |
| Host package selection | PASS | Evaluated neko5's final Home Manager package list. EasyEffects is absent and the existing `obs-studio` remains |
| Production audio | PASS, evaluation | neko7 evaluates PipeWire and Pulse compatibility to `true` |
| Capture privilege wrapper | PASS, evaluation | neko5 evaluates `programs.gpu-screen-recorder.enable` to `true` |
| Optional isolated display | PASS, evaluation | An extended neko7 module with `services.splitcast-display.enable=true` and `user="tenzyu"` evaluates a manual Xorg unit with `-nolisten tcp`. The host default remains disabled |
| OBS source patch | PASS | `git apply --check` against the locked OBS source and a complete dedicated OBS build |
| CLI package | PASS | Complete package build and packaged `splitcast --help` |
| Package behavior | PASS | `checks.x86_64-linux.splitcast-package` loads the app example, imports websocket-client, and runs actual FFmpeg LADSPA processing |
| Generated role configs | PASS | Both JSON derivations build. `checks.x86_64-linux.splitcast-configs` validates both with the packaged app and checks roles, ports, SSH peers, and dependency paths |
| Full host evaluation | BLOCKED | Normal evaluation exceeded a 240-second timeout during existing Catppuccin IFD dependencies. A diagnostic run with `--no-allow-import-from-derivation` identifies Catppuccin Firefox on neko5 and Catppuccin palette on neko7 |
| Both complete host toplevel builds | NOT_RUN | Full evaluation must complete first. Targeted SplitCast checks pass independently |
| Optional VOICEVOX package | BLOCKED | `nix build --no-link path:/home/tenzyu/.nixfiles#splitcast-voicevox` exceeded a 1200-second timeout. The model dependency log reached fixup. This is not a completed engine build or synthesis test |
| Live OBS listener and NVIDIA display | NOT_RUN | No OBS or display service was started |
| Deployment and service activation | NOT_RUN | No system generation was activated and no service was started |

## Successful build outputs

- `splitcast-obs` produced `/nix/store/jrbma5c750j0c5lv7md06ms9if84zivk-obs-studio-splitcast-32.1.2`.
- `splitcast` produced `/nix/store/pl7g7h76d8ajbgib6fyx14bwhlp0m78q-splitcast-0.1.0`.
- `splitcast-package` produced `/nix/store/k10qy0a2hfa9b1ksxxgqd9rayb5x3hqp-splitcast-package-check`.
- `splitcast-configs` produced `/nix/store/ps208wy8phhzm65b28ws004s6i68x2iv-splitcast-host-configs-check`.
- Capture JSON produced `/nix/store/3wxn0hzp99lcwcb7b0g0f3g7738x06n5-splitcast-capture.json`.
- Production JSON produced `/nix/store/009rrb1zri8x3y1q7sydm4rk5djs3j7w-splitcast-production.json`.

The first package check used a single RNNoise control and failed with `Control c3 must be set`.
The final check reads the application example's label and five-control vector instead of maintaining separate defaults.
The final package and configuration checks pass.

## Locked dependency versions

| Dependency | Version |
| --- | --- |
| Python | 3.13.15 |
| websocket-client | 1.9.0 |
| ffmpeg-full | 8.1.2 |
| GPU Screen Recorder | 5.13.8 |
| PipeWire | 1.6.6 |
| Pulse tools | 17.0 |
| MediaMTX | 1.18.2 |
| v4l-utils | 1.32.0 |
| RNNoise plugin | 1.10 |
| Dedicated OBS | 32.1.2 |
| Optional VOICEVOX engine | 0.25.2 |
| Optional VOICEVOX core | 0.16.2 |
| Optional VOICEVOX models | 0.16.4 |
| Optional VOICEVOX ONNX runtime | 1.17.3 |

The evaluated ffmpeg-full flags include `--enable-libpulse`, `--enable-ladspa`, `--enable-nvenc`, and network support.
RNNoise processing also passed with the actual FFmpeg binary and plugin.
The OBS build includes `obs-nvenc.so`, `obs-websocket.so`, `obs-ffmpeg.so`, and `text-freetype2.so`.
These package checks do not establish physical-device or NVENC runtime acceptance.

Exact repeatable build commands and manual operation commands are in [README.md](README.md).
