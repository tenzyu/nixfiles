from __future__ import annotations

import base64
import copy
import datetime
import http.client
import hashlib
import importlib.util
import io
import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import wave
from pathlib import Path

from splitcast.agent import Agent, Backend
from splitcast.config import Config, Error, Lifecycle, SCHEMA, atomic_write, secret
from splitcast.media import camera_command, game_command, microphone_command, processor_command
from splitcast.obs import OBS
from splitcast.process import Processes, run, wait_for
from splitcast.server import Server
from splitcast.tts import EventSub, SpeechQueue, validate_wav


ROOT = Path(__file__).resolve().parents[1]


def sample(directory):
    data = json.loads((ROOT / "example.json").read_text())
    data["peer"]["state_dir"] = str(directory / "state")
    data["peer"]["token_file"] = str(directory / "control.token")
    data["peer"]["remote_token_file"] = str(directory / "remote.token")
    data["obs"]["password_file"] = str(directory / "obs.password")
    data["obs"]["twitch_key_file"] = str(directory / "twitch.key")
    for key in ("token_file", "remote_token_file"):
        atomic_write(data["peer"][key], "very-private-test-token-" + "x" * 32)
    atomic_write(data["obs"]["password_file"], "obs-secret-not-in-diagnostics")
    return data


def wav():
    out = io.BytesIO()
    with wave.open(out, "wb") as stream:
        stream.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
        stream.writeframes(b"\x01\x00" * 2400)
    return out.getvalue()


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="splitcast-test-")
        self.directory = Path(self.temp.name)
        self.data = sample(self.directory)
        self.config = Config.parse(self.data)

    def tearDown(self):
        self.temp.cleanup()


class ConfigTests(Fixture):
    def test_example_roundtrip_and_strict_rejection(self):
        self.assertEqual(Config.parse(json.loads(json.dumps(self.data))).routes[0].source, "game.av")
        for update in ({"version": 2}, {"role": "local"}, {"password": "leak"}, {"version": True}):
            with self.subTest(update=update), self.assertRaises(Error):
                Config.parse(dict(self.data, **update))
        for section, field, value in (("peer", "control_port", 0), ("peer", "retry_limit", 999),
                                      ("capture", "game_audio", "app:osu|default_output"), ("tts", "voicevox_url", "http://evil.test:50021")):
            bad = copy.deepcopy(self.data)
            bad[section][field] = value
            with self.subTest(field=field), self.assertRaises(Error):
                Config.parse(bad)

    def test_routes_reject_tts_in_game_and_camera_disagreement(self):
        for mutation in (lambda d: d["routes"][0]["targets"].append("local.tts"),
                         lambda d: d["routes"][1]["processors"].clear(),
                         lambda d: d["camera"].update(enabled=True, device="/dev/video0")):
            bad = copy.deepcopy(self.data)
            mutation(bad)
            with self.assertRaises(Error):
                Config.parse(bad)

    def test_secrets_require_private_permissions(self):
        filename = self.data["peer"]["token_file"]
        self.assertIn("test-token", secret(filename))
        os.chmod(filename, 0o644)
        with self.assertRaises(Error):
            secret(filename)

    def test_media_contract_has_no_software_fallback_or_credentials(self):
        d = self.data
        d["capture"].update(target="portal", game_audio="app:osu!")
        d["audio"].update(mic_source="alsa_input.raw", rnnoise_plugin="/nix/store/test/rnnoise.so")
        d["camera"].update(device="/dev/v4l/by-id/usb-camera", enabled=True)
        d["routes"][2]["enabled"] = True
        cfg = Config.parse(d)
        game = game_command(cfg)
        self.assertEqual(game[game.index("-a") + 1], "app:osu!")
        self.assertEqual(game[game.index("-encoder") + 1], "gpu")
        self.assertEqual(game[game.index("-fallback-cpu-encoding") + 1], "no")
        self.assertIn("rtmp://127.0.0.1:1935/game", game)
        self.assertIn("rtsp://127.0.0.1:8554/mic", microphone_command(cfg))
        self.assertIn("ladspa=file=/nix/store/test/rnnoise.so", " ".join(processor_command(cfg)))
        self.assertIn("splitcast_mic", processor_command(cfg))
        self.assertIn("copy", camera_command(cfg))
        for command in (game, microphone_command(cfg), camera_command(cfg), processor_command(cfg)):
            self.assertNotIn("password", " ".join(command))
            self.assertNotIn("libx264", command)


