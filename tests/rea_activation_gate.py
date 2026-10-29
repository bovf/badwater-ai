"""Execute only generated badwaterPiMcp snippets inside a private fixture namespace.

Arguments: native module-matrix JSON and {bash: <store output>} tools JSON.
HOME must be /tmp/policy-home; no full activation or generation is run.
"""
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

assert os.environ['HOME'] == '/tmp/policy-home', 'private fixture HOME required'
cases = json.loads(Path(sys.argv[1]).read_text())
tools = json.loads(Path(sys.argv[2]).read_text())
agent = Path(os.environ['HOME']) / '.pi/agent'
agent.mkdir(parents=True)
target = agent / 'mcp.json'
owner = agent / 'badwater-mcp-owned.json'
opaque = {}
for name in ['auth.json', 'settings.json', 'keybindings.json', 'models.json']:
    path = agent / name
    path.write_bytes(('opaque synthetic only ' + name).encode())
    path.chmod(0o600)
    opaque[path] = (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns)
media = Path(os.environ['HOME']) / 'Videos/BadwaterAI/Projects/keep'
media.parent.mkdir(parents=True)
media.write_bytes(b'synthetic project/cache remains untouched')
opaque[media] = (media.read_bytes(), media.stat().st_mode, media.stat().st_mtime_ns)
original = {'mcpServers': {'user': {'command': '/synthetic/user/server', 'env': {'secret': 'opaque-synthetic-only'}}}, 'preferences': [False, 'é']}
target.write_text(json.dumps(original))
target.chmod(0o600)

def snapshot():
    return {str(p): (p.read_bytes(), p.stat().st_mode, p.stat().st_mtime_ns) for p in agent.iterdir() if p.is_file()}

def run(name, dry=False, fail=False):
    case = cases[name]
    assert case['failed'] == [] and 'writeBoundary' in case['mcpAfter']
    assert case['mcp'].startswith('run /nix/store/')
    env = dict(os.environ)
    env.pop('DRY_RUN', None)
    if dry:
        env['DRY_RUN'] = '1'
    result = subprocess.run([tools['bash'] + '/bin/bash', '-e', '-c', 'source "$1"; eval "$2"', 'mcp-gate', case['activationLibrary'], case['mcp']], env=env, capture_output=True, text=True, timeout=20)
    assert result.returncode == (1 if fail else 0), (name, result.stdout, result.stderr)
    assert 'opaque-synthetic-only' not in result.stdout + result.stderr
    if not dry and not fail:
        assert result.stdout == '' and result.stderr == '', (result.stdout, result.stderr)
        assert target.stat().st_mode & 0o777 == 0o600
        assert owner.stat().st_mode & 0o777 == 0o600
    for path, value in opaque.items():
        assert (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns) == value, path
    return json.loads(target.read_text())

before = snapshot()
run('preserveOpted', dry=True)
assert snapshot() == before and not owner.exists()
a = run('preserveBaseline')
assert set(a['mcpServers']) == {'user', 'graphify', 'web-search'}
b = run('preserveOpted')
assert set(b['mcpServers']) == {'user', 'graphify', 'web-search', 'rea'}
assert {k: v for k, v in b['mcpServers'].items() if k != 'rea'} == a['mcpServers']
assert b['preferences'] == original['preferences']
before = snapshot()
run('preserveOpted')
assert snapshot() == before, 'idempotent generated merge must not rewrite files'
run('preserveBaseline')
assert json.loads(target.read_text()) == a, 'REA disable removes only REA'
assert run('piOff') == original, 'disabled Pi cleans up owned servers only'
assert json.loads(owner.read_text()) == {'version': 1, 'servers': []}
# Unmanaged REA identity is never overwritten; failure cannot leak opaque state.
owner.unlink()
conflict = {**original, 'mcpServers': {**original['mcpServers'], 'rea': {'command': '/synthetic/private/rea', 'env': {'secret': 'opaque-synthetic-only'}}}}
target.write_text(json.dumps(conflict))
before = snapshot()
run('preserveOpted', fail=True)
assert snapshot() == before and not owner.exists()
print('PASS generated sole-owner dry-run/enable/disable/Pi-off/idempotency/conflict privacy; private modes and opaque preferences/auth/settings/models/media unchanged')
