from __future__ import annotations

import base64
import hashlib
import json
import os
import time
import uuid
from pathlib import Path

from .config import Error, atomic_write, path, secret
from .media import rtsp
from .process import wait_for


def listeners(port):
    found = []
    for filename in ("/proc/net/tcp", "/proc/net/tcp6"):
        for row in Path(filename).read_text().splitlines()[1:]:
            fields = row.split()
            address, number = fields[1].split(":")
            if int(number, 16) == port and fields[3] == "0A":
                found.append(address)
    return found


def loopback_only(port):
    addresses = listeners(port)
    if not addresses or any(a not in ("0100007F", "00000000000000000000000001000000") for a in addresses):
        raise Error("Dedicated OBS listener is not exclusively loopback; install the patched OBS build")
    return True


class OBS:
    def __init__(self, config, connect=None):
        self.config = config
        self.connect = connect

    def __enter__(self):
        try:
            if self.connect is None:
                import websocket
                self.connect = websocket.create_connection
            self.ws = self.connect(f"ws://127.0.0.1:{self.config['obs']['websocket_port']}", timeout=5,
                                   suppress_origin=True, http_proxy_host=None, http_no_proxy=["127.0.0.1"])
            hello = self.receive()
            if hello.get("op") != 0 or "authentication" not in hello.get("d", {}):
                raise Error("Dedicated OBS must require WebSocket authentication")
            auth = hello["d"]["authentication"]
            password = secret(self.config["obs"]["password_file"])
            digest = base64.b64encode(hashlib.sha256((password + auth["salt"]).encode()).digest()).decode()
            response = base64.b64encode(hashlib.sha256((digest + auth["challenge"]).encode()).digest()).decode()
            self.ws.send(json.dumps({"op": 1, "d": {"rpcVersion": 1, "authentication": response, "eventSubscriptions": 0}}))
            if self.receive().get("op") != 2:
                raise Error("OBS identification failed; check the dedicated password")
            return self
        except Error:
            if hasattr(self, "ws"):
                self.ws.close()
            raise
        except Exception:
            if hasattr(self, "ws"):
                self.ws.close()
            raise Error("Cannot authenticate dedicated OBS; run prepare or check its password file") from None

    def __exit__(self, *args):
        self.ws.close()

    def receive(self):
        raw = self.ws.recv()
        if not isinstance(raw, str) or len(raw) > 4 * 1024 * 1024:
            raise Error("Invalid OBS response")
        try:
            return json.loads(raw)
        except ValueError:
            raise Error("Invalid OBS JSON") from None

    def call(self, name, data=None):
        request_id = uuid.uuid4().hex
        try:
            self.ws.send(json.dumps({"op": 6, "d": {"requestType": name, "requestId": request_id, "requestData": data or {}}}))
            deadline = time.monotonic() + 5
            for _ in range(128):
                if time.monotonic() > deadline:
                    break
                result = self.receive()
                if result.get("op") != 7 or result.get("d", {}).get("requestId") != request_id:
                    continue
                result = result["d"]
                if result.get("requestType") != name or not result.get("requestStatus", {}).get("result"):
                    raise Error(f"OBS rejected {name}; check the dedicated profile and installed plugins")
                return result.get("responseData", {})
        except Error:
            raise
        except Exception:
            raise Error(f"OBS {name} failed; reconnect dedicated OBS") from None
        raise Error(f"OBS {name} response timeout")

    def ensure_input(self, name, kind, settings, x=0, y=0, width=1920, height=1080):
        names = {i["inputName"] for i in self.call("GetInputList")["inputs"]}
        if name not in names:
            item = self.call("CreateInput", {"sceneName": "SplitCast", "inputName": name, "inputKind": kind,
                                            "inputSettings": settings, "sceneItemEnabled": True})["sceneItemId"]
        else:
            self.call("SetInputSettings", {"inputName": name, "inputSettings": settings, "overlay": False})
            item = self.call("GetSceneItemId", {"sceneName": "SplitCast", "sourceName": name})["sceneItemId"]
        self.call("SetSceneItemTransform", {"sceneName": "SplitCast", "sceneItemId": item,
                  "sceneItemTransform": {"positionX": x, "positionY": y, "alignment": 5,
                                         "boundsType": "OBS_BOUNDS_SCALE_INNER", "boundsAlignment": 5,
                                         "boundsWidth": width, "boundsHeight": height}})

    def configure(self):
        version = self.call("GetVersion")
        kinds = self.call("GetInputKindList")["inputKinds"]
        required = {"ffmpeg_source", "pulse_input_capture", "text_ft2_source_v2"}
        if not required <= set(kinds):
            raise Error("Dedicated OBS lacks FFmpeg, Pulse capture, or FreeType text input")
        if "SplitCast" not in {s["sceneName"] for s in self.call("GetSceneList")["scenes"]}:
            self.call("CreateScene", {"sceneName": "SplitCast"})
        desired = {"GameFeed", "MicProcessed", "Overlay"}
        if self.config["camera"]["enabled"]:
            desired.add("CameraFeed")
        if self.config["tts"]["mix_remote"]:
            desired.add("TTSMix")
        managed = {"GameFeed", "MicProcessed", "Overlay", "CameraFeed", "TTSMix"}
        for source in self.call("GetInputList")["inputs"]:
            if source["inputName"] in managed - desired:
                self.call("RemoveInput", {"inputName": source["inputName"]})
        video = {"baseWidth": 1920, "baseHeight": 1080, "outputWidth": 1920,
                 "outputHeight": 1080, "fpsNumerator": 60, "fpsDenominator": 1}
        current = self.call("GetVideoSettings")
        if any(current.get(key) != value for key, value in video.items()):
            self.call("SetVideoSettings", video)
        self.ensure_input("GameFeed", "ffmpeg_source", self.media_settings("game"))
        self.ensure_input("MicProcessed", "pulse_input_capture", {"device_id": self.config["audio"]["processed_sink"] + ".monitor"})
        if self.call("GetInputSettings", {"inputName": "MicProcessed"})["inputSettings"].get("device_id") != self.config["audio"]["processed_sink"] + ".monitor":
            raise Error("OBS microphone is not bound to the explicit processed monitor")
        self.call("SetInputAudioSyncOffset", {"inputName": "MicProcessed", "inputAudioSyncOffset": self.config["audio"]["mic_offset_ms"]})
        self.call("SetInputAudioMonitorType", {"inputName": "MicProcessed", "monitorType": "OBS_MONITORING_TYPE_NONE"})
        if self.config["camera"]["enabled"]:
            self.ensure_input("CameraFeed", "ffmpeg_source", self.media_settings("camera"), 1440, 780, 480, 270)
            filters = self.call("GetSourceFilterList", {"sourceName": "CameraFeed"})["filters"]
            delay = self.config["camera"]["offset_ms"]
            if "SplitCast sync" not in {f["filterName"] for f in filters}:
                self.call("CreateSourceFilter", {"sourceName": "CameraFeed", "filterName": "SplitCast sync", "filterKind": "async_delay_filter",
                                                 "filterSettings": {"delay_ms": delay}})
            else:
                self.call("SetSourceFilterSettings", {"sourceName": "CameraFeed", "filterName": "SplitCast sync", "filterSettings": {"delay_ms": delay}})
        self.ensure_input("Overlay", "text_ft2_source_v2", {"text": "SplitCast", "font": {"face": "Sans", "size": 36}, "color1": 0xFFFFFFFF}, 32, 32, 1600, 100)
        saved_overlay = self.config.state_dir / "overlay.txt"
        if saved_overlay.exists():
            self.call("SetInputSettings", {"inputName": "Overlay", "inputSettings": {"text": saved_overlay.read_text()[:1000]}, "overlay": True})
        if self.config["tts"]["mix_remote"]:
            self.ensure_input("TTSMix", "ffmpeg_source", {"is_local_file": True, "local_file": "", "close_when_inactive": False})
        self.call("SetCurrentProgramScene", {"sceneName": "SplitCast"})
        return version.get("obsVersion", "unknown")

    def media_settings(self, name):
        return {"is_local_file": False, "input": rtsp(self.config, name), "input_format": "rtsp",
                "ffmpeg_options": "rtsp_transport=tcp", "hw_decode": True, "buffering_mb": 1,
                "restart_on_activate": True, "close_when_inactive": False, "reconnect_delay_sec": 1}

    def observed(self, output=None):
        for name in ["GameFeed"] + (["CameraFeed"] if self.config["camera"]["enabled"] else []):
            if self.call("GetMediaInputStatus", {"inputName": name}).get("mediaState") != "OBS_MEDIA_STATE_PLAYING":
                return False
        if output:
            name = "GetRecordStatus" if output == "recording" else "GetStreamStatus"
            state = self.call(name)
            if not state.get("outputActive") or state.get("outputBytes", 0) <= 0:
                return False
        return True

    def activate(self, output):
        if output == "twitch":
            key = secret(self.config["obs"]["twitch_key_file"])
            self.call("SetStreamServiceSettings", {"streamServiceType": "rtmp_custom", "streamServiceSettings": {
                "server": "rtmps://live.twitch.tv:443/app", "key": key, "use_auth": False}})
        self.call("StartRecord" if output == "recording" else "StartStream")

    def deactivate(self):
        for status, stop in (("GetRecordStatus", "StopRecord"), ("GetStreamStatus", "StopStream")):
            if self.call(status).get("outputActive"):
                self.call(stop)
                wait_for(lambda: not self.call(status).get("outputActive"), self.config["peer"]["timeout_seconds"],
                         "OBS did not finish stopping output; inspect the recording")

    def preview(self):
        return self.call("GetSourceScreenshot", {"sourceName": "SplitCast", "imageFormat": "png", "imageWidth": 960,
                                                 "imageHeight": 540})["imageData"]


