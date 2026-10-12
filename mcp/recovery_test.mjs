import assert from "node:assert/strict";
import net from "node:net";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

// Exercise the actual MCP registration and TCP transport without launching
// a window. Godot's mcp_bridge_test covers the real surface search itself.
test("surface recovery is discoverable and reports bridge success and failure", async (t) => {
  const replies = [
    { ok: true, message: "Facing nearest surface.", distance: 4 },
    { ok: false, message: "No surface found within the visible scene." },
    { error: "no view is open; call start_game first" },
  ];
  const requests = [];
  const sockets = new Set();
  const bridge = net.createServer((socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
    let buffer = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      buffer += chunk;
      let end;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const request = JSON.parse(buffer.slice(0, end));
        buffer = buffer.slice(end + 1);
        requests.push(request);
        socket.write(JSON.stringify({ id: request.id, ok: true, result: replies.shift() }) + "\n");
      }
    });
  });
  t.after(() => {
    for (const socket of sockets) socket.destroy();
    bridge.close();
  });
  bridge.listen(0, "127.0.0.1");
  await once(bridge, "listening");
  const client = new Client({ name: "surface-recovery-test", version: "1" });
  t.after(() => client.close());
  await client.connect(new StdioClientTransport({
    command: process.execPath,
    args: [fileURLToPath(new URL("./server.mjs", import.meta.url))],
    env: { ...process.env, FRACTAL_MCP_PORT: String(bridge.address().port) },
  }));
  const definitions = await client.listTools();
  assert.ok(definitions.tools.some((tool) => tool.name === "find_nearest_surface"));
  const success = await client.callTool({ name: "find_nearest_surface", arguments: {} });
  assert.equal(success.isError, false);
  assert.equal(JSON.parse(success.content[0].text).distance, 4);
  for (let i = 0; i < 2; i++) {
    const failure = await client.callTool({ name: "find_nearest_surface", arguments: {} });
    assert.equal(failure.isError, true);
  }
  assert.deepEqual(requests.map(({ cmd, args }) => ({ cmd, args })),
    Array.from({ length: 3 }, () => ({ cmd: "find_nearest_surface", args: {} })));
});
