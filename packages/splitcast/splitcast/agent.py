from __future__ import annotations

import copy
import json
import threading
import time
import uuid
from dataclasses import asdict

from . import media
from .config import Config, Error, Lifecycle, atomic_write, secret
from .net import request
from .obs import OBS, launch, loopback_only
from .process import Processes, wait_for
from .tts import EventSub, SpeechQueue, validate_wav


class Backend:
    def __init__(self, config, owner):
        self.config, self.owner = config, owner
        self.processes = Processes()
        self.media = media.Media(config, self.processes)
        self.remote_owned = False
        self.speech = None
        self.events = None
        self.played = []
        self.output = None
        self.playback_id = None
        self.playback_expires = 0
        self.tts_error = ""
        self.remote_status = None
        self.last_output_bytes = 0
        self.last_output_change = time.monotonic()
        self.obs_recovering = False

    def peer(self, command, args=None, raw=False, endpoint=None):
        p = self.config["peer"]
        token = secret(p["remote_token_file"])
        origin = f"http://127.0.0.1:{p['forward_control_port']}"
        target = f"127.0.0.1:{p['remote_control_port']}"
        headers = {"Authorization": "Bearer " + token, "Origin": "http://" + target, "Host": target}
        if endpoint:
            return request(origin + endpoint, headers=headers, raw=raw, limit=4 * 1024 * 1024, timeout=p["timeout_seconds"])
        return request(origin + "/api/command", data={"command": command, "args": dict(args or {}, _owner=self.owner)},
                       headers=headers, timeout=min(5, p["timeout_seconds"]) if command == "heartbeat" else min(120, p["timeout_seconds"] * 5), control=True)

    def doctor(self):
        return media.doctor(self.config)

    def prepare(self):
        self.media.reset_observations()
        self.last_output_bytes = 0
        self.last_output_change = time.monotonic()
        report = self.doctor()
        if not report["ok"]:
            failed = [c["action"] for c in report["checks"] if not c["ok"]]
            raise Error("Preflight failed. " + "; ".join(failed))
        if self.config["role"] == "capture":
            self.media.tunnel()
            wait_for(lambda: self.peer("status").get("role") == "production", self.config["peer"]["timeout_seconds"],
                     "Remote agent did not authenticate through SSH; start it and provision its token", self.processes)
            remote = self.peer("routes")
            if remote["transport"] != self.transport():
                raise Error("Host media/camera route selections differ; save matching routes on both hosts")
            self.remote_owned = True
            self.peer("prepare")
        else:
            self.media.receiver()
            self.media.prepare_microphone()
            launch(self.config, self.processes)
            with OBS(self.config) as obs:
                obs.configure()
            if self.config.enabled("tts"):
                self.speech = SpeechQueue(self.config["tts"], mixer=self.mix)
                if self.config["tts"]["eventsub"]:
                    self.events = EventSub(self.config["tts"], self.speech)
                    self.events.start()

    def transport(self):
        return {"ports": {k: self.config["capture"][k] for k in ("rtmp_port", "rtsp_port")},
                "camera": self.config["camera"], "routes": json.loads(json.dumps([asdict(r) for r in self.config.routes])),
                "tts_mix": self.config["tts"]["mix_remote"]}

    def start(self, output):
        self.output = output
        self.last_output_bytes = 0
        self.last_output_change = time.monotonic()
        if self.config["role"] == "capture":
            self.media.senders()
            self.peer("start", {"output": output})
            if not self.health():
                raise Error("Remote output is not observed running; inspect remote status")
        else:
            timeout = self.config["peer"]["timeout_seconds"]
            self.media.remote_camera()
            wait_for(self.media.observed, timeout, "Media paths lack moving game A/V, mic or selected camera; start capture senders", self.processes)
            self.media.process_microphone()
            with OBS(self.config) as obs:
                obs.configure()
                wait_for(obs.observed, timeout, "OBS has not decoded the selected feeds; inspect preview", self.processes)
                obs.activate(output)
                wait_for(lambda: obs.observed(output), timeout, "OBS output has not produced bytes; check NVENC or output credentials", self.processes)

    def ready_health(self):
        if any(c.process.poll() is not None for c in self.processes.children.values() if c.name != "tts-play"):
            return False
        if self.config["role"] == "capture":
            self.remote_status = self.peer("heartbeat")
            return self.remote_status["state"] == Lifecycle.READY.value and self.remote_status["output"] is None
        self.media.paths()
        if not self.media.microphone_ready():
            return False
        with OBS(self.config) as obs:
            return bool(obs.call("GetVersion"))

    def health(self):
        if any(c.process.poll() is not None for c in self.processes.children.values() if c.name != "tts-play"):
            return False
        if self.config["role"] == "capture":
            self.remote_status = self.peer("heartbeat")
            return self.remote_status["state"] == Lifecycle.RUNNING.value and self.remote_status["output"] == self.output
        if not self.media.observed():
            return False
        mic = self.processes.children.get("rnnoise")
        if not mic or time.monotonic() - mic.updated > 6:
            return False
        with OBS(self.config) as obs:
            if not obs.observed(self.output):
                return False
            output = obs.call("GetRecordStatus" if self.output == "recording" else "GetStreamStatus")
            count = output.get("outputBytes", 0)
            if count != self.last_output_bytes:
                self.last_output_change = time.monotonic()
            self.last_output_bytes = count
            return time.monotonic() - self.last_output_change < 6

    def obs_ready(self):
        loopback_only(self.config["obs"]["websocket_port"])
        with OBS(self.config) as obs:
            return bool(obs.call("GetVersion"))

    def recover(self, mic_muted=False):
        obs_child = self.processes.children.get("obs")
        if self.config["role"] == "production" and obs_child and obs_child.process.poll() is not None:
            if self.output != "recording":
                raise Error("OBS stopped during Twitch output; stop and prepare before starting again")
            self.obs_recovering = "configure"
            self.processes.restart("obs", self.config["peer"]["retry_limit"])
            self.last_output_bytes = 0
            self.last_output_change = time.monotonic()
            wait_for(self.obs_ready, self.config["peer"]["timeout_seconds"],
                     "Dedicated OBS did not authenticate and become ready; run doctor")
        for child in list(self.processes.children.values()):
            if child.process.poll() is not None and (child.name in ("game", "mic", "camera", "rnnoise") or
                                                     (child.name == "ssh" and self.config["role"] == "capture")):
                self.processes.restart(child.name, self.config["peer"]["retry_limit"])
        if self.obs_recovering:
            loopback_only(self.config["obs"]["websocket_port"])
            with OBS(self.config) as obs:
                if self.obs_recovering == "configure":
                    obs.configure()
                    obs.call("SetInputMute", {"inputName": "MicProcessed", "inputMuted": mic_muted})
                    self.obs_recovering = "recording"
                if not obs.observed():
                    return False
                if not obs.call("GetRecordStatus").get("outputActive"):
                    obs.activate("recording")
                wait_for(lambda: obs.observed("recording"), self.config["peer"]["timeout_seconds"],
                         "OBS recording did not produce bytes after restart; run doctor")
        healthy = self.health()
        if healthy:
            self.obs_recovering = False
        return healthy

    def recover_ready(self, mic_muted=False):
        child = self.processes.children.get("ssh")
        if self.config["role"] == "capture" and child and child.process.poll() is not None:
            self.processes.restart("ssh", self.config["peer"]["retry_limit"])
        child = self.processes.children.get("obs")
        if self.config["role"] == "production" and child and child.process.poll() is not None:
            self.obs_recovering = True
            self.processes.restart("obs", self.config["peer"]["retry_limit"])
            wait_for(self.obs_ready, self.config["peer"]["timeout_seconds"],
                     "Dedicated OBS did not authenticate and become ready; run doctor")
        if self.obs_recovering:
            loopback_only(self.config["obs"]["websocket_port"])
            with OBS(self.config) as obs:
                obs.configure()
                obs.call("SetInputMute", {"inputName": "MicProcessed", "inputMuted": mic_muted})
            self.obs_recovering = False
        return self.ready_health()

    def close(self):
        errors = []
        if self.config["role"] == "capture" and self.remote_owned:
            try:
                self.peer("stop")
            except Error:
                errors.append("Remote stop was not acknowledged; run stop on production before reconnecting")
            self.remote_owned = False
        if self.config["role"] == "production" and "obs" in self.processes.children:
            try:
                with OBS(self.config) as obs:
                    obs.deactivate()
            except Error:
                errors.append("OBS did not acknowledge stop; the owned OBS process group was terminated")
        if self.events:
            self.events.close()
            self.events = None
        if self.speech:
            self.speech.close()
            self.speech = None
        errors.extend(self.processes.close())
        self.output = None
        self.obs_recovering = False
        self.media.reset_observations()
        self.last_output_bytes = 0
        self.last_output_change = time.monotonic()
        self.playback_id = None
        return errors

    def tts(self, action):
        if self.config["role"] == "capture":
            if action in ("off", "mute", "skip", "clear"):
                self.processes.stop("tts-play")
                self.playback_id = None
            return self.peer("tts", {"action": action})
        if not self.speech:
            raise Error("Prepare production with the TTS route enabled")
        if action == "on" and self.events:
            self.events.start()
        result = self.speech.control(action)
        if action in ("off", "mute", "skip", "clear") and self.config["tts"]["mix_remote"]:
            with OBS(self.config) as obs:
                obs.call("TriggerMediaInputAction", {"inputName": "TTSMix", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP"})
        return result

    def tick(self):
        if self.config["role"] != "capture" or not self.remote_owned:
            return
        if "tts-play" in self.processes.children:
            child = self.processes.children["tts-play"]
            if child.process.poll() is not None:
                code = child.process.returncode
                self.processes.stop("tts-play")
                self.peer("tts-finished", {"id": self.playback_id})
                self.playback_id = None
                if code:
                    raise Error("TTS playback failed; reselect its dedicated local sink, then submit new speech")
            else:
                current = self.peer("tts", {"action": "status"})
                next_job = self.peer("tts-next")
                if current["muted"] or not current["enabled"] or time.time() > self.playback_expires or next_job.get("cancel_generation") != getattr(self, "playback_generation", None):
                    self.processes.stop("tts-play")
                    self.playback_id = None
                return
        info = self.peer("tts-next")
        if not info.get("job"):
            return
        job = info["job"]
        if job["id"] in self.played:
            self.peer("tts-ack", {"id": job["id"]})
            return
        audio = validate_wav(self.peer(None, raw=True, endpoint="/api/audio/" + job["id"]))
        destination = self.config.state_dir / "tts.wav"
        atomic_write(destination, audio)
        self.played = (self.played + [job["id"]])[-1024:]
        atomic_write(self.config.state_dir / "played.json", json.dumps(self.played))
        self.peer("tts-ack", {"id": job["id"]})
        self.processes.spawn("tts-play", ["paplay", "--device", self.config["audio"]["tts_sink"],
                                          "--property=application.name=SplitCast-TTS", str(destination)])
        self.playback_id, self.playback_expires = job["id"], job["expires"]
        self.playback_generation = info["cancel_generation"]

    def mix(self, job):
        destination = self.config.state_dir / "tts-mix.wav"
        atomic_write(destination, job.audio)
        with OBS(self.config) as obs:
            obs.call("SetInputSettings", {"inputName": "TTSMix", "inputSettings": {"is_local_file": True, "local_file": str(destination)}, "overlay": True})
            obs.call("TriggerMediaInputAction", {"inputName": "TTSMix", "mediaAction": "OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART"})


class Agent:
    def __init__(self, config, backend_factory=Backend):
        self.base = config
        override = config.state_dir / "settings.json"
        if override.exists():
            try:
                config = self.apply_settings(config, json.loads(override.read_text()))
            except (OSError, ValueError):
                raise Error("Invalid saved settings; restore settings.json before starting the agent") from None
        self.config = config
        self.factory = backend_factory
        self.owner = uuid.uuid4().hex
        self.backend = backend_factory(config, self.owner)
        ledger = config.state_dir / "played.json"
        if ledger.exists():
            try:
                played = json.loads(ledger.read_text())
                if isinstance(played, list) and all(isinstance(i, str) and len(i) <= 128 for i in played):
                    self.backend.played = played[-1024:]
            except (OSError, ValueError):
                raise Error("Invalid playback ledger; restore it to prevent duplicate playback") from None
        self.state = Lifecycle.IDLE
        self.output = None
        self.error = ""
        self.warnings = []
        self.retry_count = 0
        self.lease = None
        self.lease_deadline = 0
        self.mic_muted = False
        self.lock = threading.RLock()
        self.closed = threading.Event()
        self.thread = None

    def status(self):
        speech = self.backend.speech
        events = self.backend.events
        return {"version": 1, "role": self.config["role"], "state": self.state.value, "output": self.output,
                "error": self.error, "warnings": self.warnings, "mic_muted": self.mic_muted, "retries": self.retry_count,
                "children": self.backend.processes.status(), "tts": speech.status() if speech else None,
                "eventsub": {"connected": events.connected, "error": events.error} if events else None,
                "tts_error": self.backend.tts_error,
                "peer": {k: self.backend.remote_status.get(k) for k in ("state", "error", "mic_muted", "tts", "eventsub")}
                if self.backend.remote_status else None}

    @property
    def lease_seconds(self):
        return max(30, self.config["peer"]["timeout_seconds"] * 8)

    def expire_lease(self):
        if self.lease and time.monotonic() >= self.lease_deadline:
            self.stop()
            self.warnings.append("Production owner lease expired; prepared infrastructure and output were stopped")

    def renew_lease(self, owner):
        if not owner or owner != self.lease:
            raise Error("No matching production owner; prepare a new session")
        self.lease_deadline = time.monotonic() + self.lease_seconds

    def prepare(self, owner=None):
        if self.lease and owner != self.lease:
            raise Error("Production belongs to another session; stop it explicitly on production first")
        if self.state in (Lifecycle.READY, Lifecycle.RUNNING):
            if owner != self.lease:
                raise Error("Production is already prepared locally; stop it before claiming a remote session")
            return self.status()
        if self.state != Lifecycle.IDLE:
            raise Error("Stop the previous session before preparing again")
        self.state, self.error, self.lease = Lifecycle.PREPARING, "", owner
        self.lease_deadline = time.monotonic() + self.lease_seconds if owner else 0
        try:
            self.backend.prepare()
            self.state = Lifecycle.READY
            if owner:
                self.renew_lease(owner)
        except Exception as exc:
            self.fail(exc)
            raise Error(self.error) from None
        return self.status()

    def start(self, output="recording", owner=None):
        if output not in ("recording", "twitch"):
            raise Error("Select recording or explicitly select twitch")
        if self.lease and owner != self.lease:
            raise Error("Production belongs to another session")
        if owner and self.state != Lifecycle.IDLE and owner != self.lease:
            raise Error("Production is already prepared locally")
        if self.state == Lifecycle.RUNNING:
            if output != self.output:
                raise Error("Stop before changing output")
            return self.status()
        if self.state == Lifecycle.IDLE:
            self.prepare(owner)
        if self.state != Lifecycle.READY:
            raise Error("Stop, run doctor, and prepare before starting")
        try:
            self.backend.start(output)
            self.output = output
            self.state = Lifecycle.RUNNING
            self.retry_count = 0
            if owner:
                self.renew_lease(owner)
        except Exception as exc:
            self.fail(exc)
            raise Error(self.error) from None
        return self.status()

    def fail(self, exc):
        self.error = str(exc) if isinstance(exc, Error) else "Session operation failed; stop and run doctor"
        self.warnings = self.backend.close()
        self.state, self.output = Lifecycle.FAILED, None

    def stop(self, owner=None):
        if owner and self.state != Lifecycle.IDLE and owner != self.lease:
            raise Error("Production belongs to another session")
        self.state = Lifecycle.STOPPING
        self.warnings = self.backend.close()
        self.state, self.output, self.lease = Lifecycle.IDLE, None, None
        self.lease_deadline = 0
        self.mic_muted = False
        self.error, self.retry_count = "", 0
        return self.status()

    @staticmethod
    def apply_settings(config, settings):
        allowed = {"peer": {"ssh_host"}, "capture": {"target", "game_audio"},
                   "audio": {"mic_source", "tts_sink", "mic_offset_ms"}, "camera": set(config["camera"]),
                   "tts": {"enabled", "mix_remote", "eventsub"}}
        if not isinstance(settings, dict):
            raise Error("Settings must be a JSON object")
        data = copy.deepcopy(config.data)
        for section, values in settings.items():
            if section not in allowed or not isinstance(values, dict) or set(values) - allowed[section]:
                raise Error("Unsupported route setting")
            data[section].update(values)
        for route in data["routes"]:
            if route["id"] == "camera":
                route["enabled"] = data["camera"]["enabled"]
            if route["id"] == "tts":
                route["targets"] = ["local.tts"] + (["obs.tts"] if data["tts"]["mix_remote"] else [])
        return Config.parse(data)

    def command(self, name, args=None):
        with self.lock:
            self.expire_lease()
            args = dict(args or {})
            owner = args.pop("_owner", None)
            if owner is not None and (not isinstance(owner, str) or not 1 <= len(owner) <= 128 or self.config["role"] != "production"):
                raise Error("Invalid production owner")
            allowed = {"status": set(), "heartbeat": set(), "doctor": set(), "devices": {"remote"}, "prepare": set(), "start": {"output"},
                       "stop": set(), "routes": {"settings"}, "mic": {"action"}, "tts": {"action"}, "say": {"text", "id"},
                       "preview": set(), "overlay": {"text"}, "diagnostics": set(), "tts-next": set(), "tts-ack": {"id"}, "tts-finished": {"id"}}
            if name not in allowed or set(args) - allowed[name]:
                raise Error("Unknown command or arguments")
            if self.lease and owner is not None and owner != self.lease:
                raise Error("Production belongs to another session")
            if name == "heartbeat":
                if self.state not in (Lifecycle.READY, Lifecycle.RUNNING, Lifecycle.DEGRADED):
                    raise Error("Production is not prepared; stop and prepare a new session")
                self.renew_lease(owner)
                return self.status()
            if name == "status":
                return self.status()
            if name == "doctor":
                return self.backend.doctor()
            if name == "prepare":
                return self.prepare(owner)
            if name == "start":
                return self.start(args.get("output", "recording"), owner)
            if name == "stop":
                return self.stop(owner)
            if name == "diagnostics":
                status = self.status()
                return {"version": 1, "role": status["role"], "state": status["state"], "output": status["output"],
                        "children": status["children"], "retries": status["retries"], "mic_muted": self.mic_muted}
            if name == "devices":
                result = {"local": media.devices(self.config["role"])}
                if self.config["role"] == "capture" and args.get("remote", True):
                    if "ssh" not in self.backend.processes.children:
                        self.backend.media.tunnel()
                    try:
                        remote = wait_for(lambda: self.backend.peer("devices", {"remote": False}),
                                          self.config["peer"]["timeout_seconds"], "Cannot discover remote cameras; check SSH and production agent", self.backend.processes)
                        result["remote"] = remote["local"]
                    finally:
                        if self.state == Lifecycle.IDLE:
                            self.backend.processes.stop("ssh")
                return result
            if name == "routes":
                if "settings" in args:
                    if self.state != Lifecycle.IDLE:
                        raise Error("Route changes interrupt media; stop before saving selections")
                    config = self.apply_settings(self.config, args["settings"])
                    shared = {k: v for k, v in args["settings"].items() if k in ("camera", "tts")}
                    if self.config["role"] == "capture" and shared:
                        connection = self.factory(config, self.owner)
                        try:
                            connection.media.tunnel()
                            wait_for(lambda: connection.peer("status").get("role") == "production",
                                     config["peer"]["timeout_seconds"], "Cannot save shared selections; connect the production agent", connection.processes)
                            connection.peer("routes", {"settings": shared})
                        finally:
                            connection.processes.close()
                    saved = {section: {key: value for key, value in config[section].items()
                                      if key in values} for section, values in args["settings"].items()}
                    existing = self.config.state_dir / "settings.json"
                    previous = json.loads(existing.read_text()) if existing.exists() else {}
                    for section, values in saved.items():
                        previous.setdefault(section, {}).update(values)
                    atomic_write(existing, json.dumps(previous))
                    self.config = config
                    played = self.backend.played
                    self.backend = self.factory(config, self.owner)
                    self.backend.played = played
                return {"routes": [asdict(r) for r in self.config.routes], "transport": self.backend.transport(),
                        "selection": {"peer": {"ssh_host": self.config["peer"]["ssh_host"]},
                                      "capture": {k: self.config["capture"][k] for k in ("target", "game_audio")},
                                      "audio": {k: self.config["audio"][k] for k in ("mic_source", "tts_sink", "mic_offset_ms")},
                                      "camera": self.config["camera"], "tts": {k: self.config["tts"][k] for k in ("enabled", "mix_remote", "eventsub")}}}
            if self.state not in (Lifecycle.READY, Lifecycle.RUNNING, Lifecycle.DEGRADED):
                raise Error("Prepare the session first")
            if name in ("tts", "say", "tts-next", "tts-ack", "tts-finished"):
                if not self.config.enabled("tts"):
                    raise Error("TTS route is disabled")
                if name == "tts":
                    return self.backend.tts(args.get("action", "status"))
                if self.config["role"] == "capture":
                    return self.backend.peer(name, args)
                speech = self.backend.speech
                if name == "say":
                    return speech.enqueue(args.get("text"), args.get("id"))
                if name == "tts-next":
                    return {"job": speech.next(), "cancel_generation": speech.generation}
                if name == "tts-finished":
                    return speech.finished(args.get("id"))
                return speech.acknowledge(args.get("id"))
            if self.config["role"] == "capture":
                result = self.backend.peer(name, args)
                if name == "mic":
                    self.mic_muted = result["muted"]
                return result
            with OBS(self.config) as obs:
                if name == "preview":
                    return {"image": obs.preview()}
                if name == "overlay":
                    text = args.get("text")
                    if not isinstance(text, str) or len(text) > 1000:
                        raise Error("Overlay text must be at most 1000 characters")
                    obs.call("SetInputSettings", {"inputName": "Overlay", "inputSettings": {"text": text}, "overlay": True})
                    atomic_write(self.config.state_dir / "overlay.txt", text)
                    return {"updated": True}
                action = args.get("action", "status")
                if action not in ("mute", "unmute", "status"):
                    raise Error("Use mic mute, unmute, or status")
                if action != "status":
                    self.mic_muted = action == "mute"
                    obs.call("SetInputMute", {"inputName": "MicProcessed", "inputMuted": self.mic_muted})
                return {"muted": obs.call("GetInputMute", {"inputName": "MicProcessed"})["inputMuted"]}

    def monitor_once(self):
        if not self.lock.acquire(blocking=False):
            return
        try:
            self.expire_lease()
            if self.state not in (Lifecycle.READY, Lifecycle.RUNNING, Lifecycle.DEGRADED):
                return
            prepared = self.output is None
            try:
                if prepared and self.state == Lifecycle.DEGRADED:
                    healthy = self.backend.recover_ready(self.mic_muted)
                elif prepared:
                    healthy = self.backend.ready_health()
                elif self.state == Lifecycle.DEGRADED:
                    healthy = self.backend.recover(self.mic_muted)
                else:
                    healthy = self.backend.health()
                if not healthy:
                    raise Error("Prepared infrastructure stopped; run doctor and reconnect" if prepared else
                                "Media, processed audio, or OBS output stopped; inspect doctor and reconnect the missing device")
                self.state, self.error = Lifecycle.READY if prepared else Lifecycle.RUNNING, ""
            except Error as exc:
                self.state, self.error = Lifecycle.DEGRADED, str(exc)
                self.retry_count += 1
                if self.retry_count > self.config["peer"]["retry_limit"]:
                    self.fail(Error("Recovery limit reached. " + self.error))
            if self.state in (Lifecycle.READY, Lifecycle.RUNNING):
                try:
                    self.backend.tick()
                    self.backend.tts_error = ""
                except Error as exc:
                    self.backend.tts_error = str(exc)
        finally:
            self.lock.release()

    def monitor(self):
        def loop():
            while not self.closed.wait(2):
                try:
                    self.monitor_once()
                except Exception:
                    with self.lock:
                        self.fail(Error("Supervisor failed; stop and run doctor"))
        self.thread = threading.Thread(target=loop, daemon=True)
        self.thread.start()

    def close(self):
        self.closed.set()
        if self.thread:
            self.thread.join(3)
        with self.lock:
            self.stop()
