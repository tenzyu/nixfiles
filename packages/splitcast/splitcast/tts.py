from __future__ import annotations

import collections
import datetime
import fcntl
import io
import json
import os
import re
import stat
import threading
import time
import uuid
import wave
from dataclasses import dataclass
from urllib.parse import urlencode, urlsplit

from .config import Error, atomic_write, path, secret
from .net import Unauthorized, request

TWITCH_VALIDATE_URL = "https://id.twitch.tv/oauth2/validate"
TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token"


@dataclass
class Job:
    id: str
    text: str
    expires: float
    audio: bytes | None = None


def validate_wav(audio):
    if len(audio) > 4 * 1024 * 1024:
        raise Error("TTS audio exceeds 4 MiB")
    try:
        with wave.open(io.BytesIO(audio)) as wav:
            if wav.getcomptype() != "NONE" or wav.getnchannels() not in (1, 2) or wav.getsampwidth() != 2 or not 8000 <= wav.getframerate() <= 48000:
                raise Error("TTS WAV must be bounded PCM16 audio")
            if not 0 < wav.getnframes() <= wav.getframerate() * 30:
                raise Error("TTS WAV must be at most 30 seconds")
            if len(wav.readframes(wav.getnframes())) != wav.getnframes() * wav.getnchannels() * 2:
                raise Error("Truncated TTS audio")
    except (wave.Error, EOFError):
        raise Error("Invalid TTS WAV") from None
    return audio


def synthesize(config, text):
    root = config["voicevox_url"].rstrip("/")
    query = urlencode({"text": text, "speaker": config["speaker"]})
    audio_query = request(root + "/audio_query?" + query, method="POST")
    audio = request(root + "/synthesis?" + urlencode({"speaker": config["speaker"]}), data=audio_query,
                    raw=True, limit=4 * 1024 * 1024, timeout=15)
    return validate_wav(audio)


