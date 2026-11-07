# SplitCast Rust rewrite (inactive foundation)

A **full migration is the selected direction**, but this crate is not yet feature-parity with `packages/splitcast` (Python). Do not enable it as the live capture or production service. The Nix package `splitcast-rs-core` is opt-in for builds and tests; both host roles retain their current settings.

## Why this crate exists

- Typed lifecycle transitions preserve the `Idle / Preparing / Ready / Running / Degraded / Failed / Stopping` contract.
- A bounded process-group owner creates separate groups and attempts TERM→KILL cleanup, without a shell wrapper. **This is not sufficient for full descendant cleanup if the leader exits early**: a systemd/cgroup v2 owner is required before runtime parity.
- There is no raw frame processing in Rust: media runs in GSR/libva/FFmpeg/OBS, which already use native code.
- No `CAP_SYS_ADMIN`, global sysctl, firewall or compositor change is made by this crate.

## Build / test without modifying any host

```
cd packages/splitcast-rs
cargo test --locked --offline
cargo run --locked --offline -- selfcheck
# or, from the nixfiles root:
nix build .#splitcast-rs-core
```

## Feature parity gates (all currently NOT VERIFIED)

1. Strict schema and routes equivalent to `packages/splitcast/splitcast/config.py` and `example.json`; reject unknown fields and dangerous sources.
2. Authenticated control API with explicit local/remote ownership, token privacy and source-origin checks.
3. Local/remote preparation, SHA/transport compatibility, session lease and bounded retries; no orphaned subprocesses.
4. Real GSR KMS capture, exact game-only audio, SSH/tailnet media transport and MediaMTX receive observations.
5. Mic capture and remote RNNoise; camera passthrough/VAAPI; VOICEVOX/TTS, Twitch/EventSub, observable OBS output.
6. Replay old Python behavioral/negative/real-device tests against Rust; differential results agree, including failure injection and recovery.
7. Verify zero changes to known-good osu! renderer, 1280x720 settings, pen mapping and Direct Scanout before enabling service on neko5.
8. Verify that stock OBS security boundary holds for local, physical network and Tailscale connections on neko7, including after reboot.
9. Explicitly authorize cutover; rollback by selecting existing Python agent and previous NixOS generation.

The incomplete implementation is intentionally unreferenced by `systemd.user.services`.
