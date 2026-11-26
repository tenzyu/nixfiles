"""Exercise the report contract with disposable receipts, never boot or GC."""
import contextlib
import importlib.util
import io
import json
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location("memory_ab", Path(__file__).with_name("memory-ab.py"))
ab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ab)

with tempfile.TemporaryDirectory() as tmp:
    directory = Path(tmp)
    refs = {arm: {"closure": "/nix/store/" + arm} for arm in ab.ARMS}
    ab.write_new(directory / "manifest.json", refs)
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        assert ab.report(directory) == 2
        for arm in ab.ARMS:
            for index in range(ab.BOOTS):
                boot = f"{arm}-{index}"
                closure = refs[arm]["closure"]
                for phase in ab.PHASES:
                    sample = {
                        "hostname": "neko5", "effective_uid": 0,
                        "identity": {"boot_id": boot, "current_system": closure,
                                     "booted_system": closure, "machine": "x86_64",
                                     "product": "fixture", "vendor": "fixture"},
                        "meminfo_kib": {"MemTotal": 2048 * 1024,
                                        "MemAvailable": (1024 if arm == "baseline" else 1536) * 1024},
                        "processes": [{"pss_kib": 1024}],
                    }
                    path = directory / f"{boot}-{phase}.json"
                    receipt = {"arm": arm, "boot": boot, "phase": phase,
                               "closure": closure, "samples": [sample] * ab.SAMPLES}
                    ab.write_new(path, receipt)
        assert ab.report(directory) == 0
        assert "candidate - baseline: -512.00 MiB" in output.getvalue()
        bad = dict(receipt, closure="/nix/store/wrong")
        path.write_text(json.dumps(bad))
        try:
            ab.report(directory)
        except ValueError as error:
            assert "Wrong closure" in str(error)
        else:
            raise AssertionError("wrong closure accepted")
print("A/B report contract passed")
