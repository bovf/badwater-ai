"""Pure consumer-input GitLab module matrix assertions; no account/network access."""
import json
import sys
from pathlib import Path

READS = {
    'get_mcp_server_version', 'get_project', 'get_issue', 'get_work_item',
    'get_merge_request', 'list_merge_requests', 'get_merge_request_commits',
    'get_merge_request_diffs', 'get_merge_request_pipelines', 'get_merge_request_notes',
    'get_repository_file', 'list_repository_tree', 'get_commit', 'get_pipeline',
    'get_pipeline_jobs', 'get_job', 'list_pipelines',
}
for filename in sys.argv[1:]:
    cases = json.loads(Path(filename).read_text())
    assert len(cases) == 16
    for name in ['missingHost', 'invalidHost', 'missingPackage', 'piOff', 'excludeCodemode', 'conflictingPackage', 'namespaceCollision', 'badEnabled', 'badExposure']:
        assert cases[name].get('failed') or cases[name].get('evaluationFailed'), name
    for name in ['defaultOff', 'disabledPoison', 'baseline']:
        case = cases[name]
        assert case['failed'] == [] and not case['enabled']
        assert not case['selected'] and not case['servers']
        assert not any('badwater-gitlab' in p for p in case['packages'])
    enabled = cases['enabled']
    assert enabled['failed'] == [] and enabled['enabled']
    assert [p['name'] for p in enabled['selected']] == ['badwater-gitlab']
    assert any('-glab-' in Path(p).name for p in enabled['packages'])
    assert not any('-badwater-gitlab-' in Path(p).name for p in enabled['packages']), 'skill manifest root must not enter buildEnv'
    assert len(enabled['files']) == 1 and next(iter(enabled['files'])).endswith('/badwater-gitlab')
    assert cases['duplicate']['selected'] == enabled['selected']
    assert enabled['activationNames'] == cases['baseline']['activationNames'], 'second activation/MCP owner introduced'
    assert enabled['servers'].keys() == {'badwater-gitlab'}
    server = enabled['servers']['badwater-gitlab']
    assert server['url'] == 'https://gitlab.example.test/api/v4/mcp'
    assert server['enabled'] is False and server['exposure'] == 'hidden'
    assert server['toolExposure'] == dict.fromkeys(READS, 'codemode')
    assert not {'command', 'headers', 'auth', 'oauth', 'env'} & server.keys()
    assert cases['explicitConnect']['servers']['badwater-gitlab'] == {**server, 'enabled': True}
    kept = cases['preserved']
    assert kept['preferences'] == {'defaultModel': 'existing-model', 'defaultProvider': 'anthropic', 'extraSettings': {'compaction': {'keepRecentTokens': 9876}}}
    assert kept['servers']['existing'] == {'url': 'https://existing.example/mcp', 'exposure': 'hidden'}
    print(f'PASS16 GitLab policy cases: disabled/lazy/dependencies/host/exact reads/single-owner/model preservation: {filename}')
