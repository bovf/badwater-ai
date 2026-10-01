// Run with Node 24 in a private filesystem/network namespace (only /nix/store,
// this test and a fresh generated HOME exposed), env -i PI_OFFLINE=1.
// Network isolation alone does not hide host Unix sockets or absolute home paths.
// Argument: pre-publication manifest from the temporary Home Manager fixture.
// Loads the CLI's actual builtin factories, but starts only MCP/discovery lifecycle:
// no other extension lifecycle, model calls, browser/LSP/relay or hardware activity.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
const manifest = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
assert.equal(process.env.HOME, manifest.homeDir);
assert(manifest.homeDir.startsWith('/tmp/'));
const root = `${manifest.pi.path}/lib/node_modules/pi-monorepo`;
const sdk = await import(pathToFileURL(`${root}/dist/index.js`));
const { builtInExtensions } = await import(pathToFileURL(`${root}/dist/extensions/index.js`));
const agentDir = `${process.env.HOME}/.pi/agent`;
const settings = JSON.parse(fs.readFileSync(`${agentDir}/settings.json`, 'utf8'));
assert.equal(settings['archimedes.mcp'].enabled, false);
assert(!settings.extensions?.includes('-builtin:mcp'));
assert(!fs.lstatSync(`${agentDir}/settings.json`).isSymbolicLink());
assert(!fs.lstatSync(`${agentDir}/keybindings.json`).isSymbolicLink());
for (const path of settings.packages) assert(fs.lstatSync(path).isSymbolicLink());
const settingsManager = sdk.SettingsManager.create(process.cwd(), agentDir);
const loader = new sdk.DefaultResourceLoader({
  cwd: process.cwd(), agentDir, settingsManager, noContextFiles: true,
  extensionFactories: builtInExtensions,
});
await loader.reload();
const loaded = loader.getExtensions();
assert.deepEqual(loaded.errors, []);
assert.deepEqual(loaded.warnings, []);
console.log(JSON.stringify({packageWarnings: loaded.warnings}));
for (const result of [loader.getSkills(), loader.getPrompts(), loader.getThemes()]) {
  assert.deepEqual(result.diagnostics, []);
}
assert(loader.getSkills().skills.some(s => s.name === 'graphify'));
assert(loader.getSkills().skills.some(s => s.name === 'web-search'));
const arch = loaded.extensions.find(e => e.path.includes('/pi-archimedes'));
assert(arch);
const starts = arch.handlers.get('session_start');
// Execute the actual lazy handler: older Archimedes gates MCP here; 2.9
// removes that component entirely. Neither may take ownership from builtin MCP.
await starts.at(-1)({type: 'session_start'}, {hasUI: false});
assert(!arch.tools.has('mcp'));
assert(!arch.commands.has('mcp'));
assert(arch.tools.has('manage_todo_list'));
assert(!arch.tools.has('subagent'));
const archSource = fs.readFileSync(`${manifest.packages['pi-archimedes'].path}/src/index.ts`, 'utf8');
assert(archSource.includes('false /* Pi core owns clipboard image handling. */'));
assert(archSource.includes('false /* pi-subagents owns delegation. */'));
const archManifest = JSON.parse(fs.readFileSync(`${manifest.packages['pi-archimedes'].path}/package.json`, 'utf8'));
if (!archManifest.dependencies?.['@pi-archimedes/mcp']) {
  assert(!archSource.includes('@pi-archimedes/mcp'));
  assert(!archSource.includes('registerMcp'));
  const plugins = fs.readFileSync(`${manifest.packages['pi-archimedes'].path}/src/plugins.ts`, 'utf8');
  assert(!plugins.includes('@pi-archimedes/mcp'));
  assert(!plugins.includes('archimedes.mcp'));
  console.log('PASS: installed Archimedes has no MCP component; historical disabled gate not exercised');
}
assert.deepEqual(loaded.extensions.filter(e => e.commands.has('mcp')).map(e => e.path), ['builtin:mcp']);
const commit = loaded.extensions.find(e => e.path.endsWith('badwater-commit-rules.ts'));
const rules = await commit.handlers.get('before_agent_start')[0]({systemPrompt: 'base'}, {});
assert(rules.systemPrompt.startsWith('base'));
assert(rules.systemPrompt.includes('Do not add Co-authored-by'));
console.log(`PASS: ${loaded.extensions.length} CLI-equivalent factories; resources; actual Archimedes lazy handler; exactly one /mcp owner`);

