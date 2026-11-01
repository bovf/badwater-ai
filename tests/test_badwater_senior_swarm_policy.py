"""Check evaluated swarm matrices; --resources also reads native built JSON only.

python3 tests/test_badwater_senior_swarm_policy.py [--resources] native.json arm-linux.json darwin.json
No activation, browser, OAuth or model request is performed here.
"""
import json
import re
import sys
from pathlib import Path

resources = '--resources' in sys.argv
filenames = [p for p in sys.argv[1:] if p != '--resources']
assert filenames, 'pass evaluated tests/badwater-senior-swarm-module-matrix.nix matrices'
for index, filename in enumerate(filenames):
    cases = json.loads(Path(filename).read_text())
    darwin = not cases['opted']['browserEnabled']
    invalid = {'contextOnlyPiOff', 'seniorSwarmPiOff', 'missingPackage', 'missingSubagents', 'missingBrowser', 'missingCodemode', 'normalizedNames', 'mixed', 'mixedArgs', 'mixedEnv', 'mixedType', 'plainHTTP', 'userinfo', 'query', 'fragment', 'headers', 'auth', 'oauth', 'port'}
    if darwin: invalid.add('browserOn')
    bounds = {'concurrentLow', 'concurrentHigh', 'agentsLow', 'agentsHigh', 'repairsLow', 'repairsHigh', 'conflictingPackages'}
    for name, case in cases.items():
        if name in bounds:
            assert case == {'evaluationFailed': True}, (name, case)
        elif name in invalid:
            assert case.get('failed'), (name, case)
        else:
            assert case['failed'] == [], (name, case)
    for name in ['defaultOff', 'disabledPoison', 'piOff']:
        case = cases[name]
        assert not case['seniorSwarmEnabled'] and not case['selected'] and not case['files'] and not case['mcpServers']
        assert not any('badwater-senior-swarm' in p or 'subagents' in p for p in case['packages'])
    opted = cases['opted']
    assert {p['name'] for p in opted['selected']} == {'badwater-senior-swarm', 'pi-subagents'}
    assert len(opted['selected']) == 2
    identities = lambda selected: {p['name']: p['package'] for p in selected}
    for name in ['duplicate', 'explicitSubagents']:
        assert identities(cases[name]['selected']) == identities(opted['selected']), 'identical explicit outputs must deduplicate'
        assert [p['name'] for p in cases[name]['selected']] == ['pi-subagents', 'badwater-senior-swarm'], 'consumer-first extension order must survive'
    assert opted['mcpServers'] == {'context7': {'url': 'https://mcp.context7.com/mcp', 'exposure': 'codemode'}}
    assert cases['contextOff']['mcpServers'] == {}
    assert not cases['contextOnly']['seniorSwarmEnabled'] and not cases['contextOnly']['selected']
    assert not cases['browserOff']['browserEnabled']
    assert not any('badwater-senior-swarm-browser' in p for p in cases['browserOff']['packages'])
    assert any('badwater-senior-swarm-browser' in p for p in opted['packages']) == (not darwin)
    assert len(opted['files']) == 2 and all(p.startswith('.pi/agent/nix-packages/') for p in opted['files'])
    base = cases['baseline']; combined = cases['combined']
    assert combined['context'] == base['context'] and combined['keybindings'] == base['keybindings']
    assert combined['activationNames'] == base['activationNames']
    assert not any('badwater-senior-swarm' in n.lower() or 'context7' in n.lower() for n in combined['activationNames'])
    assert 'writeBoundary' in combined['mcpAfter'] and combined['mcp'].startswith('run /nix/store/')
    assert combined['mcpServers'] == {**base['mcpServers'], **opted['mcpServers']}
    if resources and index == 0:
        def source(case, field, suffix):
            paths = re.findall(r'/nix/store/[^\s\\]+', cases[case][field])
            return json.loads(Path(next(p for p in paths if p.endswith(suffix))).read_text())
        settings = source('opted', 'settings', '-pi-settings.json')
        seniorSwarm = settings['badwaterSeniorSwarm']
        assert {k: v for k, v in seniorSwarm.items() if k != 'browserCommand'} == {'maxConcurrent': 6, 'maxAgents': 32, 'maxRepairCycles': 2, 'roleModels': {}}
        assert seniorSwarm['browserCommand'].startswith('/nix/store/') and seniorSwarm['browserCommand'].endswith('/bin/badwater-senior-swarm-browser')
        assert not {'defaultModel', 'defaultProvider'} & settings.keys()
        assert not any('subagent' in k.lower() for k in settings)
        explicit = source('explicitSettings', 'settings', '-pi-settings.json')
        assert explicit['defaultProvider'] == 'anthropic' and explicit['defaultModel'] == 'settings-parent'
        assert explicit['badwaterSeniorSwarm'] == {**seniorSwarm, 'maxAgents': 7, 'roleModels': {'badwater-senior-swarm.qa': 'qa-option', 'badwater-senior-swarm.developer': 'developer-explicit'}, 'browserCommand': '/fixture/custom-browser', 'opaque': {'keep': True}}
        assert source('browserOff', 'settings', '-pi-settings.json')['badwaterSeniorSwarm']['browserCommand'] is None
        assert source('bounds', 'settings', '-pi-settings.json')['badwaterSeniorSwarm']['maxRepairCycles'] == 0
        before = source('baseline', 'settings', '-pi-settings.json'); after = source('combined', 'settings', '-pi-settings.json')
        assert after == {**before, 'badwaterSeniorSwarm': seniorSwarm, 'packages': settings['packages']}
        declared = source('combined', 'mcp', '-pi-mcp.json')['mcpServers']
        assert set(declared) == {'graphify', 'web-search', 'rea', 'context7'}
        assert {k: v for k, v in declared.items() if k != 'context7'} == source('baseline', 'mcp', '-pi-mcp.json')['mcpServers']
        assert source('piOff', 'mcp', '-pi-mcp.json')['mcpServers'] == {}
    print(f'PASS swarm defaults/dependencies/dedup/transport/bounds/single-owner and preservation: {filename}')
