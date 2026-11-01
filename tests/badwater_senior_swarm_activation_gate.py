"""Run only generated badwaterPiMcp snippets in a private filesystem/network namespace.

Arguments: native swarm matrix JSON and store bash path. HOME=/tmp/policy-home.
Uses Home Manager's real run helper, not a simulated dry-run implementation.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

assert os.environ['HOME'] == '/tmp/policy-home', 'private fixture HOME required'
cases = json.loads(Path(sys.argv[1]).read_text())
agent = Path(os.environ['HOME']) / '.pi/agent'
agent.mkdir(parents=True)
target = agent / 'mcp.json'
owner = agent / 'badwater-mcp-owned.json'
opaque = {}
for name in ['auth.json', 'settings.json', 'keybindings.json', 'models.json']:
    path = agent / name
    path.write_bytes(('synthetic-only private ' + name).encode()); path.chmod(0o600)
    opaque[path] = (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns)
auth = {'oauth': {'clientSecret': 'synthetic-only-private'}, 'auth': {'provider': 'fixture'}}
original = {'mcpServers': {'user': {'url': 'https://user.example/mcp', **auth}}, 'preferences': [False, 'é']}
target.write_text(json.dumps(original)); target.chmod(0o600)

def snapshot():
    return {p: (p.read_bytes(), p.stat().st_mode, p.stat().st_mtime_ns) for p in agent.iterdir()}

def run(name, dry=False, fail=False):
    case = cases[name]
    assert case['failed'] == [] and case['mcp'].startswith('run /nix/store/')
    assert 'writeBoundary' in case['mcpAfter']
    env = dict(os.environ); env.pop('DRY_RUN', None)
    if dry: env['DRY_RUN'] = '1'
    result = subprocess.run([sys.argv[2] + '/bin/bash', '-e', '-c', 'source "$1"; eval "$2"', 'badwater-senior-swarm-mcp-gate', case['activationLibrary'], case['mcp']], env=env, capture_output=True, text=True, timeout=20)
    assert result.returncode == (1 if fail else 0), (name, result.stdout, result.stderr)
    assert 'synthetic-only-private' not in result.stdout + result.stderr
    if not dry and not fail:
        assert not result.stdout and not result.stderr, (result.stdout, result.stderr)
        assert target.stat().st_mode & 0o777 == 0o600 and owner.stat().st_mode & 0o777 == 0o600
    for path, state in opaque.items():
        assert (path.read_bytes(), path.stat().st_mode, path.stat().st_mtime_ns) == state
    return json.loads(target.read_text())

before = snapshot(); run('combined', dry=True); assert snapshot() == before and not owner.exists()
baseline = run('baseline'); combined = run('combined')
assert combined == {**baseline, 'mcpServers': {**baseline['mcpServers'], 'context7': {'url': 'https://mcp.context7.com/mcp', 'exposure': 'codemode'}}}
d = json.loads(target.read_text()); d['mcpServers']['context7'].update({**auth, 'headers': {'Authorization': 'synthetic-only-private'}, 'metadata': {'keep': True}}); target.write_text(json.dumps(d))
before = snapshot(); run('combined'); assert snapshot() == before
run('combined', dry=True); assert snapshot() == before
assert run('baseline') == baseline
assert run('piOff') == original
assert json.loads(owner.read_text()) == {'version': 1, 'servers': []}
# An unmanaged URL mismatch fails before either file is replaced, with no opaque output.
owner.unlink(); d = {**original, 'mcpServers': {**original['mcpServers'], 'context7': {'url': 'https://other.example/mcp', **auth}}}; target.write_text(json.dumps(d))
before = snapshot(); run('combined', fail=True); assert snapshot() == before and not owner.exists()
# Actual immutable-store declaration migration keeps the established 0644 default.
target.unlink()
declaration = next(p for p in re.findall(r'/nix/store/[^\s\\]+', cases['opted']['mcp']) if p.endswith('-pi-mcp.json'))
target.symlink_to(declaration)
# run() expects existing private regular modes; this migration is checked separately.
case = cases['opted']
result = subprocess.run([sys.argv[2] + '/bin/bash', '-e', '-c', 'source "$1"; eval "$2"', 'badwater-senior-swarm-store-migration', case['activationLibrary'], case['mcp']], capture_output=True, text=True, timeout=20)
assert result.returncode == 0 and not result.stdout and not result.stderr
assert not target.is_symlink() and target.stat().st_mode & 0o777 == 0o644
assert owner.stat().st_mode & 0o777 == 0o600
assert json.loads(target.read_text())['mcpServers'] == cases['opted']['mcpServers']
print('PASS generated sole MCP owner: real HM dry-run, add/remove/Pi-off, idempotency, conflicts, opaque auth/settings/models preservation, private modes and store migration; no network calls')
