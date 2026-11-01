"""Single MCP configuration owner; preserve opaque unrelated fields, remove only owned names."""
import json
import os
import re
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


def transport_identity(entry):
    """Identity is transport plus exact endpoint, never exposure or opaque auth.

    HTTP aliases are equivalent, but distinct URLs are not: do not normalize away
    paths/ports that can select a different authorization server.
    """
    if not isinstance(entry, dict):
        return None
    if 'url' in entry:
        if entry.get('type', 'http') not in ('http', 'streamable-http') or any(k in entry for k in ('command', 'args', 'env', 'cwd')):
            return None
        return ('http', entry['url'])
    if entry.get('type', 'stdio') != 'stdio' or not isinstance(entry.get('command'), str):
        return None
    if any(k in entry for k in ('headers',)):
        return None
    return ('stdio', entry['command'], entry.get('args', []))


def validate_managed(entry):
    identity = transport_identity(entry)
    if identity is None:
        raise ValueError('managed MCP transport schema is invalid; original file preserved')
    if identity[0] == 'http':
        url = entry['url']
        parsed = re.fullmatch(r'(https?)://([A-Za-z0-9][A-Za-z0-9.-]*|\[::1\])(:([1-9][0-9]{0,4}))?(/[^\s?#@\\]*)?', url) if isinstance(url, str) else None
        if not parsed or (parsed[1] != 'https' and parsed[2] not in ('localhost', '127.0.0.1', '[::1]')) or (parsed[4] and int(parsed[4]) > 65535):
            raise ValueError('managed MCP URL must be HTTPS or fixture loopback HTTP without credentials/query/fragment; original file preserved')
    elif not entry['command'].startswith('/') or not isinstance(entry.get('args', []), list) or not all(isinstance(arg, str) for arg in entry.get('args', [])):
        raise ValueError('managed MCP command/args schema is invalid; original file preserved')
    if any(k in entry for k in ('headers', 'auth', 'oauth')):
        raise ValueError('managed MCP credentials must remain in private runtime configuration; original file preserved')
    if entry.get('exposure', 'deferred') not in ('codemode', 'deferred', 'direct', 'hidden'):
        raise ValueError('managed MCP exposure is invalid; original file preserved')


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
    if not all(isinstance(name, str) and re.fullmatch(r'[A-Za-z0-9_-]+', name) and isinstance(entry, dict) for name, entry in desired.items()):
        raise ValueError('managed MCP servers must be named objects; original file preserved')
    legacy = declaration.get('legacyServers', {})
    if not isinstance(legacy, dict) or not all(isinstance(name, str) and isinstance(entry, dict) for name, entry in legacy.items()):
        raise ValueError('unsupported legacy managed MCP declaration schema; original file preserved')
    for entry in [*desired.values(), *legacy.values()]:
        validate_managed(entry)
    servers = dict(current.get('mcpServers', {}))
    owned = set(owner['servers'])
    # Adopt only an exact transport identity, retaining opacity of unrelated entries.
    for name, entry in legacy.items():
        if transport_identity(servers.get(name)) == transport_identity(entry):
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
        old = servers.get(name, {})
        if name in servers and name not in owned and transport_identity(old) != transport_identity(entry):
            raise ValueError('requested managed MCP name conflicts with an unrelated server; rename or remove that declaration explicitly')
        previous = transport_identity(old)
        if previous and previous[0] == 'http' and 'url' in entry and previous != transport_identity(entry) and any(k in old for k in ('headers', 'auth', 'oauth')):
            raise ValueError('HTTP endpoint change with private auth requires explicit local reconciliation; original file preserved')
        # Owned transport migrations remove incompatible fields, not user auth or
        # unrelated metadata. HTTP headers must never become a stdio environment.
        kept = dict(old) if isinstance(old, dict) else {}
        incompatible = ('command', 'args', 'env', 'cwd') if 'url' in entry else ('url', 'headers', 'args')
        for key in (*incompatible, 'type'):
            kept.pop(key, None)
        servers[name] = {**kept, **entry}
    updated = {**current, 'mcpServers': servers}
    # Keep private modes on existing regular files; store-symlink migrations use the default.
    target_mode = target.stat().st_mode & 0o777 if target.exists() and not target.is_symlink() else 0o644
    owner_mode = manifest.stat().st_mode & 0o777 if manifest.exists() and not manifest.is_symlink() else 0o600
    # Crash-safe ownership: retain both old/new names until the MCP replacement succeeds.
    pending = {'version': 1, 'servers': sorted(owned | desired.keys())}
    if pending != owner or not manifest.exists() or manifest.is_symlink():
        atomic(manifest, pending, owner_mode)
    if updated != current or target.is_symlink() or not target.exists():
        atomic(target, updated, target_mode)
    next_owner = {'version': 1, 'servers': sorted(desired)}
    if next_owner != pending:
        atomic(manifest, next_owner, owner_mode)


if __name__ == '__main__':
    try:
        merge(json.loads(Path(sys.argv[1]).read_text()), Path(sys.argv[2]), Path(sys.argv[3]))
    except (ValueError, OSError) as exc:
        # Never print MCP config/server/environment values, which may contain user secrets.
        print('badwaterPiMcp: ' + str(exc), file=sys.stderr)
        raise SystemExit(1)
