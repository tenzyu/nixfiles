# Graphics and distributed streaming research

This folder contains historical research, not active machine state. For executed behavior, consult `modules/`, `scripts/`, `packages/`, and the running host. `git push` does not imply NixOS activation.

- [User-approved implementation boundaries](DECISIONS-2026-11-06.md): stock OBS, Rust migration and rollback.
- [Implementation research](RESEARCH-2026-11-05.md): observed graphics, audio and capture limitations; dated material.
- [System RFC](SYSTEM-RFC.md): kernel/i915, DMA-BUF, transport/security alternatives; proposal, not deployment.
- [Graphics lab scripts](../../scripts/graphics-lab/README.md): diagnostics and experiments.
- [SplitCast Rust candidate](../../packages/splitcast-rs/README.md): not yet demonstrated as a production replacement.

The separately supplied *osu! LLM Wiki, 2026-11-13* is the organized working knowledge base for neko5 input, audio, update and draw. It is not in this repository; no relative link is assumed. Six identical historical files were removed here after checking Git blob hashes against the copy in that wiki. The original files remain available in [Git history](https://github.com/tenzyu/nixfiles/tree/1d05b8b6901c6b9f0d990f2b88009867932c1321/docs/graphics-streaming).

Other evidence, including SplitCast logs, is retained pending source-preserving consolidation. Preserve distinctions among `PASS`, `FAIL`, `NOT_RUN`, and `BLOCKED`. For fullscreen, the 2026-11-12 observed 2/0 state produced 10/10 Direct Scanout samples; do not reintroduce the removed static window rule.