class SyntheticBackend(Backend):
    def doctor(self):
        return {"ok": True, "checks": [{"name": "synthetic", "ok": True}]}

    def prepare(self):
        self.processes.spawn("receiver", [sys.executable, "-c", "import time; time.sleep(300)"])

    def start(self, output):
        if getattr(self, "reject", False):
            raise Error("Synthetic receiver did not observe media")
        self.processes.spawn("sender", [sys.executable, "-c", "import time; time.sleep(300)"])

    def health(self):
        return all(c.process.poll() is None for c in self.processes.children.values())

    def ready_health(self):
        return self.health()

    def recover(self, mic_muted=False):
        return self.health()

    def close(self):
        return self.processes.close()

    def tick(self):
        pass


class LifecycleTests(Fixture):
    def setUp(self):
        super().setUp()
        self.agent = Agent(self.config, SyntheticBackend)

    def tearDown(self):
        self.agent.close()
        super().tearDown()

    def test_five_lifecycles_are_observed_and_leave_no_children(self):
        for _ in range(5):
            self.assertEqual(self.agent.command("prepare")["state"], "ready")
            running = self.agent.command("start")
            self.assertEqual(running["state"], "running")
            self.assertEqual(running["output"], "recording")
            pids = [c["pid"] for c in running["children"]]
            self.assertEqual(len(pids), 2)
            self.assertEqual([c["pid"] for c in self.agent.command("start")["children"]], pids)
            for pid in pids:
                os.kill(pid, 0)
            self.assertEqual(self.agent.command("stop")["children"], [])
            for pid in pids:
                with self.assertRaises(ProcessLookupError):
                    os.kill(pid, 0)
        self.assertEqual(self.agent.command("stop")["state"], "idle")

    def test_partial_start_rolls_back_and_never_reports_running(self):
        self.agent.command("prepare")
        child = self.agent.backend.processes.children["receiver"].process
        self.agent.backend.reject = True
        with self.assertRaises(Error):
            self.agent.command("start")
        state = self.agent.command("status")
        self.assertEqual(state["state"], "failed")
        self.assertIn("did not observe media", state["error"])
        self.assertEqual(state["children"], [])
        self.assertIsNotNone(child.poll())

    def test_loss_degrades_and_exhausts_bounded_retries(self):
        self.agent.command("start")
        child = self.agent.backend.processes.children["receiver"].process
        os.kill(child.pid, signal.SIGKILL)
        child.wait()
        self.agent.monitor_once()
        self.assertEqual(self.agent.command("status")["state"], "degraded")
        for _ in range(self.config["peer"]["retry_limit"]):
            self.agent.monitor_once()
        self.assertEqual(self.agent.command("status")["state"], "failed")
        self.assertEqual(self.agent.command("status")["children"], [])

    def test_route_edits_are_idle_only_and_survive_agent_restart(self):
        self.agent.command("routes", {"settings": {"capture": {"target": "DP-1", "game_audio": "app:osu!"}}})
        self.agent.command("start")
        with self.assertRaises(Error):
            self.agent.command("routes", {"settings": {"capture": {"target": "portal"}}})
        self.agent.close()
        self.agent = Agent(self.config, SyntheticBackend)
        selection = self.agent.command("routes")["selection"]
        self.assertEqual(selection["capture"], {"target": "DP-1", "game_audio": "app:osu!"})

    def test_diagnostics_are_allowlisted_even_when_error_contains_secrets(self):
        self.agent.error = "VERY_SECRET_OAUTH media-password obs-secret"
        result = self.agent.command("diagnostics")
        self.assertEqual(set(result), {"version", "role", "state", "output", "children", "retries", "mic_muted"})
        self.assertNotIn("SECRET", json.dumps(result))

    def test_output_requires_explicit_valid_selection(self):
        with self.assertRaises(Error):
            self.agent.command("start", {"output": "auto"})
        self.assertEqual(self.agent.command("start", {"output": "twitch"})["output"], "twitch")

    def test_tts_loss_does_not_stop_healthy_game_output(self):
        self.agent.command("start")
        def disconnected():
            raise Error("Speech return disconnected")
        self.agent.backend.tick = disconnected
        self.agent.monitor_once()
        status = self.agent.command("status")
        self.assertEqual(status["state"], "running")
        self.assertEqual(status["tts_error"], "Speech return disconnected")
        self.assertTrue(all(c["alive"] for c in status["children"]))

    def test_missing_preflight_capability_never_launches_media(self):
        self.agent.close()
        self.agent = Agent(self.config)
        self.agent.backend.doctor = lambda: {"ok": False, "checks": [{"ok": False, "action": "Install a compatible GPU encoder"}]}
        with self.assertRaises(Error):
            self.agent.command("prepare")
        self.assertEqual(self.agent.command("status")["state"], "failed")
        self.assertEqual(self.agent.command("status")["children"], [])


