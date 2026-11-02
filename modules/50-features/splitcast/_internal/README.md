# SplitCast Nix integration

## Feature ownership

`splitcast-capture` and `splitcast-production` each register a NixOS module and a Home Manager module through `flake.modules`.
The framework owns their `local.features.<name>.enable` options.
NixOS enables PipeWire, Pulse compatibility, WirePlumber, and graphics support.
The capture role also enables the NixOS GSR capability wrapper.
Home Manager installs the CLI, generates JSON, and defines one user agent unit.

neko5 explicitly enables capture for tenzyu. neko7 explicitly enables production for tenzyu.
The peer SSH host is selected in each host's `home-manager.users.tenzyu` configuration.
The desktop package list omits EasyEffects only when the capture feature is enabled.

The agent owns MediaMTX, FFmpeg, and its dedicated OBS child.
systemd owns the outer cgroup. There are no separate media units.
The agent units have an empty `Install.WantedBy` and require a manual start.
They restart after failure with a five-second delay and a limit of three starts per minute.
Stop sends signals to the entire cgroup and permits SIGKILL after 20 seconds.
The capture unit does not set `NoNewPrivileges`, because GSR uses the NixOS capability wrapper.

## Home Manager options

Each role has the following options under `local.features.splitcast-<role>`.

| Option | Type | Default |
| --- | --- | --- |
| `enable` | boolean | `false`, supplied by the framework |
| `package` | package | `pkgs.callPackage packages/splitcast {}` |
| `settings` | attribute set of JSON values | `{}` |
| `configFile` | absolute path string | generated JSON in the Nix store |
| `environment` | attribute set of strings | `{}` |

The generated file also appears at `~/.config/splitcast/capture.json` or `~/.config/splitcast/production.json`.
Configuration generation reads `package.example` with `builtins.fromJSON`.
The merge order is the application example, role defaults, then `settings`.
The application validates the resulting schema. Nix accepts only JSON values, not arbitrary Nix values.
`settings` contains credential paths. Secret values belong in runtime files with mode 0600.
An external `configFile` changes the agent's input path. The generated reference file remains available.
The application owns mutable runtime selections.

The capture control port is 17870. Production uses 17871.
Capture forwards remote control to 17872. Production reserves 17873 for the opposite direction.
The production token path is `~/.config/splitcast/production.token`.
The capture token path is `~/.config/splitcast/control.token`.
The application example owns media defaults for RTMP 1935, RTSP 8554, MediaMTX API 9997, OBS 4455, and VOICEVOX 50021.
Cross-host connections use SSH forwarding. The Nix features add no firewall rules.

## Packages

`packages.<system>.splitcast` wraps Python as `splitcast`, with `-m splitcast` and a packaged `PYTHONPATH`.
The wrapper supplies Python, websocket-client, ffmpeg-full, GPU Screen Recorder, PipeWire tools, Pulse tools, MediaMTX, V4L2 tools, OpenSSH, coreutils, procps, iproute2, and dedicated OBS on `PATH`.
`LADSPA_PATH` points to the RNNoise LADSPA output.
The generated `audio.rnnoise_plugin` names `librnnoise_ladspa.so` by its store path.
The generated `obs.binary` names the dedicated OBS binary by its store path.

`packages.<system>.splitcast-obs` is OBS with the WebSocket server patched to bind an explicit IPv4 loopback endpoint.
The upstream `ipv4_only` option binds wildcard IPv4 and is insufficient.
The dedicated package omits CEF browser sources. FFmpeg media sources, text, images, NVENC, and WebSocket remain enabled.
The user's existing `obs-studio` package remains independently installed.

`packages.<system>.splitcast-voicevox` is the locked nixpkgs VOICEVOX engine.
That package includes the engine, its wrapped core, models, and ONNX runtime.
Its package set permits only the `voicevox-onnxruntime` unfree dependency.
The integration does not create a VOICEVOX service. TTS remains disabled in the example until configured.
The engine is an external prerequisite for TTS, on production loopback only.

## Command reference

These commands build artifacts without activating a system generation.

```sh
nix build --no-link path:/home/tenzyu/.nixfiles#splitcast
nix build --no-link path:/home/tenzyu/.nixfiles#splitcast-obs
nix build --no-link path:/home/tenzyu/.nixfiles#checks.x86_64-linux.splitcast-package
nix build --no-link path:/home/tenzyu/.nixfiles#checks.x86_64-linux.splitcast-configs
nix build --no-link path:/home/tenzyu/.nixfiles#nixosConfigurations.neko5.config.system.build.toplevel
nix build --no-link path:/home/tenzyu/.nixfiles#nixosConfigurations.neko7.config.system.build.toplevel
```

After an operator deploys the configuration, the manual control-agent commands are as follows.
Starting an agent exposes its UI and control API. Media starts only through the application's prepare and start operations.

```sh
# neko5
systemctl --user start splitcast-capture.service
splitcast doctor --config "$HOME/.config/splitcast/capture.json"
splitcast status --config "$HOME/.config/splitcast/capture.json"
systemctl --user stop splitcast-capture.service

# neko7
systemctl --user start splitcast-production.service
splitcast doctor --config "$HOME/.config/splitcast/production.json"
systemctl --user stop splitcast-production.service

# Optional production VOICEVOX process, manually supervised in this terminal.
nix run path:/home/tenzyu/.nixfiles#splitcast-voicevox -- --host 127.0.0.1 --port 50021
```

## Optional isolated production display

The NixOS production module declares `services.splitcast-display.enable`, `user`, and `display`.
Defaults are `false`, an empty user name, and display number 99.
An enabled display requires an existing user and the NVIDIA driver.
The Xorg unit has no `wantedBy`, uses a per-start Xauthority cookie, and disables TCP listening.
The display manager and the user's desktop session are independent of this unit.

This NixOS configuration selects the isolated display for the agent.

```nix
services.splitcast-display = {
  enable = true;
  user = "tenzyu";
};
home-manager.users.tenzyu.local.features.splitcast-production.environment = {
  DISPLAY = ":99";
  XAUTHORITY = "/run/splitcast-display/Xauthority";
  QT_QPA_PLATFORM = "xcb";
};
```

After deployment, `sudo systemctl start splitcast-display.service` starts the display manually.
`sudo systemctl stop splitcast-display.service` stops it.
This display is disabled in the host definitions until the operator selects it.
Actual NVIDIA display initialization and OBS rendering require a hardware check.

## Verification ownership

`checks.<system>.splitcast-package` runs the packaged CLI help, imports websocket-client, loads the packaged example through the application validator, and processes synthetic audio through the real RNNoise LADSPA filter with ffmpeg-full.
`checks.x86_64-linux.splitcast-configs` validates the actual generated neko5 and neko7 configurations through the packaged application, including their role, peer, control ports, RNNoise library, and dedicated OBS binary.
This check does not certify camera access, GSR capture, NVENC operation, synchronization, VOICEVOX synthesis, or Twitch output.
