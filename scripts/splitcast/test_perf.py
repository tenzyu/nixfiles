import copy
import csv
import json
import os
from pathlib import Path
import tempfile
import unittest
import io
from contextlib import redirect_stdout
from unittest.mock import patch

import perf


def matrix():
    spec = {
        "common": {k: "fixed" for k in perf.COMMON_KEYS},
        "workload": {c: {k: "fixed" for k in perf.WORKLOAD_KEYS} for c in perf.CONDITIONS},
    }
    spec["common"]["cpu_count"] = 8
    spec["common"].update(replay_sha256="0" * 64, fps_cap=240, resolution="1920x1080")
    spec["common"]["environment_flags"] = {k: "fixed" for k in perf.FLAG_KEYS}
    for scenario in spec["workload"].values():
        scenario["versions"] = {"tool": "fixture"}
    runs = []
    for series in perf.SERIES:
        for condition, cpu in zip(perf.CONDITIONS, (100, 400, 200)):
            runs.append({
                "schema": 1, "kind": "performance", "series": series, "condition": condition,
                "revision": series, "conditions": copy.deepcopy(spec), "instrument_smoke": False,
                "duration_s": 600, "requested_duration_s": 600, "interval_s": 1,
                "clock_ticks_per_s": 100, "cpu_count": 8, "errors": [],
                "samples": [{"elapsed_s": i, "interval_s": int(i > 0), "ticks": cpu if i else 0,
                             "identities": ["boot:100:900"], "errors": []} for i in range(601)],
                "frames": {"source": "external_csv", "unit": "ms", "method": "nearest_rank", "samples": 60000,
                           "coverage_s": 600, "p99_ms": 10},
                "collector_versions": {"python": "fixed"}, "system_cpu_total_percent": 50,
                "gpu": {"status": "NOT_RUN"}, "route_dump": {"status": "PASS"}, "network": {"status": "NOT_RUN"},
            })
    return runs


