// Actual generated-policy CLI builtin MCP discovery. Private filesystem/network
// namespace, cleared env and fixture HOME/cwd only; inspect startup hooks first.
// No prompts, model/provider/auth, browser, backend or REA tool calls.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { readFile, writeFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';

const manifest = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.equal(process.cwd(), process.env.HOME);
assert.equal(manifest.homeDir, process.env.HOME);
assert(manifest.homeDir.startsWith('/tmp/'));
const core = `${manifest.pi.path}/lib/pi/node_modules/@earendil-works/pi-coding-agent`;
const { createMcpToolName } = await import(pathToFileURL(`${core}/dist/extensions/mcp/tools.js`));
const graphSource = await readFile(`${manifest.graphify.path}/${manifest.graphify.sitePackages}/graphify/serve.py`, 'utf8');
const graphNames = [...graphSource.matchAll(/types\.Tool\(\s*name="([^"]+)"/g)].map(m => m[1]);
assert.equal(graphNames.length, 10);
const catalog = JSON.parse(await readFile(`${manifest.rea.path}/lib/rea/dist/mcp-catalog.json`, 'utf8'));
assert.equal(catalog.tools.length, 229);
const expected = [
  ...graphNames.map(n => createMcpToolName('graphify', n)),
  createMcpToolName('web-search', 'web_search'),
  ...catalog.tools.map(t => createMcpToolName('rea', t.name)),
].toSorted();
const agent = `${manifest.homeDir}/.pi/agent`;
const paths = ['settings.json', 'keybindings.json', 'mcp.json', 'models.json'];
const originals = new Map(await Promise.all(paths.map(async p => [p, await readFile(`${agent}/${p}`)])));
const settings = JSON.parse(originals.get('settings.json'));
const probe = `${manifest.homeDir}/cli-mcp-probe.mjs`;
const done = `${manifest.homeDir}/cli-mcp-ready.json`;
await writeFile(probe, `import {writeFile} from 'node:fs/promises'; import {setTimeout as delay} from 'node:timers/promises'; export default function(pi){ pi.on('session_start',()=>{ void(async()=>{for(let i=0;i<800;i++){const names=pi.getAllTools().map(t=>t.name).filter(n=>n.startsWith('mcp__')).sort(); if(JSON.stringify(names)===${JSON.stringify(JSON.stringify(expected))}){await writeFile(${JSON.stringify(done)},JSON.stringify(names));return;} await delay(50);}})();});}`);
await writeFile(`${agent}/settings.json`, JSON.stringify({...settings, extensions: [...(settings.extensions ?? []), probe]}));
let child;
let exited;
let deadline;
try {
  child = spawn(`${manifest.pi.path}/bin/pi`, ['--offline', '--mode', 'rpc', '--no-session', '--approve'], {stdio: ['pipe', 'pipe', 'pipe']});
  exited = once(child, 'exit');
  let stderr = '';
  const records = [];
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', c => stderr += c);
  createInterface({input: child.stdout}).on('line', line => records.push(JSON.parse(line)));
  deadline = setTimeout(() => child.kill('SIGKILL'), 60_000);
  child.stdin.write('{"id":"resources","type":"get_commands"}\n');
  let names;
  for (let i = 0; i < 900; i++) {
    try { names = JSON.parse(await readFile(done, 'utf8')); break; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (child.exitCode !== null) break;
    await delay(50);
  }
  assert(names, `actual CLI did not discover generated servers: ${stderr} ${JSON.stringify(records)}`);
  assert.deepEqual(names, expected);
  assert.equal(new Set(names).size, expected.length);
  child.stdin.end();
  assert.deepEqual(await exited, [0, null], stderr);
  assert.equal(stderr, '');
  assert(!records.some(r => r.type === 'error' || r.type === 'extension_error' || r.level === 'warning' || r.level === 'error' || r.notifyType === 'warning' || r.notifyType === 'error'), JSON.stringify(records));
  const response = records.find(r => r.id === 'resources');
  assert.equal(response?.success, true);
  assert.equal(response.data.commands.filter(c => c.name === 'mcp').length, 1);
  for (const path of paths.filter(p => p !== 'settings.json')) assert.deepEqual(await readFile(`${agent}/${path}`), originals.get(path));
  console.log(JSON.stringify({tools: names, commands: response.data.commands.map(c => c.name)}, null, 2));
  console.log('PASS actual generated CLI RPC: sole builtin /mcp, complete 240-tool Graphify/search/REA inventory, all selected packages, zero stderr, no tool/model calls');
} finally {
  clearTimeout(deadline);
  if (child?.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  if (exited) await exited;
  await writeFile(`${agent}/settings.json`, originals.get('settings.json'));
  for (const path of paths) assert.deepEqual(await readFile(`${agent}/${path}`), originals.get(path));
}
