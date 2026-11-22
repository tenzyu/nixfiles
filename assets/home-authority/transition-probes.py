#!/usr/bin/env python3
"""Disposable-VM transition counterexamples; never operate on a real HOME.

Each transition is deterministic and uses actual GNU Coreutils and mount
backing. These are deliberately adverse probes, not a production cutover.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path("/home/fixture-transition")
CROSS_TARGET = Path("/run/home-authority-cross-device-target")
MV = ("mv", "-T", "--no-copy", "--update=none-fail", "--")


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def clean():
    # VM fixture only: the scratch location is not a real user's HOME.
    if ROOT.exists():
        shutil.rmtree(ROOT)
    if CROSS_TARGET.exists():
        if CROSS_TARGET.is_dir():
            shutil.rmtree(CROSS_TARGET)
        else:
            CROSS_TARGET.unlink()


def crash_failpoints():
    """Kill the trusted transition process at three precise syscall points.

    These disposable scratch trees intentionally have no recovery journal.
    Their outcomes characterize an unsafe protocol; they are not a
    production 'recovery succeeded' assertion.
    """
    results = {}
    for stage in ("before_move", "after_move", "after_seal"):
        work = ROOT / ("interrupt-" + stage)
        work.mkdir(mode=0o700)
        os.chown(work, 1000, 100)
        source = work / ".legacy"
        target = work / "canonical"
        write(source / "incumbent", "acknowledged\n")
        previous_inode = source.stat().st_ino
        child = os.fork()
        if child == 0:
            try:
                if stage != "before_move":
                    os.rename(source, target)
                if stage == "after_seal":
                    subprocess.run(
                        ["chattr", "+i", str(work)],
                        check=True, capture_output=True,
                    )
                os._exit(77)
            except BaseException:
                os._exit(1)
        _, status = os.waitpid(child, 0)
        require(os.WIFEXITED(status) and os.WEXITSTATUS(status) == 77,
                f"fault injection was not executed at {stage}")
        moved = not source.exists() and (target / "incumbent").exists()
        kept = source.exists() and not target.exists()
        require(moved if stage != "before_move" else kept,
                f"unexpected state after SIGKILL at {stage}")
        data_path = target if moved else source
        require((data_path / "incumbent").read_text() == "acknowledged\n",
                f"durable baseline lost at {stage}")
        require(data_path.stat().st_ino == previous_inode,
                f"incumbent inode replaced at {stage}")
        if stage == "after_move":
            interposed = run(
                "runuser", "-u", "fixture", "--", "mkdir", str(source)
            )
            require(interposed.returncode == 0 and source.is_dir(),
                    "unsealed crash window was not demonstrated")
            exposure = "VIOLATION"
        elif stage == "after_seal":
            interposed = run(
                "runuser", "-u", "fixture", "--", "mkdir", str(source)
            )
            require(interposed.returncode != 0 and not source.exists(),
                    "sealed crash window allowed forbidden recreation")
            exposure = "DENIED"
        else:
            exposure = "NOT_APPLICABLE_PRE_MOVE"
        results[stage] = {
            "trusted_process_exit": 77,
            "durable_baseline_survived": True,
            "incumbent_inode_preserved": True,
            "legacy_recreation": exposure,
            "recovery_commit_journal": "ABSENT",
            "safe_recovery_automatically_established": False,
        }
        if stage == "after_seal":
            restored = run("chattr", "-i", str(work))
            require(restored.returncode == 0, "scratch seal cleanup failed")
        shutil.rmtree(work)
    return results


def probe():
    clean()
    ROOT.mkdir(mode=0o700)
    os.chown(ROOT, 1000, 100)
    evidence = {}
    try:
        # Deterministic adversarial interposition precisely between the
        # rename and the +i seal. No probabilistic scheduling outcome.
        legacy = ROOT / ".legacy"
        canonical = ROOT / "canonical"
        write(legacy / "incumbent", "original\n")
        original_inode = os.stat(legacy).st_ino
        moved = run(*MV, str(legacy), str(canonical))
        require(moved.returncode == 0 and not legacy.exists(), "initial rename failed")
        require(os.stat(canonical).st_ino == original_inode, "rename did not retain inode")
        intervening = run(
            "runuser", "-u", "fixture", "--", "sh", "-c",
            'set -eu; mkdir "$1"; printf new-writer > "$1/new"', "sh", str(legacy)
        )
        require(intervening.returncode == 0, f"cannot exercise unwrapped writer: {intervening.stderr}")
        distinct = os.stat(legacy).st_ino != os.stat(canonical).st_ino
        state_is_split = (
            distinct
            and (legacy / "new").read_text() == "new-writer"
            and (canonical / "incumbent").read_text() == "original\n"
            and not (canonical / "new").exists()
        )
        require(state_is_split, "the intended unprotected transition counterexample did not reproduce")
        evidence["rename_to_seal_interposition"] = {
            "result": "GAP_CONFIRMED",
            "writer": "unwrapped fixture UID 1000",
            "canonical_inode_preserved": True,
            "new_legacy_inode_distinct": distinct,
            "new_writer_state_missing_from_canonical": True,
            "meaning": "rename and chattr are not an atomic no-writer cutover",
        }

        # Fail closed when both roots contain data, and prove no overwrite.
        source = ROOT / "occupied-source"
        target = ROOT / "occupied-target"
        write(source / "source-only", "source\n")
        write(target / "target-only", "target\n")
        collision = run(*MV, str(source), str(target))
        preserved = (
            collision.returncode != 0
            and (source / "source-only").read_text() == "source\n"
            and (target / "target-only").read_text() == "target\n"
            and not (target / "source-only").exists()
        )
        require(preserved, "occupied destination was not preserved by no-clobber move")
        evidence["occupied_destination"] = {
            "result": "REJECTED_WITHOUT_DATA_LOSS",
            "exit_code": collision.returncode,
            "preserved_both_backings": preserved,
        }

        # An EXDEV must not trigger Coreutils' copy+delete fallback.
        cross_source = ROOT / "cross-source"
        write(cross_source / "keep", "source-on-original-fs\n")
        source_dev = os.stat(ROOT).st_dev
        dest_dev = os.stat(CROSS_TARGET.parent).st_dev
        require(source_dev != dest_dev, "cross-device fixture unavailable; no silent skip")
        cross = run(*MV, str(cross_source), str(CROSS_TARGET))
        clean_failure = (
            cross.returncode != 0
            and (cross_source / "keep").read_text() == "source-on-original-fs\n"
            and not CROSS_TARGET.exists()
        )
        require(clean_failure, "cross-device rename copied data or lost incumbent")
        evidence["cross_filesystem_no_copy"] = {
            "result": "REJECTED_WITHOUT_COPY",
            "source_device": source_dev,
            "target_device": dest_dev,
            "exit_code": cross.returncode,
            "source_survives": True,
            "target_absent": True,
        }
        evidence["crash_failpoints"] = crash_failpoints()
        print(json.dumps(evidence, sort_keys=True))
    finally:
        clean()


if __name__ == "__main__":
    probe()