class SpeechQueue:
    def __init__(self, config, synthesizer=None, mixer=None):
        self.config = config
        self.synthesizer = synthesizer or (lambda text: synthesize(config, text))
        self.mixer = mixer
        self.pending = collections.deque()
        self.ready = collections.OrderedDict()
        self.seen = collections.deque(maxlen=1024)
        self.enabled = config["enabled"]
        self.muted = False
        self.error = ""
        self.lock = threading.RLock()
        self.closed = threading.Event()
        self.generation = 0
        self.synthesis_generation = 0
        self.active = None
        self.playing = None
        self.thread = threading.Thread(target=self._worker, daemon=True)
        self.thread.start()

    def enqueue(self, text, identifier=None):
        if not isinstance(text, str) or not 0 < len(text.strip()) <= self.config["max_text"] or any(ord(c) < 32 and c != "\n" for c in text):
            raise Error("Speech text is empty, oversized, or contains control characters")
        identifier = identifier or uuid.uuid4().hex
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", identifier):
            raise Error("Invalid speech ID")
        with self.lock:
            self.expire()
            if identifier in self.seen:
                return {"id": identifier, "duplicate": True}
            if not self.enabled or self.muted:
                raise Error("TTS is disabled or muted")
            if len(self.pending) + len(self.ready) + bool(self.active) + bool(self.playing) >= self.config["queue_limit"]:
                raise Error("TTS queue is full; skip speech or wait")
            self.seen.append(identifier)
            self.pending.append(Job(identifier, text.strip(), time.time() + self.config["expiry_seconds"]))
            return {"id": identifier, "duplicate": False}

    def expire(self):
        now = time.time()
        self.pending = collections.deque(j for j in self.pending if j.expires > now)
        self.ready = collections.OrderedDict((k, j) for k, j in self.ready.items() if j.expires > now)
        if self.playing and self.playing.expires <= now:
            self.playing = None

    def _worker(self):
        while not self.closed.wait(.05):
            with self.lock:
                self.expire()
                if not self.enabled or self.muted or not self.pending:
                    continue
                job = self.pending.popleft()
                generation = self.synthesis_generation
                self.active = job
            try:
                audio = validate_wav(self.synthesizer(job.text))
                with self.lock:
                    if generation == self.synthesis_generation and job.expires > time.time() and self.enabled and not self.muted:
                        job.audio = audio
                        self.ready[job.id] = job
                        self.error = ""
            except Exception:
                with self.lock:
                    self.error = "VOICEVOX synthesis failed; check its loopback service, then submit a new speech job"
            finally:
                with self.lock:
                    self.active = None

    def next(self):
        with self.lock:
            self.expire()
            if not self.enabled or self.muted or not self.ready or self.playing:
                return None
            job = next(iter(self.ready.values()))
            return {"id": job.id, "expires": job.expires}

    def audio(self, identifier):
        with self.lock:
            self.expire()
            if identifier not in self.ready or not self.enabled or self.muted:
                raise Error("Speech is unavailable or expired")
            return self.ready[identifier].audio

    def acknowledge(self, identifier):
        with self.lock:
            job = self.ready.pop(identifier, None)
            if job:
                self.playing = job
        if job and self.config["mix_remote"] and self.mixer:
            self.mixer(job)
        return {"acknowledged": identifier}

    def finished(self, identifier):
        with self.lock:
            if self.playing and self.playing.id == identifier:
                self.playing = None
        return {"finished": identifier}

    def control(self, action):
        with self.lock:
            if action in ("on", "off"):
                self.enabled = action == "on"
            elif action in ("mute", "unmute"):
                self.muted = action == "mute"
            elif action not in ("skip", "clear", "status"):
                raise Error("Use tts on, off, mute, unmute, skip, clear, or status")
            if action in ("off", "mute", "skip", "clear"):
                self.generation += 1
                if action == "skip":
                    if self.playing:
                        self.playing = None
                    elif self.ready:
                        self.ready.popitem(last=False)
                    elif self.active:
                        self.synthesis_generation += 1
                    elif self.pending:
                        self.pending.popleft()
                else:
                    self.synthesis_generation += 1
                    self.pending.clear()
                    self.ready.clear()
                    self.playing = None
            return self.status()

    def status(self):
        with self.lock:
            self.expire()
            return {"enabled": self.enabled, "muted": self.muted, "pending": len(self.pending), "ready": len(self.ready),
                    "active": bool(self.active), "playing": self.playing.id if self.playing else None, "error": self.error}

    def close(self):
        self.closed.set()
        self.control("clear")
        self.thread.join(1)


