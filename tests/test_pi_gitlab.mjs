// Real Pi builtin HTTP MCP with local synthetic server; no GitLab/OAuth/model traffic.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import {pathToFileURL} from 'node:url';

assert.equal(process.env.BADWATER_GITLAB_FIXTURE, '1'); assert.equal(process.env.PI_OFFLINE, '1');
const [core, matrixFile] = process.argv.slice(2), cases = JSON.parse(fs.readFileSync(matrixFile, 'utf8'));
const declaration = cases.enabled.servers['badwater-gitlab']; assert.equal(declaration.enabled, false); assert.equal(declaration.exposure, 'hidden');
const root = `${core}/lib/pi/node_modules/@earendil-works/pi-coding-agent`;
const sdk = await import(pathToFileURL(`${root}/dist/index.js`));
const {builtInExtensions} = await import(pathToFileURL(`${root}/dist/extensions/index.js`));
const methods = [], called = [], errors = [];
const server = http.createServer(async (req, res) => {
  assert.equal(req.url, '/mcp'); assert(!req.headers.authorization); assert(!req.headers['private-token']);
  if (req.method !== 'POST') { res.writeHead(405).end(); return; }
  let body = ''; for await (const chunk of req) body += chunk; const message = JSON.parse(body); methods.push(message.method);
  if (message.id === undefined) { res.writeHead(202).end(); return; }
  let result;
  if (message.method === 'initialize') result = {protocolVersion: message.params.protocolVersion, capabilities: {tools: {}}, serverInfo: {name: 'synthetic-gitlab', version: '1'}};
  else if (message.method === 'tools/list') result = {tools: ['get_project', 'save_merge_request', 'future_unknown_tool'].map(name => ({name, description: 'Synthetic fixture', annotations: {readOnlyHint: true}, inputSchema: {type: 'object', properties: {project: {type: 'string'}}}}))};
  else if (message.method === 'tools/call') { called.push(message.params.name); assert.equal(message.params.name, 'get_project', 'non-read tool reached server'); result = {content: [{type: 'text', text: 'synthetic-project'}]}; }
  else { res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify({jsonrpc: '2.0', id: message.id, error: {code: -32601, message: 'Unsupported fixture method'}})); return; }
  res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify({jsonrpc: '2.0', id: message.id, result}));
});
await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
let session;
try {
  const url = `http://127.0.0.1:${server.address().port}/mcp`;
  for (const enabled of [false, true]) {
    const agentDir = path.join(process.env.HOME, '.pi/agent'); fs.mkdirSync(agentDir, {recursive: true, mode: 0o700});
    const source = {mcpServers: {'badwater-gitlab': {...declaration, url, enabled}}};
    fs.writeFileSync(path.join(agentDir, 'mcp.json'), JSON.stringify(source), {mode: 0o600});
    fs.writeFileSync(path.join(agentDir, 'settings.json'), JSON.stringify({defaultTools: ['+codemode'], enableInstallTelemetry: false, enableAnalytics: false}), {mode: 0o600});
    const before = fs.readFileSync(path.join(agentDir, 'mcp.json'), 'utf8');
    const settingsManager = sdk.SettingsManager.create(process.cwd(), agentDir);
    const loader = new sdk.DefaultResourceLoader({cwd: process.cwd(), agentDir, settingsManager, noContextFiles: true, extensionFactories: builtInExtensions.filter(e => ['mcp', 'codemode', 'tool-search'].includes(e.name))}); await loader.reload();
    const loaded = loader.getExtensions(); assert.deepEqual(loaded.errors, []); assert.deepEqual(loaded.warnings, []); assert.equal(loaded.extensions.filter(e => e.commands.has('mcp')).length, 1);
    const runtime = await sdk.ModelRuntime.create({authPath: path.join(agentDir, 'inert-auth.json'), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false});
    ({session} = await sdk.createAgentSession({cwd: process.cwd(), agentDir, settingsManager, resourceLoader: loader, sessionManager: sdk.SessionManager.inMemory(process.cwd()), modelRuntime: runtime,
      model: {id: 'inert', name: 'Inert', provider: 'fixture', api: 'openai-completions', baseUrl: 'http://127.0.0.1:1', reasoning: false, input: ['text'], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 8192, maxTokens: 1}}));
    await session.bindExtensions({mode: 'print', onError: error => errors.push(error)});
    const mcp = loaded.extensions.find(e => e.path === 'builtin:mcp'); assert(mcp);
    const ctx = {cwd: process.cwd(), hasUI: false, mode: 'print', ui: {notify() {}}}; await mcp.commands.get('mcp').handler('', ctx);
    const read = 'mcp__badwater_gitlab__get_project', write = 'mcp__badwater_gitlab__save_merge_request', unknown = 'mcp__badwater_gitlab__future_unknown_tool';
    if (!enabled) { assert.deepEqual(methods, []); assert(!session.getCallableToolNames().includes(read)); }
    else {
      assert(session.getCallableToolNames().includes(read));
      for (const name of [write, unknown]) { assert(!session.getCallableToolNames().includes(name)); session.setActiveToolsByName([...session.getActiveToolNames(), name]); assert(!session.getActiveToolNames().includes(name), 'hidden tool activated'); }
      const reply = await mcp.tools.get(read).definition.execute('fixture-read', {project: 'authorized-fixture'}, undefined, undefined, ctx); assert(!reply.isError); assert.equal(reply.content[0].text, 'synthetic-project');
    }
    assert.equal(fs.readFileSync(path.join(agentDir, 'mcp.json'), 'utf8'), before); assert.equal(fs.statSync(path.join(agentDir, 'mcp.json')).mode & 0o777, 0o600);
    const authFile = path.join(agentDir, 'mcp-auth.json');
    if (fs.existsSync(authFile)) { const text = fs.readFileSync(authFile, 'utf8'); assert.deepEqual(text.trim() ? JSON.parse(text) : {}, {}); assert.equal(fs.statSync(authFile).mode & 0o777, 0o600); }
    await session.dispose(); session = undefined;
  }
  assert.deepEqual(errors, []); assert.deepEqual(called, ['get_project']); assert.equal(methods.filter(name => name === 'initialize').length, 1);
  console.log('PASS native Pi: disabled GitLab makes zero requests; explicit fixture enable exposes exact reads, hides writes/unknowns despite hints; one MCP owner, private state unchanged; no remote/auth/model calls');
} finally { await session?.dispose(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
