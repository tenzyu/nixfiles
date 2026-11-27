"""Exercise the production streaming archive validator with synthetic tar files."""
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

VALIDATOR = Path(__file__).with_name("archive-checks.py")


class ArchiveChecks(unittest.TestCase):
    def validate(self, members):
        with tempfile.TemporaryDirectory() as directory:
            stage = Path(directory) / "archive.tar.gz"
            with tarfile.open(stage, "w:gz") as archive:
                for name, kind in members:
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    if kind == tarfile.REGTYPE:
                        member.size = 1
                        archive.addfile(member, io.BytesIO(b"x"))
                    else:
                        archive.addfile(member)
            return subprocess.run([sys.executable, str(VALIDATOR), "validate", str(stage)],
                                  capture_output=True, text=True)

    def test_required_members_unique(self):
        good = [("survival", tarfile.DIRTYPE),
                ("survival/world", tarfile.DIRTYPE),
                ("survival/world/level.dat", tarfile.REGTYPE)]
        self.assertEqual(self.validate(good).returncode, 0)
        for name, kind in good:
            with self.subTest(name=name):
                result = self.validate(good + [(name, kind)])
                self.assertEqual(result.returncode, 69)
                self.assertIn("duplicate required archive member", result.stderr)
        alias = self.validate(good + [("survival/world/./level.dat", tarfile.REGTYPE)])
        self.assertEqual(alias.returncode, 69)


if __name__ == "__main__":
    unittest.main()
