// POST /mcp: the call centre's ship tools as an MCP server over Streamable HTTP
// (stateless; every answer is a single JSON response), so any MCP client can
// fly the linked ship from anywhere. Each request runs through the link on the
// game's McpBridge: tools/list -> ship_tools, tools/call -> ship_tool.

const SUPPORTED = ["2025-06-18", "2025-03-26", "2024-11-05"];
const err = (id, code, message) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

export async function handleMcp(req, res, game, log = console) {
  const msg = req.body;
  if (Array.isArray(msg)) return res.status(400).json(err(null, -32600, "Batches are not supported"));
  if (!msg || typeof msg !== "object" || !msg.method) return res.status(400).json(err(null, -32600, "Not a JSON-RPC request"));
  if (msg.id === undefined || msg.id === null) return res.status(202).end(); // a notification
  const { id, method, params = {} } = msg;
  const ok = (result) => res.json({ jsonrpc: "2.0", id, result });
  try {
    switch (method) {
      case "initialize":
        return ok({
          protocolVersion: SUPPORTED.includes(params.protocolVersion) ? params.protocolVersion : SUPPORTED[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: "icebox-ship", title: "Starship Icebox (call centre ship tools)", version: "1.0.0" },
          instructions: "Fly the starship Icebox, stranded inside a fractal. Start with get_ship_status and scan_surroundings. The game must be running with its call centre and linked to this server.",
        });
      case "ping":
        return ok({});
      case "tools/list": {
        const { tools = [] } = game.connected ? await game.call("ship_tools", {}, 5000) : {};
        return ok({ tools });
      }
      case "tools/call": {
        if (!game.connected) {
          return ok({ content: [{ type: "text", text: "The ship is not linked: start the game with its call centre and the phone link." }], isError: true });
        }
        const r = await game.call("ship_tool", { name: params.name, arguments: params.arguments ?? {} }, 15_000);
        return ok({ content: [{ type: "text", text: JSON.stringify(r) }], structuredContent: r, isError: r.ok === false });
      }
      default:
        return res.json(err(id, -32601, `Method not found: ${method}`));
    }
  } catch (e) {
    log.warn(`mcp ${method}: ${e.message}`);
    return res.json(err(id, -32603, e.message));
  }
}
