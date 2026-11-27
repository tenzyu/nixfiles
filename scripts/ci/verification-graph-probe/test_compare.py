import unittest
from compare import compare, snapshot


def row(name, key="a"):
    return {"attrPath": [name], "drvPath": "/nix/store/" + key * 32 + "-check.drv"}


class GraphTests(unittest.TestCase):
    def test_same_and_changed(self):
        base = snapshot(["a", "b"], [row("a"), row("b")])
        head = snapshot(["a", "b"], [row("b", "b"), row("a")])
        self.assertEqual(compare(base, head)["a"]["status"], "same-derivation")
        self.assertEqual(compare(base, head)["b"]["status"], "changed")

    def test_added_removed(self):
        result = compare(snapshot(["a"], [row("a")]), snapshot(["b"], [row("b")]))
        self.assertEqual(result["a"]["status"], "removed")
        self.assertEqual(result["b"]["status"], "added")

    def test_missing_or_failed_is_unknown(self):
        base = snapshot(["a"], [row("a")])
        for rows in ([], [{**row("a"), "error": "failure"}], [{"attrPath": ["a"], "drvPath": "bad"}]):
            self.assertEqual(compare(base, snapshot(["a"], rows))["a"]["status"], "unknown")
            self.assertEqual(compare(snapshot(["a"], rows), base)["a"]["status"], "unknown")

    def test_duplicate_and_unexpected_fail_closed(self):
        for names, rows in ((["a", "a"], []), (["a"], [row("a"), row("a")]), (["a"], [row("b")]), (["a"], [{"attrPath": ["a", "b"]}])):
            with self.assertRaises(ValueError):
                snapshot(names, rows)

    def test_names_are_not_hardcoded(self):
        names = ["future-check", "check.with.dot"]
        result = compare(snapshot(names, [row(n) for n in names]), snapshot(names, [row(n) for n in names]))
        self.assertEqual(set(result), set(names))


if __name__ == "__main__":
    unittest.main()
