// POST /mcp: the ship's MCP server re-exposed over MCP's Streamable HTTP
// transport (stateless, JSON responses), so any MCP client (Claude Code,
// Claude Desktop, the MCP inspector, curl) can fly the ship too. Requests are
// proxied to the game over the ship link.

const SUPPORTED = ['2025-06-18', '2025-03-26', '2024-11-05'];

function reply(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(body === undefined ? '' : JSON.stringify(body));
}

const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });

export function authorized(req, token) {
  if (!token) return true;
  const auth = req.headers.authorization ?? '';
  if (auth === `Bearer ${token}`) return true;
  const q = new URL(req.url, 'http://x').searchParams.get('token');
  return q === token;
}

export async function handleMcp(req, res, rawBody, gameLink, { token = '' } = {}) {
  if (!authorized(req, token)) return reply(res, 401, rpcError(null, -32001, 'Unauthorized'));
  let msg;
  try {
    msg = JSON.parse(rawBody || '');
  } catch {
    return reply(res, 400, rpcError(null, -32700, 'Parse error'));
  }
  if (Array.isArray(msg)) return reply(res, 400, rpcError(null, -32600, 'Batches are not supported'));
  if (!msg || typeof msg !== 'object' || !msg.method) {
    // a response or something else we did not ask for
    return reply(res, 202);
  }
  if (msg.id === undefined || msg.id === null) return reply(res, 202);   // a notification
  const { id, method, params = {} } = msg;
  try {
    switch (method) {
      case 'initialize':
        return reply(res, 200, { jsonrpc: '2.0', id, result: {
          protocolVersion: SUPPORTED.includes(params.protocolVersion) ? params.protocolVersion : SUPPORTED[0],
          capabilities: { tools: { listChanged: false } },
          serverInfo: { name: 'icebox-ship', title: 'Starship Icebox (via Sub-Dimensional Support)', version: '1.0.0' },
          instructions: gameLink.instructions || 'Controls for the starship Icebox, stranded in a Mandelbox. The game must be running and connected to this relay.',
        } });
      case 'ping':
        return reply(res, 200, { jsonrpc: '2.0', id, result: {} });
      case 'tools/list':
        return reply(res, 200, { jsonrpc: '2.0', id, result: { tools: gameLink.tools } });
      case 'tools/call':
        if (!gameLink.connected) {
          return reply(res, 200, { jsonrpc: '2.0', id, result: {
            content: [{ type: 'text', text: 'The ship link is down: start the game with the call centre (call_center/run.sh).' }],
            isError: true,
          } });
        }
        return reply(res, 200, { jsonrpc: '2.0', id, result: await gameLink.request('tools/call', params) });
      default:
        return reply(res, 200, rpcError(id, -32601, `Method not found: ${method}`));
    }
  } catch (err) {
    return reply(res, 200, rpcError(id, err.code ?? -32603, err.message));
  }
}
