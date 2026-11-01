// Actual Pi builtin streamable-HTTP fixture, not a mock MCP client.
// Run core's Node 22 in an env-cleared private filesystem AND network namespace.
// Argument: Pi output path. No Context7/OAuth/provider/model/browser traffic.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import {pathToFileURL} from 'node:url';

assert.equal(process.env.HOME, '/tmp/policy-home');
assert.equal(process.env.PI_OFFLINE, '1');
const root = `${process.argv[2]}/lib/pi/node_modules/@earendil-works/pi-coding-agent`;
const sdk = await import(pathToFileURL(`${root}/dist/index.js`));
const {builtInExtensions} = await import(pathToFileURL(`${root}/dist/extensions/index.js`));
const agentDir = `${process.env.HOME}/.pi/agent`;
fs.mkdirSync(agentDir, {recursive: true, mode: 0o700});
const methods = [];
const server = http.createServer(async (req, res) => {
  // There is no OAuth challenge, remote proxy, SSE or other fallback here.
  assert.equal(req.url, '/mcp');
  if (req.method !== 'POST') { res.writeHead(405).end(); return; }
  let text = '';
  for await (const chunk of req) text += chunk;
  const message = JSON.parse(text);
  methods.push(message.method);
  if (message.id === undefined) { res.writeHead(202).end(); return; }
  let result;
  switch (message.method) {
    case 'initialize': result = {protocolVersion: message.params.protocolVersion, capabilities: {tools: {}}, serverInfo: {name: 'private-http-fixture', version: '1'}}; break;
    case 'tools/list': result = {tools: [{name: 'echo', description: 'Synthetic local fixture', inputSchema: {type: 'object', properties: {text: {type: 'string'}}, required: ['text']}}]}; break;
    case 'tools/call': assert.equal(message.params.name, 'echo'); result = {content: [{type: 'text', text: message.params.arguments.text}]}; break;
    default: res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify({jsonrpc: '2.0', id: message.id, error: {code: -32601, message: 'Fixture method not implemented'}})); return;
  }
  res.writeHead(200, {'Content-Type': 'application/json'}).end(JSON.stringify({jsonrpc: '2.0', id: message.id, result}));
});
await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
let session;
try {
  const url = `http://127.0.0.1:${server.address().port}/mcp`;
  const settings = {defaultTools: ['+codemode']};
  fs.writeFileSync(`${agentDir}/settings.json`, JSON.stringify(settings), {mode: 0o600});
  const notifications = []; const errors = [];
  // Each declaration gets a fresh native loader/session; /mcp has no reload action.
  for (const type of [undefined, 'http', 'streamable-http']) {
    fs.writeFileSync(`${agentDir}/mcp.json`, JSON.stringify({mcpServers: {fixture: {url, ...(type ? {type} : {}), exposure: 'codemode'}}}), {mode: 0o600});
    const settingsManager = sdk.SettingsManager.create(process.cwd(), agentDir);
    const loader = new sdk.DefaultResourceLoader({cwd: process.cwd(), agentDir, settingsManager, noContextFiles: true, extensionFactories: builtInExtensions.filter(e => ['mcp', 'codemode', 'tool-search'].includes(e.name))});
    await loader.reload();
    const loaded = loader.getExtensions();
    assert.deepEqual(loaded.errors, []); assert.deepEqual(loaded.warnings, []);
    assert.deepEqual(loaded.extensions.filter(e => e.commands.has('mcp')).map(e => e.path), ['builtin:mcp']);
    const modelRuntime = await sdk.ModelRuntime.create({authPath: `${agentDir}/inert-auth.json`, modelsPath: null, refreshOnCreate: false, allowModelNetwork: false});
    ({session} = await sdk.createAgentSession({cwd: process.cwd(), agentDir, settingsManager, resourceLoader: loader, sessionManager: sdk.SessionManager.inMemory(process.cwd()), modelRuntime,
      model: {id: 'inert', name: 'Inert', provider: 'fixture', api: 'openai-completions', baseUrl: 'http://127.0.0.1:1', reasoning: false, input: ['text'], cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}, contextWindow: 8192, maxTokens: 1}}));
    const mcp = loaded.extensions.find(e => e.path === 'builtin:mcp');
    const ctx = {cwd: process.cwd(), hasUI: false, mode: 'print', ui: {notify: (text, level) => notifications.push({text, level})}};
    await session.bindExtensions({mode: 'print', onError: e => errors.push(e)});
    await mcp.commands.get('mcp').handler('', ctx);
    assert(mcp.tools.has('mcp__fixture__echo'));
    const reply = await mcp.tools.get('mcp__fixture__echo').definition.execute('fixture-call', {text: 'synthetic-only'}, undefined, undefined, ctx);
    assert(!reply.isError); assert.equal(reply.content[0].text, 'synthetic-only');
    await session.dispose(); session = undefined;
  }
  assert.deepEqual(errors, []);
  assert(!notifications.some(n => ['error', 'warning'].includes(n.level)), JSON.stringify(notifications));
  assert(methods.includes('initialize') && methods.includes('tools/list') && methods.includes('tools/call'));
  assert.equal(methods.filter(m => m === 'initialize').length, 3);
  console.log('PASS actual Pi builtin sole /mcp owner: omitted/http/streamable-http initialize/list/synthetic echo over private loopback; no OAuth/model/Context7 requests');
} finally {
  await session?.dispose();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