def launch(config, processes):
    if listeners(config["obs"]["websocket_port"]):
        raise Error("OBS port is already owned; choose a dedicated port without touching the existing OBS")
    root = config.state_dir / "obs-config"
    studio = root / "obs-studio"
    password = secret(config["obs"]["password_file"])
    atomic_write(studio / "plugin_config/obs-websocket/config.json", json.dumps({
        "server_enabled": True, "server_port": config["obs"]["websocket_port"], "auth_required": True,
        "server_password": password, "alerts_enabled": False, "first_load": False}))
    recording = path(config["obs"]["recording_dir"])
    recording.mkdir(parents=True, exist_ok=True)
    basic = ("[General]\nName=SplitCast\n[Video]\nBaseCX=1920\nBaseCY=1080\nOutputCX=1920\nOutputCY=1080\n"
             "FPSType=0\nFPSCommon=60\n[Output]\nMode=Advanced\n[AdvOut]\nEncoder=obs_nvenc_h264_tex\n"
             f"RecType=Standard\nRecFilePath={recording}\nRecFormat2=mkv\nRecEncoder=obs_nvenc_h264_tex\n"
             "TrackIndex=1\nRecTracks=1\nRescale=false\n[Audio]\nSampleRate=48000\nChannelSetup=Stereo\n")
    atomic_write(studio / "basic/profiles/SplitCast/basic.ini", basic)
    encoder = {"rate_control": "CBR", "bitrate": config["obs"]["bitrate_kbps"], "keyint_sec": 2,
               "preset": "p5", "tune": "ll", "multipass": "disabled", "profile": "high", "bf": 0,
               "lookahead": False, "psycho_aq": False}
    for filename in ("streamEncoder.json", "recordEncoder.json"):
        atomic_write(studio / "basic/profiles/SplitCast" / filename, json.dumps(encoder))
    atomic_write(studio / "user.ini", "[Basic]\nProfile=SplitCast\nProfileDir=SplitCast\nSceneCollection=SplitCast\nSceneCollectionFile=SplitCast\n[General]\nFirstRun=true\n")
    scenes = studio / "basic/scenes/SplitCast.json"
    # A fresh owned collection prevents OBS from replaying the previous TTS file on Prepare.
    atomic_write(scenes, json.dumps({"name": "SplitCast", "current_scene": "SplitCast", "current_program_scene": "SplitCast",
                                   "scene_order": [{"name": "SplitCast"}], "sources": [], "groups": [], "transitions": [],
                                   "quick_transitions": [], "DesktopAudioDevice1": None, "DesktopAudioDevice2": None,
                                   "AuxAudioDevice1": None, "AuxAudioDevice2": None, "AuxAudioDevice3": None, "AuxAudioDevice4": None}))
    env = dict(os.environ, XDG_CONFIG_HOME=str(root))
    processes.spawn("obs", [config["obs"]["binary"], "--multi", "--disable-shutdown-check", "--profile", "SplitCast",
                            "--collection", "SplitCast"], env)

    def ready():
        loopback_only(config["obs"]["websocket_port"])
        with OBS(config) as obs:
            return bool(obs.call("GetVersion"))

    wait_for(ready, config["peer"]["timeout_seconds"], "Dedicated OBS did not authenticate; check display, patched loopback build and password", processes)
