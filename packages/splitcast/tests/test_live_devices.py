import json
import os
import shlex
import shutil
import subprocess
import time
from unittest import skipUnless
from unittest.mock import patch

from splitcast.agent import Agent
from splitcast.config import Config, Error
from splitcast.media import Media, doctor, ffmpeg, rtsp
from splitcast.obs import OBS
from splitcast.process import run, wait_for
from test_media_e2e import free_ports
from test_splitcast import Fixture


class InstalledGSRTests(Fixture):
    @skipUnless(shutil.which("gpu-screen-recorder"), "Requires installed GSR and a graphical session")
    def test_actual_gsr_help_info_and_fail_closed_doctor(self):
        self.assertEqual(run(["gpu-screen-recorder", "--version"]).strip(), "5.13.8")
        with self.assertRaises(Error):
            run(["gpu-screen-recorder", "--help"])
        text = run(["gpu-screen-recorder", "--help"], allowed_codes=(0, 1))
        self.assertTrue(all(flag in text for flag in ("-encoder", "-fallback-cpu-encoding", "--list-application-audio")))
        info = run(["gpu-screen-recorder", "--info"])
        self.assertIn("section=video_codecs", info)
        self.assertIn("h264", info.splitlines())
        report = doctor(self.config)
        checks = {c["name"]: c for c in report["checks"]}
        self.assertTrue(checks["capture.flags"]["ok"])
        self.assertTrue(checks["capture.gpu"]["ok"])
        self.assertFalse(checks["capture.selection"]["ok"])
        self.assertFalse(report["ok"])


