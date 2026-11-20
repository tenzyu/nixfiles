#!/usr/bin/env python3
"""Hermetic unittest; no game, tablet, audio or Wayland is touched."""
import errno
import hashlib
import importlib.util
import json
import os
import selectors
import signal
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack, contextmanager
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

source = Path(__file__).with_name("osu-lab.py")
spec = importlib.util.spec_from_file_location("osu_lab", source)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


EVDEV = {"kind": "evdev", "path": "/dev/input/event77", "name": "synthetic"}
PW_HEADER = "S   ID  QUANT   RATE    WAIT    BUSY   W/Q   B/Q  ERR FORMAT           NAME\n"
PW_LEGACY_HEADER = "S ID QUANT RATE WAIT BUSY W/Q B/Q ERR NAME\n"


def event(usec, typ=0, code=0, value=0):
    return lab.EVENT.pack(1, usec, typ, code, value)


def display_sample(monitor=None, *, fullscreen=2, client=0, window="osu!", status="ok"):
    return {"display": {"status": status,
                        "window": {"class": window, "fullscreen": fullscreen, "fullscreenClient": client, "monitor": 0},
                        "monitor": None if monitor is None else {"name": lab.MONITOR, "id": 0, **monitor}}}


def pw_row(node, err, name, format_field="S32LE 2 48000"):
    prefix = f"R {node:4}    256  48000   1.0us   2.0us  0.20  0.10  {err:>3}"
    if format_field is None:
        return f"{prefix} {name}\n"
    return f"{prefix} {format_field:>16} {name}\n"


@contextmanager
def pipe_observer(clock, device=EVDEV):
    read_fd, write_fd = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
    with mock.patch.object(lab, "node_candidates", return_value=[device]), \
         mock.patch.object(lab.os, "open", return_value=read_fd), \
         mock.patch.object(lab.fcntl, "ioctl", side_effect=clock):
        observer = lab.InputObserver()
    with observer, os.fdopen(write_fd, "wb", buffering=0) as writer:
        yield observer, writer, read_fd


def read_batch(observer, writer, payload, now=1_020_000_000):
    writer.write(payload)
    with mock.patch.object(lab.time, "monotonic_ns", return_value=now):
        observer.sample(0.1)