class EventSub:
    def __init__(self, config, queue):
        self.config, self.queue = config, queue
        self.closed = threading.Event()
        self.error = ""
        self.connected = False
        self.ws = None
        self.thread = None

    def start(self):
        if self.thread and self.thread.is_alive():
            return
        self.closed.clear()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def authorize(self, force_refresh=False, rejected_token=None):
        filename = path(self.config["credentials_file"])
        lockfile = filename.with_name(filename.name + ".lock")
        try:
            fd = os.open(lockfile, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            with os.fdopen(fd, "r+") as lock:
                info = os.fstat(lock.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise Error("EventSub credential lock must be private")
                try:
                    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise Error("EventSub credentials are already in use; retry later") from None
                credentials = json.loads(secret(str(filename)))
                required = {"client_id", "access_token", "broadcaster_user_id", "user_id"}
                optional = {"refresh_token", "client_secret"}
                if (not isinstance(credentials, dict) or not required <= credentials.keys() or
                    credentials.keys() - required - optional or
                    any(not isinstance(value, str) or not value for value in credentials.values())):
                    raise Error("Invalid EventSub credential fields")
                if rejected_token is not None and credentials["access_token"] != rejected_token:
                    force_refresh = False

                def validate():
                    return request(TWITCH_VALIDATE_URL, headers={"Authorization": "OAuth " + credentials["access_token"]})

                if not force_refresh:
                    try:
                        validation = validate()
                    except Unauthorized:
                        force_refresh = True
                if force_refresh:
                    if "refresh_token" not in credentials:
                        raise Error("EventSub token expired; authorize again with a refresh token")
                    form = {"grant_type": "refresh_token", "client_id": credentials["client_id"],
                            "refresh_token": credentials["refresh_token"]}
                    if "client_secret" in credentials:
                        form["client_secret"] = credentials["client_secret"]
                    rotated = request(TWITCH_TOKEN_URL, data=form, form=True)
                    if not isinstance(rotated, dict) or any(not isinstance(rotated.get(k), str) or not rotated[k]
                                                            for k in ("access_token", "refresh_token")):
                        raise Error("Invalid token refresh response; authorize again")
                    credentials.update({k: rotated[k] for k in ("access_token", "refresh_token")})
                    atomic_write(filename, json.dumps(credentials))
                    validation = validate()
                if validation.get("user_id") != credentials["user_id"] or validation.get("client_id") != credentials["client_id"] or "user:read:chat" not in validation.get("scopes", []):
                    raise Error("EventSub token does not match the configured user, client, or scope")
                return {"Client-Id": credentials["client_id"], "Authorization": "Bearer " + credentials["access_token"]}
        except (OSError, ValueError):
            raise Error("Cannot read or update private EventSub credentials") from None

    def _run(self):
        try:
            headers = self.authorize()
            credentials = json.loads(secret(self.config["credentials_file"]))
            import websocket
            url = "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30"
            subscribe = True
            attempts = 0
            while not self.closed.is_set() and attempts <= 3:
                try:
                    if attempts:
                        headers = self.authorize()
                    self.ws = websocket.create_connection(url, timeout=40)
                    self.connected = False
                    while not self.closed.is_set():
                        raw = self.ws.recv()
                        if len(raw) > 65536:
                            raise Error("EventSub message too large")
                        message = json.loads(raw)
                        kind = message.get("metadata", {}).get("message_type")
                        if kind == "session_welcome":
                            if subscribe:
                                request("https://api.twitch.tv/helix/eventsub/subscriptions", headers=headers, data={
                                    "type": "channel.chat.message", "version": "1", "condition": {
                                        "broadcaster_user_id": credentials["broadcaster_user_id"], "user_id": credentials["user_id"]},
                                    "transport": {"method": "websocket", "session_id": message["payload"]["session"]["id"]}})
                            self.connected = True
                            self.error = ""
                        elif kind == "notification":
                            self.notification(message)
                        elif kind == "session_reconnect":
                            reconnect = message["payload"]["session"]["reconnect_url"]
                            parsed = urlsplit(reconnect)
                            if parsed.scheme != "wss" or parsed.hostname != "eventsub.wss.twitch.tv" or parsed.username or parsed.password:
                                raise Error("Invalid EventSub reconnect origin")
                            url, subscribe = reconnect, False
                            break
                        elif kind == "revocation":
                            raise Error("EventSub subscription revoked")
                except Unauthorized:
                    try:
                        headers = self.authorize(force_refresh=True, rejected_token=headers["Authorization"][7:])
                    except Error:
                        self.error = "EventSub token refresh failed; renew the private credentials"
                        break
                    attempts += 1
                    url, subscribe = "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30", True
                except Exception:
                    self.error = "EventSub disconnected; check or renew the private user token, then restart TTS"
                    attempts += 1
                    if self.closed.wait(min(2 ** attempts, 8)):
                        break
                    url, subscribe = "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30", True
                finally:
                    self.connected = False
                    if self.ws:
                        self.ws.close()
            if attempts > 3:
                self.error = "EventSub retry limit reached; renew credentials and restart TTS"
        except Exception:
            self.error = "EventSub configuration or authentication failed; provision a valid user:read:chat token file"

    def notification(self, message):
        try:
            stamp = message["metadata"]["message_timestamp"]
            created = datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
            if abs(time.time() - created) > self.config["expiry_seconds"]:
                return
            event = message["payload"]["event"]
            self.queue.enqueue(event["message"]["text"], event["message_id"])
        except (KeyError, ValueError, Error):
            pass

    def close(self):
        self.closed.set()
        if self.ws:
            self.ws.close()
        if self.thread:
            self.thread.join(1)
