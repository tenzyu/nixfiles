# Documentation index

`flake.nix`, `modules/`, `packages/`, and `scripts/` are the executable definitions. Git state is not proof of deployment on either host.

- [Graphics/streaming historical research](graphics-streaming/README.md) — prior proposals and evidence, not authoritative for current runtime.
- [SplitCast end-to-end evidence](E2E_RESULTS.md) and [Nix verification gates](evidence/splitcast-nix-gates.md) — preserve unfinished and failed gates.
- [SplitCast historical architecture](ARCHITECTURE_DECISIONS.md), [remote-development notes](splitcast-remote-development.md), and [neko7 migration](opencode-neko7-migration.md).

The user-provided *osu! LLM Wiki* (2026-11-13) is maintained separately from this Git repository; it holds the working summaries and raw captures for neko5 osu! optimisation. Do not automatically replace that source of evidence with dated documents under `docs/`.

Six byte-identical archived copies were removed from `docs/graphics-streaming/`; they remain recoverable in [the pre-cleanup commit](https://github.com/tenzyu/nixfiles/tree/1d05b8b6901c6b9f0d990f2b88009867932c1321/docs/graphics-streaming) and in the supplied wiki. Remaining SplitCast logs under `docs/evidence/` have not been shown redundant and are deliberately retained for a separate source-preserving pass.
