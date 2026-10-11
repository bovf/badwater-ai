"""Single MCP configuration owner; preserve opaque unrelated fields, remove only owned names."""
import json
import os
import sys
import tempfile
from pathlib import Path


def read(path, default):
    if not path.exists() and not path.is_symlink():
        return default
    if path.is_symlink():
        if not str(path.resolve()).startswith('/nix/store/'):
            raise ValueError('refusing non-Nix MCP/ownership symlink; preserve it and repair explicitly')
    elif not path.is_file() or path.stat().st_nlink != 1:
        raise ValueError('refusing non-regular or hardlinked MCP/ownership file')
    return json.loads(path.read_text())


def atomic(path, value, mode):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(name).unlink(missing_ok=True)


def merge(declaration, target, manifest):
    for parent in target.parents:
        if parent.is_symlink():
            raise ValueError('MCP parent directories must not be symlinks')
    current = read(target, {})
    owner = read(manifest, {'version': 1, 'servers': []})
    if not isinstance(current, dict) or not isinstance(current.get('mcpServers', {}), dict) or not isinstance(owner, dict) or type(owner.get('version')) is not int or owner.get('version') != 1 or not isinstance(owner.get('servers'), list) or not all(isinstance(n, str) for n in owner['servers']):
        raise ValueError('unsupported MCP/ownership schema; original file preserved')
    if not isinstance(declaration, dict) or not isinstance(declaration.get('mcpServers'), dict):
        raise ValueError('unsupported managed MCP declaration schema; original file preserved')
    desired = declaration['mcpServers']
    if not all(isinstance(name, str) and isinstance(entry, dict) for name, entry in desired.items()):
        raise ValueError('managed MCP servers must be named objects; original file preserved')
    legacy = declaration.get('legacyServers', {})
    if not isinstance(legacy, dict) or not all(isinstance(name, str) and isinstance(entry, dict) for name, entry in legacy.items()):
        raise ValueError('unsupported legacy managed MCP declaration schema; original file preserved')
    for entry in [*desired.values(), *legacy.values()]:
        if not isinstance(entry.get('command'), str) or not entry['command'].startswith('/') or not isinstance(entry.get('args', []), list) or not all(isinstance(arg, str) for arg in entry.get('args', [])):
            raise ValueError('managed MCP command/args schema is invalid; original file preserved')
    servers = dict(current.get('mcpServers', {}))
    owned = set(owner['servers'])
    # Adopt only an exact old managed command/args pair, retaining opacity of unrelated entries.
    for name, entry in legacy.items():
        old = servers.get(name)
        if isinstance(old, dict) and old.get('command') == entry['command'] and old.get('args', []) == entry.get('args', []):
            owned.add(name)
    if not desired and not owned and not manifest.exists():
        return
    for name in owned - desired.keys():
        servers.pop(name, None)
    normalized = {}
    for name in servers.keys() | desired.keys():
        key = name.replace('-', '_')
        if key in normalized and (name in desired or normalized[key] in desired):
            raise ValueError('managed MCP namespace conflicts after builtin normalization; original file preserved')
        normalized[key] = name
    for name, entry in desired.items():
        # Keep unrelated optional fields of a managed entry, e.g. user metadata; command/args/exposure remain declarative.
        old = servers.get(name, {})
        if name in servers and name not in owned and (not isinstance(old, dict) or old.get('command') != entry['command'] or old.get('args', []) != entry.get('args', [])):
            raise ValueError('requested managed MCP name conflicts with an unrelated server; rename or remove that declaration explicitly')
        servers[name] = {**(old if isinstance(old, dict) else {}), **entry}
    updated = {**current, 'mcpServers': servers}
    # Crash-safe ownership: retain both old/new names until the MCP replacement succeeds.
    pending = {'version': 1, 'servers': sorted(owned | desired.keys())}
    if pending != owner or not manifest.exists() or manifest.is_symlink():
        atomic(manifest, pending, 0o600)
    if updated != current or target.is_symlink() or not target.exists() or (target.stat().st_mode & 0o777) != 0o644:
        atomic(target, updated, 0o644)
    next_owner = {'version': 1, 'servers': sorted(desired)}
    if next_owner != pending:
        atomic(manifest, next_owner, 0o600)


if __name__ == '__main__':
    try:
        merge(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]), Path(sys.argv[3]))
    except (ValueError, OSError) as exc:
        # Never print MCP config/server/environment values, which may contain user secrets.
        print('badwaterPiMcp: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
