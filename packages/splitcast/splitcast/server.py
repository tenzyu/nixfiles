from __future__ import annotations

import hmac
import json
import re
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .config import Error, atomic_write, path, secret


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 8

    def __init__(self, agent, port=None):
        self.agent = agent
        self.slots = threading.BoundedSemaphore(8)
        token_file = path(agent.config["peer"]["token_file"])
        if not token_file.exists():
            atomic_write(token_file, secrets.token_urlsafe(32) + "\n")
        self.token = secret(str(token_file))
        if len(self.token) < 32 or "\n" in self.token or "\r" in self.token:
            raise Error("Control token must be a single line of at least 32 characters")
        super().__init__(("127.0.0.1", agent.config["peer"]["control_port"] if port is None else port), Handler)

    def process_request(self, request, address):
        request.settimeout(5)
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "SplitCast"
    sys_version = ""

    def log_message(self, *args):
        pass

    def respond(self, code, value, content_type="application/json"):
        body = json.dumps(value, ensure_ascii=False).encode() if content_type == "application/json" else value
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        self.end_headers()
        self.wfile.write(body)

    def boundary(self, auth=True):
        port = self.server.server_address[1]
        hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        host = self.headers.get("Host", "")
        if len(self.headers.get_all("Host", [])) != 1 or host not in hosts:
            self.respond(403, {"error": "Use the loopback control address"})
            return False
        origin = self.headers.get("Origin")
        if origin is not None and origin != "http://" + host:
            self.respond(403, {"error": "Cross-origin requests are forbidden"})
            return False
        if auth:
            token = self.headers.get("Authorization", "")
            if origin != "http://" + host or not hmac.compare_digest(token, "Bearer " + self.server.token):
                self.respond(403, {"error": "Same-origin bearer token required"})
                return False
        return True

    def do_GET(self):
        if not self.boundary(auth=False):
            return
        assets = {"/": ("index.html", "text/html; charset=utf-8"), "/ui.js": ("ui.js", "text/javascript; charset=utf-8"),
                  "/style.css": ("style.css", "text/css; charset=utf-8")}
        if self.path in assets:
            name, mime = assets[self.path]
            self.respond(200, (Path(__file__).parent / "web" / name).read_bytes(), mime)
            return
        if not self.boundary():
            return
        try:
            if self.path == "/api/status":
                self.respond(200, self.server.agent.command("status"))
            elif re.fullmatch(r"/api/audio/[A-Za-z0-9_-]{1,128}", self.path):
                with self.server.agent.lock:
                    speech = self.server.agent.backend.speech
                    if speech is None:
                        raise Error("No production speech queue")
                    self.respond(200, speech.audio(self.path.rsplit("/", 1)[1]), "audio/wav")
            else:
                self.respond(404, {"error": "Unknown endpoint"})
        except Error as exc:
            self.respond(409, {"error": str(exc)})

    def do_POST(self):
        if not self.boundary():
            return
        if self.path != "/api/command":
            self.respond(404, {"error": "Unknown endpoint"})
            return
        try:
            if self.headers.get_content_type() != "application/json" or self.headers.get("Transfer-Encoding"):
                raise Error("Use finite application/json requests")
            lengths = self.headers.get_all("Content-Length", [])
            if len(lengths) != 1 or not lengths[0].isdigit() or not 0 < int(lengths[0]) <= 16384:
                raise Error("JSON body must be at most 16 KiB")
            size = int(lengths[0])
            chunks = []
            remaining = size
            deadline = time.monotonic() + 5
            while remaining:
                timeout = deadline - time.monotonic()
                if timeout <= 0:
                    raise TimeoutError
                self.connection.settimeout(timeout)
                part = self.rfile.read1(remaining)
                if not part:
                    break
                chunks.append(part)
                remaining -= len(part)
            raw = b"".join(chunks)
            if len(raw) != size:
                raise Error("Incomplete JSON body")
            body = json.loads(raw)
            if not isinstance(body, dict) or set(body) != {"command", "args"} or not isinstance(body["command"], str) or not isinstance(body["args"], dict):
                raise Error("Expected command and args object")
            result = self.server.agent.command(body["command"], body["args"])
            self.respond(200, result)
        except (ValueError, RecursionError, UnicodeError):
            self.respond(400, {"error": "Invalid JSON body"})
        except (TimeoutError, socket.timeout):
            self.respond(408, {"error": "Request body timed out"})
        except Error as exc:
            self.respond(409, {"error": str(exc)})
        except Exception:
            self.respond(500, {"error": "Control command failed; inspect status and doctor"})
