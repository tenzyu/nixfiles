import tempfile
import unittest
from pathlib import Path
from check_docs import check, parse_meta

class TestDocs(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.mem = self.root / "docs/memory"
        self.mem.mkdir(parents=True)
        (self.root / "fixture.txt").write_text("ground truth")
        (self.mem / "index.md").write_text('---\nokf_version: "0.2"\n---\n# Index\n- [Claim](claim.md) — evidence\n')
        (self.mem / "claim.md").write_text(
            '---\ntype: Reference\nstatus: stable\nsources:\n'
            '  - id: fixture\n    resource: ../../fixture.txt\n---\n# Claim\n[Proof](../../fixture.txt)\n')
    def test_valid(self):
        self.assertEqual(check(self.root)[0], [])
    def test_missing_type(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text().replace("type: Reference\n", ""))
        self.assertTrue(any("missing required" in e for e in check(self.root)[0]))
    def test_invalid_yaml(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text().replace("  - id: fixture", "  - invalid syntax"))
        with self.assertRaises(ValueError):
            parse_meta(p)
    def test_broken_link(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text() + "\n[missing](none.md)\n")
        self.assertTrue(any("broken link" in e for e in check(self.root)[0]))
    def test_bad_fragment(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text() + "\n[bad](claim.md#absent)\n")
        self.assertTrue(any("broken fragment" in e for e in check(self.root)[0]))
    def test_dont_parse_fenced_examples_as_links(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text() + "\n~~~md\n[no](missing.md)\n~~~\n")
        self.assertEqual(check(self.root)[0], [])
    def test_missing_index(self):
        (self.mem / "index.md").write_text('---\nokf_version: "0.2"\n---\n# Empty\n')
        self.assertTrue(any("unindexed concept" in e for e in check(self.root)[0]))
    def test_bad_status(self):
        p = self.mem / "claim.md"
        p.write_text(p.read_text().replace("status: stable", "status: unknown"))
        self.assertTrue(any("invalid OKF status" in e for e in check(self.root)[0]))

if __name__ == "__main__":
    unittest.main()
