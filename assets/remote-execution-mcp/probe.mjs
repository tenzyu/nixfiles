import {Client} from "@modelcontextprotocol/sdk/client/index.js";
import {StreamableHTTPClientTransport} from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";

const url = new URL(process.env.MCP_URL ?? "http://127.0.0.1:18991/mcp");
const open = async name => {
  const client = new Client({name, version:"1"});
  const transport = new StreamableHTTPClientTransport(url);
  await client.connect(transport);
  return {client, transport};
};
const call = async (client, name, args) => {
  const result = await client.callTool({name, arguments:args});
  assert.notEqual(result.isError, true, JSON.stringify(result));
  return result.content.map(part => part.text ?? "").join("\n");
};
const run = (client, command, timeout_ms = 3000) =>
  call(client, "start_process", {command, timeout_ms});
const pidFrom = output => {
  const match = output.match(/PID (\d+)/);
  assert.ok(match, output);
  return Number(match[1]);
};
const a = await open("a");
const b = await open("b");
const fixture = "$HOME/mcp-fixture-" + randomUUID();
try {
  assert.notEqual(a.transport.sessionId, b.transport.sessionId);
  const {tools} = await a.client.listTools();
  assert.equal(tools.length, 25);
  for (const tool of tools) assert.equal(tool.inputSchema.type, "object", tool.name);
  assert.match(await call(a.client, "get_config", {}), /"telemetryEnabled"\s*:\s*false/);
  for (const code of [0, 7]) {
    const started = await run(a.client, "sleep 1; exit " + code, 100);
    const output = await call(a.client, "read_process_output", {pid:pidFrom(started), timeout_ms:5000});
    assert.match(output, new RegExp("exit code " + code + "\\b"));
  }

  const ready = await run(a.client, 'set -eu; mkdir -p "' + fixture + '"; cd "' + fixture + '"; git init -q; git -c user.name=fixture -c user.email=fixture@example.invalid commit --allow-empty -qm init; git worktree add -qb alpha a; git worktree add -qb beta b; echo WORKTREES_READY');
  assert.match(ready, /WORKTREES_READY/);
  const results = await Promise.all([
    run(a.client, 'set -eu; cd "' + fixture + '/a"; echo alpha > artifact; sleep 1; cat artifact; git branch --show-current'),
    run(b.client, 'set -eu; cd "' + fixture + '/b"; echo beta > artifact; cat artifact; git branch --show-current')
  ]);
  assert.match(results[0], /alpha\nalpha/);
  assert.match(results[1], /beta\nbeta/);
  if (process.env.MCP_CHECK_GUEST === "1") {
    const guest = await run(b.client, "set -eu; test $(id -u) -ne 0; nix --version; rustc --version; cargo --version; bun --version; git --version; test \"$(nix eval --offline --raw --expr '\"guest-eval\"')\" = guest-eval; echo GUEST_TOOLS_OK");
    assert.match(guest, /GUEST_TOOLS_OK/);
  }
  const running = await run(a.client, "sleep 3; echo SESSION_DONE", 100);
  assert.match(await call(b.client, "list_sessions", {}), /No active sessions/);
  const pid = pidFrom(running);
  const sid = a.transport.sessionId;
  await a.client.close();
  const headers = {"Content-Type":"application/json", Accept:"application/json, text/event-stream", "MCP-Protocol-Version":"2025-03-26"};
  const invalid = await fetch(url, {
    method:"POST", headers:{...headers, "Mcp-Session-Id":"does-not-exist"},
    body:JSON.stringify({jsonrpc:"2.0",id:1,method:"tools/list"})
  });
  assert.equal(invalid.status, 404);
  const resumed = await fetch(url, {
    method:"POST", headers:{...headers, "Mcp-Session-Id":sid},
    body:JSON.stringify({jsonrpc:"2.0",id:123,method:"tools/call",params:{name:"read_process_output",arguments:{pid,timeout_ms:5000}}})
  });
  assert.equal(resumed.status, 200);
  assert.match(await resumed.text(), /SESSION_DONE/);
  const cleanup = await run(b.client, 'set -eu; rm -rf -- "' + fixture + '"; echo FIXTURE_REMOVED');
  assert.match(cleanup, /FIXTURE_REMOVED/);
  await fetch(url, {method:"DELETE",headers:{...headers,"Mcp-Session-Id":sid}});
  console.log("PASS: discovery, schemas, exit codes, worktrees, session separation and reconnect");
} finally {
  await b.transport.terminateSession().catch(() => {});
  await a.client.close().catch(() => {});
  await b.client.close().catch(() => {});
}
