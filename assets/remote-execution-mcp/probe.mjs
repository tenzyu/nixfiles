import {Client} from "@modelcontextprotocol/sdk/client/index.js";
import {StreamableHTTPClientTransport} from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import assert from "node:assert/strict";
const url=new URL("http://127.0.0.1:18991/mcp");
const open=async name=>{const c=new Client({name,version:"1"});const t=new StreamableHTTPClientTransport(url);await c.connect(t);return {c,t};};
const a=await open("a"),b=await open("b");
const call=async(c,name,args)=>{const r=await c.callTool({name,arguments:args});assert.notEqual(r.isError,true);return r.content[0].text;};
const run=(c,command,timeout_ms=3000)=>call(c,"start_process",{command,timeout_ms});
try{
assert.notEqual(a.t.sessionId,b.t.sessionId);
const tools=await a.c.listTools(); assert.ok(tools.tools.some(x=>x.name==="start_process")); console.log("TOOLS",tools.tools.length);
const cfg=await call(a.c,"get_config",{}); assert.match(cfg,/"telemetryEnabled"\s*:\s*false/); console.log("TELEMETRY_DISABLED");
for (const code of [0,7]){
 const p=await run(a.c,"sleep 1; exit "+code,100);
 const pid=Number(p.match(/PID (\d+)/)[1]);
 const result=await call(a.c,"read_process_output",{pid,timeout_ms:5000});
 console.log("EXIT",code,result);assert.match(result,new RegExp("exit code "+code+"\\b"));
}
const p=await run(a.c,"sleep 3; echo SESSION_DONE",100);
assert.match(await call(b.c,"list_sessions",{}),/No active sessions/);
const pid=Number(p.match(/PID (\d+)/)[1]);
const sid=a.t.sessionId;
await a.c.close();
const invalid=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json",Accept:"application/json, text/event-stream","Mcp-Session-Id":"does-not-exist"},body:JSON.stringify({jsonrpc:"2.0",id:1,method:"tools/list"})});assert.equal(invalid.status,404);
const headers={"Content-Type":"application/json",Accept:"application/json, text/event-stream","Mcp-Session-Id":sid,"MCP-Protocol-Version":"2025-03-26"};
const r=await fetch(url,{method:"POST",headers,body:JSON.stringify({jsonrpc:"2.0",id:123,method:"tools/call",params:{name:"read_process_output",arguments:{pid,timeout_ms:5000}}})});
const body=await r.text();console.log("RESUME",r.status,body.slice(0,800));assert.equal(r.status,200);assert.match(body,/SESSION_DONE/);
}finally{await b.t.terminateSession().catch(()=>{});await a.c.close().catch(()=>{});await b.c.close().catch(()=>{});}
