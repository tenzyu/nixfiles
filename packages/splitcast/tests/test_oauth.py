import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs
from unittest.mock import patch

from splitcast.config import Error, atomic_write
from splitcast.tts import EventSub
from test_splitcast import Fixture


class OAuthTests(Fixture):
    def test_refresh_rotates_private_file_and_failed_refresh_preserves_it(self):
        credentials = {"client_id": "client", "client_secret": "secret-value", "access_token": "old-access",
                       "refresh_token": "old+refresh/", "broadcaster_user_id": "broadcaster", "user_id": "user"}
        filename = self.directory / "twitch.json"
        atomic_write(filename, json.dumps(credentials))
        requests = []
        fail = [False]
        unavailable = [False]

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def respond(self, status, data):
                body = json.dumps(data).encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            def do_GET(self):
                token = self.headers.get("Authorization")
                if unavailable[0]:
                    self.respond(503, {})
                elif token == "OAuth new-access":
                    self.respond(200, {"client_id": "client", "user_id": "user", "scopes": ["user:read:chat"]})
                else:
                    self.respond(401, {})
            def do_POST(self):
                requests.append(parse_qs(self.rfile.read(int(self.headers["Content-Length"])).decode()))
                if fail[0]:
                    self.respond(401, {"message": "secret-value old+refresh/"})
                else:
                    self.respond(200, {"access_token": "new-access", "refresh_token": "new-refresh"})

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        url = f"http://127.0.0.1:{server.server_port}"
        config = dict(self.config["tts"], credentials_file=str(filename))
        eventsub = EventSub(config, None)
        with patch("splitcast.tts.TWITCH_VALIDATE_URL", url + "/validate"), patch("splitcast.tts.TWITCH_TOKEN_URL", url + "/token"):
            headers = eventsub.authorize()
            self.assertEqual(headers["Authorization"], "Bearer new-access")
            saved = json.loads(filename.read_text())
            self.assertEqual(saved["refresh_token"], "new-refresh")
            self.assertEqual(saved["access_token"], "new-access")
            self.assertEqual(os.stat(filename).st_mode & 0o777, 0o600)
            self.assertEqual(requests[0]["refresh_token"], ["old+refresh/"])
            self.assertEqual(eventsub.authorize(force_refresh=True, rejected_token="old-access")["Authorization"],
                             "Bearer new-access")
            self.assertEqual(len(requests), 1)
            fail[0] = True
            before = filename.read_bytes()
            with self.assertRaises(Error) as error:
                eventsub.authorize(force_refresh=True)
            self.assertNotIn("secret-value", str(error.exception))
            self.assertNotIn("new-refresh", str(error.exception))
            self.assertEqual(filename.read_bytes(), before)
            unavailable[0] = True
            with self.assertRaises(Error):
                eventsub.authorize()
            self.assertEqual(len(requests), 2)
            self.assertEqual(filename.read_bytes(), before)
            os.chmod(filename, 0o644)
            with self.assertRaises(Error):
                eventsub.authorize(force_refresh=True)
            self.assertEqual(len(requests), 2)