class TestLatencyLab(unittest.TestCase):
    def test_distribution(self):
        p = lab.dist([1, 2, 3, 4, 5])
        self.assertEqual(p, {"count": 5, "min": 1, "p50": 3, "p95": 4.8,
                             "p99": 4.96, "p99_9": 4.996, "max": 5})
        self.assertIsNone(lab.dist([])["p99"])

    def test_histogram(self):
        h = lab.histogram([0, 0.2, 2.5, 5, 13.0], 0, 12, .5)
        self.assertEqual(sum(h["counts"]), 4)
        self.assertEqual(h["outside_range"], 1)
        self.assertEqual(h["counts"][5], 1)

    def test_unknown_evdev_clock_batched_and_split_reads(self):
        clock_error = OSError(errno.EINVAL, "clock selection failed")
        with pipe_observer(clock_error) as (observer, writer, _):
            payload = event(0, 1, 330, 1) + event(0) + event(1000, 1, 330, 0) + event(1000)
            read_batch(observer, writer, payload)
            read_batch(observer, writer, event(2000)[:8], now=1_022_000_000)
            read_batch(observer, writer, event(2000)[8:], now=1_024_000_000)
            output = observer.result()["devices"][0]
        for key in ("key_down", "key_up", "pen_touch_down", "pen_touch_up"):
            self.assertEqual(output[key], 1)
        self.assertEqual(output["reports"], 3)
        self.assertTrue(output["counts_complete"])
        self.assertIsNone(output["timing"]["period_clock"])
        self.assertEqual(output["period_ms"]["count"], 0)
        self.assertIsNone(output["period_ms"]["p50"])
        self.assertEqual(output["observer_delay_ms"]["count"], 0)
        self.assertEqual(output["read_interval_ms"]["count"], 2)
        self.assertEqual(output["read_interval_ms"]["p50"], 2)
        self.assertNotIn("key_code", output)
        self.assertNotIn("330", json.dumps(output))

    def test_aligned_evdev_measures_intervals_within_one_read(self):
        with pipe_observer(None) as (observer, writer, _):
            # Intervals of 1, 2, 3, 4 and 5 ms. The last event coincides with read completion.
            read_batch(observer, writer, b"".join(event(t) for t in (0, 1000, 3000, 6000, 10000, 15000)),
                       now=1_015_000_000)
            output = observer.result()["devices"][0]
        self.assertEqual(output["timing"]["period_clock"], lab.MONOTONIC)
        self.assertEqual(output["reads"], 1)
        self.assertEqual(output["read_interval_ms"]["count"], 0)
        self.assertEqual(output["period_ms"], lab.dist([1, 2, 3, 4, 5]))
        self.assertEqual(output["observer_delay_ms"], lab.dist([15, 14, 12, 9, 5, 0]))

    def test_duplicate_and_unaligned_values_do_not_create_zero_period(self):
        with pipe_observer(None) as (observer, writer, _):
            read_batch(observer, writer, b"".join(event(t) for t in (1000, 1000, 3000, 990000, 5000, 8000)))
            output = observer.result()["devices"][0]
        self.assertEqual(output["period_ms"], lab.dist([2, 3]))
        self.assertEqual(output["observer_delay_ms"]["count"], 5)

    def test_dropped_frames_discard_pending_counts_and_reset_timing(self):
        with pipe_observer(None) as (observer, writer, _):
            read_batch(observer, writer, event(0, 1, 330, 1) + event(0) + event(2000) +
                       event(3000, 1, 30, 1) + event(4000, 0, 3) + event(5000, 1, 330, 0))
            read_batch(observer, writer, event(6000) + event(12000, 1, 330, 0) + event(12000) + event(15000)
                       + event(16000, 1, 30, 1))
            output = observer.result()["devices"][0]
        self.assertEqual(output["reports"], 4)
        self.assertEqual(output["syn_dropped"], 1)
        self.assertEqual(output["key_down"], 1)
        self.assertEqual(output["key_up"], 1)
        self.assertEqual(output["period_ms"], lab.dist([2, 3]))
        self.assertEqual(output["observer_delay_ms"]["count"], 4)
        self.assertFalse(output["counts_complete"])

    def test_hidraw_periods_use_read_completion_only(self):
        device = {**EVDEV, "kind": "hidraw", "path": "/dev/hidraw7"}
        with pipe_observer(None, device) as (observer, writer, _):
            for now in (10_000_000, 12_000_000, 16_000_000):
                read_batch(observer, writer, b"sample", now)
            output = observer.result()["devices"][0]
        self.assertEqual(output["timing"]["period_source"], "hidraw read completion")
        self.assertEqual(output["period_ms"], lab.dist([2, 4]))
        self.assertEqual(output["period_ms"], output["read_interval_ms"])
        self.assertIsNone(output["timing"]["dispatch_clock"])

    def test_eof_and_read_error_close_once_before_descriptor_reuse(self):
        for failure in (None, OSError(errno.ENODEV, "unplugged")):
            with self.subTest(failure=failure), pipe_observer(None) as (observer, writer, fd):
                if failure is None:
                    writer.close()
                    observer.sample(.1)
                else:
                    writer.write(event(0))
                    with mock.patch.object(lab.os, "read", side_effect=failure):
                        observer.sample(.1)
                with self.assertRaises(OSError):
                    os.fstat(fd)
                replacement, other = os.pipe()
                try:
                    self.assertEqual(replacement, fd)
                    observer.close()
                    observer.close()
                    os.fstat(replacement)
                finally:
                    os.close(replacement)
                    os.close(other)
                result = observer.result()
                self.assertFalse(result["devices"][0]["counts_complete"])
                self.assertIn("end of file" if failure is None else "read error", result["status"][-1]["status"])

    def test_registration_failure_closes_opened_fd(self):
        fd, writer = os.pipe()
        self.addCleanup(os.close, writer)
        selector = selectors.DefaultSelector()
        with mock.patch.object(lab, "node_candidates", return_value=[EVDEV]), \
             mock.patch.object(lab.os, "open", return_value=fd), \
             mock.patch.object(lab.selectors, "DefaultSelector", return_value=selector), \
             mock.patch.object(selector, "register", side_effect=OSError(errno.EPERM, "denied")):
            with lab.InputObserver() as observer:
                self.assertEqual(observer.result()["devices"], [])
                self.assertIn("unavailable", observer.result()["status"][0]["status"])
        with self.assertRaises(OSError):
            os.fstat(fd)

    def test_evdev_permission_denial_keeps_input_unavailable(self):
        with mock.patch.object(lab, "node_candidates", return_value=[EVDEV]), \
             mock.patch.object(lab.os, "open", side_effect=PermissionError(errno.EACCES, "denied")):
            with lab.InputObserver() as observer:
                self.assertEqual(observer.result()["devices"], [])
                self.assertIn("unavailable", observer.result()["status"][0]["status"])

    def test_nonblocking_retry_does_not_close_the_device(self):
        with pipe_observer(None) as (observer, writer, fd):
            writer.write(event(0))
            with mock.patch.object(lab.os, "read", side_effect=BlockingIOError(errno.EAGAIN, "try again")):
                observer.sample(.1)
            os.fstat(fd)
            observer.sample(.1)
            self.assertEqual(observer.result()["devices"][0]["reports"], 1)

    def test_constructor_failure_closes_previously_owned_descriptors(self):
        fd, writer = os.pipe()
        self.addCleanup(os.close, writer)
        device2 = {**EVDEV, "path": "/dev/input/event78"}
        with mock.patch.object(lab, "node_candidates", return_value=[EVDEV, device2]), \
             mock.patch.object(lab.os, "open", side_effect=[fd, RuntimeError("setup fault")]):
            with self.assertRaisesRegex(RuntimeError, "setup fault"):
                lab.InputObserver()
        with self.assertRaises(OSError):
            os.fstat(fd)

    def test_frame_logs_are_only_slow_samples(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root) / "performance-logs"
            folder.mkdir()
            (folder / "performance-update.log").write_text('| Slow frame on thread "Update"\n| * Frame length : 11ms (allowable: 10ms)\n\n| * Frame length : 54ms (allowable: 10ms)')
            obj = lab.parse_slow_logs(root)
            self.assertEqual(obj["performance-update.log"]["slow_frame_count"], 2)
            self.assertEqual(obj["performance-update.log"]["slow_lengths_ms"]["max"], 54)
            self.assertIn("NOT all-frame p99", obj["performance-update.log"]["note"])

    def test_pw_top_parser(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root) / "top.txt"
            for header, format_field in ((PW_HEADER, "S32LE 2 48000"), (PW_HEADER, ""), (PW_LEGACY_HEADER, None)):
                with self.subTest(header=header, format_field=format_field):
                    p.write_text(header + "".join(pw_row(32, err, "+ alsa_output.fixture", format_field) for err in (3, 6)))
                    analysis = lab.analyze({"pw_top": lab.parse_pw_top(p)})
                    row = analysis["audio"]["pw_top"]["nodes"]["alsa_output.fixture"]
                    self.assertEqual((row["first_err"], row["last_err"], row["delta_err"]), (3, 6, 3))
                    self.assertEqual(row["delta_err_source"], lab.PW_ERR_SOURCE)

    def test_pw_top_unsupported_header_and_unavailable_err(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root) / "top.txt"
            p.write_text(PW_HEADER.replace("ERR FORMAT", "FORMAT ERR") +
                         pw_row(32, 3, "alsa_output.fixture") + pw_row(32, 6, "alsa_output.fixture"))
            self.assertEqual(lab.parse_pw_top(p), {"status": "raw_capture_only", "nodes": {}})
            p.write_text(PW_HEADER + "".join(pw_row(32, err, "alsa_output.fixture") for err in (3, "---", 6)))
            row = lab.parse_pw_top(p)["nodes"]["alsa_output.fixture"]
            self.assertEqual((row["first_err"], row["last_err"], row["delta_err"]), (3, 6, None))

    def test_display_snapshot_keeps_independent_responses(self):
        item = display_sample({"directScanoutTo": "1"})["display"]
        with mock.patch.object(lab, "command", side_effect=[None, item["window"]]):
            self.assertEqual(lab.display_snapshot()["window"], item["window"])
        with mock.patch.object(lab, "command", side_effect=[[item["monitor"]], None]):
            self.assertEqual(lab.display_snapshot()["monitor"], item["monitor"])

    def test_draw_denominators_include_only_observed_eligible_samples(self):
        data = {"samples": [
            display_sample(None, status="hyprctl monitors unavailable"),
            display_sample({"activelyTearing": True}),
            display_sample({"directScanoutTo": None}),
            display_sample({"directScanoutTo": "invalid"}),
            display_sample({"directScanoutTo": "0", "activelyTearing": False,
                            "directScanoutBlockedBy": ["TRANSFORM"]}),
            display_sample({"directScanoutTo": "1"}),
            display_sample({"directScanoutTo": "5ae", "activelyTearing": False}),
            display_sample({"directScanoutTo": "0xabc", "activelyTearing": True}),
            display_sample({"id": None, "directScanoutTo": "1", "activelyTearing": True}),
            display_sample({"directScanoutTo": "1", "activelyTearing": True}, client=2),
            display_sample({"directScanoutTo": "1", "activelyTearing": True}, window="other"),
        ]}
        draw = lab.analyze(data)["draw"]
        self.assertEqual(draw["eligible_samples"], 7)
        self.assertEqual(draw["dso_observed_samples"], 4)
        self.assertEqual(draw["dso_samples"], 3)
        self.assertEqual(draw["dso_ratio"], 75)
        self.assertEqual(draw["tearing_observed_dso_samples"], 2)
        self.assertEqual(draw["actively_tearing_samples"], 1)
        self.assertEqual(draw["tearing_ratio_among_dso"], 50)
        self.assertEqual(draw["dso_blockers"], {"TRANSFORM": 1})
        self.assertEqual(draw["monitor_observations"], {"samples": 10, "dso_observed": 7, "dso_active": 6,
                                                        "tearing_observed": 7, "tearing_active": 5})

    def test_unavailable_monitor_fields_are_distinct_from_observed_zero(self):
        for mon, dso, tear in ((None, None, None), ({}, None, None),
                               ({"directScanoutTo": 0}, 0, None),
                               ({"directScanoutTo": "1"}, 100, None),
                               ({"directScanoutTo": "1", "activelyTearing": False}, 100, 0)):
            with self.subTest(monitor=mon):
                draw = lab.analyze({"samples": [display_sample(mon)]})["draw"]
                self.assertEqual(draw["dso_ratio"], dso)
                self.assertEqual(draw["tearing_ratio_among_dso"], tear)

    def test_foreground_game_requires_matching_monitor_ids(self):
        for output, foreground in ((0, 1), (None, 0), (0, None), (None, None), (0, False), (-1, -1)):
            with self.subTest(output=output, foreground=foreground):
                item = display_sample({"id": output, "directScanoutTo": "1", "activelyTearing": True})
                if output is None:
                    del item["display"]["monitor"]["id"]
                window = item["display"]["window"]
                if foreground is None:
                    del window["monitor"]
                else:
                    window["monitor"] = foreground
                draw = lab.analyze({"samples": [item]})["draw"]
                self.assertEqual(draw["eligible_samples"], 0)
                self.assertIsNone(draw["dso_ratio"])
                self.assertIsNone(draw["tearing_ratio_among_dso"])
                self.assertEqual(draw["monitor_observations"]["dso_active"], 1)
                self.assertEqual(draw["monitor_observations"]["tearing_active"], 1)

    def test_report_generation_and_unknown(self):
        data={"config":{"label":"400hz-8x-sync", "seconds":90},"started":"2026-11-13T12:00:00+09:00","ended":"2026-11-13T12:01:30+09:00",
              "samples":[], "input":{"devices":[],"status":[{"status":"unavailable: Permission denied"}]},
              "proc_start":{"pid":None},"pw_top":{"nodes":{}}}
        a=lab.analyze(data)
        document=lab.html_report(data,a)
        self.assertIn('未測定',document)
        self.assertIn('実効内部periodではありません',document)
        self.assertIn('400hz-8x-sync',document)
        self.assertNotIn('NaN',document)

    def test_comparison_never_invents_number(self):
        data={"config":{"label":"A"},"analysis":{"draw":{"dso_ratio":None,"tearing_ratio_among_dso":None},
                "system":{"temp_C":{"max":None},"throttle_delta":None},"update":{"thread_sched":[]},
                "input":{"devices":[]},"audio":{"pw_top":{"nodes":{}}}}}
        result=lab.comparison_html([data,{**data,"config":{"label":"B"}}])
        self.assertIn('未測定',result)
        self.assertNotIn('nan',result)


    def test_pw_top_requires_nondecreasing_samples_from_one_observed_node(self):
        with tempfile.TemporaryDirectory() as root:
            p = Path(root) / "top.txt"
            samples = [(32, 0, "single"), (33, 3, "reset"), (33, 0, "reset"), (33, 4, "reset"),
                       (35, 3, "replaced"), (36, 4, "replaced"), (34, 2, "zero"), (34, 2, "zero")]
            p.write_text(PW_HEADER + "".join(pw_row(node, err, f"alsa_output.{name}") for node, err, name in samples))
            nodes = lab.analyze({"pw_top": lab.parse_pw_top(p)})["audio"]["pw_top"]["nodes"]
            for name in ("single", "reset", "replaced"):
                self.assertIsNone(nodes[f"alsa_output.{name}"]["delta_err"])
                self.assertIsNone(nodes[f"alsa_output.{name}"]["delta_err_source"])
            self.assertEqual(nodes["alsa_output.zero"]["delta_err"], 0)
            self.assertEqual(nodes["alsa_output.zero"]["delta_err_source"], lab.PW_ERR_SOURCE)

    def test_each_performance_log_delta_is_preserved_and_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "logs", Path(tmp) / "session"
            (src / "logs").mkdir(parents=True)
            out.mkdir()
            name = "performance-update.log"
            first, second = src / name, src / "logs" / name
            first.write_text("Frame length: 9ms\n")
            second.write_text("Frame length: 100ms\n")
            start = lab.find_perf_logs(src)
            with first.open("a") as f:
                f.write("Frame length: 11ms\n")
            # Rotation to a new inode even though its size is equal to the old log.
            replaced = second.with_suffix(".new")
            replaced.write_text("Frame length: 200ms\n")
            replaced.replace(second)
            end = lab.find_perf_logs(src)
            with first.open("a") as f:
                f.write("Frame length: 222ms\n")
            copied = lab.copy_perf_log_deltas(out, start, end)
            self.assertEqual(len({x["saved"] for x in copied}), 2)
            self.assertEqual(lab.parse_slow_logs(out)[name]["slow_lengths_ms"], lab.dist([11, 200]))

    def test_counter_resets_and_zero_are_distinct(self):
        for counts, want in (([3, 3], 0), ([5], None), ([3, 0, 4], None)):
            samples = [{"cpu": {"throttle_count": c}} for c in counts]
            system = lab.analyze({"samples": samples})["system"]
            self.assertEqual(system["throttle_delta"], want)
            self.assertEqual(system["throttle_observations"], len(counts))

    def test_report_and_compare_keep_legacy_evidence_and_symlink_targets_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, other = Path(tmp) / "old", Path(tmp) / "other"
            root.mkdir()
            other.mkdir()
            old_input = {**EVDEV, **dict.fromkeys(lab.INPUT_COUNTS, 0), "reports": 2, "syn_dropped": 0,
                         "period_ms": lab.dist([0]), "observer_delay_ms": lab.dist([]),
                         "histogram": lab.histogram([0], 0, 12, 0.5)}
            old_nodes = {
                "alsa_output.reset": {"observations": 3, "first_err": 3, "last_err": 4, "delta_err": 1},
                "alsa_output.replaced": {"observations": 2, "first_err": 3, "last_err": 4, "delta_err": 1},
                "alsa_output.zero": {"observations": 2, "first_err": 2, "last_err": 2, "delta_err": 0},
            }
            legacy = {"version": "2026-11-13.1", "config": {"label": "Old", "seconds": 90},
                      "input": {"devices": [old_input], "status": []}, "samples": [display_sample({})],
                      "pw_top": {"status": "parsed", "nodes": old_nodes}}
            lab.write_json(root / "data.json", legacy)
            lab.write_json(other / "data.json", {**legacy, "config": {"label": "Other", "seconds": 10}})
            (root / "pw-top-batch.txt").write_text(
                "R 32 256 48000 1us 2us 0.2 0.1 3 alsa_output.reset\n"
                "R 32 256 48000 1us 2us 0.2 0.1 0 alsa_output.reset\n"
                "R 32 256 48000 1us 2us 0.2 0.1 4 alsa_output.reset\n"
                "R 33 256 48000 1us 2us 0.2 0.1 3 alsa_output.replaced\n"
                "R 34 256 48000 1us 2us 0.2 0.1 4 alsa_output.replaced\n"
                "R 35 256 48000 1us 2us 0.2 0.1 2 alsa_output.zero\n"
                "R 35 256 48000 1us 2us 0.2 0.1 2 alsa_output.zero\n")
            (root / "performance-logs").mkdir()
            (root / "performance-logs/performance-update.log").write_text("Frame length: 74 ms")
            evidence = list(root.rglob("*.txt")) + list(root.rglob("*.log")) + [root / "data.json", other / "data.json"]
            before = [hashlib.sha256(p.read_bytes()).digest() for p in evidence]
            for name in ("analysis.json", "comparison.json"):
                (root / name).hardlink_to(root / "data.json")
            for name in ("report.html", "comparison.html"):
                (root / name).symlink_to(root / "pw-top-batch.txt")
            self.assertEqual(lab.report(SimpleNamespace(session=root)), 0)
            self.assertEqual(lab.compare(SimpleNamespace(sessions=[root, other], out=root)), 0)
            self.assertEqual(before, [hashlib.sha256(p.read_bytes()).digest() for p in evidence])
            summary = json.loads((root / "analysis.json").read_text())
            self.assertEqual(summary["capture"]["status"], "unknown")
            self.assertIsNone(summary["input"]["devices"][0]["timing"]["period_clock"])
            self.assertIsNone(summary["input"]["devices"][0]["period_ms"]["p50"])
            self.assertIsNone(summary["draw"]["dso_ratio"])
            self.assertEqual(json.loads((root / "data.json").read_text()), legacy)
            comparison = json.loads((root / "comparison.json").read_text())[0]["analysis"]
            for result in (summary, comparison):
                self.assertEqual(result["audio"]["pw_top"]["nodes"],
                                 {name: {**row, "err_source": None, "delta_err": None} for name, row in old_nodes.items()})
            html = (root / "comparison.html").read_text()
            self.assertIn("Δは未判定", html)
            self.assertIn("未測定 (0/0 observed)", html)

    def test_legacy_aligned_timing_is_recovered_only_when_supported(self):
        periods = [2, 4]
        device = {**EVDEV, "period_ms": lab.dist(periods), "observer_delay_ms": lab.dist([0, 2]), "syn_dropped": 0}
        status = [{"path": EVDEV["path"], "status": "opened", "clock": lab.MONOTONIC}]
        for changed, expected_period, expected_delay in (({}, 3, 1),
                                                         ({"syn_dropped": 1}, None, None),
                                                         ({"period_ms": lab.dist([0, 4])}, None, 1)):
            result = lab.analyze_input({"devices": [{**device, **changed}], "status": status})["devices"][0]
            self.assertEqual(result["period_ms"]["p50"], expected_period)
            self.assertEqual(result["observer_delay_ms"]["p50"], expected_delay)

    def test_cli_replays_legacy_format_rows_and_preserves_unlinked_output_observation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            archived, incomplete = root / "linked", root / "unlinked"
            name = "alsa_output.fixture"
            row = {"observations": 2, "first_err": 48000, "last_err": 48000, "delta_err": 0,
                   "delta_err_source": "pw-top same observed node ID and nondecreasing ERR samples"}
            mode = {"width": 1366, "height": 768, "refreshRate": 60.003, "vrr": False}
            evidence = []
            for session, linked in ((archived, True), (incomplete, False)):
                session.mkdir()
                sample = display_sample({**mode, "directScanoutTo": "0" if linked else "1",
                                         "activelyTearing": not linked})
                if not linked:
                    del sample["display"]["monitor"]["id"]
                data_path = session / "data.json"
                data_path.write_text(json.dumps({
                    "version": "2026-11-20.2", "samples": [sample],
                    "config": {"label": session.name, "seconds": 10, "expected_tablet_hz": 400,
                               "expected_bass": "-128", "game_settings": "8x-sync"},
                    "proc_start": {"environ": {"OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD": "-128"}},
                    "capture": {"status": "complete", "clock": lab.MONOTONIC, "elapsed_s": 10, "sample_interval_s": 1},
                    "pw_top": {"status": "parsed", "nodes": {name: row}},
                }))
                evidence.append(data_path)
            raw = archived / "pw-top-batch.txt"
            raw.write_text(PW_HEADER + pw_row(32, 3, name) + pw_row(32, 6, name))
            evidence.append(raw)
            before = [hashlib.sha256(path.read_bytes()).digest() for path in evidence]

            for session in (archived, incomplete):
                subprocess.run([sys.executable, "-B", source, "report", session], check=True, capture_output=True)
            subprocess.run([sys.executable, "-B", source, "compare", archived, incomplete, "--out", root],
                           check=True, capture_output=True)
            reports = [json.loads((session / "analysis.json").read_text()) for session in (archived, incomplete)]
            comparison = json.loads((root / "comparison.json").read_text())
            self.assertEqual([entry["analysis"] for entry in comparison], reports)
            linked_row, unlinked_row = [report["audio"]["pw_top"]["nodes"][name] for report in reports]
            self.assertEqual((linked_row["first_err"], linked_row["last_err"], linked_row["delta_err"]), (3, 6, 3))
            self.assertEqual((unlinked_row["first_err"], unlinked_row["last_err"]), (48000, 48000))
            self.assertIsNone(unlinked_row["err_source"])
            self.assertIsNone(unlinked_row["delta_err"])
            self.assertIsNone(unlinked_row["delta_err_source"])
            self.assertIn("保存値・ERR列未確認", (incomplete / "report.html").read_text())
            self.assertEqual(reports[0]["draw"]["dso_ratio"], 0)
            self.assertIsNone(reports[1]["draw"]["dso_ratio"])
            self.assertEqual(reports[1]["draw"]["monitor_observations"]["dso_active"], 1)
            html = (root / "comparison.html").read_text()
            self.assertIn("0.000 (0/1 observed)", html)
            self.assertIn("未測定 (0/0 observed)", html)
            self.assertNotIn("+100.000", html)
            self.assertEqual(before, [hashlib.sha256(path.read_bytes()).digest() for path in evidence])

    def test_atomic_publication_refuses_to_replace_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            capture = Path(tmp) / "data.json"
            capture.write_text("original evidence")
            with self.assertRaises(FileExistsError):
                lab.write_json(capture, {"samples": []}, new=True)
            self.assertEqual(capture.read_text(), "original evidence")
            self.assertEqual(list(Path(tmp).iterdir()), [capture])

    def test_comparison_suppresses_delta_for_mismatched_or_partial_windows(self):
        config = {"label": "A", "seconds": 10, "expected_tablet_hz": 400,
                  "expected_bass": "-128", "game_settings": "8x-sync"}
        window = {"status": "complete", "clock": lab.MONOTONIC, "elapsed_s": 10, "sample_interval_s": 1}
        first = {"config": config, "version": lab.VERSION,
                 "environment": {"bass": "-128", "monitor_modes": [(1366, 768, 60.003, False)]},
                 "analysis": lab.analyze({"capture": window, "samples": [display_sample({"directScanoutTo": "1"})]})}
        second = {**first, "config": {**config, "label": "B"},
                  "analysis": lab.analyze({"capture": window, "samples": [display_sample({"directScanoutTo": "0"})]})}
        self.assertIn("-100.000", lab.comparison_html([first, second]))
        mismatches = [
            {**second, "config": {**config, "expected_tablet_hz": 1000}},
            {**second, "version": "older"},
            {**second, "environment": {**first["environment"], "bass": "-256"}},
            {**second, "environment": {**first["environment"], "monitor_modes": [(1366, 768, 60.003, 0)]}},
            {**second, "environment": {**first["environment"], "monitor_modes": [(1366, 768, 61, False)]}},
            {**second, "analysis": {**second["analysis"], "capture": {**window, "status": "partial"}}},
            {**second, "analysis": {**second["analysis"], "capture": {**window, "elapsed_s": 13}}},
            {**second, "analysis": {**second["analysis"], "capture": {**window, "elapsed_s": None}}},
        ]
        for other in mismatches:
            with self.subTest(other=other):
                report = lab.comparison_html([first, other])
                self.assertNotIn("-100.000", report)
                self.assertIn("0.000 (0/1 observed)", report)
                self.assertIn("100.000 (1/1 observed)", report)
                self.assertIn("Δは未判定", report)

    def test_compare_preserves_dso_observations_with_missing_conditions(self):
        config = {"seconds": 10, "expected_tablet_hz": 400, "expected_bass": "-128", "game_settings": "8x-sync"}
        window = {"status": "complete", "clock": lab.MONOTONIC, "elapsed_s": 10, "sample_interval_s": 1}
        mode = {"width": 1366, "height": 768, "refreshRate": 60.003, "vrr": False}
        cases = [(None, {}), (None, mode), (" ", mode), ("-128", {}), ("-128", {**mode, "vrr": None}), ("-128", mode)]
        for bass, display_mode in cases:
            with self.subTest(bass=bass, display_mode=display_mode), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                sessions = [root / "active", root / "inactive"]
                for session, scanout in zip(sessions, ("1", "0")):
                    session.mkdir()
                    proc = {"environ": {"OSU_TEMP_TESTING_BASS_CONFIG_DEV_PERIOD": bass}} if bass else {}
                    lab.write_json(session / "data.json", {
                        "version": "2026-11-20.1", "config": {**config, "label": session.name},
                        "capture": window, "proc_start": proc,
                        "samples": [display_sample({**display_mode, "directScanoutTo": scanout})],
                    })
                self.assertEqual(lab.compare(SimpleNamespace(sessions=sessions, out=root)), 0)
                report = (root / "comparison.html").read_text()
                self.assertIn("100.000 (1/1 observed)", report)
                self.assertIn("0.000 (0/1 observed)", report)
                expected_delta = bass == "-128" and display_mode == mode
                self.assertEqual("-100.000" in report, expected_delta)
                self.assertEqual("Δは未判定" in report, not expected_delta)


