from __future__ import annotations

import enum
import copy
import json
import os
import re
import stat
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit


class Error(Exception):
    """A safe, actionable message suitable for the control API."""


class Lifecycle(str, enum.Enum):
    IDLE = "idle"
    PREPARING = "preparing"
    READY = "ready"
    RUNNING = "running"
    DEGRADED = "degraded"
    FAILED = "failed"
    STOPPING = "stopping"


ROUTES = {
    "game": ("game.av", ["capture.gpu", "transport.rtmp"], ["local.headphones", "obs.game"]),
    "mic": ("mic.raw", ["transport.rtsp", "remote.rnnoise"], ["obs.mic"]),
    "camera": ("camera.selected", ["camera.hardware", "transport.rtsp"], ["obs.camera"]),
    "tts": ("chat.text", ["remote.voicevox", "transport.http"], ["local.tts"]),
    "overlay": ("overlay.text", ["obs.text"], ["obs.overlay"]),
}


def obj(properties):
    return {"type": "object", "properties": properties, "required": list(properties), "additionalProperties": False}


def string(maximum=4096, pattern=None):
    out = {"type": "string", "maxLength": maximum}
    if pattern:
        out["pattern"] = pattern
    return out


def integer(low, high):
    return {"type": "integer", "minimum": low, "maximum": high}


def choice(*values):
    return {"enum": list(values)}


PORT = integer(1024, 65535)
BOOL = {"type": "boolean"}
NAME = string(256, r"^[A-Za-z0-9_.:-]*$")
SCHEMA = obj({
    "version": {"const": 1, "type": "integer"}, "role": choice("capture", "production"),
    "peer": obj({"ssh_host": string(253, r"^[A-Za-z0-9][A-Za-z0-9_.@-]*$"), "ssh_port": integer(1, 65535),
                 "control_port": PORT, "remote_control_port": PORT, "forward_control_port": PORT,
                 "token_file": string(), "remote_token_file": string(), "state_dir": string(),
                 "retry_limit": integer(0, 5), "timeout_seconds": integer(1, 60)}),
    "capture": obj({"target": string(256), "game_audio": string(256), "width": integer(320, 3840),
                    "height": integer(240, 2160), "fps": choice(30, 60), "bitrate_kbps": integer(1000, 50000),
                    "rtmp_port": PORT, "rtsp_port": PORT, "api_port": PORT}),
    "audio": obj({"mic_source": NAME, "tts_sink": NAME, "processed_sink": string(64, r"^splitcast_[A-Za-z0-9_]+$"),
                  "rnnoise_plugin": string(), "rnnoise_label": string(128, r"^[A-Za-z0-9_]+$"),
                  "rnnoise_control": string(64, r"^[0-9.|-]+$"), "gain_db": integer(-30, 20),
                  "mic_offset_ms": integer(-2000, 2000)}),
    "camera": obj({"enabled": BOOL, "location": choice("capture", "production"), "device": string(),
                   "mode": choice("h264", "hardware"), "encoder": choice("h264_vaapi", "h264_nvenc"),
                   "hw_device": string(), "width": integer(160, 3840), "height": integer(120, 2160),
                   "fps": integer(1, 60), "offset_ms": integer(0, 2000)}),
    "obs": obj({"binary": string(), "websocket_port": PORT, "password_file": string(),
                "recording_dir": string(), "twitch_key_file": string(), "bitrate_kbps": integer(1000, 10000)}),
    "tts": obj({"enabled": BOOL, "voicevox_url": string(), "speaker": integer(0, 10000),
                "queue_limit": integer(1, 32), "expiry_seconds": integer(5, 300), "max_text": integer(1, 500),
                "mix_remote": BOOL, "eventsub": BOOL, "credentials_file": string()}),
    "routes": {"type": "array", "minItems": 5, "maxItems": 5, "items": obj({
        "id": choice(*ROUTES), "source": choice(*(v[0] for v in ROUTES.values())),
        "processors": {"type": "array", "minItems": 1, "maxItems": 2, "items": string(64)},
        "targets": {"type": "array", "minItems": 1, "maxItems": 2, "items": string(64)}, "enabled": BOOL})},
})
SCHEMA.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "title": "SplitCast version 1"})


