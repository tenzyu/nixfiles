#!/usr/bin/env python3
"""Hermetic unittest; no game, tablet, audio or Wayland is touched."""
import importlib.util
import json
import os
import selectors
import struct
import tempfile
import unittest
from pathlib import Path

source = Path(__file__).with_name("osu-lab.py")
spec = importlib.util.spec_from_file_location("osu_lab", source)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


class TestLatencyLab(unittest.TestCase):
    def test_distribution(self):
        p = lab.dist([0.5, 1, 2, 3, 4, 5])
        self.assertEqual(p["count"], 6)
        self.assertEqual(p["min"], 0.5)
        self.assertEqual(p["max"], 5)
        self.assertGreaterEqual(p["p99"], p["p95"])
        self.assertEqual(lab.dist([])["p99"], None)

    def test_histogram(self):
        h = lab.histogram([0, 0.2, 2.5, 5, 13.0], 0, 12, .5)
        self.assertEqual(sum(h["counts"]), 4)
        self.assertEqual(h["outside_range"], 1)
        self.assertEqual(h["counts"][5], 1)

    def test_input_event_parser_does_not_store_key_identity(self):
        obs = lab.InputObserver.__new__(lab.InputObserver)
        obs.selector = selectors.DefaultSelector()
        obs.devices = []
        obs.status = []
        readfd, writefd = os.pipe2(os.O_NONBLOCK | os.O_CLOEXEC)
        device = dict(kind="evdev", path="/dev/input/event77", name="test", fd=readfd,
                      kernel_clock="unavailable", key_down=0, key_up=0, key_repeat=0,
                      pen_touch_down=0, pen_touch_up=0, syn_dropped=0,
                      reports=0, last_ns=None, tail=b"", intervals_ms=[], dispatch_delay_ms=[])
        obs.devices.append(device)
        obs.selector.register(readfd, selectors.EVENT_READ, device)
        # BTN_TOUCH down/up and two separate state-change SYN_REPORT packets
        payload = b''.join([lab.EVENT.pack(1, 0, 1, 330, 1), lab.EVENT.pack(1, 0, 0, 0, 0),
                            lab.EVENT.pack(1, 1000, 1, 330, 0), lab.EVENT.pack(1, 1000, 0, 0, 0),
                            lab.EVENT.pack(1, 2000, 0, 3, 0)])
        os.write(writefd, payload)
        obs.sample(.1)
        os.close(writefd)
        output = obs.result()["devices"][0]
        self.assertEqual(output["key_down"], 1)
        self.assertEqual(output["key_up"], 1)
        self.assertEqual(output["pen_touch_down"], 1)
        self.assertEqual(output["pen_touch_up"], 1)
        self.assertEqual(output["reports"], 2)
        self.assertEqual(output["syn_dropped"], 1)
        self.assertEqual(output["period_ms"]["count"], 1)
        self.assertNotIn("key_code", output)

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
            p.write_text('S ID QUANT RATE WAIT BUSY W/Q B/Q ERR NAME\nR 32 256 48000 1us 2us 0.2 0.1 3 alsa_output.pci-0000_00_1f.3.analog-stereo\nR 32 256 48000 1us 2us 0.2 0.1 6 alsa_output.pci-0000_00_1f.3.analog-stereo\n')
            got = lab.parse_pw_top(p)
            self.assertEqual(next(iter(got["nodes"].values()))["delta_err"], 3)

    def test_dso_counts_only_correct_foreground(self):
        def snapshot(fs,fc,dso,tear=False):
            return {"cpu":{"temp_C": 86, "throttle_count": 12, "cpu_kHz": 3000000},
                    "display":{"window":{"class":"osu!", "fullscreen":fs, "fullscreenClient":fc},
                               "monitor":{"name":"eDP-1","directScanoutTo":"1" if dso else "0", "activelyTearing":tear}},
                    "threads":[]}
        data={"samples":[snapshot(2,0,True),snapshot(2,0,True,True),snapshot(2,2,False),snapshot(0,0,False)],
              "input":{"devices":[],"status":[]},"pw_top":{"nodes":{}},
              "proc_start":{"pid":5}}
        a=lab.analyze(data)
        self.assertEqual(a["draw"]["eligible_samples"],2)
        self.assertEqual(a["draw"]["dso_samples"],2)
        self.assertEqual(a["draw"]["dso_ratio"],100)
        self.assertEqual(a["draw"]["actively_tearing_samples"],1)
        self.assertEqual(a["system"]["throttle_delta"], 0)

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
