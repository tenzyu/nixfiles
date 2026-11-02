import json
import os
import shutil
import subprocess
import sys
import threading
import unittest

from splitcast.agent import Agent
from splitcast.config import Config, atomic_write
from splitcast.net import request
from splitcast.process import Processes, wait_for
from splitcast.server import Server
from test_media_e2e import free_ports
from test_splitcast import Fixture, ROOT, SyntheticBackend


@unittest.skipUnless(shutil.which("geckodriver") and shutil.which("firefox"), "Requires geckodriver and Firefox for the real browser test")
class BrowserTests(Fixture):
    def test_controls_and_untrusted_result_text_in_real_firefox(self):
        agent = Agent(self.config, SyntheticBackend)
        server = Server(agent, port=0)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(agent.close)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        processes = Processes()
        self.addCleanup(processes.close)
        port = free_ports(1)[0]
        processes.spawn("webdriver", ["geckodriver", "--host", "127.0.0.1", "--port", str(port)],
                        env=dict(os.environ, MOZ_HEADLESS="1"))
        origin = f"http://127.0.0.1:{port}"
        wait_for(lambda: request(origin + "/status").get("value", {}).get("ready"), 10, "WebDriver did not start")
        value = request(origin + "/session", data={"capabilities": {"alwaysMatch": {"browserName": "firefox",
                        "moz:firefoxOptions": {"binary": shutil.which("firefox"), "args": ["-headless", "-no-remote"]}}}}, timeout=60)
        session = origin + "/session/" + value["value"]["sessionId"]
        self.addCleanup(lambda: request(session, method="DELETE", timeout=10))
        def script(source):
            return request(session + "/execute/sync", data={"script": source, "args": []})["value"]
        request(session + "/url", data={"url": f"http://127.0.0.1:{server.server_port}/"})
        wait_for(lambda: script("return !!document.getElementById('connect')"), 15, "Token entry did not load")
        self.assertFalse(script("return document.getElementById('authentication').hidden"))
        self.assertTrue(script("return document.getElementById('start').disabled"))
        self.assertIsNone(script("return sessionStorage.getItem('splitcast.token')"))
        self.data["peer"]["control_port"] = server.server_port
        filename = self.directory / "browser.json"
        atomic_write(filename, json.dumps(self.data))
        cli = subprocess.run([sys.executable, "-m", "splitcast", "ui", "--config", str(filename)],
                             env=dict(os.environ, PYTHONPATH=str(ROOT) + os.pathsep + os.environ.get("PYTHONPATH", "")),
                             capture_output=True, timeout=5)
        self.assertEqual(cli.returncode, 0, cli.stderr.decode())
        url = cli.stdout.decode().strip()
        self.assertNotIn("?", url)
        self.assertIn("/#token=", url)
        request(session + "/url", data={"url": url})
        wait_for(lambda: script("return document.getElementById('status').textContent.includes('idle')"), 15, "UI did not connect")
        self.assertEqual(script("return location.hash"), "")
        self.assertEqual(script("return location.search"), "")
        self.assertEqual(script("return sessionStorage.getItem('splitcast.token')"), server.token)
        self.assertTrue(script("return document.getElementById('authentication').hidden"))
        request(session + "/refresh", data={})
        wait_for(lambda: script("return document.getElementById('status').textContent.includes('idle')"), 15, "Session token did not survive reload")
        script("document.querySelector('[data-command=prepare]').click()")
        wait_for(lambda: script("return document.getElementById('status').textContent.includes('ready')"), 10, "Prepare did not reach UI")
        script("document.getElementById('start').click()")
        wait_for(lambda: script("return document.getElementById('status').textContent.includes('running')"), 10, "Start did not reach UI")
        self.assertEqual(agent.command("status")["output"], "recording")
        agent.backend.doctor = lambda: {"ok": False, "error": '<img id="injected" src=x onerror="window.pwned=1">'}
        script("document.querySelector('[data-command=doctor]').click()")
        wait_for(lambda: script("return document.getElementById('result').textContent.includes('injected')"), 10, "Doctor result missing")
        self.assertFalse(script("return !!document.getElementById('injected') || !!window.pwned"))
        script("document.querySelector('[data-command=stop]').click()")
        wait_for(lambda: script("return document.getElementById('status').textContent.includes('idle')"), 10, "Stop did not reach UI")
        self.assertEqual(agent.command("status")["children"], [])
        second = Server(agent, port=0)
        threading.Thread(target=second.serve_forever, daemon=True).start()
        self.addCleanup(second.server_close)
        self.addCleanup(second.shutdown)
        request(session + "/url", data={"url": f"http://127.0.0.1:{second.server_port}/"})
        wait_for(lambda: script("return !!document.getElementById('connect')"), 15, "Bare page missing")
        self.assertIsNone(script("return sessionStorage.getItem('splitcast.token')"))
        script("document.getElementById('control-token').value = 'wrong'; document.getElementById('connect').click()")
        wait_for(lambda: script("return document.getElementById('error').textContent.includes('bearer')"), 5, "Wrong token was not rejected")
        self.assertTrue(script("return document.getElementById('start').disabled"))
        request(session + "/execute/sync", data={"script": "document.getElementById('control-token').value = arguments[0]; document.getElementById('connect').click()", "args": [second.token]})
        wait_for(lambda: script("return document.getElementById('authentication').hidden"), 5, "Manual token entry failed")
        self.assertEqual(script("return document.getElementById('control-token').value"), "")


if __name__ == "__main__":
    unittest.main()