def validate(value, schema=SCHEMA, path="config"):
    kind = schema.get("type")
    types = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool}
    if kind and type(value) is not types[kind]:
        raise Error(f"{path}: expected {kind}")
    if "const" in schema and value != schema["const"] or "enum" in schema and value not in schema["enum"]:
        raise Error(f"{path}: unsupported value")
    if kind == "object":
        if set(value) != set(schema["properties"]):
            raise Error(f"{path}: missing or unknown fields")
        for key, item in value.items():
            validate(item, schema["properties"][key], f"{path}.{key}")
    elif kind == "array":
        if not schema.get("minItems", 0) <= len(value) <= schema.get("maxItems", 100):
            raise Error(f"{path}: invalid length")
        for item in value:
            validate(item, schema["items"], path + "[]")
    elif kind == "string":
        if len(value) > schema.get("maxLength", 4096) or "\x00" in value or "\n" in value or "\r" in value:
            raise Error(f"{path}: invalid string")
        if "pattern" in schema and not re.fullmatch(schema["pattern"], value):
            raise Error(f"{path}: invalid identifier")
    elif kind == "integer" and "minimum" in schema and not schema["minimum"] <= value <= schema["maximum"]:
        raise Error(f"{path}: out of range")


def path(value):
    return Path(os.path.expandvars(value)).expanduser()


def atomic_write(destination, content, mode=0o600):
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = destination.with_name(destination.name + ".tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "wb") as stream:
        os.fchmod(stream.fileno(), mode)
        stream.write(content.encode() if isinstance(content, str) else content)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(destination)


def secret(filename):
    p = path(filename)
    try:
        with p.open("r", encoding="utf-8") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077 or info.st_uid != os.getuid():
                raise Error("Credential file must be owned by this user with mode 0600")
            value = stream.read(65537).strip()
    except OSError:
        raise Error("Credential file unavailable; provision the configured credential path") from None
    if not value or len(value) > 65536:
        raise Error("Credential file is empty or oversized")
    return value


@dataclass(frozen=True)
class Route:
    id: str
    source: str
    processors: tuple[str, ...]
    targets: tuple[str, ...]
    enabled: bool


@dataclass(frozen=True)
class Config:
    data: dict
    routes: tuple[Route, ...]

    @classmethod
    def parse(cls, data):
        data = copy.deepcopy(data)
        validate(data)
        if {r["id"] for r in data["routes"]} != set(ROUTES):
            raise Error("routes: each supported route must occur exactly once")
        routes = []
        for route in data["routes"]:
            source, processors, targets = ROUTES[route["id"]]
            allowed_targets = targets + (["obs.tts"] if route["id"] == "tts" and data["tts"]["mix_remote"] else [])
            if (route["source"], route["processors"], route["targets"]) != (source, processors, allowed_targets):
                raise Error("routes: unsupported connection; use the documented finite routes")
            routes.append(Route(route["id"], source, tuple(processors), tuple(allowed_targets), route["enabled"]))
        enabled = {r.id: r.enabled for r in routes}
        if not enabled["game"] or not enabled["mic"] or not enabled["overlay"]:
            raise Error("game, mic and overlay routes are required")
        if enabled["camera"] != data["camera"]["enabled"]:
            raise Error("camera.enabled and camera route must agree")
        if data["tts"]["enabled"] and not enabled["tts"]:
            raise Error("TTS requires the tts route")
        url = urlsplit(data["tts"]["voicevox_url"])
        if url.scheme != "http" or url.hostname != "127.0.0.1" or url.username or url.password or url.path not in ("", "/") or url.query or url.fragment:
            raise Error("voicevox_url must be an HTTP loopback origin")
        ports = [data["peer"]["control_port"], data["peer"]["forward_control_port"], data["obs"]["websocket_port"]]
        ports += [data["capture"][key] for key in ("rtmp_port", "rtsp_port", "api_port")]
        if len(set(ports)) != len(ports):
            raise Error("Local listener ports must be distinct")
        if data["capture"]["game_audio"] and not re.fullmatch(r"app:[^|;\r\n]+", data["capture"]["game_audio"]):
            raise Error("game_audio must use GSR app: capture, never a sink monitor")
        if data["capture"]["game_audio"].casefold() == "app:splitcast-tts":
            raise Error("Game capture must exclude the SplitCast-TTS application")
        if data["camera"]["enabled"] and not data["camera"]["device"].startswith("/dev/v4l/by-id/"):
            raise Error("Choose a stable camera /dev/v4l/by-id/ path from devices")
        return cls(data, tuple(routes))

    @classmethod
    def load(cls, filename):
        try:
            p = path(filename)
            if p.stat().st_size > 65536:
                raise Error("Config exceeds 64 KiB")
            return cls.parse(json.loads(p.read_text()))
        except (OSError, ValueError):
            raise Error("Cannot read configuration JSON") from None

    def __getitem__(self, key):
        return self.data[key]

    @property
    def state_dir(self):
        return path(self["peer"]["state_dir"]) / self["role"]

    def enabled(self, route):
        return next(r.enabled for r in self.routes if r.id == route)
