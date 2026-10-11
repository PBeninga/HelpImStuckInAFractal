// The support-line relay: one HTTP server with
//   POST /twilio/voice   Twilio's incoming-call webhook -> TwiML <Connect><Stream>
//   WS   /twilio/media   the call's audio (Twilio Media Streams)
//   WS   /game           the game's ship link (it serves MCP; we are the client)
//   POST /mcp            the ship's tools for any MCP client (Streamable HTTP)
//   GET  /               status
// One call at a time: there is one ship.

import http from 'node:http';
import crypto from 'node:crypto';
import { WebSocketServer } from 'ws';
import { GameLink } from './game-link.js';
import { SupportCall } from './support-call.js';
import { TwilioMediaBridge, streamTwiml, busyTwiml, validSignature } from './twilio.js';
import { handleMcp, authorized } from './mcp-http.js';
import { formatPhoneNumber } from './config.js';

const TOKEN_TTL_MS = 60_000;
const MAX_BODY = 1_000_000;

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('body too large'));
        req.destroy();
      } else {
        chunks.push(c);
      }
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

export function createRelay({ config, log = console, WebSocketImpl } = {}) {
  const gameLink = new GameLink({ log });
  const streamTokens = new Map();   // one-time tokens for /twilio/media, -> expiry
  let activeCall = null;

  if (config.twilio.phoneNumber) {
    gameLink.notify('ship/config', { support_number: formatPhoneNumber(config.twilio.phoneNumber) }, { sticky: true });
  }

  function newCall(mode) {
    if (activeCall) return null;
    const call = new SupportCall({ config, gameLink, mode, log, WebSocketImpl });
    activeCall = call;
    call.on('ended', () => {
      if (activeCall === call) activeCall = null;
    });
    return call;
  }

  function issueStreamToken() {
    const now = Date.now();
    for (const [t, exp] of streamTokens) if (exp < now) streamTokens.delete(t);
    const token = crypto.randomUUID();
    streamTokens.set(token, now + TOKEN_TTL_MS);
    return token;
  }

  function acceptStreamToken(token) {
    const exp = token && streamTokens.get(token);
    if (!exp) return false;
    streamTokens.delete(token);
    return exp >= Date.now();
  }

  function publicHost(req) {
    if (config.publicUrl) return new URL(config.publicUrl).host;
    return req.headers['x-forwarded-host'] ?? req.headers.host;
  }

  async function onTwilioVoice(req, res) {
    const body = await readBody(req);
    const params = Object.fromEntries(new URLSearchParams(body));
    if (config.twilio.validateSignatures) {
      const url = config.publicUrl + req.url;
      if (!validSignature(config.twilio.authToken, url, params, req.headers['x-twilio-signature'])) {
        log.warn?.('[twilio] rejected a webhook with a bad signature');
        res.writeHead(403).end('bad signature');
        return;
      }
    }
    res.writeHead(200, { 'Content-Type': 'text/xml' });
    if (activeCall) {
      log.info?.('[twilio] busy: a call is already in progress');
      res.end(busyTwiml());
      return;
    }
    const caller = String(params.From ?? '');
    log.info?.(`[twilio] incoming call from ...${caller.slice(-4)}`);
    gameLink.notify('ship/call', { state: 'ringing' }, { sticky: true });
    res.end(streamTwiml(`wss://${publicHost(req)}/twilio/media`, { token: issueStreamToken() }));
  }

  function status() {
    return {
      ok: true,
      game_connected: gameLink.connected,
      ship: gameLink.serverInfo?.name ?? null,
      tools: gameLink.tools.map((t) => t.name),
      call_active: Boolean(activeCall),
      support_number: formatPhoneNumber(config.twilio.phoneNumber),
      openai_key_set: Boolean(config.openai.apiKey),
      model: config.openai.model,
    };
  }

  const server = http.createServer(async (req, res) => {
    try {
      const path = new URL(req.url, 'http://x').pathname;
      if (req.method === 'GET' && (path === '/' || path === '/health')) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(status(), null, 2));
      } else if (req.method === 'POST' && path === '/twilio/voice') {
        await onTwilioVoice(req, res);
      } else if (path === '/mcp') {
        if (req.method !== 'POST') {
          res.writeHead(405, { Allow: 'POST' }).end();
          return;
        }
        await handleMcp(req, res, await readBody(req), gameLink, { token: config.shipLinkToken });
      } else {
        res.writeHead(404).end('not found');
      }
    } catch (err) {
      log.error?.(`[http] ${err.stack ?? err.message}`);
      if (!res.headersSent) res.writeHead(500).end('error');
    }
  });

  const wss = new WebSocketServer({ noServer: true });
  server.on('upgrade', (req, socket, head) => {
    const path = new URL(req.url, 'http://x').pathname;
    if (path === '/game') {
      if (!authorized(req, config.shipLinkToken)) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
        socket.destroy();
        return;
      }
      wss.handleUpgrade(req, socket, head, (ws) => {
        log.info?.('[game] the ship is dialling in');
        gameLink.attach(ws);
      });
    } else if (path === '/twilio/media') {
      wss.handleUpgrade(req, socket, head, (ws) => {
        new TwilioMediaBridge({ ws, acceptToken: acceptStreamToken, createCall: () => newCall('audio'), log });
      });
    } else {
      socket.destroy();
    }
  });

  return {
    server,
    gameLink,
    status,
    newCall,
    get activeCall() { return activeCall; },
    listen(port = config.port, host = config.host) {
      return new Promise((resolve) => server.listen(port, host, () => resolve(server.address().port)));
    },
    close() {
      activeCall?.end('server shutting down');
      for (const ws of wss.clients) ws.terminate();
      return new Promise((resolve) => server.close(() => resolve()));
    },
  };
}