class ComparatorTests(unittest.TestCase):
    def test_cli_never_overwrites_inputs_or_existing_results(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            runs = matrix()
            for command, selected in (("compare", runs), ("compare-series", runs[:3])):
                inputs = []
                for index, run in enumerate(selected):
                    path = root / f"{command}-{index}.json"
                    path.write_text(json.dumps(run))
                    inputs.append(path)
                for output, initial in ((inputs[0], inputs[0].read_bytes()),
                                        (root / f"{command}-prior.json", b"prior evidence\n")):
                    if output != inputs[0]:
                        output.write_bytes(initial)
                    stdout = io.StringIO()
                    with patch("sys.argv", ["perf.py", command, *map(str, inputs), "--output", str(output)]), redirect_stdout(stdout):
                        self.assertEqual(perf.main(), 2)
                    self.assertEqual(output.read_bytes(), initial)
                    self.assertEqual(json.loads(stdout.getvalue())["status"], "REFUSED")

    def test_compare_one_series_compares_all_three_conditions(self):
        runs = matrix()[:3]
        result = perf.compare_series(runs)
        self.assertEqual(result["status"], "COMPARABLE")
        self.assertEqual(set(result["conditions"]), set(perf.CONDITIONS))
        self.assertEqual(result["obs_increment_one_core_percent"], 300)
        self.assertEqual(result["splitcast_increment_one_core_percent"], 100)

    def test_compare_one_series_refuses_missing_or_mixed_cells(self):
        with self.assertRaisesRegex(perf.EvidenceError, "exactly three"):
            perf.compare_series(matrix()[:2])
        runs = matrix()[:3]
        runs[0]["series"] = "new"
        with self.assertRaisesRegex(perf.EvidenceError, "same series"):
            perf.compare_series(runs)

    def test_known_cpu_change_and_normalization(self):
        runs = matrix()
        for sample in runs[-1]["samples"][1:]:
            sample["ticks"] = 120
        result = perf.compare(runs)
        self.assertEqual(result["new_minus_baseline"]["splitcast"]["process_one_core_percent"], -80)
        self.assertEqual(result["series"]["new"]["conditions"]["splitcast"]["process_machine_percent"], 15)
        self.assertAlmostEqual(result["series"]["baseline"]["obs_increment_reduction_percent"], 200 / 300 * 100)
        self.assertAlmostEqual(result["series"]["new"]["obs_increment_reduction_percent"], 280 / 300 * 100)

    def test_known_p99_change(self):
        runs = matrix()
        runs[-1]["frames"]["p99_ms"] = 12
        result = perf.compare(runs)
        self.assertEqual(result["new_minus_baseline"]["splitcast"]["p99_ms"], 2)
        self.assertAlmostEqual(result["series"]["new"]["splitcast_p99_degradation_percent"], 20)

    def test_changed_replay_flags_and_workload_refused(self):
        for location, key in (("common", "replay_sha256"), ("common", "fps_cap"), ("common", "background_profile")):
            runs = matrix()
            runs[-1]["conditions"][location][key] = {"replay_sha256": "1" * 64, "fps_cap": 120, "background_profile": "changed"}[key]
            with self.assertRaisesRegex(perf.EvidenceError, "incomparable conditions"):
                perf.compare(runs)
        runs = matrix()
        runs[-1]["conditions"]["workload"]["obs_current"]["encoder_flags"] = "changed"
        with self.assertRaisesRegex(perf.EvidenceError, "incomparable conditions"):
            perf.compare(runs)

    def test_missing_and_error_samples_refused(self):
        for mutation, expected in (
            (lambda r: r["samples"].pop(300), "missing CPU interval"),
            (lambda r: r["samples"][300].update(errors=["read_error"]), "missing/error CPU sample"),
            (lambda r: r.update(frames=None), "missing/unsupported frame"),
            (lambda r: r.update(errors=["missing child"]), "contains errors"),
            (lambda r: r["samples"][300].update(identities=[]), "missing/error CPU sample"),
            (lambda r: r["gpu"].update(status="ERROR"), "gpu contains errors"),
        ):
            runs = matrix()
            mutation(runs[-1])
            with self.assertRaisesRegex(perf.EvidenceError, expected):
                perf.compare(runs)

    def test_duration_and_smoke_refused(self):
        for field, value, expected in (("duration_s", 599, "incomplete duration"), ("instrument_smoke", True, "smoke")):
            runs = matrix()
            runs[-1][field] = value
            with self.assertRaisesRegex(perf.EvidenceError, expected):
                perf.compare(runs)

    def test_obs_increment_denominator_zero_or_negative_refused(self):
        for ticks in (100, 50):
            runs = matrix()
            for sample in runs[1]["samples"][1:]:
                sample["ticks"] = ticks
            with self.assertRaisesRegex(perf.EvidenceError, "invalid OBS increment denominator"):
                perf.compare(runs)

    def test_missing_and_duplicate_cells_refused(self):
        with self.assertRaisesRegex(perf.EvidenceError, "six run files"):
            perf.compare(matrix()[:-1])
        runs = matrix()
        runs[-1] = runs[0]
        with self.assertRaisesRegex(perf.EvidenceError, "duplicate matrix cell"):
            perf.compare(runs)


class InstrumentsTests(unittest.TestCase):
    def test_init_conditions_prefills_only_host_facts(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "conditions.json"
            with patch.object(perf.sys, "argv", ["perf.py", "init-conditions", "--output", str(path)]):
                self.assertEqual(perf.main(), 0)
            generated = json.loads(path.read_text())
            example = json.loads(Path(perf.__file__).with_name("conditions.example.json").read_text())
            self.assertEqual(generated["common"]["kernel"], perf.platform.release())
            self.assertEqual(generated["common"]["cpu_count"], perf.os.cpu_count())
            self.assertEqual(generated["common"]["replay_sha256"], example["common"]["replay_sha256"])
            self.assertEqual(generated["workload"], example["workload"])

    def test_init_conditions_refuses_existing_file_without_changing_it(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "conditions.json"
            original = b'{"operator": "keep this"}\n'
            path.write_bytes(original)
            with patch.object(perf.sys, "argv", ["perf.py", "init-conditions", "--output", str(path)]):
                self.assertEqual(perf.main(), 2)
            self.assertEqual(path.read_bytes(), original)

    def test_descendants_persist_after_reparenting_and_pid_reuse_refused(self):
        initial = {1: {"pid": 1, "ppid": 0, "start": 10, "ticks": 100},
                   2: {"pid": 2, "ppid": 1, "start": 11, "ticks": 50}}
        tree = perf.ProcessTree([1], "boot", initial)
        self.assertEqual(tree.sample(initial)[0], 0)
        next_table = copy.deepcopy(initial)
        next_table[1]["ticks"] += 7
        next_table[2].update(ppid=0, ticks=63)
        delta, ids, errors = tree.sample(next_table)
        self.assertEqual(delta, 20)
        self.assertEqual(set(ids), {"boot:1:10", "boot:2:11"})
        self.assertEqual(errors, [])
        next_table[2].update(start=99, ticks=1)
        self.assertIn("descendant_missing_or_reused", tree.sample(next_table)[2])

    def test_new_descendant_ticks_counted_without_parent_waited_ticks(self):
        initial = {1: {"pid": 1, "ppid": 0, "start": 10, "ticks": 100}}
        tree = perf.ProcessTree([1], "boot", initial)
        tree.sample(initial)
        current = {1: {"pid": 1, "ppid": 0, "start": 10, "ticks": 110},
                   2: {"pid": 2, "ppid": 1, "start": 20, "ticks": 15}}
        self.assertEqual(tree.sample(current)[0], 25)

    def test_real_proc_reader_observes_current_process(self):
        record = perf.read_stat(f"/proc/{os.getpid()}/stat")
        self.assertEqual(record["pid"], os.getpid())
        self.assertGreater(record["start"], 0)

    def test_frame_parser_known_p99_and_missing_coverage(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "frames.csv"
            with path.open("w", newline="") as handle:
                writer = csv.writer(handle)
                writer.writerow(["elapsed_s", "frame_time_ms"])
                elapsed = 0
                for i in range(100):
                    ms = 20 if i >= 98 else 10
                    elapsed += ms / 1000
                    writer.writerow([elapsed, ms])
            self.assertEqual(perf.frame_times(path, elapsed)["p99_ms"], 20)
            with self.assertRaisesRegex(perf.EvidenceError, "does not cover"):
                perf.frame_times(path, 600)
            path.write_text("elapsed_s,frame_time_ms\n" + "".join(f"{i / 10},10\n" for i in range(21)))
            with self.assertRaisesRegex(perf.EvidenceError, "do not account"):
                perf.frame_times(path, 2)

    def test_gpu_engines_remain_separate(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "intel.json"
            path.write_text(json.dumps([{"engines": {"Render/3D/0": {"busy": 20}, "Video/0": {"busy": 80}}}]))
            result = perf.gpu_samples(path)
            self.assertEqual(result["Render/3D/0"]["mean_busy_percent"], 20)
            self.assertEqual(result["Video/0"]["mean_busy_percent"], 80)
            self.assertNotIn("total", result)
            path.write_text(json.dumps([{"engines": {"Render/3D/0": {"busy": 20}, "Video/0": {"busy": 80}}},
                                        {"engines": {"Render/3D/0": {"busy": 30}}}]))
            with self.assertRaisesRegex(perf.EvidenceError, "missing an engine"):
                perf.gpu_samples(path)

    def test_external_gpu_evidence_does_not_claim_window_alignment(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "intel.json"
            path.write_text(json.dumps([{"engines": {"Render/3D/0": {"busy": 20}, "Video/0": {"busy": 80}}}]))
            result = perf.gpu_evidence(path)
            self.assertEqual(result["status"], "UNVERIFIED")
            self.assertIn("not verified", result["coverage"])
            self.assertEqual(result["engines"]["Video/0"]["mean_busy_percent"], 80)

    def test_tailscale_status_reports_actual_direct_relay_fields_only(self):
        peer = {"HostName": "test-peer", "CurAddr": "192.0.2.1:1234", "Relay": "test-region", "Online": True, "Active": True,
                "TailscaleIPs": ["100.64.0.1"], "PrivateField": "must-not-leak", "TxBytes": 100, "RxBytes": 200}
        with patch.object(perf, "command_json", return_value={"status": "PASS", "value": {"Peer": {"privatekey": peer}}}):
            self.assertEqual(perf.tailscale_summary("test-peer")["path"], "direct")
            peer["CurAddr"] = ""
            self.assertEqual(perf.tailscale_summary("test-peer")["path"], "relay")
            self.assertNotIn("must-not-leak", json.dumps(perf.tailscale_summary("test-peer")))
            self.assertNotIn("100.64", json.dumps(perf.tailscale_summary("test-peer")))
            peer["Online"] = False
            self.assertEqual(perf.tailscale_summary("test-peer")["path"], "unknown")

    def test_route_summary_excludes_private_properties(self):
        dump = [{"id": 2, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": "private-device-name", "media.class": "Audio/Source", "password": "must-not-leak"}}},
                {"id": 3, "type": "PipeWire:Interface:Link", "info": {"props": {"link.input.node": 2, "link.output.node": 1, "device.serial": "must-not-leak"}}}]
        with patch.object(perf, "command_json", return_value={"status": "PASS", "value": dump}):
            summary = perf.route_summary()
        self.assertNotIn("private-device-name", json.dumps(summary))
        self.assertNotIn("must-not-leak", json.dumps(summary))
        self.assertEqual(summary["links"][0]["link.input.node"], 2)


if __name__ == "__main__":
    unittest.main()
