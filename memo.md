# SplitCast operator decisions

These instructions supplement the 2026-11-13 task. They do not prove implementation or deployment.

- Primary configuration is TOML. Keep one validation contract for TOML and any transitional JSON input used by Nix and differential tests.
- Prefer a usable TUI for selecting source, processor and target. Do not allow arbitrary connections that capture unapproved audio or create loopback.
- Any desktop GUI uses Zed's GPUI. A browser control interface and desktop GUI are different clients.
- Write all application logic in Rust. Use Rust/WASM for browser views. JavaScript, if required for generated WASM loading, contains no command, validation, lifecycle or rendering logic. Views use the same Rust control model.
- Remove SplitCast Python runtime code and its service delegation. Use the pre-migration Git revision only as a development oracle, not an installed runtime dependency.
- The operator subsequently authorized direct commit/push to main and waived PR creation. Never force-push or discard the original checkout's five local commits.
- NixOS switch, production service cutover, public ports, Twitch publication and game/library modifications remain prohibited without separate approval.
- Keep `rustCandidate=false` and neko5 capture disabled until feature parity and competitive non-regression are proved and the operator approves cutover.
- Use focused TDD for cheap behavioral regressions. Preserve real failing-before and passing-after evidence. Compilation failure is not behavioral red evidence.
- At most three child agents run concurrently. Limit repair/retest loops for a blocker to three cycles and report remaining gaps honestly.

The Python oracle archive is outside Git at `/tmp/opencode/splitcast-python-oracle-6ceeb53.tar`. Its source revision is `6ceeb53b0d1e267fa01f04c94fdb6226877c93cf`.
