import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("context", Path(__file__).parents[1] / "modules/home-manager/pi-openai-context.py")
assert spec and spec.loader
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ContextMerge(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.target = self.root / "agent/models.json"
        self.owner = self.root / "agent/badwater-openai-context-owned.json"
        self.desired = {p: {"modelOverrides": {"gpt-6.1-sol": {"contextWindow": 1050000}}} for p in m.PROVIDERS}

    def put(self, value):
        self.target.parent.mkdir(exist_ok=True)
        self.target.write_text(json.dumps(value))

    def apply(self, desired=None):
        m.merge(self.desired if desired is None else desired, self.target, self.owner)

    def contents(self):
        return json.loads(self.target.read_text())

    def test_disabled_creates_nothing(self):
        self.apply({})
        self.assertFalse(self.target.parent.exists())

    def test_new_private_writable_regular_file_and_idempotence(self):
        self.apply()
        self.assertEqual(self.contents(), {"providers": self.desired})
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.owner.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.target.parent.stat().st_mode & 0o777, 0o700)
        times = (self.target.stat().st_mtime_ns, self.owner.stat().st_mtime_ns)
        self.apply()
        self.assertEqual(times, (self.target.stat().st_mtime_ns, self.owner.stat().st_mtime_ns))

    def test_preserve_credentials_other_models_fields_and_restore(self):
        original = {"providers": {"openai": {"apiKey": "synthetic-private", "baseUrl": "https://example.invalid", "modelOverrides": {"gpt-6.1-sol": {"contextWindow": 500000, "maxTokens": 8000, "input": ["text"]}, "other": {"contextWindow": 42}}}, "unrelated": {"opaque": [1, False, "é"]}}, "metadata": {"keep": True}}
        self.put(original)
        auth = self.target.parent / "auth.json"
        auth.write_bytes(b"synthetic untouched credential fixture")
        self.apply()
        out = self.contents()
        expected = json.loads(json.dumps(original))
        expected["providers"]["openai"]["modelOverrides"]["gpt-6.1-sol"]["contextWindow"] = 1050000
        expected["providers"]["openai-codex"] = self.desired["openai-codex"]
        self.assertEqual(out, expected)
        self.assertNotIn("synthetic-private", self.owner.read_text())
        self.assertEqual(auth.read_bytes(), b"synthetic untouched credential fixture")
        self.apply({})
        self.assertEqual(self.contents(), original)
        self.assertEqual(json.loads(self.owner.read_text()), {"version": 1, "previous": {}})

    def test_catalog_change_restores_removed_model_and_keeps_first_original(self):
        self.put({"providers": {"openai": {"modelOverrides": {"gpt-6.1-sol": {"contextWindow": 500000}}}}})
        self.apply()
        changed = {"openai": {"modelOverrides": {"gpt-6.1-sol": {"contextWindow": 1000000}, "new": {"contextWindow": 123456}}}}
        self.apply(changed)
        self.assertNotIn("openai-codex", self.contents()["providers"])
        self.apply({})
        self.assertEqual(self.contents(), {"providers": {"openai": {"modelOverrides": {"gpt-6.1-sol": {"contextWindow": 500000}}}}})

    def test_unsafe_files_and_parent_symlinks_are_preserved(self):
        self.root.joinpath("private").mkdir()
        self.target.parent.symlink_to(self.root / "private")
        with self.assertRaisesRegex(ValueError, "symlinks"):
            self.apply()
        self.assertFalse(self.root.joinpath("private/models.json").exists())
        self.target.parent.unlink()
        self.put({})
        os.link(self.target, self.root / "hardlink")
        with self.assertRaisesRegex(ValueError, "hardlinked"):
            self.apply()
        self.target.unlink()
        self.target.symlink_to(self.root / "hardlink")
        with self.assertRaisesRegex(ValueError, "symlink"):
            self.apply()
        self.assertEqual((self.root / "hardlink").read_text(), "{}")

    def test_bad_schemas_values_and_ownership_fail_before_writes(self):
        for current in [[], {"providers": []}, {"providers": {"openai": []}}, {"providers": {"openai": {"modelOverrides": []}}}, {"providers": {"openai": {"modelOverrides": {"gpt-6.1-sol": []}}}}]:
            self.put(current)
            before = self.target.read_bytes()
            with self.assertRaises((ValueError, TypeError)):
                self.apply()
            self.assertEqual(self.target.read_bytes(), before)
            self.assertFalse(self.owner.exists())
        self.put({})
        for value in [True, False, 0, -1, 1.5, "1050000", 2**53, None]:
            with self.assertRaises(ValueError):
                self.apply({"openai": {"modelOverrides": {"bad": {"contextWindow": value}}}})
            self.assertEqual(self.target.read_text(), "{}")
            self.assertFalse(self.owner.exists())
        for version in [True, 1.0, "1", 2]:
            self.owner.write_text(json.dumps({"version": version, "previous": {}}))
            with self.assertRaises(ValueError):
                self.apply()
            self.assertEqual(self.target.read_text(), "{}")

    def test_interrupted_replacement_and_disable_restore_original(self):
        original = {"providers": {"openai": {"modelOverrides": {"gpt-6.1-sol": {"contextWindow": 500000}}}}}
        self.put(original)
        atomic = m.atomic
        def fail_target(path, value):
            if path == self.target:
                raise OSError("synthetic interrupted target replacement")
            atomic(path, value)
        with patch.object(m, "atomic", fail_target), self.assertRaises(OSError):
            self.apply()
        self.assertEqual(self.contents(), original)
        self.assertTrue(self.owner.exists())
        self.apply({})
        self.assertEqual(self.contents(), original)


if __name__ == "__main__":
    unittest.main()
