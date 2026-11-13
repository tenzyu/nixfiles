# Canonical asset maintenance (protection against knowledge drift)

When new verified evidence arrives, update **the same** canonical artifacts **in the same patch**, rather than adding a detached supplement and asking the reader to reconcile it.

Authoritative repo paths:

- `docs/graphics-streaming/NEKO5-OBSERVED-2026-11-07.md` — dated snapshot and known unknowns.
- `docs/graphics-streaming/EVIDENCE-2026-11-07.tsv` — claim-level authority with limitations.
- `docs/graphics-streaming/PRIORITY-2026-11-07.tsv` — ranked work, evidence and acceptance gates.
- `docs/graphics-streaming/ADR-2026-11-07-performance-first.md` — ideal target and no-regression invariants.
- `docs/graphics-streaming/SPLITCAST-AGENT-PORTING-2026-11-07.md` — implementation/port roadmap.
- `docs/graphics-streaming/architecture/index.html`, eight layer SVGs, and `REPORT-2026-11-07.md` — **replace in place**, not appendix-only.
- `docs/graphics-streaming/architecture/facts-2026-11-07.json` — machine-readable nonsecret snapshot summary.
- `docs/graphics-streaming/SYSTEM-RFC.md` — historical context; always point to current target docs.

For the next measurement, create a **new dated facts snapshot** and either rename/update the canonical HTML/report accordingly or clearly mark that they have become historical, while supplying the newly rebuilt HTML with the current data. Do not silently overwrite raw evidence. Include the base `main` SHA and committed source identity. Never copy private serials, MACs, tokens or network IPs into public docs.

Minimum synchronisation steps for an agent:

1. Parse latest user-designated raw files and assign one evidence ID per concrete claim. Keep mismatches and missing fields explicit; do not infer values by mixing dates.
2. Recompute units and quantities; distinguish USB endpoint `bInterval` from real HID sample cadence, ALSA ring capacity from acoustic latency, and DSO sample ratio from presented-frame success rate.
3. Update every node affected by a changed claim **inside the SVG and card text**, plus overview, report, priority/ADR and code comments. The HTML must retain all six original detailed paths (Input, Audio, Update/Draw, SplitCast, Kernel, Overview) and the measured/verified tabs.
4. Regenerate/export each standalone SVG from the HTML source. Test SVG XML parse, HTML tab count and JS syntax. Run `python3 scripts/osu-performance/verify-assets.py` from repo root. This check catches some stale labels but is not a scientific verification.
5. Produce a fresh `git diff` patch relative to the currently confirmed `main` commit. `git apply --check`, apply and reverse-check against an exact working tree; run Nix evaluation/build if available. Report any skipped validation clearly.
6. Do not turn measurement hypotheses into installed tuning by copying an ADR. Default gamer/runtime configuration only changes after paired measurements, passing guards, and explicit approval for system activation.

The evidence hierarchy is: current user-designated runtime capture > exact running-code/driver implementation > fresh upstream primary docs > existing repo implementation (migration inventory) > historical ADRs > hypothesis. This is **source relevance** ordering, not an assumption that a single snapshot proves causality.

New 15:30 audio evidence is embedded into the existing diagram and canonical report, not a detached explanatory note. See `AUDIO-VALIDATION-2026-11-07.md` and `facts-2026-11-07.json.follow_up_2026_11_07_1530`. Always distinguish driver graph quantum from follower suggestions, ALSA period from buffered data, and physically emitted sound from software scheduling. Current direct-scanout success condition remains unchanged.