class RemoteSenderCleanupTests(Fixture):
    def test_real_ssh_stdin_eof_reaps_remote_child(self):
        ssh = shutil.which("ssh")
        host = os.environ.get("SPLITCAST_TEST_CAPTURE_SSH_HOST")
        identity = os.environ.get("SPLITCAST_TEST_CAPTURE_IDENTITY")
        if not ssh or not host or not identity or not os.path.exists(identity):
            self.skipTest("Set SPLITCAST_TEST_CAPTURE_SSH_HOST and SPLITCAST_TEST_CAPTURE_IDENTITY for remote cleanup")
        marker = f"/tmp/splitcast-eof-cleanup-{os.getpid()}"
        remote = ("child=''; cleanup() { kill $child 2>/dev/null || true; "
                  "wait $child 2>/dev/null || true; }; trap cleanup EXIT; "
                  "sleep 300 & child=$!; " + f"printf '%s\\n' \"$child\" > {shlex.quote(marker)}; "
                  "cat >/dev/null")
        base = [ssh, "-i", identity, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", host]
        try:
            child = subprocess.Popen([*base, "sh -c " + shlex.quote(remote)], stdin=subprocess.PIPE)
            self.addCleanup(lambda: child.poll() is None and child.kill())
            pid_text = ""
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                remaining = deadline - time.monotonic()
                result = subprocess.run([*base, "cat " + shlex.quote(marker)], capture_output=True, text=True,
                                        timeout=min(2, remaining), check=False)
                if result.returncode == 0:
                    pid_text = result.stdout.strip()
                    break
                time.sleep(min(.1, max(0, deadline - time.monotonic())))
            self.assertTrue(pid_text, "Remote cleanup fixture did not start")
            remote_pid = int(pid_text)
            child.stdin.close()
            child.wait(timeout=5)

            def remote_child_gone():
                probe = subprocess.run([*base, "kill -0 " + str(remote_pid)],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False)
                return probe.returncode != 0

            self.assertTrue(wait_for(remote_child_gone, 5, "Remote child survived SSH stdin EOF"))
        finally:
            cleanup = subprocess.run([*base, "rm -f " + shlex.quote(marker)], timeout=5, check=False)
            if cleanup.returncode:
                self.fail(f"Could not remove remote cleanup marker (ssh exit {cleanup.returncode})")


@skipUnless(os.environ.get("SPLITCAST_OBS_BINARY") and os.environ.get("SPLITCAST_RNNOISE_PLUGIN"),
            "Set SPLITCAST_OBS_BINARY to the loopback-patched OBS and SPLITCAST_RNNOISE_PLUGIN for real Pulse/OBS delivery")
class PulseOBSRegressionTests(Fixture):
    def setUp(self):
        super().setUp()
        if os.environ.get("SPLITCAST_OBS_TRACE") != "1":
            return
        original = OBS.receive
        trace = os.path.join(os.environ["XDG_RUNTIME_DIR"], "obs-protocol.jsonl")

        def receive(obs):
            start = time.monotonic()
            try:
                message = original(obs)
            except Exception as exc:
                with open(trace, "a") as stream:
                    stream.write(json.dumps({"elapsed": time.monotonic() - start, "exception": type(exc).__name__}) + "\n")
                raise
            if message.get("op") == 7:
                data = message.get("d", {})
                with open(trace, "a") as stream:
                    stream.write(json.dumps({"elapsed": time.monotonic() - start, "request": data.get("requestType"),
                                             "status": data.get("requestStatus")}) + "\n")
            return message

        tracer = patch.object(OBS, "receive", receive)
        tracer.start()
        self.addCleanup(tracer.stop)

    def prepare_agent(self, owner=None):
        self.data["role"] = "production"
        ports = free_ports(4)
        self.data["capture"].update(dict(zip(("rtmp_port", "rtsp_port", "api_port"), ports)))
        self.data["obs"].update(binary=os.environ["SPLITCAST_OBS_BINARY"], websocket_port=ports[3],
                                recording_dir=str(self.directory / "recordings"))
        self.data["audio"].update(processed_sink="splitcast_test_" + str(os.getpid()),
                                  rnnoise_plugin=os.environ["SPLITCAST_RNNOISE_PLUGIN"])
        agent = Agent(Config.parse(self.data))
        self.addCleanup(agent.close)
        with patch.object(agent.backend, "doctor", return_value={"ok": True}):
            agent.command("prepare", {"_owner": owner} if owner else {})
        self.assertEqual(agent.command("status")["state"], "ready")
        self.assertIsNone(agent.command("status")["output"])
        return agent

    def pulse(self, kind):
        return json.loads(run(["pactl", "-f", "json", "list", kind]))

    @skipUnless(os.environ.get("SPLITCAST_OBS_RECORD_TEST") == "1", "Requires explicit isolated OBS recording test")
    def test_real_recording_recovers_after_obs_exit(self):
        agent = self.prepare_agent()
        backend = agent.backend
        processes = backend.processes
        remote_host = os.environ.get("SPLITCAST_TEST_CAPTURE_SSH_HOST")
        if remote_host:
            binary = os.environ["SPLITCAST_TEST_CAPTURE_FFMPEG"]
            identity = os.environ["SPLITCAST_TEST_CAPTURE_IDENTITY"]
            game = [binary, "-re", "-vaapi_device", "/dev/dri/renderD128", "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30",
                    "-re", "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", "-vf", "format=nv12,hwupload",
                    "-c:v", "h264_vaapi", "-g", "30", "-c:a", "aac", "-f", "flv",
                    f"rtmp://127.0.0.1:{agent.config['capture']['rtmp_port']}/game"]
            mic = [binary, "-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                   "-c:a", "libopus", "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(agent.config, "mic")]
            ports = (agent.config["capture"]["rtmp_port"], agent.config["capture"]["rtsp_port"])
            target = os.environ.get("SPLITCAST_TEST_CAPTURE_TARGET")
            if target:
                remote_python = os.environ["SPLITCAST_TEST_CAPTURE_PYTHON"]
                forwards = [arg for port in ports for arg in ("-L", f"127.0.0.1:{port}:127.0.0.1:{port}")]
                tunnel = ["ssh", "-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                          "-o", "ConnectTimeout=5", *forwards, "--", target]
                probe = [remote_python, "-c", "import socket,sys; [socket.create_connection(('127.0.0.1',int(p)),1).close() for p in sys.argv[1:]]", *map(str, ports)]
                prefix = ("tunnel=''\ngame=''\nmic=''\n"
                          "cleanup() { kill $tunnel $game $mic 2>/dev/null || true; "
                          "wait $tunnel $game $mic 2>/dev/null || true; }\n"
                          "trap cleanup EXIT HUP TERM\n" +
                          shlex.join(tunnel) + " >/dev/null 2>&1 &\ntunnel=$!\n" +
                          "n=0\nwhile ! " + shlex.join(probe) + " >/dev/null 2>&1; do\n" +
                          "  kill -0 \"$tunnel\" 2>/dev/null || exit 1\n  n=$((n+1))\n  [ \"$n\" -lt 50 ] || exit 1\n  sleep 0.2\ndone\n")
                forwards = []
            else:
                prefix = "game=''\nmic=''\ntrap 'kill $game $mic 2>/dev/null || true' EXIT HUP TERM\n"
                forwards = [arg for port in ports for arg in ("-R", f"127.0.0.1:{port}:127.0.0.1:{port}")]
            script = (prefix + shlex.join(game) + " >/dev/null 2>&1 &\ngame=$!\n" +
                      shlex.join(mic) + " >/dev/null 2>&1 &\nmic=$!\ncat >/dev/null\n")
            processes.spawn("remote-senders", ["ssh", "-i", identity, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes",
                                             "-o", "ExitOnForwardFailure=yes", *forwards, remote_host,
                                             "sh -c " + shlex.quote(script)], stdin=subprocess.PIPE)
        else:
            processes.spawn("synthetic-game", ffmpeg("-re", "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30",
                            "-re", "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=48000", "-c:v", "libx264",
                            "-preset", "ultrafast", "-tune", "zerolatency", "-g", 30, "-c:a", "aac", "-f", "flv",
                            f"rtmp://127.0.0.1:{agent.config['capture']['rtmp_port']}/game"))
            processes.spawn("synthetic-mic", ffmpeg("-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                            "-c:a", "libopus", "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(agent.config, "mic")))
        observations = []
        call = OBS.call
        def observe(obs, name, data=None):
            try:
                result = call(obs, name, data)
            except Error as exc:
                if name in ("GetMediaInputStatus", "StartRecord", "GetRecordStatus"):
                    observations.append((name, str(exc)))
                raise
            if name in ("GetMediaInputStatus", "StartRecord", "GetRecordStatus"):
                observations.append((name, result))
            if (name == "GetRecordStatus" and not result.get("outputActive") and
                os.environ.get("SPLITCAST_OBS_DIAGNOSTIC") == "1" and
                not os.path.exists(os.path.join(os.environ["XDG_RUNTIME_DIR"], "obs-screen.png"))):
                subprocess.run(["import", "-window", "root", os.path.join(os.environ["XDG_RUNTIME_DIR"], "obs-screen.png")], check=False)
                with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "obs-windows.txt"), "w") as output:
                    subprocess.run(["xwininfo", "-root", "-tree"], stdout=output, check=False)
            return result
        try:
            with patch.object(OBS, "call", observe):
                self.assertEqual(agent.command("start", {"output": "recording"})["state"], "running")
        except Error:
            logs = sorted((agent.config.state_dir / "obs-config/obs-studio/logs").glob("*.txt"))
            if logs and os.environ.get("XDG_RUNTIME_DIR"):
                shutil.copy2(logs[-1], os.path.join(os.environ["XDG_RUNTIME_DIR"], "recording-obs.log"))
                with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "recording-observations.json"), "w") as output:
                    json.dump(observations, output)
            raise
        previous = {p.name for p in (self.directory / "recordings").glob("*.mkv")}
        self.assertTrue(previous, "OBS did not create the first recording")
        original = processes.children["obs"].process
        original.kill()
        original.wait()
        agent.monitor_once()
        self.assertEqual(agent.command("status")["state"], "degraded")
        deadline = time.monotonic() + 30
        def snapshot():
            result = {"status": agent.command("status"), "phase": backend.obs_recovering}
            microphone = processes.children.get("rnnoise")
            if microphone:
                result["microphone_age"] = time.monotonic() - microphone.updated
            if result["status"]["state"] != "failed":
                try:
                    result["paths"] = [{k: p.get(k) for k in ("name", "ready", "bytesReceived", "tracks")}
                                       for p in backend.media.paths()]
                    with OBS(agent.config) as obs:
                        result["game"] = obs.call("GetMediaInputStatus", {"inputName": "GameFeed"})
                        result["recording"] = obs.call("GetRecordStatus")
                except Error as exc:
                    result["probe_error"] = str(exc)
            return result
        recovery = [snapshot()]
        while agent.command("status")["state"] == "degraded" and time.monotonic() < deadline:
            time.sleep(2)
            agent.monitor_once()
            recovery.append(snapshot())
        status = agent.command("status")
        if status["state"] != "running" and os.environ.get("XDG_RUNTIME_DIR"):
            with open(os.path.join(os.environ["XDG_RUNTIME_DIR"], "recovery-status.json"), "w") as output:
                json.dump(recovery, output)
            logs = sorted((agent.config.state_dir / "obs-config/obs-studio/logs").glob("*.txt"))
            for index, log in enumerate(logs):
                shutil.copy2(log, os.path.join(os.environ["XDG_RUNTIME_DIR"], f"recovery-obs-{index}.log"))
        self.assertEqual(status["state"], "running", status["error"])
        self.assertNotEqual(processes.children["obs"].process.pid, original.pid)
        with OBS(agent.config) as obs:
            recording = obs.call("GetRecordStatus")
            self.assertTrue(recording["outputActive"])
            self.assertGreater(recording["outputBytes"], 0)
        time.sleep(3)
        agent.command("stop")
        recordings = [p for p in (self.directory / "recordings").glob("*.mkv") if p.name not in previous]
        self.assertTrue(recordings, "OBS did not create a new recording after recovery")
        observed = []
        for index, recording in enumerate(recordings):
            if os.environ.get("XDG_RUNTIME_DIR"):
                shutil.copy2(recording, os.path.join(os.environ["XDG_RUNTIME_DIR"], f"recovered-{index}.mkv"))
            probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name",
                                    "-of", "default=noprint_wrappers=1", str(recording)], capture_output=True, text=True, timeout=10)
            observed.append((recording.name, recording.stat().st_size, probe.returncode, probe.stdout.strip(), probe.stderr.strip()))
        self.assertTrue(any(size > 0 and code == 0 and result == "codec_name=h264" for _, size, code, result, _ in observed),
                        f"No recorded H.264 video was readable: {observed}")
        for recording in recordings:
            decoded = subprocess.run(["ffmpeg", "-v", "error", "-i", str(recording), "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"],
                                     capture_output=True, text=True, timeout=20)
            self.assertEqual((decoded.returncode, decoded.stderr.strip()), (0, ""), "Recovered recording did not finalize cleanly")

    def test_prepare_connects_real_obs_pulse_input_and_start_processor_delivers_samples(self):
        agent = self.prepare_agent()
        backend = agent.backend
        sink = self.data["audio"]["processed_sink"]
        source = next(s for s in self.pulse("sources") if s["name"] == sink + ".monitor")
        pid = backend.processes.children["obs"].process.pid
        def obs_capture():
            return [s for s in self.pulse("source-outputs") if int(s["source"]) == int(source["index"])
                    and s["properties"].get("application.process.id") == str(pid) and not s["corked"]]
        self.assertTrue(wait_for(obs_capture, 8, "MicProcessed has no real OBS Pulse source-output after Prepare"))
        self.assertNotIn("rnnoise", backend.processes.children)
        self.assertTrue(backend.ready_health())
        backend.processes.spawn("synthetic-mic", ffmpeg("-re", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                                "-c:a", "libopus", "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(agent.config, "mic")))
        wait_for(lambda: any(i["name"] == "mic" and i.get("ready") for i in backend.media.paths()), 10, "Synthetic mic not published")
        backend.media.process_microphone()
        with OBS(agent.config) as obs:
            obs.ws.send(json.dumps({"op": 3, "d": {"eventSubscriptions": 1 << 16}}))
            deadline = time.monotonic() + 8
            peak = 0
            while time.monotonic() < deadline:
                event = obs.receive()
                if event.get("d", {}).get("eventType") != "InputVolumeMeters":
                    continue
                for item in event["d"]["eventData"]["inputs"]:
                    if item["inputName"] == "MicProcessed":
                        peak = max(peak, *(value for channel in item["inputLevelsMul"] for value in channel))
                if peak > 0.000001:
                    break
            self.assertGreater(peak, 0.000001, "OBS MicProcessed received no nonzero processed samples")
        self.assertTrue(obs_capture())
        print(f"OBS MicProcessed source-output is connected to {sink}.monitor; delivered peak={peak:.8f}")
        obs_process = backend.processes.children["obs"].process
        agent.command("stop")
        self.assertIsNotNone(obs_process.poll())
        self.assertNotIn(sink, {s["name"] for s in self.pulse("sinks")})
        self.assertFalse(obs_capture())

    def test_real_ready_receiver_death_and_abandoned_lease_cleanup(self):
        agent = self.prepare_agent("owner-a")
        receiver = agent.backend.processes.children["mediamtx"].process
        receiver.kill()
        receiver.wait()
        agent.monitor_once()
        self.assertEqual(agent.command("status")["state"], "degraded")
        for _ in range(self.data["peer"]["retry_limit"]):
            agent.monitor_once()
        self.assertEqual(agent.command("status")["state"], "failed")
        self.assertEqual(agent.command("status")["children"], [])
        agent.command("stop")
        with patch.object(agent.backend, "doctor", return_value={"ok": True}):
            agent.command("prepare", {"_owner": "owner-b"})
        processes = [child.process for child in agent.backend.processes.children.values()]
        with patch("splitcast.agent.time.monotonic", return_value=agent.lease_deadline + 1):
            agent.monitor_once()
        self.assertEqual(agent.command("status")["state"], "idle")
        self.assertTrue(all(child.poll() is not None for child in processes))
        self.assertNotIn(self.data["audio"]["processed_sink"], {s["name"] for s in self.pulse("sinks")})

    def test_actual_pulse_plugin_does_not_reconnect_unchanged_late_device(self):
        agent = self.prepare_agent()
        self.data["audio"]["processed_sink"] += "_late"
        late = Media(Config.parse(self.data), agent.backend.processes)
        sink = self.data["audio"]["processed_sink"]
        with OBS(agent.config) as obs:
            obs.ensure_input("LateMic", "pulse_input_capture", {"device_id": sink + ".monitor"})
            late.prepare_microphone()
            obs.ensure_input("LateMic", "pulse_input_capture", {"device_id": sink + ".monitor"})
            source = next(s for s in self.pulse("sources") if s["name"] == sink + ".monitor")
            time.sleep(1)
            self.assertFalse([s for s in self.pulse("source-outputs") if int(s["source"]) == int(source["index"])])
            obs.call("RemoveInput", {"inputName": "LateMic"})
