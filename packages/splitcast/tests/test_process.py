import os
import subprocess
import sys
import tempfile
import time
import unittest

from splitcast.process import Processes


class ProcessesStopTests(unittest.TestCase):
    def test_restart_preserves_stdin_pipe(self):
        with tempfile.TemporaryDirectory(prefix="splitcast-restart-stdin-") as directory:
            marker = os.path.join(directory, "marker")
            code = f"import sys; sys.stdin.buffer.read(); open({marker!r}, 'a').write('eof\\n')"
            processes = Processes()
            processes.spawn("fixture", [sys.executable, "-c", code], stdin=subprocess.PIPE)
            try:
                processes.restart("fixture", 1)
                restarted = processes.children["fixture"]
                self.assertIsNotNone(restarted.process.stdin)
                restarted.process.stdin.close()
                restarted.process.wait(timeout=5)
                with open(marker) as fixture:
                    self.assertEqual(fixture.read().splitlines(), ["eof", "eof"])
            finally:
                processes.stop("fixture")

    def test_stop_delivers_stdin_eof_before_cleaning_process_group(self):
        with tempfile.TemporaryDirectory(prefix="splitcast-stop-eof-") as directory:
            marker = os.path.join(directory, "marker")
            child_code = (
                "import subprocess,sys; "
                "p=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(300)']); "
                f"open({marker!r}, 'w').write(str(p.pid)+'\\n'); "
                f"sys.stdin.buffer.read(); open({marker!r}, 'a').write('done\\n')"
            )
            processes = Processes()
            processes.spawn("fixture", [sys.executable, "-c", child_code], stdin=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 5
                while not os.path.exists(marker) and time.monotonic() < deadline:
                    if processes.children["fixture"].process.poll() is not None:
                        self.fail("fixture process exited before creating its marker")
                    time.sleep(0.05)
                self.assertTrue(os.path.exists(marker), "fixture process did not create its marker")
                processes.stop("fixture")
                with open(marker) as fixture:
                    lines = fixture.read().splitlines()
                self.assertEqual(lines[1:], ["done"], "stdin EOF was not processed before termination")
                status = f"/proc/{lines[0]}/stat"
                deadline = time.monotonic() + 2
                while os.path.exists(status) and time.monotonic() < deadline:
                    with open(status) as process_status:
                        if process_status.read().split()[2] == "Z":
                            break
                    time.sleep(0.05)
                if os.path.exists(status):
                    with open(status) as process_status:
                        self.assertEqual(process_status.read().split()[2], "Z", "process-group child survived stop")
            finally:
                processes.stop("fixture")


if __name__ == "__main__":
    unittest.main()
