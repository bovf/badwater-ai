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
# Execute real directory snippets with Home Manager's actual dry-run-aware run helper.
def initialize_directories(case,dry=False):
 declaration=D[case]['videoDirectories'];assert Path(declaration['activationLibrary']).is_file();environment=dict(os.environ)
 if dry:environment['DRY_RUN']='1'
 else:environment.pop('DRY_RUN',None)
 r=subprocess.run([P['bash']+'/bin/bash','-e','-c','source "$1"; eval "$2"','directory-gate',declaration['activationLibrary'],declaration['script'] or ':'],env=environment,capture_output=True,text=True,timeout=20);assert r.returncode==0 and not r.stderr,(r.stdout,r.stderr)
 return declaration
old_project=Path('/fixture/home/.local/share/badwater/video/old-project/keep');old_project.parent.mkdir(parents=True);old_project.write_bytes(b'pre-change project remains here');old_stat=old_project.stat()
v=initialize_directories('video',dry=True);roots=[Path(p) for p in v['readRoots']+[v['writeRoot']]];assert all(not p.exists() for p in roots)
initialize_directories('disabled');assert all(not p.exists() for p in roots)
initialize_directories('video');assert all(p.is_dir() and p.stat().st_mode&0o777==0o700 for p in roots);markers=[]
for p in roots:
 marker=p/'keep';marker.write_bytes(b'original project/raw/cache data');markers.append((marker,marker.read_bytes(),marker.stat().st_mtime_ns,marker.stat().st_mode))
roots[0].chmod(0o750);root_modes=[p.stat().st_mode for p in roots]
initialize_directories('video');initialize_directories('workflowMcpOff');initialize_directories('piOff')
assert [p.stat().st_mode for p in roots]==root_modes and old_project.read_bytes()==b'pre-change project remains here' and old_project.stat().st_mtime_ns==old_stat.st_mtime_ns
assert all(marker.read_bytes()==body and marker.stat().st_mtime_ns==mtime and marker.stat().st_mode==mode for marker,body,mtime,mode in markers)
v=initialize_directories('videoCustomDirectories');assert all(Path(p).is_dir() for p in v['readRoots']+[v['writeRoot']]);assert not Path('/fixture/INJECTED').exists() and not Path('/fixture/home/INJECTED').exists()
# Supported migration from an actual immutable generated Nix-store MCP file.
target.unlink();owner.unlink();decl=next(s for s in re.findall(r'/nix/store/[^\s\\]+',D['video']['mcp']) if s.endswith('-pi-mcp.json'));assert Path(decl).is_file();target.symlink_to(decl);migrated=run('video');assert set(migrated['mcpServers'])=={'badwater-video'};assert target.read_text()!=Path(decl).read_text() or not target.is_symlink();run('piOff');assert json.loads(target.read_text())['mcpServers']=={}
Path('/fixture/acceptance.json').write_text(json.dumps({'generatedSources':{n:D[n]['mcp'] for n in ['preserveBuiltins','video','onlyNew','piOff']},'soleOwnerTransitions':True,'graphifyWebSearchUnrelatedEntriesPreserved':True,'disableRemovesOwnedOnly':True,'piOffCleanup':True,'immutableNixStoreSymlinkMigratedToWritable0644':True,'opaqueAuthSettingsKeybindingsUntouched':True,'mediaProjectsCacheUntouched':True,'videoDirectoryDefaultsCreated':True,'videoDirectoriesHonorDryRunAndDisable':True,'videoDirectoriesIdempotentAndMcpIndependent':True,'customVideoDirectoriesShellEscaped':True,'scope':'Generated MCP/directory snippets only, not full activation/live deployment'},indent=2));print('PASS generated sole MCP owner enable/disable/Pi-off transitions and store-symlink migration; synthetic auth/settings/keybindings/data preserved')
