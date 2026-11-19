"""Source drift regression using a real temporary Git repository."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from wiki_scan import inspect

class ScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.invalid")
        self._git("config", "user.name", "Test")
        (self.root / "docs/memory").mkdir(parents=True)
        (self.root / "src.nix").write_text("first\n")
        (self.root / "docs/memory/topic.md").write_text("---\ntype: Reference\n---\n# Topic\n")
        self._git("add", ".")
        self._git("commit", "-qm", "initial")
        self.baseline = self._git("rev-parse", "HEAD").strip()
        self.manifest = self.root / "provenance.json"

    def _git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True,
                              text=True, check=True).stdout

    def _manifest(self, **row):
        self.manifest.write_text(json.dumps({
            "schema_version": 1, "reviewed_revision": self.baseline,
            "pages": [{"page": "docs/memory/topic.md", "sources": ["src.nix"], **row}]
        }))
        return self.manifest

    def test_same_revision_is_current(self):
        self.assertEqual(inspect(self.root, self._manifest())[0]["status"], "CURRENT")

    def test_source_change_is_review(self):
        (self.root / "src.nix").write_text("changed\n")
        self._git("add", ".")
        self._git("commit", "-qm", "change source")
        self.assertEqual(inspect(self.root, self._manifest())[0]["status"], "REVIEW")

    def test_pinned_source_blob_survives_commit_changes(self):
        (self.root / "src.nix").write_text("changed\n")
        blob = self._git("hash-object", "src.nix").strip()
        self._git("add", ".")
        self._git("commit", "-qm", "change source")
        self.assertEqual(inspect(self.root, self._manifest(source_blobs={"src.nix": blob}))[0]["status"], "CURRENT")
        (self.root / "src.nix").write_text("new drift\n")
        self.assertEqual(inspect(self.root, self.manifest)[0]["status"], "REVIEW")

    def test_unknown_blob_source_is_rejected(self):
        with self.assertRaises(ValueError):
            inspect(self.root, self._manifest(source_blobs={"nope": "0"*40}))

if __name__ == "__main__":
    unittest.main()