class ProcessTests(Fixture):
    def test_dead_leader_does_not_orphan_process_group(self):
        manager = Processes()
        marker = self.directory / "descendant.pid"
        code = ("import os,time,pathlib; pid=os.fork(); "
                f"pathlib.Path({str(marker)!r}).write_text(str(os.getpid())) if pid == 0 else None; "
                "time.sleep(300) if pid == 0 else None")
        child = manager.spawn("forker", [sys.executable, "-c", code])
        child.process.wait(3)
        wait_for(marker.exists, 3, "Descendant did not start")
        descendant = int(marker.read_text())
        manager.close()
        def gone_or_zombie():
            proc = Path(f"/proc/{descendant}/stat")
            return not proc.exists() or proc.read_text().split()[2] == "Z"
        self.assertTrue(wait_for(gone_or_zombie, 3, "Live orphan remains"))

    def test_probe_timeout_kills_owned_group(self):
        before = time.monotonic()
        with self.assertRaises(Error):
            run([sys.executable, "-c", "import time; time.sleep(300)"], timeout=.1)
        self.assertLess(time.monotonic() - before, 4)

    def test_child_retry_budget_and_prior_process_cleanup(self):
        manager = Processes()
        self.addCleanup(manager.close)
        child = manager.spawn("sender", [sys.executable, "-c", "import time; time.sleep(300)"])
        pids = [child.process.pid]
        for _ in range(2):
            manager.restart("sender", 2)
            pids.append(manager.children["sender"].process.pid)
        with self.assertRaises(Error):
            manager.restart("sender", 2)
        self.assertEqual(manager.status()[0]["retries"], 2)
        self.assertEqual(len(set(pids)), 3)
        for pid in pids[:-1]:
            with self.assertRaises(ProcessLookupError):
                os.kill(pid, 0)


class SpeechTests(Fixture):
    def queue(self, synthesizer=None):
        settings = dict(self.config["tts"], enabled=True, queue_limit=2)
        queue = SpeechQueue(settings, synthesizer or (lambda text: wav()))
        self.addCleanup(queue.close)
        return queue

    def test_bounded_dedup_identified_wav_and_ack(self):
        queue = self.queue()
        self.assertFalse(queue.enqueue("Hello", "message-1")["duplicate"])
        self.assertTrue(queue.enqueue("Hello", "message-1")["duplicate"])
        queue.enqueue("Again", "message-2")
        with self.assertRaises(Error):
            queue.enqueue("Overflow", "message-3")
        job = wait_for(queue.next, 3, "No synthesized job")
        self.assertEqual(job["id"], "message-1")
        self.assertEqual(validate_wav(queue.audio(job["id"])), wav())
        queue.acknowledge(job["id"])
        with self.assertRaises(Error):
            queue.audio(job["id"])

    def test_mute_and_skip_cancel_inflight_synthesis(self):
        release = threading.Event()
        entered = threading.Event()
        def synth(text):
            entered.set()
            release.wait(3)
            return wav()
        queue = self.queue(synth)
        queue.enqueue("One", "one")
        self.assertTrue(entered.wait(2))
        queue.control("mute")
        release.set()
        wait_for(lambda: not queue.status()["active"], 3, "Synthesis did not finish")
        queue.control("unmute")
        self.assertIsNone(queue.next())
        self.assertTrue(queue.enqueue("One", "one")["duplicate"])

    def test_expiry_and_eventsub_replay_dedup(self):
        queue = self.queue()
        eventsub = EventSub(dict(self.config["tts"], enabled=True), queue)
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        message = {"metadata": {"message_timestamp": now}, "payload": {"event": {"message_id": "chat-1", "message": {"text": "hello"}}}}
        eventsub.notification(message)
        eventsub.notification(message)
        wait_for(queue.next, 3, "EventSub message not synthesized")
        self.assertEqual(queue.status()["ready"], 1)
        queue.ready["chat-1"].expires = time.time() - 1
        self.assertIsNone(queue.next())
        message["metadata"]["message_timestamp"] = "2000-01-01T00:00:00Z"
        message["payload"]["event"]["message_id"] = "old"
        eventsub.notification(message)
        self.assertEqual(queue.status()["pending"], 0)

    def test_invalid_audio_fails_closed_and_queue_can_continue(self):
        queue = self.queue(lambda text: b"not a wave")
        queue.enqueue("Hello")
        wait_for(lambda: queue.status()["error"], 3, "Expected synthesis error")
        self.assertIsNone(queue.next())
        self.assertIn("synthesis failed", queue.status()["error"])

    def test_skip_playing_job_preserves_the_next_job(self):
        queue = self.queue()
        queue.enqueue("One", "one")
        queue.enqueue("Two", "two")
        wait_for(lambda: queue.status()["ready"] == 2, 3, "Jobs not ready")
        queue.acknowledge("one")
        self.assertIsNone(queue.next())
        queue.control("skip")
        self.assertEqual(queue.next()["id"], "two")


