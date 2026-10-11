import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('merge', Path(__file__).parents[1] / 'modules/home-manager/pi-mcp-merge.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class MCPMerge(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.target = self.root / 'agent/mcp.json'; self.owner = self.root / 'agent/badwater-mcp-owned.json'
        self.entry = {'command': '/nix/store/fixture/bin/server', 'args': ['mcp'], 'exposure': 'codemode'}
    def apply(self, servers, legacy=None): m.merge({'mcpServers': servers, 'legacyServers': legacy or {}}, self.target, self.owner)
    def contents(self): return json.loads(self.target.read_text())
    def test_disabled_without_state_creates_nothing(self):
        self.apply({}); self.assertFalse(self.target.parent.exists())
    def test_only_new_servers_preserve_unrelated_opaque_fields(self):
        original = {'mcpServers': {'user': {'command': '/user/server', 'env': {'opaque': 'synthetic-only'}}}, 'extensionMetadata': {'keep': [1, False, 'é']}}
        self.target.parent.mkdir(); self.target.write_text(json.dumps(original)); auth = self.target.parent / 'auth.json'; auth.write_bytes(b'synthetic do not inspect'); before = auth.read_bytes()
        self.apply({'badwater-video': self.entry}); out = self.contents(); self.assertEqual(out['mcpServers']['user'], original['mcpServers']['user']); self.assertEqual(out['extensionMetadata'], original['extensionMetadata']); self.assertEqual(auth.read_bytes(), before); self.assertEqual(self.target.stat().st_mode & 0o777, 0o644); self.assertFalse(self.target.is_symlink())
        self.apply({}); self.assertEqual(self.contents(), original); self.assertEqual(auth.read_bytes(), before)
    def test_owned_replacement_keeps_optional_fields(self):
        self.apply({'new': self.entry}); d=self.contents(); d['mcpServers']['new']['localMetadata']={'keep':True}; self.target.write_text(json.dumps(d)); changed={**self.entry,'args':['new-arg']}; self.apply({'new':changed}); self.assertEqual(self.contents()['mcpServers']['new']['localMetadata'], {'keep':True}); self.assertEqual(self.contents()['mcpServers']['new']['args'], ['new-arg'])
    def test_conflicting_unmanaged_name_is_not_overwritten(self):
        self.target.parent.mkdir(); self.target.write_text(json.dumps({'mcpServers':{'new':{'command':'/different'}}})); before=self.target.read_bytes()
        with self.assertRaisesRegex(ValueError,'conflicts'): self.apply({'new':self.entry})
        self.assertEqual(self.target.read_bytes(),before); self.assertFalse(self.owner.exists())
    def test_exact_legacy_owned_pair_adoption_and_disable(self):
        old={'command':'/nix/store/old/server','args':[]}; self.target.parent.mkdir(); self.target.write_text(json.dumps({'mcpServers':{'graphify':old,'other':{'command':'/user'}}})); self.apply({}, {'graphify':old}); self.assertEqual(self.contents()['mcpServers'],{'other':{'command':'/user'}})
    def test_unmatched_legacy_is_not_removed(self):
        self.target.parent.mkdir(); original={'mcpServers':{'graphify':{'command':'/user/custom'}}}; self.target.write_text(json.dumps(original)); self.apply({}, {'graphify':{'command':'/nix/store/old/server','args':[]}}); self.assertEqual(self.contents(),original)
    def test_corrupt_schema_and_hardlinks_fail_without_changes(self):
        self.target.parent.mkdir(); self.target.write_text('{broken'); before=self.target.read_bytes()
        with self.assertRaises(ValueError): self.apply({'new':self.entry})
        self.assertEqual(self.target.read_bytes(),before); self.target.write_text('{}'); os.link(self.target,self.root/'link')
        with self.assertRaisesRegex(ValueError,'hardlinked'): self.apply({'new':self.entry})
        self.assertEqual(self.target.read_text(),'{}')
    def test_non_store_symlink_never_follows_auth(self):
        self.target.parent.mkdir(); auth=self.root/'auth.json'; auth.write_text('{}'); self.target.symlink_to(auth)
        with self.assertRaisesRegex(ValueError,'symlink'): self.apply({'new':self.entry})
        self.assertEqual(auth.read_text(),'{}'); self.assertTrue(self.target.is_symlink())

    def test_wrong_top_level_schemas_fail_without_writes(self):
        for value in [[], {'mcpServers': []}]:
            self.target.parent.mkdir(exist_ok=True); self.target.write_text(json.dumps(value)); before = self.target.read_bytes()
            with self.assertRaisesRegex(ValueError, 'schema'): self.apply({'badwater-video': self.entry})
            self.assertEqual(self.target.read_bytes(), before); self.assertFalse(self.owner.exists())
        self.target.write_text('{}'); self.owner.write_text('[]')
        with self.assertRaisesRegex(ValueError, 'schema'): self.apply({'badwater-video': self.entry})
        self.assertEqual(self.owner.read_text(), '[]')
    def test_normalized_unmanaged_namespace_conflict(self):
        self.target.parent.mkdir(); original = {'mcpServers': {'badwater_video': {'command': '/user/server'}}}; self.target.write_text(json.dumps(original))
        with self.assertRaisesRegex(ValueError, 'normalization'): self.apply({'badwater-video': self.entry})
        self.assertEqual(self.contents(), original); self.assertFalse(self.owner.exists())
    def test_interrupted_transition_retains_cleanup_authority(self):
        from unittest.mock import patch
        self.apply({'old': self.entry}); real = m.atomic
        def fail_target(path, value, mode):
            if path == self.target: raise OSError('synthetic interrupted replacement')
            real(path, value, mode)
        with patch.object(m, 'atomic', fail_target):
            with self.assertRaises(OSError): self.apply({'new': self.entry})
        self.assertEqual(json.loads(self.owner.read_text())['servers'], ['new', 'old'])
        self.assertEqual(list(self.contents()['mcpServers']), ['old']); self.apply({})
        self.assertEqual(self.contents()['mcpServers'], {}); self.assertEqual(json.loads(self.owner.read_text())['servers'], [])

    def test_ownership_version_is_exact_integer_one(self):
        self.target.parent.mkdir(); self.target.write_text('{}')
        for version in [True, False, 1.0, '1', 0, 2, None]:
            self.owner.write_text(json.dumps({'version': version, 'servers': []})); before = self.owner.read_bytes()
            with self.assertRaisesRegex(ValueError, 'schema'): self.apply({'new': self.entry})
            self.assertEqual(self.target.read_text(), '{}'); self.assertEqual(self.owner.read_bytes(), before)

    def test_malformed_managed_and_legacy_declarations_preserve_files(self):
        self.target.parent.mkdir(); self.target.write_text('{}')
        declarations = [[], {'mcpServers': []}, {'mcpServers': {'new': []}}, {'mcpServers': {'new': {}}}, {'mcpServers': {'new': {**self.entry, 'args': 'mcp'}}}, {'mcpServers': {}, 'legacyServers': []}, {'mcpServers': {}, 'legacyServers': {'old': {'command': 1}}}]
        for declaration in declarations:
            with self.assertRaises(ValueError): m.merge(declaration, self.target, self.owner)
            self.assertEqual(self.target.read_text(), '{}'); self.assertFalse(self.owner.exists())

    def test_directory_fsync_failure_keeps_recovery_authority(self):
        import stat
        from unittest.mock import patch
        self.apply({'old': self.entry}); real = m.os.fsync
        def fail_directory(fd):
            if stat.S_ISDIR(m.os.fstat(fd).st_mode): raise OSError('synthetic directory fsync failure')
            real(fd)
        with patch.object(m.os, 'fsync', fail_directory):
            with self.assertRaisesRegex(OSError, 'directory fsync'): self.apply({'new': self.entry})
        self.assertEqual(json.loads(self.owner.read_text())['servers'], ['new', 'old']); self.assertEqual(list(self.contents()['mcpServers']), ['old']); self.apply({}); self.assertEqual(self.contents()['mcpServers'], {})

if __name__=='__main__':unittest.main()
