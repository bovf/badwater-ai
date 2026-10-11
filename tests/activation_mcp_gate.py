"""Execute generated sole-owner MCP activation snippets, in synthetic HOME only."""
import hashlib,json,os,re,subprocess
from pathlib import Path
D=json.loads(Path('/harness/module-contexts.json').read_text())['cases'];P=json.loads(Path('/harness/paths.json').read_text());agent=Path(os.environ['HOME'])/'.pi/agent';agent.mkdir(parents=True);target=agent/'mcp.json';owner=agent/'badwater-mcp-owned.json';unchanged={}
for name in ['auth.json','settings.json','keybindings.json']:
 path=agent/name;path.write_bytes(('synthetic opaque '+name+'\n').encode());unchanged[name]=hashlib.sha256(path.read_bytes()).hexdigest()
raw=Path('/fixture/raw');raw.mkdir();data=Path('/fixture/derived');data.mkdir();(data/'user-project.fcproj').write_bytes(b'synthetic native user data');(data/'user-cache').mkdir();(data/'user-cache/keep').write_bytes(b'cache remains');private_files={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in data.rglob('*') if p.is_file()}
original={'mcpServers':{'user-server':{'command':'/inert/server','env':{'opaque':'synthetic only'},'custom':[False,'é']}},'top':{'preserve':[1,False]}};target.write_text(json.dumps(original));
def run(case):
 r=subprocess.run([P['bash']+'/bin/bash','-e','-c',D[case]['mcp']],capture_output=True,text=True,timeout=20);assert r.returncode==0,(r.stdout,r.stderr);assert not r.stdout and not r.stderr,(r.stdout,r.stderr);assert not target.is_symlink() and target.stat().st_mode&0o777==0o644;assert owner.stat().st_mode&0o777==0o600
 assert {n:hashlib.sha256((agent/n).read_bytes()).hexdigest() for n in unchanged}==unchanged
 assert {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in data.rglob('*') if p.is_file()}==private_files
 return json.loads(target.read_text())
a=run('preserveBuiltins');assert set(a['mcpServers'])=={'user-server','graphify','web-search','badwater-video'};assert a['mcpServers']['user-server']==original['mcpServers']['user-server'] and a['top']==original['top'];assert a['mcpServers']['graphify']['command'].startswith('/nix/store/')
b=run('video');assert set(b['mcpServers'])=={'user-server','badwater-video'};c=run('onlyNew');assert set(c['mcpServers'])=={'user-server','fixture'};d=run('piOff');assert d==original;assert json.loads(owner.read_text())['servers']==[]
# Supported migration from an actual immutable generated Nix-store MCP file.
target.unlink();owner.unlink();decl=next(s for s in re.findall(r'/nix/store/[^\s\\]+',D['video']['mcp']) if s.endswith('-pi-mcp.json'));assert Path(decl).is_file();target.symlink_to(decl);migrated=run('video');assert set(migrated['mcpServers'])=={'badwater-video'};assert target.read_text()!=Path(decl).read_text() or not target.is_symlink();run('piOff');assert json.loads(target.read_text())['mcpServers']=={}
Path('/fixture/acceptance.json').write_text(json.dumps({'generatedSources':{n:D[n]['mcp'] for n in ['preserveBuiltins','video','onlyNew','piOff']},'soleOwnerTransitions':True,'graphifyWebSearchUnrelatedEntriesPreserved':True,'disableRemovesOwnedOnly':True,'piOffCleanup':True,'immutableNixStoreSymlinkMigratedToWritable0644':True,'opaqueAuthSettingsKeybindingsUntouched':True,'mediaProjectsCacheUntouched':True,'scope':'Generated MCP owner snippets only, not full activation/live deployment'},indent=2));print('PASS generated sole MCP owner enable/disable/Pi-off transitions and store-symlink migration; synthetic auth/settings/keybindings/data preserved')
