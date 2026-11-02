import os
import secrets
import shlex
import shutil
import socket
import subprocess
import time
import unittest
from unittest.mock import patch

from splitcast.agent import Agent
from splitcast.config import Config, Error, Lifecycle, atomic_write
from test_splitcast import Fixture


REMOTE = r'''
import json, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
token = sys.stdin.readline().strip()
owner = None
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        global owner
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        current = request['args']['_owner']
        if self.headers.get('Authorization') != 'Bearer ' + token or (owner and owner != current):
            self.send_error(403)
            return
        owner = current
        body = json.dumps({'state': 'ready', 'output': None, 'owner': owner}).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
threading.Thread(target=lambda: (sys.stdin.read(), server.shutdown()), daemon=True).start()
server.serve_forever()
server.server_close()
'''


@unittest.skipUnless(os.getenv("SPLITCAST_TEST_SSH_HOST") and os.getenv("SPLITCAST_TEST_SSH_IDENTITY")
                     and os.getenv("SPLITCAST_TEST_REMOTE_PYTHON"), "Requires explicitly configured two-host SSH test")
class TwoHostSSHTests(Fixture):
    def test_real_ssh_tunnel_reconnects_and_renews_same_owner(self):
        host = os.environ["SPLITCAST_TEST_SSH_HOST"]
        identity = os.environ["SPLITCAST_TEST_SSH_IDENTITY"]
        ssh = shutil.which("ssh")
        remote_python = os.environ["SPLITCAST_TEST_REMOTE_PYTHON"]
        token = secrets.token_urlsafe(32)
        server = subprocess.Popen([ssh, "-i", identity, "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", host,
                                   shlex.quote(remote_python) + " -u -c " + shlex.quote(REMOTE)],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.addCleanup(self.stop_server, server)
        server.stdin.write(token + "\n")
        server.stdin.flush()
        remote_port = int(server.stdout.readline())
        ports = []
        sockets = []
        try:
            for _ in range(3):
                sock = socket.socket()
                sock.bind(("127.0.0.1", 0))
                sockets.append(sock)
                ports.append(sock.getsockname()[1])
        finally:
            for sock in sockets:
                sock.close()
        wrapper = self.directory / "ssh"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(ssh) + " -i " + shlex.quote(identity) +
                           ' -o IdentitiesOnly=yes "$@"\n')
        wrapper.chmod(0o700)
        self.data["peer"].update(ssh_host=host, remote_control_port=remote_port,
                                 forward_control_port=ports[0], retry_limit=5)
        self.data["capture"].update(rtmp_port=ports[1], rtsp_port=ports[2])
        atomic_write(self.data["peer"]["remote_token_file"], token)
        agent = Agent(Config.parse(self.data))
        self.addCleanup(agent.close)
        agent.backend.tick = lambda: None
        with patch.dict(os.environ, PATH=str(self.directory) + os.pathsep + os.environ.get("PATH", "")):
            agent.backend.media.tunnel()
            agent.backend.remote_owned = True
            agent.state = Lifecycle.READY
            deadline = time.monotonic() + 10
            while True:
                try:
                    response = agent.backend.peer("heartbeat")
                    break
                except Error:
                    if time.monotonic() >= deadline:
                        raise
                    time.sleep(0.1)
            self.assertEqual(response["owner"], agent.owner)
            old = agent.backend.processes.children["ssh"].process
            old.kill()
            old.wait()
            agent.monitor_once()
            self.assertEqual(agent.command("status")["state"], "degraded")
            deadline = time.monotonic() + 8
            while agent.command("status")["state"] == "degraded" and time.monotonic() < deadline:
                agent.monitor_once()
                time.sleep(0.6)
            self.assertEqual(agent.command("status")["state"], "ready")
            self.assertNotEqual(agent.backend.processes.children["ssh"].process.pid, old.pid)
            self.assertEqual(agent.backend.peer("heartbeat")["owner"], agent.owner)

    @staticmethod
    def stop_server(server):
        server.stdin.close()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()
            server.wait()
        server.stdout.close()
