# SplitCast Rust candidate

SplitCast keeps game capture and transport on neko5 and moves production work to neko7. Official osu!lazer and its bundled libraries remain untouched. The candidate is **partial, not production-ready**. Nix keeps neko5 capture disabled and `rustCandidate=false`. With Python removed, the false setting selects an explicit migration gate, not a hidden Rust or Python fallback.

## Use without changing the running system

```sh
nix build .#splitcast-rs-core
result/bin/splitcast validate --config packages/splitcast-rs/example.toml
result/bin/splitcast doctor --offline --config packages/splitcast-rs/example.toml
result/bin/splitcast agent --config /private/path/capture.toml
result/bin/splitcast tui --config /private/path/capture.toml
```

`validate` needs no agent or credentials. `doctor` reports local prerequisites, not successful capture or gameplay safety. Provision each configured control token as a private, user-owned file. The agent does not print tokens or stream keys. Run the TUI against the loopback agent. Browser assets are built from Rust/WASM and use the same portable command crate. Desktop GPUI is not implemented.

The example has no selected game/audio devices and does not authorize capture. Start defaults to recording. Twitch requires an explicit output selection and separate operator permission. Agent startup never starts an output.

## Structure

- `splitcast-protocol` owns portable, validated commands used by native and WASM clients.
- `lifecycle.rs` owns phase, authority, lease expiry and explicit output selection. Idle has no authority. Running always carries its selected output.
- `workers.rs` owns typed native workers. Every owned worker is included in teardown automatically.
- `agent.rs` coordinates effects. It is still larger than the target role-specific backend design and is not a completed architectural migration.
- `audio.rs` gives production its own cookie-authenticated Unix-socket Pulse server and null sink. No physical device module or player audio route is loaded.
- `media.rs` defines native video workers and local monotonic receive observations. Those observations are not an end-to-end frame-age measurement.
- `obs.rs` uses native Rust WebSocket, authentication, JSON and base64 handling with total deadlines.
- `tts.rs` is a tested, bounded synthesis component. End-to-end delivery, playback, remote mixing and EventSub remain incomplete and are refused by the live command path.
- `tui.rs` and `splitcast-web` are views, not independent lifecycle controllers.

## Verify

```sh
cd packages/splitcast-rs
cargo test --locked --offline
cargo clippy --all-targets --locked --offline -- -D warnings
cargo test private_audio_dies -- --ignored --nocapture
```

The ignored audio test requires `pulseaudio` and `pactl`. The ignored synthetic SSH test requires explicit two-host authorization and its documented staged tools. Neither runs during ordinary unit tests. The subprocess tests need a C linker, `bash` and coreutils during development.

Read [the design wiki](../../docs/graphics-streaming/wiki/INDEX.md), [run evidence](../../docs/graphics-streaming/rust-completion-20261113.md), and [synthetic SSH evidence](../../docs/evidence/splitcast-synthetic-ssh-20261113.md) before interpreting a passing check. Package builds, synthetic recording and loopback API tests do not establish feature parity or competitive non-regression.

## Remaining acceptance gates

Native GSR capture, authorized game-only audio, moving OBS decode/preview, end-to-end mic and camera paths, RNNoise, TTS delivery, EventSub, shared route transactions, congestion recovery and gameplay non-regression are not accepted. GSR/gameplay testing is blocked by the absent privileged KMS helper and lack of an authorized active-game trial. Do not replace that path with portal capture, disable Direct Scanout, or modify the game to make a test pass.

There is no retained Python runtime. To recover the former implementation, use the earlier Git revision or an already-existing NixOS generation with the operator's approval. Do not activate a generation, enable Rust selection or publish Twitch output as part of a build or test.
