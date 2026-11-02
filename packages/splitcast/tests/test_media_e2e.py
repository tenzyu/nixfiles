from __future__ import annotations

import http.client
import json
import os
import shutil
import socket
import sys
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch

from splitcast.agent import Agent, Backend
from splitcast.config import Config, SCHEMA, atomic_write
from splitcast.media import Media, ffmpeg, rtsp, rnnoise_filter
from splitcast.process import Processes, run, wait_for
from splitcast.server import Server
from splitcast.tts import SpeechQueue
from test_splitcast import Fixture, ROOT, SyntheticBackend, wav


def free_ports(count):
    sockets = [socket.socket() for _ in range(count)]
    try:
        for s in sockets:
            s.bind(("127.0.0.1", 0))
        return [s.getsockname()[1] for s in sockets]
    finally:
        for s in sockets:
            s.close()


class SyntheticMediaTests(Fixture):
    @unittest.skipUnless(all(shutil.which(b) for b in ("ffmpeg", "ffprobe", "mediamtx")), "Requires FFmpeg, ffprobe and MediaMTX in PATH")
    def test_real_rtmp_av_and_rtsp_mic_roundtrip_and_loss(self):
        self.data["capture"].update(dict(zip(("rtmp_port", "rtsp_port", "api_port"), free_ports(3))))
        self.data["camera"].update(enabled=True, device="/dev/v4l/by-id/synthetic-only")
        self.data["routes"][2]["enabled"] = True
        config = Config.parse(self.data)
        processes = Processes()
        self.addCleanup(processes.close)
        media = Media(config, processes)
        media.receiver()
        processes.spawn("synthetic-game", ffmpeg("-re", "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30",
                        "-re", "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", "-c:v", "libx264",
                        "-preset", "ultrafast", "-tune", "zerolatency", "-g", 30, "-pix_fmt", "yuv420p", "-c:a", "aac",
                        "-f", "flv", f"rtmp://127.0.0.1:{config['capture']['rtmp_port']}/game"))
        processes.spawn("synthetic-mic", ffmpeg("-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                        "-c:a", "libopus", "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(config, "mic")))
        processes.spawn("synthetic-camera", ffmpeg("-re", "-f", "lavfi", "-i", "testsrc2=s=160x120:r=30",
                        "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-g", 30,
                        "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(config, "camera")))
        try:
            self.assertTrue(wait_for(media.observed, 15, "No moving synthetic A/V and mic", processes))
        except Exception:
            self.fail("Synthetic readiness failed. " + json.dumps(media.paths()))
        recordings = {}
        for name in ("game", "mic", "camera"):
            destination = self.directory / (name + ".mkv")
            run(ffmpeg("-rtsp_transport", "tcp", "-i", rtsp(config, name), "-t", 2, "-c", "copy", "-y", destination), timeout=15)
            recordings[name] = json.loads(run(["ffprobe", "-v", "error", "-count_packets", "-show_streams", "-of", "json", str(destination)]))["streams"]
            run(ffmpeg("-i", destination, "-f", "null", "-"), timeout=10)
        game = {s["codec_type"]: s for s in recordings["game"]}
        self.assertEqual(game["video"]["codec_name"], "h264")
        self.assertEqual(game["audio"]["codec_name"], "aac")
        self.assertGreater(int(game["video"]["nb_read_packets"]), 10)
        self.assertGreater(int(game["audio"]["nb_read_packets"]), 10)
        self.assertEqual(recordings["mic"][0]["codec_name"], "opus")
        self.assertGreater(int(recordings["mic"][0]["nb_read_packets"]), 10)
        self.assertEqual(recordings["camera"][0]["codec_name"], "h264")
        self.assertGreater(int(recordings["camera"][0]["nb_read_packets"]), 10)
        processes.stop("synthetic-game")
        self.assertTrue(wait_for(lambda: not media.observed(), 8, "Media loss was not observed"))

    @unittest.skipUnless(os.environ.get("SPLITCAST_RNNOISE_PLUGIN") and shutil.which("ffmpeg"), "Set SPLITCAST_RNNOISE_PLUGIN to test real RNNoise samples")
    def test_rnnoise_processes_synthetic_samples(self):
        self.data["audio"]["rnnoise_plugin"] = os.environ["SPLITCAST_RNNOISE_PLUGIN"]
        config = Config.parse(self.data)
        for name, filters in (("dry", "anull"), ("processed", rnnoise_filter(config))):
            run(ffmpeg("-f", "lavfi", "-i", "anoisesrc=sample_rate=48000:seed=42:amplitude=0.01", "-t", 1,
                       "-af", filters, "-ar", 48000, "-ac", 1, "-c:a", "pcm_s16le", "-y", self.directory / (name + ".wav")))
        dry = (self.directory / "dry.wav").read_bytes()
        processed = (self.directory / "processed.wav").read_bytes()
        self.assertGreater(len(processed), 90000)
        self.assertNotEqual(dry, processed)


class SpeechReturnTests(Fixture):
    def test_voicevox_tcp_to_identified_forwarded_wav_and_separate_synthetic_playback(self):
        audio = wav()
        calls = []
        class Voicevox(BaseHTTPRequestHandler):
            def do_POST(self):
                size = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(size)
                calls.append((self.path, body))
                data = b'{"speedScale":1}' if self.path.startswith("/audio_query?") else audio
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            def log_message(self, *args):
                pass
        voicevox = ThreadingHTTPServer(("127.0.0.1", 0), Voicevox)
        voice_thread = threading.Thread(target=voicevox.serve_forever, daemon=True)
        voice_thread.start()
        self.addCleanup(voicevox.server_close)
        self.addCleanup(voicevox.shutdown)
        self.data["role"] = "production"
        self.data["tts"].update(enabled=True, voicevox_url=f"http://127.0.0.1:{voicevox.server_port}")
        production = Agent(Config.parse(self.data), SyntheticBackend)
        production.command("prepare")
        production.backend.speech = SpeechQueue(self.data["tts"])
        self.addCleanup(production.backend.speech.close)
        server = Server(production, port=0)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.addCleanup(production.close)
        self.data["role"] = "capture"
        self.data["peer"].update(forward_control_port=server.server_port, remote_control_port=server.server_port)
        self.data["audio"]["tts_sink"] = "synthetic-headphones"
        atomic_write(self.data["peer"]["remote_token_file"], server.token)
        backend = Backend(Config.parse(self.data), "synthetic-session")
        backend.remote_owned = True
        self.addCleanup(backend.processes.close)
        binary_dir = self.directory / "bin"
        binary_dir.mkdir()
        marker = self.directory / "played.wav"
        argv_file = self.directory / "playback-argv.json"
        atomic_write(binary_dir / "paplay", f"#!{sys.executable}\nimport json,sys,pathlib\npathlib.Path({str(marker)!r}).write_bytes(pathlib.Path(sys.argv[-1]).read_bytes())\npathlib.Path({str(argv_file)!r}).write_text(json.dumps(sys.argv[1:]))\n", mode=0o700)
        job = backend.peer("say", {"text": "A synthetic comment", "id": "return-1"})
        self.assertEqual(job["id"], "return-1")
        wait_for(lambda: production.backend.speech.next(), 5, "VOICEVOX did not synthesize")
        with patch.dict(os.environ, {"PATH": str(binary_dir) + os.pathsep + os.environ.get("PATH", "")}):
            backend.tick()
            wait_for(marker.exists, 5, "Synthetic playback did not consume audio")
            child = backend.processes.children["tts-play"].process
            self.assertEqual(child.wait(5), 0)
            backend.tick()
        self.assertEqual(marker.read_bytes(), audio)
        self.assertEqual(json.loads(argv_file.read_text())[:2], ["--device", "synthetic-headphones"])
        self.assertIn("application.name=SplitCast-TTS", json.loads(argv_file.read_text())[2])
        self.assertTrue(calls[0][0].startswith("/audio_query?"))
        self.assertTrue(calls[1][0].startswith("/synthesis?"))
        self.assertEqual(production.backend.speech.status()["ready"], 0)
        self.assertEqual(json.loads((backend.config.state_dir / "played.json").read_text()), ["return-1"])


class ArtifactTests(Fixture):
    def test_published_schema_matches_runtime_schema(self):
        self.assertEqual(json.loads((ROOT / "schema.json").read_text()), SCHEMA)

    def test_real_agent_process_cli_status_and_clean_shutdown(self):
        self.data["peer"]["control_port"] = free_ports(1)[0]
        config_file = self.directory / "config.json"
        atomic_write(config_file, json.dumps(self.data))
        env = dict(os.environ, PYTHONPATH=str(ROOT) + os.pathsep + os.environ.get("PYTHONPATH", ""))
        processes = Processes()
        self.addCleanup(processes.close)
        child = processes.spawn("agent", [sys.executable, "-m", "splitcast", "agent", "--config", str(config_file)], env=env)
        config = Config.parse(self.data)
        def status():
            try:
                value = run([sys.executable, "-m", "splitcast", "--config", str(config_file), "status"], timeout=5, env=env)
                return json.loads(value)
            except Exception:
                return None
        self.assertEqual(wait_for(status, 8, "Agent CLI never connected")["state"], "idle")
        self.assertIsNone(child.process.poll())
        processes.stop("agent")
        self.assertEqual(child.process.returncode, 0)
        self.assertEqual(list(config.state_dir.glob("*.wav")), [])


if __name__ == "__main__":
    unittest.main()
