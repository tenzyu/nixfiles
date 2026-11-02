import http.client
import json
import os
import sys
import threading
from unittest.mock import patch

from splitcast.agent import Agent, Backend
from splitcast.config import Config, Error
from splitcast.media import Media, doctor
from splitcast.process import Processes, run
from splitcast.server import Server
from test_splitcast import Fixture, SyntheticBackend


class DefectTests(Fixture):
    def production(self):
        self.data["role"] = "production"
        return Config.parse(self.data)

    def test_capture_ssh_reconnect_preserves_prepared_and_running_session(self):
        for running in (False, True):
            with self.subTest(running=running):
                agent = Agent(self.config)
                self.addCleanup(agent.close)
                backend = agent.backend
                backend.doctor = lambda: {"ok": True}
                backend.tick = lambda: None
                backend.media.tunnel = lambda: backend.processes.spawn(
                    "ssh", [sys.executable, "-c", "import time; time.sleep(300)"])
                backend.media.senders = lambda: None
                remote = {"state": "ready", "output": None}
                owners = []

                def peer(command, args=None, **kwargs):
                    owners.append(backend.owner)
                    if command == "status":
                        return {"role": "production"}
                    if command == "routes":
                        return {"transport": backend.transport()}
                    if command == "start":
                        remote.update(state="running", output=args["output"])
                    return dict(remote)

                backend.peer = peer
                agent.command("prepare")
                if running:
                    agent.command("start")
                original = backend.processes.children["ssh"].process
                original.kill()
                original.wait()
                agent.monitor_once()
                self.assertEqual(agent.command("status")["state"], "degraded")
                agent.monitor_once()
                status = agent.command("status")
                self.assertEqual(status["state"], "running" if running else "ready")
                self.assertEqual(status["output"], "recording" if running else None)
                self.assertNotEqual(status["children"][0]["pid"], original.pid)
                self.assertTrue(status["children"][0]["alive"])
                self.assertEqual(set(owners), {agent.owner})
                agent.close()

    def test_help_exit_one_is_explicit_and_other_errors_still_fail(self):
        command = [sys.executable, "-c", "import sys; print('-encoder -fallback-cpu-encoding --list-application-audio'); sys.exit(1)"]
        with self.assertRaises(Error):
            run(command)
        self.assertIn("-encoder", run(command, allowed_codes=(0, 1)))
        with self.assertRaises(Error):
            run([sys.executable, "-c", "raise SystemExit(2)"], allowed_codes=(0, 1))

    def test_doctor_help_exit_one_does_not_hide_missing_flags_or_gpu(self):
        binary = self.directory / "gpu-screen-recorder"
        binary.write_text(f"#!{sys.executable}\nimport sys\nif '--help' in sys.argv:\n print('-encoder -fallback-cpu-encoding --list-application-audio'); sys.exit(1)\nif '--info' in sys.argv: print('section=video_codecs\\nh264\\nh264_software\\nsection=image_formats')\n")
        binary.chmod(0o700)
        with patch.dict(os.environ, PATH=str(self.directory) + os.pathsep + os.environ.get("PATH", "")):
            checks = {c["name"]: c["ok"] for c in doctor(self.config)["checks"]}
            self.assertTrue(checks["capture.flags"])
            self.assertTrue(checks["capture.gpu"])
            binary.write_text(f"#!{sys.executable}\nprint('h264_software'); raise SystemExit(1)\n")
            checks = {c["name"]: c["ok"] for c in doctor(self.config)["checks"]}
            self.assertFalse(checks["capture.flags"])
            self.assertFalse(checks["capture.gpu"])
            binary.write_text(f"#!{sys.executable}\nimport sys\nprint('-encoder -fallback-cpu-encoding --list-application-audio' if '--help' in sys.argv else 'h264_software')\n")
            checks = {c["name"]: c["ok"] for c in doctor(self.config)["checks"]}
            self.assertTrue(checks["capture.flags"])
            self.assertFalse(checks["capture.gpu"])

    def test_real_backend_five_cycles_reset_media_and_output_observations(self):
        backend = Backend(self.production(), "test")
        self.addCleanup(backend.close)
        clock = [100.0]
        counts = {"game": 900000, "mic": 800000}
        output_bytes = [700000]
        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def configure(self): pass
            def observed(self, output=None): return True
            def activate(self, output): pass
            def call(self, name): return {"outputBytes": output_bytes[0]}
        def paths():
            return [{"name": name, "ready": True, "tracks": ["H264", "MPEG-4 Audio"] if name == "game" else ["Opus"],
                     "bytesReceived": count} for name, count in counts.items()]
        backend.media.paths = paths
        backend.doctor = lambda: {"ok": True}
        backend.media.receiver = lambda: None
        def processor():
            child = backend.processes.spawn("rnnoise", [sys.executable, "-c", "import time; time.sleep(300)"])
            child.updated = clock[0]
        def ready(check, timeout, message, processes=None):
            if not check():
                raise Error(message)
        with patch("splitcast.agent.OBS", WireOBS), patch("splitcast.agent.launch"), \
             patch("splitcast.media.run", side_effect=lambda argv: "[]" if "list" in argv else "123"), \
             patch("splitcast.agent.time.monotonic", side_effect=lambda: clock[0]), \
             patch("splitcast.agent.wait_for", side_effect=ready), \
             patch.object(backend.media, "process_microphone", side_effect=processor):
            for cycle in range(5):
                with self.subTest(cycle=cycle):
                    backend.prepare()
                    backend.start("recording")
                    self.assertTrue(backend.health())
                    clock[0] += 7
                    counts.update({k: v + 100 for k, v in counts.items()})
                    output_bytes[0] += 100
                    backend.processes.children["rnnoise"].updated = clock[0]
                    self.assertTrue(backend.health())
                    backend.close()
                    clock[0] += 10
                    counts.update(game=100, mic=100)
                    output_bytes[0] = 100

    def test_publisher_epoch_drop_rebaselines_without_masking_a_stall(self):
        media = Media(self.config, Processes())
        clock = [100.0]
        count = [100000]
        media.paths = lambda: [{"name": n, "ready": True, "bytesReceived": count[0], "tracks": ["H264", "AAC"]} for n in ("game", "mic")]
        with patch("splitcast.media.time.monotonic", side_effect=lambda: clock[0]):
            self.assertTrue(media.observed())
            clock[0] += 7
            count[0] = 10
            self.assertTrue(media.observed())
            clock[0] += 1
            count[0] = 20
            self.assertTrue(media.observed())
            clock[0] += 7
            self.assertFalse(media.observed())

    def test_obs_output_counter_decrease_rebaselines_then_detects_stall(self):
        backend = Backend(self.production(), "test")
        self.addCleanup(backend.close)
        clock = [100.0]
        count = [900000]
        child = backend.processes.spawn("rnnoise", [sys.executable, "-c", "import time; time.sleep(300)"])
        backend.output = "recording"
        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def observed(self, output=None): return True
            def call(self, name): return {"outputBytes": count[0]}
        with patch.object(backend.media, "observed", return_value=True), patch("splitcast.agent.OBS", WireOBS), \
             patch("splitcast.agent.time.monotonic", side_effect=lambda: clock[0]):
            child.updated = clock[0]
            self.assertTrue(backend.health())
            clock[0] += 7
            child.updated = clock[0]
            count[0] = 100
            self.assertTrue(backend.health())
            clock[0] += 7
            child.updated = clock[0]
            self.assertFalse(backend.health())

    def test_ready_dead_receiver_degrades_then_fails_with_bounded_cleanup(self):
        agent = Agent(self.production())
        self.addCleanup(agent.close)
        agent.backend.doctor = lambda: {"ok": True}
        def receiver():
            agent.backend.processes.spawn("mediamtx", [sys.executable, "-c", "import time; time.sleep(300)"])
        with patch.object(agent.backend.media, "receiver", side_effect=receiver), \
             patch.object(agent.backend.media, "prepare_microphone"), patch("splitcast.agent.launch"), patch("splitcast.agent.OBS"):
            agent.command("prepare")
            child = agent.backend.processes.children["mediamtx"].process
            child.kill()
            child.wait()
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            self.assertIsNone(agent.command("status")["output"])
            for _ in range(self.config["peer"]["retry_limit"]):
                agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "failed")
            self.assertEqual(agent.command("status")["children"], [])

    def test_ready_obs_restart_restores_mute_without_starting_output(self):
        agent = Agent(self.production())
        self.addCleanup(agent.close)
        agent.backend.doctor = lambda: {"ok": True}
        agent.backend.tick = lambda: None
        calls = []
        muted = [False]
        fail_configure = [False]

        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def configure(self):
                calls.append("configure")
                if fail_configure[0]:
                    fail_configure[0] = False
                    raise Error("OBS not ready")
            def deactivate(self): pass
            def call(self, name, data=None):
                calls.append(name)
                if name == "SetInputMute":
                    muted[0] = data["inputMuted"]
                if name == "GetInputMute":
                    return {"inputMuted": muted[0]}
                return {"obsVersion": "test"}

        def launch_obs(config, processes):
            processes.spawn("obs", [sys.executable, "-c", "import time; time.sleep(300)"])

        with patch.object(agent.backend.media, "receiver"), patch.object(agent.backend.media, "prepare_microphone"), \
             patch.object(agent.backend.media, "microphone_ready", return_value=True), \
             patch.object(agent.backend.media, "paths", return_value=[]), patch("splitcast.agent.launch", side_effect=launch_obs), \
             patch("splitcast.agent.OBS", WireOBS), patch("splitcast.agent.loopback_only", create=True):
            agent.command("prepare")
            agent.command("mic", {"action": "mute"})
            old = agent.backend.processes.children["obs"].process
            old.kill()
            old.wait()
            muted[0] = False
            fail_configure[0] = True
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            agent.monitor_once()
            status = agent.command("status")
            self.assertEqual(status["state"], "ready")
            self.assertIsNone(status["output"])
            self.assertNotEqual(status["children"][0]["pid"], old.pid)
            self.assertTrue(agent.command("mic")["muted"])
            self.assertEqual(calls.count("configure"), 3)
            self.assertNotIn("StartStream", calls)
            self.assertNotIn("StartRecord", calls)

    def test_ready_obs_restart_waits_until_websocket_accepts_requests(self):
        agent = Agent(self.production())
        self.addCleanup(agent.close)
        agent.backend.doctor = lambda: {"ok": True}
        agent.backend.tick = lambda: None
        state = {"restarting": False, "probes": 0}

        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def deactivate(self): pass
            def configure(self):
                if state["restarting"] and state["probes"] < 3:
                    raise Error("OBS is not ready to perform the request")
            def call(self, name, data=None):
                if name == "GetVersion" and state["restarting"]:
                    state["probes"] += 1
                    if state["probes"] < 3:
                        raise Error("OBS is not ready to perform the request")
                return {"obsVersion": "test"}

        def launch_obs(config, processes):
            processes.spawn("obs", [sys.executable, "-c", "import time; time.sleep(300)"])

        with patch.object(agent.backend.media, "receiver"), patch.object(agent.backend.media, "prepare_microphone"), \
             patch.object(agent.backend.media, "microphone_ready", return_value=True), \
             patch.object(agent.backend.media, "paths", return_value=[]), patch("splitcast.agent.launch", side_effect=launch_obs), \
             patch("splitcast.agent.OBS", WireOBS), patch("splitcast.agent.loopback_only", return_value=True):
            agent.command("prepare")
            child = agent.backend.processes.children["obs"].process
            child.kill()
            child.wait()
            state["restarting"] = True
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "ready")
            self.assertGreaterEqual(state["probes"], 3)

    def test_recording_obs_restart_resumes_only_after_inputs_and_mute_are_restored(self):
        agent = Agent(self.production())
        self.addCleanup(agent.close)
        backend = agent.backend
        backend.doctor = lambda: {"ok": True}
        backend.tick = lambda: None
        state = {"recording": False, "bytes": 100, "muted": False, "input_ready": True}
        calls = []

        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def configure(self): calls.append("configure")
            def deactivate(self): state["recording"] = False
            def observed(self, output=None):
                return state["input_ready"] and (not output or (state["recording"] and state["bytes"] > 0))
            def activate(self, output):
                calls.append("activate:" + output)
                state["recording"] = True
            def call(self, name, data=None):
                calls.append(name)
                if name == "SetInputMute": state["muted"] = data["inputMuted"]
                if name == "GetInputMute": return {"inputMuted": state["muted"]}
                if name == "GetRecordStatus": return {"outputActive": state["recording"], "outputBytes": state["bytes"]}
                return {"obsVersion": "test"}

        def spawn(name):
            child = backend.processes.spawn(name, [sys.executable, "-c", "import time; time.sleep(300)"])
            if name == "rnnoise":
                import time
                child.updated = time.monotonic()

        def immediate(check, timeout, message, processes=None):
            if not check():
                raise Error(message)
            return True

        with patch.object(backend.media, "receiver"), patch.object(backend.media, "prepare_microphone"), \
             patch.object(backend.media, "remote_camera"), patch.object(backend.media, "observed", return_value=True), \
             patch.object(backend.media, "process_microphone", side_effect=lambda: spawn("rnnoise")), \
             patch("splitcast.agent.launch", side_effect=lambda config, processes: spawn("obs")), \
             patch("splitcast.agent.OBS", WireOBS), patch("splitcast.agent.loopback_only"), \
             patch("splitcast.agent.wait_for", side_effect=immediate):
            agent.command("prepare")
            agent.command("start", {"output": "recording"})
            agent.command("mic", {"action": "mute"})
            old = backend.processes.children["obs"].process
            old.kill()
            old.wait()
            state.update(recording=False, muted=False, input_ready=False, bytes=0)
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            self.assertEqual(calls.count("activate:recording"), 1)
            state["input_ready"] = True
            agent.monitor_once()
            self.assertTrue(state["muted"])
            self.assertTrue(state["recording"])
            self.assertEqual(agent.command("status")["state"], "degraded")
            state["bytes"] = 100
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "running")
            self.assertEqual(calls.count("activate:recording"), 2)
            self.assertNotIn("activate:twitch", calls)

    def test_twitch_output_does_not_restart_obs_automatically(self):
        backend = Backend(self.production(), "owner")
        self.addCleanup(backend.close)
        backend.output = "twitch"
        child = backend.processes.spawn("obs", [sys.executable, "-c", "import time; time.sleep(300)"])
        child.process.kill()
        child.process.wait()
        with self.assertRaisesRegex(Error, "Twitch output"):
            backend.recover()
        self.assertIs(backend.processes.children["obs"].process, child.process)
        self.assertIsNotNone(child.process.poll())

    def test_recording_recovery_waits_for_first_output(self):
        import time
        backend = Backend(self.production(), "owner")
        self.addCleanup(backend.close)
        backend.output = "recording"
        backend.obs_recovering = "recording"
        microphone = backend.processes.spawn("rnnoise", [sys.executable, "-c", "import time; time.sleep(300)"])
        microphone.updated = time.monotonic()
        probes = []

        class WireOBS:
            def __init__(self, config): pass
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def deactivate(self): pass
            def observed(self, output=None):
                if output:
                    probes.append(output)
                    return len(probes) >= 3
                return True
            def call(self, name, data=None):
                return {"outputActive": True, "outputBytes": 100}

        with patch("splitcast.agent.OBS", WireOBS), patch("splitcast.agent.loopback_only"), \
             patch.object(backend.media, "observed", return_value=True):
            self.assertTrue(backend.recover())
            self.assertGreaterEqual(len(probes), 3)
            self.assertFalse(backend.obs_recovering)

    def test_authenticated_owner_heartbeat_expiry_rejects_stale_owner_and_reclaims(self):
        agent = Agent(self.production(), SyntheticBackend)
        self.addCleanup(agent.close)
        server = Server(agent, port=0)
        self.addCleanup(server.server_close)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        self.data["role"] = "capture"
        self.data["peer"].update(forward_control_port=server.server_port, remote_control_port=server.server_port)
        owner = Backend(Config.parse(self.data), "owner-a")
        other = Backend(Config.parse(self.data), "owner-b")
        clock = [100.0]
        with patch("splitcast.agent.time.monotonic", side_effect=lambda: clock[0]):
            self.assertEqual(owner.peer("prepare")["state"], "ready")
            self.assertGreaterEqual(agent.lease_seconds, 30)
            self.assertGreaterEqual(agent.lease_seconds, min(180, self.data["peer"]["timeout_seconds"] * 8))
            child = agent.backend.processes.children["receiver"].process
            deadline = agent.lease_deadline
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port)
            connection.request("POST", "/api/command", json.dumps({"command": "heartbeat", "args": {"_owner": "owner-a"}}),
                               {"Authorization": "Bearer wrong", "Content-Type": "application/json", "Origin": f"http://127.0.0.1:{server.server_port}"})
            response = connection.getresponse()
            self.assertEqual(response.status, 403)
            response.read()
            connection.close()
            self.assertEqual(agent.lease_deadline, deadline)
            with self.assertRaises(Error): other.peer("prepare")
            with self.assertRaises(Error): other.peer("heartbeat")
            clock[0] += agent.lease_seconds - 1
            self.assertEqual(owner.peer("heartbeat")["state"], "ready")
            clock[0] += agent.lease_seconds - 1
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "ready")
            clock[0] += 2
            with self.assertRaises(Error): owner.peer("heartbeat")
            self.assertIsNotNone(child.poll())
            self.assertEqual(agent.command("status")["state"], "idle")
            self.assertEqual(other.peer("prepare")["state"], "ready")
            with self.assertRaises(Error): owner.peer("start")
            self.assertEqual(other.peer("heartbeat")["state"], "ready")

    def test_capture_ready_renews_owner_and_recovery_stays_ready(self):
        backend = Backend(self.config, "owner-a")
        backend.remote_owned = True
        backend.peer = lambda command, args=None: {"state": "ready", "output": None} if command == "heartbeat" else self.fail("Health must use an owner heartbeat")
        self.assertTrue(backend.ready_health())
        self.assertFalse(backend.health())
        agent = Agent(self.config, SyntheticBackend)
        self.addCleanup(agent.close)
        agent.command("prepare")
        with patch.object(agent.backend, "ready_health", side_effect=[False, True]):
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "ready")
            self.assertIsNone(agent.command("status")["output"])

    def test_local_prepared_session_cannot_be_stolen_by_remote_owner(self):
        agent = Agent(self.production(), SyntheticBackend)
        self.addCleanup(agent.close)
        agent.command("prepare")
        with self.assertRaises(Error): agent.command("prepare", {"_owner": "intruder"})
        with self.assertRaises(Error): agent.command("heartbeat", {"_owner": "intruder"})
        with self.assertRaises(Error): agent.command("start", {"_owner": "intruder"})
        with self.assertRaises(Error): agent.command("stop", {"_owner": "intruder"})
        self.assertEqual(agent.command("status")["state"], "ready")

    def test_forged_fetch_metadata_never_discloses_token(self):
        agent = Agent(self.config, SyntheticBackend)
        self.addCleanup(agent.close)
        server = Server(agent, port=0)
        self.addCleanup(server.server_close)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.shutdown)
        for site in ("same-origin", "same-site", "none"):
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port)
            connection.request("GET", "/api/session", headers={"Sec-Fetch-Site": site, "Origin": f"http://127.0.0.1:{server.server_port}"})
            response = connection.getresponse()
            self.assertGreaterEqual(response.status, 400)
            self.assertNotIn(server.token.encode(), response.read())
            connection.close()
