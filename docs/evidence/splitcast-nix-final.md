# SplitCast final Nix gate evidence

This run resumes the required host builds on `feat/splitcast-e2e`. The prior report is [SplitCast Nix gate evidence](splitcast-nix-gates.md).

## Exit condition

Both current host toplevels must finish with exit 0 and valid output paths. Each result must identify its application source. An actual build error, the 1800-second command deadline, or the disk reserve guard can leave a gate incomplete.

The disk guard checks available bytes every five seconds and stops the active command at 22 GiB available to preserve the requested 20 GiB reserve. Elapsed wall time is command logging, not a benchmark.

## Checklist

- [x] State the exit condition as a checkable predicate before the first iteration (tests green, repro fixed, all N PRs merged, pixel-diff zero).
- [x] Pick the wake mechanism using Claude Code's `loop` skill (a built-in, not a pstack skill). An event to watch (CI, a merge, a ref advancing) gets a watcher subagent that wakes you on the event, with a long time-based heartbeat as fallback. No event gets a fixed-interval heartbeat sized to when the result is worth re-checking. Pick each subagent's reasoning level for the job, per the Subagents section.
  - Use the available shell monitor and fixed-interval polling. The user prohibited subagents.
- [ ] Each iteration makes the smallest change the evidence justifies, verifies it against the predicate, commits if it advanced, discards changes that didn't help. Belt-and-suspenders that "might help" gets reverted, not left to ride.
  - Code edits and commits are outside the user-authorized scope. Each iteration executes and records a gate.
- [ ] Mid-run discoveries are yours. Address broken skills, related bugs, flaky verifiers, review noise, tooling failures, orphaned follow-ups, and fixable drift yourself via poteto-mode. Put out-of-band fixes in their own PR. Do not park reversible work for the human or use `AskUserQuestion`. Surface only irreversible actions, genuine product or preference calls no experiment can settle, or a real dead end. Keep the predicate as the main drive, and return to it after each side fix.
  - The main session owns changes to the existing deprecated-pattern check. This run records its observed state.
- [ ] Checkpoint every iteration via the **show-me-your-work** skill, a row for what changed and whether the predicate moved.
  - The decision table below keeps the trail within the two authorized evidence files.
- [ ] Stop when the predicate is met. A plateau is not a stop, so keep going and pivot your approach to push past it. Surface a genuine dead end rather than spinning, and never relax the predicate to declare victory.

## Decision trail

| UTC | Phase | Decision | Reason | Evidence | Result |
| --- | --- | --- | --- | --- | --- |
| 2026-11-01T15:05:01Z | Start | Resume neko7, then build neko5 against the current package. | Earlier neko7 stopped at its deadline and earlier neko5 used older application source. | `splitcast-nix-gates.md` | In progress |

## Results

Results are pending. [The command log](splitcast-nix-final.log) records actual UTC clock timestamps, command statuses, source identities, and disk checkpoints.
