from __future__ import annotations

import json
import os
import re
import shutil
import time
from pathlib import Path

from .config import Error, atomic_write, path
from .net import request
from .process import Processes, run, wait_for


def ffmpeg(*args):
    return ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-progress", "pipe:1", *map(str, args)]


def rtsp(config, name):
    return f"rtsp://127.0.0.1:{config['capture']['rtsp_port']}/{name}"


def microphone_command(config):
    return ffmpeg("-thread_queue_size", 256, "-f", "pulse", "-sample_rate", 48000,
                  "-channels", 1, "-i", config["audio"]["mic_source"], "-vn", "-ac", 1,
                  "-ar", 48000, "-c:a", "libopus", "-b:a", "96k", "-application", "lowdelay",
                  "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(config, "mic"))


def game_command(config):
    c = config["capture"]
    return ["gpu-screen-recorder", "-w", c["target"], "-s", f"{c['width']}x{c['height']}",
            "-f", str(c["fps"]), "-fm", "cfr", "-k", "h264", "-encoder", "gpu",
            "-fallback-cpu-encoding", "no", "-tune", "performance", "-bm", "cbr",
            "-q", str(c["bitrate_kbps"]), "-keyint", "2", "-a", c["game_audio"],
            "-ac", "aac", "-ab", "192", "-cursor", "no", "-c", "flv",
            "-o", f"rtmp://127.0.0.1:{c['rtmp_port']}/game"]


def camera_command(config):
    c = config["camera"]
    args = []
    if c["mode"] == "hardware" and c["encoder"] == "h264_vaapi":
        args += ["-vaapi_device", c["hw_device"]]
    args += ["-f", "v4l2", "-input_format", "h264" if c["mode"] == "h264" else "yuyv422",
             "-video_size", f"{c['width']}x{c['height']}", "-framerate", c["fps"], "-i", c["device"], "-an"]
    if c["mode"] == "h264":
        args += ["-c:v", "copy"]
    else:
        if c["encoder"] == "h264_vaapi":
            args += ["-vf", "format=nv12,hwupload"]
        args += ["-c:v", c["encoder"], "-b:v", "4M", "-g", c["fps"] * 2]
    return ffmpeg(*args, "-f", "rtsp", "-rtsp_transport", "tcp", rtsp(config, "camera"))


def rnnoise_filter(config):
    a = config["audio"]
    plugin = str(path(a["rnnoise_plugin"]))
    if not re.fullmatch(r"/[A-Za-z0-9_./+-]+", plugin):
        raise Error("RNNoise plugin path contains unsupported filter characters")
    return (f"aresample=48000:async=1000,aformat=channel_layouts=mono,"
            f"ladspa=file={plugin}:plugin={a['rnnoise_label']}:controls={a['rnnoise_control']},"
            f"highpass=f=80,volume={a['gain_db']}dB,alimiter=limit=0.95")


def camera_mode_supported(config, description):
    c = config["camera"]
    required = "H264" if c["mode"] == "h264" else "YUYV"
    format_matches = size_matches = False
    for line in description.splitlines():
        if match := re.search(r"\[\d+\]:\s*'([^']+)'", line):
            format_matches, size_matches = match[1] == required, False
        if match := re.search(r"Size: Discrete (\d+)x(\d+)", line):
            size_matches = (int(match[1]), int(match[2])) == (c["width"], c["height"])
        if format_matches and size_matches and (match := re.search(r"\(([\d.]+) fps\)", line)):
            if abs(float(match[1]) - c["fps"]) < .05:
                return True
    return False


def processor_command(config):
    return ffmpeg("-rtsp_transport", "tcp", "-i", rtsp(config, "mic"), "-vn", "-af", rnnoise_filter(config),
                  "-ar", 48000, "-ac", 1, "-f", "pulse", "-device", config["audio"]["processed_sink"], "SplitCast processed microphone")


def devices(role):
    result = {"role": role, "cameras": [], "sources": [], "sinks": [], "capture_targets": "", "applications": "", "errors": []}
    for name in ("sources", "sinks"):
        try:
            items = json.loads(run(["pactl", "-f", "json", "list", name]))
            result[name] = [{"name": i["name"], "description": i.get("description", "")} for i in items]
        except (Error, ValueError, KeyError):
            result["errors"].append(f"Cannot discover Pulse {name}; start this user's PipeWire/Pulse service")
    for device in sorted(Path("/dev/v4l/by-id").glob("*")):
        try:
            modes = run(["v4l2-ctl", "--device", str(device), "--list-formats-ext"])
            result["cameras"].append({"device": str(device), "resolved": str(device.resolve()), "formats": modes})
        except Error:
            result["errors"].append("Camera enumeration failed; check access or an existing owner")
    if role == "capture":
        for key, option in (("capture_targets", "--list-capture-options"), ("applications", "--list-application-audio")):
            try:
                result[key] = run(["gpu-screen-recorder", option])
            except Error:
                result["errors"].append(f"GSR {key} discovery failed; check graphical session")
    return result


def doctor(config):
    checks = []

    def check(name, function, action):
        try:
            if function() is False:
                raise Error(action)
            checks.append({"name": name, "ok": True, "action": ""})
        except (Error, OSError, ValueError):
            checks.append({"name": name, "ok": False, "action": action})

    role = config["role"]
    required = ["ffmpeg", "ffprobe", "pactl"]
    required += ["ssh", "gpu-screen-recorder", "paplay"] if role == "capture" else ["mediamtx", config["obs"]["binary"]]
    for binary in required:
        check(f"binary.{Path(binary).name}", lambda b=binary: bool(shutil.which(b)), f"Install {Path(binary).name} in the agent PATH")
    check("pulse", lambda: bool(run(["pactl", "info"])), "Start this user's PipeWire and pipewire-pulse services")
    discovery = devices(role)
    if role == "capture":
        check("capture.selection", lambda: bool(config["capture"]["target"]) and bool(config["capture"]["game_audio"]),
              "Use devices and explicitly set capture.target and capture.game_audio=app:GAME")
        check("capture.application", lambda: config["capture"]["game_audio"][4:].casefold() in discovery["applications"].casefold()
              and bool(config["capture"]["game_audio"]), "Start the selected game and choose its exact app: audio name from devices")
        check("capture.gpu", lambda: "h264" in run(["gpu-screen-recorder", "--info"]).lower().splitlines(),
              "Check GSR --info, VA-API/NVIDIA and portal access; software fallback is disabled")
        help_text = ""
        try:
            help_text = run(["gpu-screen-recorder", "--help"], allowed_codes=(0, 1))
        except Error:
            pass
        check("capture.flags", lambda: all(f in help_text for f in ("-encoder", "-fallback-cpu-encoding", "--list-application-audio")),
              "Install GSR 5.13.8 or a compatible build with application audio and explicit GPU encoding")
        for key, collection in (("mic_source", "sources"), ("tts_sink", "sinks")):
            check("audio." + key, lambda k=key, c=collection: config["audio"][k] in {x["name"] for x in discovery[c]},
                  f"Select audio.{key} from devices; default devices are never changed")
        check("audio.raw", lambda: bool(config["audio"]["mic_source"]) and not any(x in config["audio"]["mic_source"].lower()
              for x in ("monitor", "easyeffects", "rnnoise", "splitcast_")), "Select a raw microphone source, not a monitor or processed source")
    else:
        check("ffmpeg.ladspa", lambda: "ladspa" in run(["ffmpeg", "-hide_banner", "-filters"]), "Use FFmpeg with LADSPA enabled")
        check("ffmpeg.pulse", lambda: "pulse" in run(["ffmpeg", "-hide_banner", "-devices"]), "Use FFmpeg with Pulse input and output")
        check("rnnoise.samples", lambda: run(ffmpeg("-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", ".15",
              "-af", rnnoise_filter(config), "-f", "null", "-")) is not None,
              "Set audio.rnnoise_plugin to the RNNoise LADSPA .so and check its label/controls")
        check("nvenc.frames", lambda: run(ffmpeg("-f", "lavfi", "-i", "color=s=1920x1080:r=60", "-frames:v", 2,
              "-c:v", "h264_nvenc", "-f", "null", "-")) is not None,
              "Make NVIDIA/NVENC available to this user; no software encoder fallback is allowed")
        from .config import secret
        check("obs.authentication", lambda: bool(secret(config["obs"]["password_file"])), "Provision a private OBS password file")
    camera = config["camera"]
    if camera["enabled"] and camera["location"] == role:
        check("camera.selection", lambda: any(c["device"] == camera["device"] for c in discovery["cameras"]),
              "Select a stable /dev/v4l/by-id/ path on the chosen host")
        size = f"{camera['width']}x{camera['height']}"
        check("camera.mode", lambda: camera_mode_supported(config, run(["v4l2-ctl", "--device", camera["device"], "--list-formats-ext"])),
              "Choose a camera size and frame rate listed by devices; capture never substitutes another format")
        if camera["mode"] == "hardware":
            args = []
            if camera["encoder"] == "h264_vaapi":
                args += ["-vaapi_device", camera["hw_device"]]
            args += ["-f", "lavfi", "-i", f"color=s={size}:r={camera['fps']}", "-frames:v", 2]
            if camera["encoder"] == "h264_vaapi":
                args += ["-vf", "format=nv12,hwupload"]
            args += ["-c:v", camera["encoder"], "-f", "null", "-"]
            check("camera.hardware_frames", lambda: run(ffmpeg(*args)) is not None,
                  "Make the explicitly selected camera hardware encoder available; CPU fallback is disabled")
    if config["tts"]["enabled"] and role == "production":
        check("voicevox", lambda: bool(request(config["tts"]["voicevox_url"].rstrip("/") + "/speakers")), "Start the configured loopback VOICEVOX service")
    return {"ok": all(c["ok"] for c in checks), "checks": checks, "capture_method": "GSR screen/portal capture, not an OpenGL hook"}


class Media:
    def __init__(self, config, processes: Processes):
        self.config, self.processes = config, processes
        self.reset_observations()

    def reset_observations(self):
        self.last_bytes = {}
        self.last_change = {}

    def tunnel(self):
        c, p = self.config["capture"], self.config["peer"]
        argv = ["ssh", "-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2", "-o", "ConnectTimeout=5",
                "-p", str(p["ssh_port"])]
        for local, remote in ((p["forward_control_port"], p["remote_control_port"]),
                              (c["rtmp_port"], c["rtmp_port"]), (c["rtsp_port"], c["rtsp_port"])):
            argv += ["-L", f"127.0.0.1:{local}:127.0.0.1:{remote}"]
        self.processes.spawn("ssh", [*argv, "--", p["ssh_host"]])

    def receiver(self):
        c = self.config["capture"]
        settings = {"logLevel": "warn", "rtsp": True, "rtspAddress": f"127.0.0.1:{c['rtsp_port']}",
                    "rtspTransports": ["tcp"], "rtmp": True, "rtmpAddress": f"127.0.0.1:{c['rtmp_port']}",
                    "api": True, "apiAddress": f"127.0.0.1:{c['api_port']}", "hls": False, "webrtc": False,
                    "srt": False, "metrics": False, "pprof": False, "playback": False,
                    "paths": {name: {"source": "publisher"} for name in ("game", "mic", "camera")}}
        filename = self.config.state_dir / "mediamtx.json"
        atomic_write(filename, json.dumps(settings))
        self.processes.spawn("mediamtx", ["mediamtx", str(filename)])
        wait_for(lambda: self.paths() is not None, self.config["peer"]["timeout_seconds"],
                 "MediaMTX API did not become ready; check its version and port conflicts", self.processes)

    def paths(self):
        return request(f"http://127.0.0.1:{self.config['capture']['api_port']}/v3/paths/list", timeout=2).get("items", [])

    def observed(self):
        expected = {"game", "mic"}
        if self.config["camera"]["enabled"]:
            expected.add("camera")
        items = {i["name"]: i for i in self.paths()}
        ready = all(name in items and items[name].get("ready") and items[name].get("bytesReceived", 0) > 0 for name in expected)
        if not ready:
            for name in expected:
                if name not in items or not items[name].get("ready"):
                    self.last_bytes.pop(name, None)
                    self.last_change.pop(name, None)
            return False
        game_tracks = re.sub(r"[^a-z0-9]", "", " ".join(map(str, items["game"].get("tracks", []))).lower())
        if "h264" not in game_tracks or not any(audio in game_tracks for audio in ("mpeg4audio", "aac")):
            return False
        current = {name: items[name]["bytesReceived"] for name in expected}
        now = time.monotonic()
        for name, count in current.items():
            if count != self.last_bytes.get(name):
                self.last_change[name] = now
            self.last_bytes[name] = count
        return all(now - self.last_change[name] < 6 for name in expected)

    def senders(self):
        self.processes.spawn("game", game_command(self.config))
        self.processes.spawn("mic", microphone_command(self.config))
        if self.config["camera"]["enabled"] and self.config["camera"]["location"] == "capture":
            self.processes.spawn("camera", camera_command(self.config))

    def remote_camera(self):
        if self.config["camera"]["enabled"] and self.config["camera"]["location"] == "production":
            self.processes.spawn("camera", camera_command(self.config))

    def prepare_microphone(self):
        sink = self.config["audio"]["processed_sink"]
        if sink in {i["name"] for i in json.loads(run(["pactl", "-f", "json", "list", "sinks"]))}:
            raise Error("Processed sink already exists; stop the previous owner before prepare")
        module = run(["pactl", "load-module", "module-null-sink", f"sink_name={sink}", "rate=48000", "channels=1",
                      "sink_properties=device.description=SplitCast_Processed_Mic"]).strip()
        if not module.isdigit():
            raise Error("Cannot identify owned Pulse module")
        self.processes.cleanups.append(lambda: run(["pactl", "unload-module", module]))

    def microphone_ready(self):
        return self.config["audio"]["processed_sink"] in {i["name"] for i in json.loads(run(["pactl", "-f", "json", "list", "sinks"]))}

    def process_microphone(self):
        self.processes.spawn("rnnoise", processor_command(self.config))
        wait_for(lambda: self.processes.children["rnnoise"].progress.get("out_time_us", "0").isdigit()
                 and int(self.processes.children["rnnoise"].progress.get("out_time_us", "0")) > 0,
                 self.config["peer"]["timeout_seconds"], "RNNoise produced no processed samples; check mic stream and LADSPA", self.processes)
