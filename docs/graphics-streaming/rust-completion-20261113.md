# Rust completion evidence

## Goal and evidence boundary

Make neko5 to neko7 SplitCast usable under Rust ownership without changing official osu!lazer or sacrificing local gameplay. This report distinguishes target, source facts, local observations and blocked live checks. It is not a cutover approval.

The attached Wiki was extracted outside Git at `/tmp/opencode/splitcast-wiki-20261113/osu-llm-wiki`. Its private raw evidence is not included in this repository. Read order was `entrypoints/OPENCODE.md`, `MEMORY.md`, `wiki/INDEX.md`, `wiki/CONTRACT.md`, `wiki/SPLITCAST-TARGET.md`, then `wiki/SCENARIOS.md`.

## Reference and running system

| Item | Observation |
| --- | --- |
| Fetched origin/main | `6ceeb53b0d1e267fa01f04c94fdb6226877c93cf` |
| Reference capture time | 2026-11-13 14:43 JST |
| Original checkout | Local main at `cd9fece`, five local commits retained unchanged |
| Work branch | `splitcast-rust-completion-20261113`, based on fetched origin/main |
| Execution host | neko7 |
| neko7 running generation | `/nix/store/j1wxm4gnqk19ga8b3fpgi81i1zcpg2pl-nixos-system-neko7-26.05.20261020.cd4ea8d` |
| neko7 named user services | `splitcast-agent.service`, `splitcast-production.service`, `splitcast-capture.service` reported inactive |
| neko5 live access | `ssh -o BatchMode=yes -o ConnectTimeout=8 neko5` failed with `Permission denied (publickey)` |
| neko5 running generation | BLOCKED. No authenticated host access established. |

The running generation is not inferred from Git. No NixOS activation or production service change was performed.

## Initial verification

The first offline Cargo test attempt could not link because the shell had no `cc`. This is an environment failure, not a failing behavioral assertion. The next test shell must explicitly provide a C compiler.

## Completion gates

- Feature parity is NOT VERIFIED.
- Two-host operation is BLOCKED by neko5 SSH authentication at this point.
- Competitive non-regression is BLOCKED by lack of live neko5 access. Historical DSO observations do not prove a new capture path.
- Production migration is NOT AUTHORIZED. Preserve both deployment gates and require separate approval for Twitch publication.
