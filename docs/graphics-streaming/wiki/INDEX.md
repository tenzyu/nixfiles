# SplitCast implementation wiki

The operator's target is a Rust-owned neko5 to neko7 stream that cannot hold up official osu!lazer. This wiki records design rules and their executable checks. It does not replace the attached Wiki's gameplay contract or prove deployment.

- [Design decisions](design.md) explains accepted and rejected structures.
- [Run evidence](../rust-completion-20261113.md) separates source, local verification, host observations and blocked acceptance gates.
- [Operator decisions](../../../memo.md) records later requirements, including TOML, TUI, Rust/WASM, GPUI and removal of Python.

Keep observations dated. A new Git commit is not a new running NixOS generation. A local regression test is not a two-host or competitive-performance test.