class HTTPTests(Fixture):
    def setUp(self):
        super().setUp()
        self.agent = Agent(self.config, SyntheticBackend)
        self.server = Server(self.agent, port=0)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.agent.close()
        self.thread.join(3)
        super().tearDown()

    def call(self, command="status", args=None, headers=None, body=None, method="POST", endpoint="/api/command"):
        origin = f"http://127.0.0.1:{self.port}"
        all_headers = {"Content-Type": "application/json", "Authorization": "Bearer " + self.server.token, "Origin": origin}
        all_headers.update(headers or {})
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(method, endpoint, json.dumps({"command": command, "args": args or {}}) if body is None and method == "POST" else body, all_headers)
        response = connection.getresponse()
        data = response.read()
        result = (response.status, response.getheaders(), data)
        connection.close()
        return result

    def test_actual_http_start_status_stop_and_security_boundaries(self):
        self.assertEqual(self.call("start")[0], 200)
        status, _, body = self.call()
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["state"], "running")
        for headers in ({"Authorization": "Bearer wrong"}, {"Origin": "http://evil.test"}, {"Host": "evil.test"}, {"Content-Type": "text/plain"}):
            self.assertGreaterEqual(self.call("stop", headers=headers)[0], 400)
            self.assertEqual(self.agent.command("status")["state"], "running")
        self.assertEqual(self.call("stop")[0], 200)
        self.assertEqual(self.agent.command("status")["state"], "idle")

    def test_finite_json_and_no_xss_rendering_or_token_in_html(self):
        for body in ("{", "[]", json.dumps({"command": "stop", "args": [], "extra": 1}), "x" * 16385):
            self.assertGreaterEqual(self.call(body=body)[0], 400)
        status, headers, body = self.call(method="GET", endpoint="/")
        self.assertEqual(status, 200)
        self.assertNotIn(self.server.token.encode(), body)
        self.assertIn("frame-ancestors 'none'", dict(headers)["Content-Security-Policy"])
        js = self.call(method="GET", endpoint="/ui.js")[2].decode()
        self.assertNotIn("innerHTML", js)
        self.assertNotIn("eval(", js)
        self.assertGreaterEqual(self.call(method="GET", endpoint="/api/session")[0], 400)
        status, _, body = self.call(method="GET", endpoint="/api/session", headers={"Sec-Fetch-Site": "same-origin"})
        self.assertGreaterEqual(status, 400)
        self.assertNotIn(self.server.token.encode(), body)

    def test_real_cli_option_placement_and_saved_settings(self):
        self.data["peer"]["control_port"] = self.port
        config_file = self.directory / "config.json"
        atomic_write(config_file, json.dumps(self.data))
        environment = dict(os.environ, PYTHONPATH=str(ROOT) + os.pathsep + os.environ.get("PYTHONPATH", ""))
        for arguments in (("--config", str(config_file), "status"), ("status", "--config", str(config_file))):
            result = subprocess.run([sys.executable, "-m", "splitcast", *arguments], env=environment, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(json.loads(result.stdout)["state"], "idle")
        result = subprocess.run([sys.executable, "-m", "splitcast", "routes", "--config", str(config_file),
                                 "--settings", '{"capture":{"target":"portal","game_audio":"app:osu!"}}'],
                                env=environment, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout)["selection"]["capture"]["target"], "portal")


