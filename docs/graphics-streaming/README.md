# Graphics and distributed streaming research

- [User-approved implementation boundaries](DECISIONS-2026-11-06.md): host changes, stock OBS security, Rust migration and rollback.
- [Implementation research](RESEARCH-2026-11-05.md): observed input, graphics, fullscreen, OBS EGL crash, capture and NixOS behavior.
- [System RFC](SYSTEM-RFC.md): kernel/i915, EGL, DMA-BUF, media-pipeline alternatives, Rust control, security and acceptance criteria; a **proposal**, not a deployed optimization.
- [Read-only diagnostics and isolated KMS capture test](../../scripts/graphics-lab/README.md).
- [Rust migration foundation](../../packages/splitcast-rs/README.md): typed state machine and process ownership; not an active service.

Keep historical evidence in `docs/evidence/`; do not mark hardware acceptance passed from unit tests. The known-good manual `Win+F` remains the fallback while the static rule is validated.
