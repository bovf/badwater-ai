"""Check tests/rea-module-matrix.nix JSON evaluations, without building generations.

Usage: python3 tests/test_rea_policy.py <native-matrix.json> [<other-system-matrix.json> ...]
The input set and current source/output bindings belong to the caller's evidence.
"""
import json
import sys
from pathlib import Path

for index, filename in enumerate(sys.argv[1:]):
    cases = json.loads(Path(filename).read_text())
    for name in ['defaultOff', 'disabledPoisonPackage']:
        case = cases[name]
        assert case['failed'] == [] and not case['reaEnabled']
        assert not any('rea-' in p for p in case['packages'])
        assert 'rea' not in case['mcpServers']
        assert not any('reverse-engineer-anything' in p for p in case['files'])
    if index:
        assert any('requires x86_64-linux' in m for m in cases['opted']['failed'])
        print(f'PASS default-off lazy evaluation and clear unsupported REA assertion: {filename}')
        continue
    for name in ['cliOnly', 'opted', 'preserveBaseline', 'preserveOpted', 'piOff', 'deferred']:
        assert cases[name]['failed'] == [], (name, cases[name])
    opted = cases['opted']
    assert opted['mcpServers']['rea']['args'] == ['mcp']
    assert opted['mcpServers']['rea']['command'].startswith('/nix/store/')
    assert opted['mcpServers']['rea']['command'].endswith('/bin/rea')
    assert opted['mcpServers']['rea']['exposure'] == 'codemode'
    assert opted['files']['.pi/agent/skills/reverse-engineer-anything'].endswith('/share/rea/skills/reverse-engineer-anything')
    for name in ['integrationPiOff', 'integrationReaOff', 'missingPackage', 'invalidMetadata', 'invalidArgs', 'relativeCommand', 'invalidExposure', 'normalizedNames', 'missingCodemode']:
        assert cases[name]['failed'], name
    for name in ['cliOnly', 'piOff']:
        assert cases[name]['mcpServers'] == {} and cases[name]['files'] == {}
    baseline = cases['preserveBaseline']; combined = cases['preserveOpted']
    assert combined['files'] == {**baseline['files'], '.pi/agent/skills/reverse-engineer-anything': opted['files']['.pi/agent/skills/reverse-engineer-anything']}
    assert combined['settings'] == baseline['settings']
    assert combined['keybindings'] == baseline['keybindings']
    assert combined['context'] == baseline['context']
    assert combined['activationNames'] == baseline['activationNames']
    assert 'writeBoundary' in combined['mcpAfter']
    assert 'run /nix/store/' in combined['mcp']
    assert not any('rea' in n.lower() for n in combined['activationNames'])
    print(f'PASS REA opt-in/dependencies, packaged skill/stdio, fail-closed inputs and single-owner preservation: {filename}')
assert len(sys.argv) > 1, 'pass evaluated module matrix JSON files'