// Real SDK session with the already loaded CLI MCP/discovery factories only.
// Explicit static inert model avoids default model/credential availability selection.
loader.getExtensions = () => ({...loaded, extensions: loaded.extensions.filter(e =>
  ['builtin:mcp', 'builtin:codemode', 'builtin:tool-search'].includes(e.path))});
const modelRuntime = await sdk.ModelRuntime.create({
  authPath: `${agentDir}/inert-auth.json`, modelsPath: null,
  refreshOnCreate: false, allowModelNetwork: false,
});
const { session } = await sdk.createAgentSession({
  cwd: process.cwd(), agentDir, settingsManager, resourceLoader: loader,
  sessionManager: sdk.SessionManager.inMemory(process.cwd()), modelRuntime,
  model: {id: 'inert', name: 'Inert', provider: 'fixture', api: 'openai-completions',
    baseUrl: 'http://127.0.0.1:1', reasoning: false, input: ['text'],
    cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 8192, maxTokens: 1},
});
const errors = [];
const notifications = [];
const mcp = loaded.extensions.find(e => e.path === 'builtin:mcp');
const ctx = {cwd: process.cwd(), hasUI: false, mode: 'print', ui: {
  notify: (text, level) => notifications.push({text, level}),
}};
try {
  await session.bindExtensions({mode: 'print', onError: e => errors.push(e)});
  // The builtin command awaits its actual initialize/list-tools work.
  await mcp.commands.get('mcp').handler('', ctx);
  assert.deepEqual(errors, []);
  assert(!notifications.some(n => n.level === 'error' || n.level === 'warning'), JSON.stringify(notifications));
  const names = loaded.extensions.flatMap(e => [...e.tools.keys()]).filter(n => n.startsWith('mcp__'));
  console.log(JSON.stringify({tools: names}));
  assert(names.length > 2);
  assert.equal(names.length, new Set(names).size);
  assert(names.includes('mcp__graphify__get_node'));
  assert(names.includes('mcp__web_search__web_search'));
  assert(session.getActiveToolNames().includes('codemode'));
  const call = async (name, args) => {
    const result = await mcp.tools.get(name).definition.execute('contract', args, undefined, undefined, ctx);
    assert(!result.isError, JSON.stringify(result));
    return result.content.map(c => c.text ?? '').join('\n');
  };
  assert((await call('mcp__graphify__graph_stats', {})).startsWith('Nodes: 1\nEdges: 0\n'));
  for (const args of [{label: 'sample'}, {node_id: 'sample.nix::sample'}]) {
    assert((await call('mcp__graphify__get_node', args)).includes('sample.nix::sample'));
  }
  assert((await call('mcp__web_search__web_search', {query: ''})).includes('empty query'));
  assert.equal(session.sessionFile, undefined);
  assert.equal(session.messages.length, 0);
  console.log(`PASS: builtin initialize/list, ${names.length} unique MCP tools, graph_stats/get_node(label/node_id), empty search; in-memory SDK session without prompts`);
  console.log(JSON.stringify({notifications, tools: names}));
} finally {
  for (const handler of mcp.handlers.get('session_shutdown')) await handler({type: 'session_shutdown'}, ctx);
  session.dispose();
}
console.log('PASS: builtin MCP connections closed; SDK session disposed');
process.exit(0);