class OBSProtocolTests(Fixture):
    def test_configure_changes_video_settings_only_when_needed(self):
        desired = {"baseWidth": 1920, "baseHeight": 1080, "outputWidth": 1920,
                   "outputHeight": 1080, "fpsNumerator": 60, "fpsDenominator": 1}

        class ConfiguredOBS(OBS):
            def __init__(self, config, actual):
                super().__init__(config)
                self.actual = actual
                self.changes = []
            def ensure_input(self, *args, **kwargs): pass
            def call(self, name, data=None):
                if name == "GetVersion": return {"obsVersion": "test"}
                if name == "GetInputKindList": return {"inputKinds": ["ffmpeg_source", "pulse_input_capture", "text_ft2_source_v2"]}
                if name == "GetSceneList": return {"scenes": [{"sceneName": "SplitCast"}]}
                if name == "GetInputList": return {"inputs": []}
                if name == "GetVideoSettings": return self.actual
                if name == "SetVideoSettings": self.changes.append(data)
                if name == "GetInputSettings": return {"inputSettings": {"device_id": self.config["audio"]["processed_sink"] + ".monitor"}}
                return {}

        matching = ConfiguredOBS(self.config, dict(desired, fps=60))
        matching.configure()
        self.assertEqual(matching.changes, [])
        different = ConfiguredOBS(self.config, dict(desired, outputWidth=1280))
        different.configure()
        self.assertEqual(different.changes, [desired])

    @unittest.skipUnless(importlib.util.find_spec("websocket"), "Requires websocket-client for the real WebSocket protocol test")
    def test_real_websocket_authenticated_request_response(self):
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        received = []
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                key = self.headers["Sec-WebSocket-Key"]
                accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
                self.send_response(101)
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", accept)
                self.end_headers()
                def send(value):
                    body = json.dumps(value).encode()
                    head = bytes([0x81, len(body)]) if len(body) < 126 else bytes([0x81, 126]) + len(body).to_bytes(2, "big")
                    self.wfile.write(head + body)
                    self.wfile.flush()
                def recv():
                    a, b = self.rfile.read(2)
                    size = b & 127
                    if size == 126:
                        size = int.from_bytes(self.rfile.read(2), "big")
                    mask = self.rfile.read(4)
                    body = self.rfile.read(size)
                    return json.loads(bytes(value ^ mask[i % 4] for i, value in enumerate(body)))
                send({"op": 0, "d": {"authentication": {"salt": "salt", "challenge": "challenge"}}})
                identify = recv()
                received.append(identify)
                if identify["d"]["authentication"] != "X2yrLiSRg3cqsmwAIzB8uQa2xD0jHQtVwrtYjHxyYpg=":
                    return
                send({"op": 2, "d": {"negotiatedRpcVersion": 1}})
                call = recv()
                received.append(call)
                send({"op": 7, "d": {"requestType": call["d"]["requestType"], "requestId": call["d"]["requestId"],
                                       "requestStatus": {"result": True}, "responseData": {"obsVersion": "synthetic-wire-server"}}})
            def log_message(self, *args):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.data["obs"]["websocket_port"] = server.server_port
        with OBS(Config.parse(self.data)) as obs:
            self.assertEqual(obs.call("GetVersion")["obsVersion"], "synthetic-wire-server")
        self.assertEqual(received[1]["d"]["requestType"], "GetVersion")

    def test_authentication_request_ids_and_opcodes(self):
        class Socket:
            def __init__(self):
                self.messages = [{"op": 0, "d": {"authentication": {"salt": "salt", "challenge": "challenge"}}}]
                self.sent = []
                self.closed = False
            def recv(self):
                return json.dumps(self.messages.pop(0))
            def send(self, value):
                value = json.loads(value)
                self.sent.append(value)
                if value["op"] == 1:
                    self.messages.append({"op": 2, "d": {"negotiatedRpcVersion": 1}})
                else:
                    self.messages.extend([{"op": 5, "d": {}}, {"op": 7, "d": {"requestId": "stale"}},
                                          {"op": 7, "d": {"requestId": value["d"]["requestId"], "requestType": value["d"]["requestType"],
                                                           "requestStatus": {"result": True}, "responseData": {"obsVersion": "test"}}}])
            def close(self):
                self.closed = True
        socket = Socket()
        with OBS(self.config, connect=lambda *a, **kw: socket) as obs:
            self.assertEqual(obs.call("GetVersion"), {"obsVersion": "test"})
            obs.call("GetVersion")
        self.assertTrue(socket.closed)
        self.assertEqual([m["op"] for m in socket.sent], [1, 6, 6])
        self.assertEqual(socket.sent[0]["d"]["authentication"], "X2yrLiSRg3cqsmwAIzB8uQa2xD0jHQtVwrtYjHxyYpg=")
        self.assertNotEqual(socket.sent[1]["d"]["requestId"], socket.sent[2]["d"]["requestId"])


if __name__ == "__main__":
    unittest.main()
