import unittest

import media


class MediaEvidenceTests(unittest.TestCase):
    def test_sync_analyzer_measures_offset_and_drift(self):
        result = media.sync_evidence([0, 2, 4, 6], [0.01, 2.015, 4.02, 6.025])
        self.assertAlmostEqual(result["first_audio_minus_video_ms"], 10)
        self.assertAlmostEqual(result["last_audio_minus_video_ms"], 25)
        self.assertAlmostEqual(result["first_to_last_drift_ms"], 15)
        self.assertFalse(result["within_20ms"])
        self.assertEqual(result["synthetic_10min_sync"], "NOT_RUN")

    def test_missing_marker_refused(self):
        with self.assertRaisesRegex(media.EvidenceError, "missing matching"):
            media.sync_evidence([0, 2, 4], [10, 12, 14])

    def test_packet_analyzer_rejects_missing_timestamp_and_stream(self):
        value = {"streams": [{"index": 0, "codec_type": "video", "codec_name": "h264"}],
                 "packets": [{"stream_index": 0, "size": 100, "pts_time": i / 60, "dts_time": i / 60} for i in range(60)]}
        result = media.packet_evidence(value, {"video"})
        self.assertEqual(result["video"]["packets"], 60)
        with self.assertRaisesRegex(media.EvidenceError, "missing/unexpected media stream"):
            media.packet_evidence(value, {"video", "audio"})
        del value["packets"][30]["pts_time"]
        with self.assertRaisesRegex(media.EvidenceError, "missing packet timestamps"):
            media.packet_evidence(value, {"video"})

    def test_rtsp_commands_use_tcp_and_supported_timeout(self):
        args = media.receiver("mic", [15554, 11935], "synthetic.mkv", 6)
        self.assertEqual(args[args.index("-rtsp_transport") + 1], "tcp")
        self.assertIn("-timeout", args)
        self.assertNotIn("-rw_timeout", args)
        text = media.config(15554, 11935)
        self.assertIn("rtspTransports: [tcp]", text)
        self.assertIn("rtmpAddress: 127.0.0.1:11935", text)
        for key in ("webrtc", "hls", "srt", "metrics", "playback", "api", "pprof"):
            self.assertIn(f"{key}: false", text)


if __name__ == "__main__":
    unittest.main()