class TestCaptureLifecycle(unittest.TestCase):
    @contextmanager
    def capture_fixture(self, root, read_fd):
        real_open = os.open

        def open_fixture(path, *args, **kwargs):
            return read_fd if path == EVDEV["path"] else real_open(path, *args, **kwargs)

        args = SimpleNamespace(out=root, label="fixture", seconds=10, tablet_hz=400, bass="-128", game_settings="8x",
                               note="", event=[], hidraw=[], logs=None, pid=None)
        with ExitStack() as stack:
            for name, value in {"node_candidates": [EVDEV], "find_perf_logs": {}, "proc_pid": None,
                                "proc_snapshot": {"pid": None}, "alsa_snapshot": {}, "pw_dump_snapshot": {},
                                "display_snapshot": display_sample({})["display"], "cpu_snapshot": {},
                                "task_snapshot": []}.items():
                stack.enter_context(mock.patch.object(lab, name, return_value=value))
            stack.enter_context(mock.patch.object(lab.os, "open", side_effect=open_fixture))
            stack.enter_context(mock.patch.object(lab.shutil, "which", return_value=None))
            yield args

    def test_sigterm_while_sampling_publishes_partial_capture_and_restores_handler(self):
        with tempfile.TemporaryDirectory() as tmp:
            fd, writer = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
            self.addCleanup(os.close, writer)
            prev = signal.getsignal(signal.SIGTERM)
            real_sample = lab.InputObserver.sample

            def sample_and_signal(observer, timeout):
                real_sample(observer, timeout)
                signal.raise_signal(signal.SIGTERM)

            os.write(writer, event(0))
            with self.capture_fixture(tmp, fd) as args, \
                 mock.patch.object(lab.InputObserver, "sample", sample_and_signal):
                self.assertEqual(lab.capture(args), 143)
            self.assertIs(signal.getsignal(signal.SIGTERM), prev)
            with self.assertRaises(OSError):
                os.fstat(fd)
            session, = Path(tmp).iterdir()
            self.assertEqual(session.stat().st_mode & 0o777, 0o700)
            self.assertFalse((session / lab.INCOMPLETE).exists())
            data = json.loads((session / "data.json").read_text())
            self.assertEqual(data["capture"]["status"], "partial")
            self.assertEqual(data["capture"]["signal"], "SIGTERM")
            self.assertEqual(data["input"]["devices"][0]["reports"], 1)
            self.assertEqual((session / "data.json").stat().st_mode & 0o777, 0o600)
            self.assertIn("capture partial", (session / "report.html").read_text())

    def test_sampling_exception_keeps_partial_capture_and_closes_fd(self):
        with tempfile.TemporaryDirectory() as tmp:
            fd, writer = os.pipe()
            self.addCleanup(os.close, writer)
            with self.capture_fixture(tmp, fd) as args, \
                 mock.patch.object(lab.InputObserver, "sample", side_effect=RuntimeError("sample fault")):
                self.assertEqual(lab.capture(args), 1)
            with self.assertRaises(OSError):
                os.fstat(fd)
            session, = Path(tmp).iterdir()
            data = json.loads((session / "data.json").read_text())
            self.assertEqual(data["capture"]["status"], "partial")
            self.assertEqual(data["capture"]["failures"], [{"stage": "sampling", "type": "RuntimeError"}])

    def test_forced_publication_failure_leaves_visible_incomplete_outcome(self):
        with tempfile.TemporaryDirectory() as tmp:
            fd, writer = os.pipe()
            self.addCleanup(os.close, writer)
            link = os.link

            def fail_data_only(src, dst):
                if dst.name == "data.json":
                    raise OSError(errno.ENOSPC, "fixture disk full")
                return link(src, dst)

            with self.capture_fixture(tmp, fd) as args, \
                 mock.patch.object(lab.time, "monotonic", side_effect=[0, 0, 10, 10, 10, 10]), \
                 mock.patch.object(lab.os, "link", side_effect=fail_data_only):
                with self.assertRaisesRegex(OSError, "disk full"):
                    lab.capture(args)
            session, = Path(tmp).iterdir()
            self.assertTrue((session / lab.INCOMPLETE).is_file())
            self.assertFalse((session / "data.json").exists())
            with self.assertRaisesRegex(ValueError, "incomplete capture"):
                lab.report(SimpleNamespace(session=session))
            with self.assertRaises(OSError):
                os.fstat(fd)

    def test_sigint_at_publication_leaves_complete_raw_capture(self):
        with tempfile.TemporaryDirectory() as tmp:
            fd, writer = os.pipe()
            self.addCleanup(os.close, writer)
            link = os.link

            def signal_at_link(src, dst):
                if dst.name == "data.json":
                    signal.raise_signal(signal.SIGINT)
                    self.assertFalse(dst.exists())
                return link(src, dst)

            with self.capture_fixture(tmp, fd) as args, \
                 mock.patch.object(lab.time, "monotonic", side_effect=[0, 0, 10, 10, 10, 10]), \
                 mock.patch.object(lab.os, "link", side_effect=signal_at_link):
                self.assertEqual(lab.capture(args), 130)
            session, = Path(tmp).iterdir()
            self.assertEqual(json.loads((session / "data.json").read_text())["capture"]["status"], "complete")
            self.assertFalse((session / lab.INCOMPLETE).exists())

    def test_retained_evidence_can_be_reported_after_render_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            fd, writer = os.pipe()
            self.addCleanup(os.close, writer)
            with self.capture_fixture(tmp, fd) as args, \
                 mock.patch.object(lab.time, "monotonic", side_effect=[0, 0, 10, 10, 10, 10]), \
                 mock.patch.object(lab, "render_report", side_effect=OSError(errno.ENOSPC, "report fault")):
                with self.assertRaisesRegex(OSError, "report fault"):
                    lab.capture(args)
            session, = Path(tmp).iterdir()
            raw = (session / "data.json").read_bytes()
            self.assertEqual(lab.report(SimpleNamespace(session=session)), 0)
            self.assertEqual((session / "data.json").read_bytes(), raw)

    def test_pw_top_reaps_only_owned_child(self):
        command = [sys.executable, "-c", "import time; time.sleep(30)"]
        popen = subprocess.Popen

        with popen(command) as unrelated, tempfile.TemporaryDirectory() as tmp:
            try:
                status = {}
                with lab.capture_signals(), mock.patch.object(lab.shutil, "which", return_value="pw-top"), \
                     mock.patch.object(lab.subprocess, "Popen", side_effect=lambda _, **kw: popen(command, **kw)):
                    with lab.pw_top_capture(Path(tmp), 10, status):
                        self.assertIsNone(unrelated.poll())
                self.assertEqual(status["returncode"], -signal.SIGTERM)
                self.assertIsNone(unrelated.poll())
            finally:
                unrelated.terminate()

    def test_pw_top_kills_and_waits_if_graceful_termination_times_out(self):
        process = mock.Mock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("pw-top", 2), -signal.SIGKILL]
        process.returncode = -signal.SIGKILL
        with tempfile.TemporaryDirectory() as tmp, lab.capture_signals(), \
             mock.patch.object(lab.shutil, "which", return_value="pw-top"), \
             mock.patch.object(lab.subprocess, "Popen", return_value=process):
            status = {}
            with self.assertRaisesRegex(RuntimeError, "body error"):
                with lab.pw_top_capture(Path(tmp), 10, status):
                    raise RuntimeError("body error")
        self.assertEqual(process.method_calls, [mock.call.poll(), mock.call.terminate(), mock.call.wait(timeout=2),
                                                mock.call.kill(), mock.call.wait(timeout=2)])
        self.assertEqual(status, {"status": "forced stop", "returncode": -signal.SIGKILL})


if __name__ == '__main__':
    unittest.main(verbosity=2)
