#!/usr/bin/env python3
"""Run real bounded Nix module evaluations; fixtures supply pinned owner inputs, not fake apps."""
import argparse,json,os,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--expression',type=Path,required=True);p.add_argument('--paths',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--nix',default='nix');a=p.parse_args();out=a.output.absolute();assert str(out).startswith('/tmp/') and out.resolve()==out and not out.is_symlink();out.mkdir(mode=0o700);paths=json.loads(a.paths.read_text());env={**os.environ,'NIX_CONFIG':os.environ.get('NIX_CONFIG','')+'\nmax-jobs = 1\ncores = 3'}
negative={'conflictingBuiltin':'must not replace','conflictingPackages':'refers to different outputs','explicitTools':'Codemode MCP exposure requires','implicitExposureTools':'Codemode MCP exposure requires','missingRuntime':'Video editing requires Linux','normalizedNames':'unique after builtin','unsupportedArtMcp':'ArtCraft has no verified','videoExcludedSound':'explicit false is respected','videoPiOff':'requires badwater.ai.pi.enable'}
positive=set('disabled elsewhere individual all allExceptArt video workflowMcpOff onlyCraftMcp onlyNew piOff preserveBuiltins identicalPackages deferredExplicitTools directExplicitTools hiddenExplicitTools both'.split());apps=set('artcraft cadcraft deckcraft designcraft effectcraft filmcraft gridcraft lightcraft pdfcraft photocraft soundcraft vectorcraft wordcraft'.split());receipts=[]
def evaluate(label,argument):
 command=[a.nix,'eval','--impure','--json','--file',str(a.expression),'--apply','f: f '+argument];start=time.monotonic()
 try:r=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=900);status=r.returncode;stdout=r.stdout;stderr=r.stderr
 except subprocess.TimeoutExpired as exc:status=124;stdout=exc.stdout or b'';stderr=exc.stderr or b''
 (out/(label+'.command.json')).write_text(json.dumps(command,indent=2));(out/(label+'.stdout')).write_bytes(stdout);(out/(label+'.stderr')).write_bytes(stderr);receipts.append({'label':label,'status':status,'seconds':time.monotonic()-start});(out/'results.json').write_text(json.dumps(receipts,indent=2));return status,stdout,stderr
status,stdout,_=evaluate('x86-batch','{}');assert status==0;d=json.loads(stdout);assert set(d['cases'])==positive|negative.keys();assert len(d['cases'])==25 and set(d['individuals'])==apps and len(d['individuals'])==13
failed={n for n,v in d['cases'].items() if v.get('failed') or v.get('evaluationFailed')};assert failed==negative.keys()
for app,r in d['individuals'].items():assert r['applications']==[app] and paths[app] in r['packages']
c=d['cases'];assert c['piOff']['packages']==c['disabled']['packages'];assert c['all']['applications']==sorted(apps);assert c['allExceptArt']['applications']==sorted(apps-{'artcraft'});assert c['video']['applications']==['filmcraft','soundcraft'];assert c['elsewhere']['applications']==[] and paths['filmcraft'] in c['elsewhere']['packages'];assert len(c['identicalPackages']['piPackages'])==1;assert set(c['both']['servers'])=={'badwater-video'}|{'craft-'+n for n in apps-{'artcraft'}};assert set(c['onlyNew']['servers'])=={'fixture'} and c['onlyNew']['servers']['fixture']['exposure']=='codemode';assert not c['workflowMcpOff']['servers'];assert set(c['onlyCraftMcp']['servers'])=={'craft-gridcraft'}
for case,text in negative.items():
 status,_,stderr=evaluate('negative-'+case,'{case="'+case+'";}');assert status!=0 and status!=124 and text.encode() in stderr,(case,status)
for system in ['aarch64-linux','aarch64-darwin']:
 for case in ['disabled','individual','video','onlyCraftMcp']:
  status,stdout,stderr=evaluate(system+'-'+case,'{system="'+system+'";case="'+case+'";}');expected=system=='aarch64-darwin' and case in ['video','onlyCraftMcp'];assert (status!=0)==expected and status!=124
  if expected:assert b'requires Linux' in stderr
  else:
   body=json.loads(stdout);assert not body.get('failed') and not body.get('evaluationFailed')
# Build the exact generated-owner context targets, then exercise only that owner in private HOME.
targets=sorted({drv+'^'+output for case in ['preserveBuiltins','video','piOff','onlyNew'] for drv,ctx in c[case]['mcpContext'].items() for output in ctx.get('outputs',[])})
command=[a.nix,'build','--json','--out-link',str(out/'owner-roots'),*targets];(out/'owner-context-build.command.json').write_text(json.dumps(command,indent=2))
with (out/'owner-context-build.stdout').open('wb') as stdout,(out/'owner-context-build.stderr').open('wb') as stderr:status=subprocess.run(command,stdout=stdout,stderr=stderr,env=env,timeout=1800).returncode
assert status==0;harness=out/'harness';harness.mkdir();(harness/'paths.json').write_text(json.dumps(paths));(harness/'module-contexts.json').write_text(json.dumps(d));(harness/'activation_mcp_gate.py').write_bytes((Path(__file__).parent/'activation_mcp_gate.py').read_bytes());fixture=out/'activation-fixture';fixture.mkdir(mode=0o700)
for name in ['home','config','data','cache','runtime','tmp']:(fixture/name).mkdir(mode=0o700)
command=[paths['bubblewrap']+'/bin/bwrap','--unshare-all','--die-with-parent','--new-session','--ro-bind','/nix/store','/nix/store','--proc','/proc','--dev','/dev','--tmpfs','/tmp','--dir','/bin','--ro-bind',paths['bash']+'/bin/bash','/bin/sh','--dir','/usr','--dir','/usr/bin','--ro-bind',paths['coreutils']+'/bin/env','/usr/bin/env','--bind',str(fixture),'/fixture','--ro-bind',str(harness),'/harness','--chdir','/fixture','--clearenv']
for key,value in {'HOME':'/fixture/home','XDG_CONFIG_HOME':'/fixture/config','XDG_DATA_HOME':'/fixture/data','XDG_CACHE_HOME':'/fixture/cache','XDG_RUNTIME_DIR':'/fixture/runtime','TMPDIR':'/fixture/tmp','PATH':paths['bash']+'/bin:'+paths['coreutils']+'/bin','PYTHONDONTWRITEBYTECODE':'1'}.items():command+=['--setenv',key,value]
command += [paths['python3']+'/bin/python3','/harness/activation_mcp_gate.py'];(out/'owner-activation.command.json').write_text(json.dumps(command,indent=2))
with (out/'owner-activation.stdout').open('wb') as stdout,(out/'owner-activation.stderr').open('wb') as stderr:status=subprocess.run(command,stdout=stdout,stderr=stderr,timeout=120).returncode
assert status==0 and not (out/'owner-activation.stderr').read_bytes();assert (fixture/'acceptance.json').is_file()
(out/'acceptance.json').write_text(json.dumps({'namedCaseCount':25,'individualExactOutputCount':13,'positiveCount':16,'negativeCount':9,'individualOutputIdentity':True,'generatedMcpOwnerTransitionsVerified':True,'piOffBaselineEquality':True,'allOverrideExclusion':True,'namesAndPackagesDeduplicated':True,'platforms':'ARM/Darwin evaluation only, no nonnative build/runtime','receipts':receipts},indent=2)+'\n');print('PASS 25 named/13 exact-output individual cases, actual 9 negatives and enabled/disabled platform evaluations')
