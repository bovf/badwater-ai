import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('merge', Path(__file__).parents[1] / 'modules/home-manager/pi-mcp-merge.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class MCPFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name); self.target = self.root / 'agent/mcp.json'; self.owner = self.root / 'agent/badwater-mcp-owned.json'
        self.entry = {'command': '/nix/store/fixture/bin/server', 'args': ['mcp'], 'exposure': 'codemode'}
    def apply(self, servers, legacy=None): m.merge({'mcpServers': servers, 'legacyServers': legacy or {}}, self.target, self.owner)
    def contents(self): return json.loads(self.target.read_text())

class MCPMerge(MCPFixture):
    def test_disabled_without_state_creates_nothing(self):
        self.apply({}); self.assertFalse(self.target.parent.exists())
    def test_only_new_servers_preserve_unrelated_opaque_fields(self):
        original = {'mcpServers': {'user': {'command': '/user/server', 'env': {'opaque': 'synthetic-only'}}}, 'extensionMetadata': {'keep': [1, False, 'é']}}
        self.target.parent.mkdir(); self.target.write_text(json.dumps(original)); auth = self.target.parent / 'auth.json'; auth.write_bytes(b'synthetic do not inspect'); before = auth.read_bytes()
        self.apply({'badwater-video': self.entry}); out = self.contents(); self.assertEqual(out['mcpServers']['user'], original['mcpServers']['user']); self.assertEqual(out['extensionMetadata'], original['extensionMetadata']); self.assertEqual(auth.read_bytes(), before); self.assertEqual(self.target.stat().st_mode & 0o777, 0o644); self.assertFalse(self.target.is_symlink())
        self.apply({}); self.assertEqual(self.contents(), original); self.assertEqual(auth.read_bytes(), before)
    def test_rea_add_remove_is_idempotent_and_preserves_private_mode(self):
        self.target.parent.mkdir(); original = {'mcpServers': {'graphify': {'command': '/synthetic/graphify'}, 'user': {'env': {'secret': 'synthetic-secret-only'}}}, 'preferences': {'keep': True}}
        self.target.write_text(json.dumps(original)); self.target.chmod(0o600)
        self.apply({'rea': self.entry}); first = self.target.read_bytes(); mtime = self.target.stat().st_mtime_ns; owner_mtime = self.owner.stat().st_mtime_ns
        self.apply({'rea': self.entry}); self.assertEqual(self.target.read_bytes(), first); self.assertEqual(self.target.stat().st_mtime_ns, mtime); self.assertEqual(self.owner.stat().st_mtime_ns, owner_mtime)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600); self.assertNotIn('synthetic-secret-only', self.owner.read_text())
        self.apply({}); self.assertEqual(self.contents(), original); self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)

    def test_invalid_inputs_do_not_disclose_opaque_values(self):
        import subprocess
        self.target.parent.mkdir(); self.target.write_text(json.dumps({'mcpServers': {'rea': {'command': '/synthetic/private', 'env': {'SECRET': 'synthetic-secret-only'}}}})); before = self.target.read_bytes()
        declaration = self.root / 'declaration.json'; declaration.write_text(json.dumps({'mcpServers': {'rea': self.entry}}))
        result = subprocess.run([os.sys.executable, str(Path(m.__file__)), str(declaration), str(self.target), str(self.owner)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1); self.assertEqual(result.stdout, ''); self.assertNotIn('synthetic-secret-only', result.stderr); self.assertNotIn('/synthetic/private', result.stderr); self.assertEqual(self.target.read_bytes(), before); self.assertFalse(self.owner.exists())

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
        declarations = [[], {'mcpServers': []}, {'mcpServers': {'new': []}}, {'mcpServers': {'new': {}}}, {'mcpServers': {'new': {**self.entry, 'args': 'mcp'}}}, {'mcpServers': {'new': {**self.entry, 'args': [1]}}}, {'mcpServers': {'new': {**self.entry, 'exposure': 'unknown'}}}, {'mcpServers': {'bad.name': self.entry}}, {'mcpServers': {}, 'legacyServers': []}, {'mcpServers': {}, 'legacyServers': {'old': {'command': 1}}}]
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

class HTTPMerge(MCPFixture):
    def setUp(self):
        super().setUp()
        self.http = {'url': 'https://mcp.context7.com/mcp', 'exposure': 'codemode'}

    def test_owned_http_endpoint_change_does_not_forward_private_auth(self):
        self.apply({'context7': self.http})
        document = self.contents()
        document['mcpServers']['context7']['headers'] = {'Authorization': 'synthetic-private-only'}
        self.target.write_text(json.dumps(document)); self.target.chmod(0o600)
        before, owner = self.target.read_bytes(), self.owner.read_bytes()
        with self.assertRaisesRegex(ValueError, 'explicit local reconciliation'):
            self.apply({'context7': {**self.http, 'url': 'https://different.example/mcp'}})
        self.assertEqual(self.target.read_bytes(), before); self.assertEqual(self.owner.read_bytes(), owner)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.apply({'context7': self.http})
        self.assertEqual(self.contents()['mcpServers']['context7']['headers'], document['mcpServers']['context7']['headers'])

    def test_http_aliases_and_fixture_loopbacks(self):
        for transport in [None, 'http', 'streamable-http']:
            for url in ['https://mcp.context7.com/mcp', 'https://example.com:443/mcp', 'http://localhost:1234/mcp', 'http://127.0.0.1/mcp', 'http://[::1]:1234/mcp']:
                entry = {**self.http, 'url': url}
                if transport: entry['type'] = transport
                self.apply({'context7': entry})
                self.assertEqual(self.contents()['mcpServers']['context7'], entry)

    def test_invalid_http_schema_never_writes_or_discloses(self):
        import subprocess
        self.target.parent.mkdir(); self.target.write_text('{}')
        bad_urls = [None, 1, [], 'http://example.com/mcp', 'http://localhost.evil/mcp', 'http://127.1/mcp', 'http://2130706433/mcp', 'http://[::ffff:127.0.0.1]/mcp', 'https://synthetic-secret@example.com/mcp', 'https://example.com/mcp?token=synthetic-secret', 'https://example.com/mcp#synthetic-secret', 'https://example.com:0/mcp', 'https://example.com:65536/mcp', 'https://example.com:00080/mcp', 'https://example.com\\\\evil/mcp', 'https://example.com/\n', '//example.com/mcp', 'https:///mcp', 'file:///tmp/mcp']
        entries = [{**self.http, 'url': url} for url in bad_urls]
        entries += [{**self.http, key: value} for key, value in [('command', '/server'), ('args', []), ('env', {}), ('cwd', '/tmp'), ('headers', {'Authorization': 'synthetic-secret'}), ('auth', {}), ('oauth', {}), ('type', 'stdio'), ('type', 'sse'), ('exposure', 'unknown')]]
        entries += [{**self.entry, 'type': 'http'}, {**self.entry, 'headers': {}}]
        declaration = self.root / 'managed.json'
        for entry in entries:
            declaration.write_text(json.dumps({'mcpServers': {'context7': entry}}))
            result = subprocess.run([os.sys.executable, m.__file__, str(declaration), str(self.target), str(self.owner)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1, entry)
            self.assertEqual(result.stdout, '')
            self.assertNotIn('synthetic-secret', result.stderr)
            self.assertEqual(self.target.read_text(), '{}'); self.assertFalse(self.owner.exists())

    def test_http_same_identity_adoption_preserves_private_auth_and_modes(self):
        self.target.parent.mkdir()
        auth = {'auth': {'provider': 'fixture'}, 'oauth': {'clientSecret': 'synthetic-secret'}, 'headers': {'Authorization': 'synthetic-secret'}, 'localMetadata': [False, 'é']}
        original = {'mcpServers': {'context7': {**self.http, 'type': 'streamable-http', **auth}, 'user': {'url': 'https://user.example/mcp', **auth}}, 'preferences': {'keep': True}}
        self.target.write_text(json.dumps(original)); self.target.chmod(0o600)
        self.apply({'context7': self.http})
        out = self.contents()
        self.assertEqual(out['mcpServers']['context7'], {**self.http, **auth})
        self.assertEqual(out['mcpServers']['user'], original['mcpServers']['user'])
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.owner.stat().st_mode & 0o777, 0o600)
        self.assertNotIn('synthetic-secret', self.owner.read_text())
        before = (self.target.read_bytes(), self.target.stat().st_mtime_ns)
        self.apply({'context7': self.http}); self.assertEqual((self.target.read_bytes(), self.target.stat().st_mtime_ns), before)
        self.apply({}); self.assertEqual(self.contents()['mcpServers'], {'user': original['mcpServers']['user']})

    def test_transport_migrations_clear_only_incompatible_fields(self):
        self.apply({'context7': {**self.entry, 'type': 'stdio', 'env': {'KEEP': 'synthetic-only'}, 'cwd': '/fixture'}})
        d = self.contents(); d['mcpServers']['context7'].update({'oauth': {'clientSecret': 'synthetic-only'}, 'auth': {'provider': 'fixture'}, 'metadata': {'keep': True}}); self.target.write_text(json.dumps(d))
        self.apply({'context7': {**self.http, 'type': 'streamable-http'}})
        out = self.contents()['mcpServers']['context7']
        for key in ['command', 'args', 'env', 'cwd']: self.assertNotIn(key, out)
        self.assertEqual(out['oauth'], {'clientSecret': 'synthetic-only'})
        d = self.contents(); d['mcpServers']['context7']['headers'] = {'Authorization': 'synthetic-only'}; self.target.write_text(json.dumps(d))
        self.apply({'context7': self.entry})
        out = self.contents()['mcpServers']['context7']
        for key in ['url', 'headers', 'type']: self.assertNotIn(key, out)
        self.assertEqual(out['metadata'], {'keep': True}); self.assertEqual(out['auth'], {'provider': 'fixture'}); self.assertIn('oauth', out)
        # Re-enable HTTP: absent stdio type must not leave a stale HTTP discriminator.
        self.apply({'context7': self.http}); self.assertEqual(self.contents()['mcpServers']['context7']['url'], self.http['url'])

    def test_owned_stdio_omitted_args_restore_default_identity(self):
        self.apply({'fixture': self.entry})
        self.apply({'fixture': {'command': self.entry['command']}})
        self.assertEqual(self.contents()['mcpServers']['fixture'], {'command': self.entry['command'], 'exposure': 'codemode'})

    def test_http_conflicts_use_exact_url_and_transport_identity(self):
        for old in [{**self.http, 'url': 'https://other.example/mcp'}, {**self.http, 'url': self.http['url'] + '/'}, self.entry, {**self.http, 'command': '/mixed'}, {**self.http, 'type': 'sse'}]:
            self.target.parent.mkdir(exist_ok=True); self.target.write_text(json.dumps({'mcpServers': {'context7': old}})); before = self.target.read_bytes()
            with self.assertRaisesRegex(ValueError, 'conflicts'): self.apply({'context7': self.http})
            self.assertEqual(self.target.read_bytes(), before); self.assertFalse(self.owner.exists())

    def test_http_legacy_exact_identity_and_normalized_conflict(self):
        self.target.parent.mkdir(); self.target.write_text(json.dumps({'mcpServers': {'context7': {**self.http, 'type': 'http', 'oauth': {'keep': 'private'}}}}))
        self.apply({}, {'context7': self.http}); self.assertEqual(self.contents()['mcpServers'], {})
        self.owner.unlink(); self.target.write_text(json.dumps({'mcpServers': {'context_7': self.http}}))
        with self.assertRaisesRegex(ValueError, 'normalization'): self.apply({'context-7': self.http})
        self.assertFalse(self.owner.exists())

if __name__=='__main__':unittest.main()
