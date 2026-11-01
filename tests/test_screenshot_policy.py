"""Evaluation-only screenshot integration policy: no desktop or image access."""
import json
import sys
from pathlib import Path

for filename in sys.argv[1:]:
    cases = json.loads(Path(filename).read_text()); assert len(cases) == 10
    for name in ['missingPackage', 'missingCli', 'piOff', 'excludeCodemode', 'collision']:
        assert cases[name]['failed'], name
    for name in ['defaultOff', 'baseline', 'disabledPoison']:
        case = cases[name]; assert not case['enabled'] and not case['selected'] and not case['servers']
        assert not any('badwater-screenshot' in p for p in case['packages'])
    if 'aarch64-darwin' in filename:
        assert cases['enabled']['failed'] and cases['duplicate']['failed']
    else:
        enabled = cases['enabled']; assert enabled['failed'] == []
        assert [p['name'] for p in enabled['selected']] == ['badwater-screenshot']
        assert cases['duplicate']['selected'] == enabled['selected']
        assert any('-badwater-screenshot-cli-' in Path(p).name for p in enabled['packages'])
        assert not any(Path(p).name.endswith('-badwater-screenshot-fixture') for p in enabled['packages'])
        assert enabled['activationNames'] == cases['baseline']['activationNames'], 'new activation/config owner added'
        assert set(enabled['servers']) == {'badwater-screenshot'}
        entry = enabled['servers']['badwater-screenshot']; assert entry['command'].endswith('/bin/badwater-screenshot')
        assert entry['args'] == ['mcp'] and entry['exposure'] == 'codemode'
        assert not {'env', 'url', 'headers', 'auth', 'oauth'} & set(entry)
    print(f'PASS10 screenshot integration cases: passive package/MCP selection, platform/dependencies/single-owner: {filename}')
