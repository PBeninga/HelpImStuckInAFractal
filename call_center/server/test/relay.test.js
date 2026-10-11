// End to end through the relay with fakes for OpenAI, the game and Twilio.

import { test, describe, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { WebSocket } from 'ws';
import { fakeOpenAI, fakeGame, startRelay, twilioCall, post, until, FAKE_TOOLS } from './helpers.js';
import { computeSignature, validSignature, streamTwiml } from '../src/twilio.js';
import { formatPhoneNumber, loadConfig } from '../src/config.js';

describe('twilio helpers', () => {
  test('signature matches the documented algorithm and rejects tampering', () => {
    const url = 'https://example.ngrok.app/twilio/voice';
    const params = { CallSid: 'CA1', From: '+15551234567', To: '+15550109001' };
    const sig = computeSignature('secret', url, params);
    assert.ok(validSignature('secret', url, params, sig));
    assert.ok(!validSignature('secret', url, { ...params, From: '+1' }, sig));
    assert.ok(!validSignature('other', url, params, sig));
    assert.ok(!validSignature('secret', url, params, undefined));
  });

  test('stream TwiML escapes and carries parameters', () => {
    const xml = streamTwiml('wss://h/twilio/media', { token: 'a"b' });
    assert.match(xml, /<Connect><Stream url="wss:\/\/h\/twilio\/media"><Parameter name="token" value="a&quot;b"\/><\/Stream><\/Connect>/);
  });

  test('phone numbers are formatted for the HUD', () => {
    assert.equal(formatPhoneNumber('+15550109001'), '+1 (555) 010-9001');
    assert.equal(formatPhoneNumber('+442071234567'), '+442071234567');
  });

  test('signature checks need both the auth token and PUBLIC_URL', () => {
    assert.equal(loadConfig({ TWILIO_AUTH_TOKEN: 'x' }).twilio.validateSignatures, false);
    assert.equal(loadConfig({ TWILIO_AUTH_TOKEN: 'x', PUBLIC_URL: 'https://a.b/' }).twilio.validateSignatures, true);
    assert.equal(loadConfig({ PUBLIC_URL: 'https://a.b/' }).publicUrl, 'https://a.b');
  });
});

describe('relay', () => {
  let openai, relay, port, game;

  before(async () => {
    openai = await fakeOpenAI();
    ({ relay, port } = await startRelay(openai));
    game = await fakeGame(port);
    await until(() => relay.gameLink.connected, 2000, 'game link');
  });

  after(async () => {
    game.close();
    await relay.close();
    await openai.close();
  });

  test('the game link does the MCP handshake and gets the HUD config', async () => {
    assert.deepEqual(game.requests.map((r) => r.method), ['initialize', 'tools/list']);
    assert.equal(game.requests[0].params.protocolVersion, '2025-06-18');
    assert.ok(game.notes('notifications/initialized').length === 1);
    await until(() => game.notes('ship/config').length, 1000, 'ship/config');
    assert.equal(game.notes('ship/config')[0].params.support_number, '+1 (555) 010-9001');
    const status = await (await fetch(`http://127.0.0.1:${port}/`)).json();
    assert.equal(status.game_connected, true);
    assert.deepEqual(status.tools, FAKE_TOOLS.map((t) => t.name));
  });

  test('/mcp proxies MCP to the game', async () => {
    const rpc = async (body) => JSON.parse((await post(port, '/mcp', JSON.stringify(body), { 'Content-Type': 'application/json' })).text);
    const init = await rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } });
    assert.equal(init.result.protocolVersion, '2025-03-26');
    assert.ok(init.result.capabilities.tools);
    const listed = await rpc({ jsonrpc: '2.0', id: 2, method: 'tools/list' });
    assert.deepEqual(listed.result.tools.map((t) => t.name), ['get_ship_status', 'fly_to_feature']);
    const called = await rpc({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'fly_to_feature', arguments: { feature_id: '#2312' } } });
    assert.equal(JSON.parse(called.result.content[0].text).message, 'did fly_to_feature');
    assert.deepEqual(game.calls.at(-1), { name: 'fly_to_feature', arguments: { feature_id: '#2312' } });
    const note = await post(port, '/mcp', JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }));
    assert.equal(note.status, 202);
    const missing = await rpc({ jsonrpc: '2.0', id: 4, method: 'prompts/list' });
    assert.equal(missing.error.code, -32601);
    const get = await fetch(`http://127.0.0.1:${port}/mcp`);
    assert.equal(get.status, 405);
  });

  test('a phone call: TwiML, session setup, greeting, audio both ways, tools, transcripts, events, barge-in, hang-up', async () => {
    const tw = await twilioCall(port);
    assert.match(tw.voice.text, new RegExp(`<Stream url="wss://127.0.0.1:${port}/twilio/media">`));
    assert.ok(tw.token, 'the TwiML carries a one-time token');
    assert.equal(game.notes('ship/call')[0].params.state, 'ringing');

    // the session is configured for phone audio with the ship's tools
    const update = await until(() => openai.of('session.update')[0], 2000, 'session.update');
    assert.equal(openai.headers.authorization, 'Bearer sk-test');
    assert.match(openai.url, /model=gpt-realtime-2\.1/);
    const s = update.session;
    assert.equal(s.type, 'realtime');
    assert.deepEqual(s.output_modalities, ['audio']);
    assert.deepEqual(s.audio.input.format, { type: 'audio/pcmu' });
    assert.deepEqual(s.audio.output.format, { type: 'audio/pcmu' });
    assert.equal(s.audio.output.voice, 'cedar');
    assert.equal(s.audio.input.turn_detection.type, 'server_vad');
    assert.deepEqual(s.tools.map((t) => t.name), ['get_ship_status', 'fly_to_feature']);
    assert.equal(s.tools[1].parameters.required[0], 'feature_id');
    assert.match(s.instructions, /Sub-Dimensional Support/);
    assert.deepEqual(s.reasoning, { effort: 'low' });
    await until(() => openai.of('response.create').length === 1, 2000, 'greeting response.create');
    await until(() => game.notes('ship/call').some((n) => n.params.state === 'connected'), 1000, 'call connected');

    // caller audio reaches OpenAI untouched
    tw.send({ event: 'media', streamSid: 'MZ1', media: { track: 'inbound', chunk: '1', timestamp: '20', payload: 'AAAA' } });
    await until(() => openai.of('input_audio_buffer.append').length === 1, 1000, 'audio append');
    assert.equal(openai.of('input_audio_buffer.append')[0].audio, 'AAAA');

    // agent audio and transcript reach Twilio and the HUD
    openai.send({ type: 'response.created', response: { id: 'r1' } });
    const chunk = Buffer.alloc(160, 0xff).toString('base64');   // 20 ms of mu-law
    openai.send({ type: 'response.output_audio.delta', item_id: 'item1', delta: chunk });
    openai.send({ type: 'response.output_audio_transcript.delta', item_id: 'item1', delta: 'Thank you for calling ' });
    openai.send({ type: 'response.output_audio_transcript.delta', item_id: 'item1', delta: 'Sub-Dimensional Support.' });
    await until(() => tw.of('media').length === 1 && tw.of('mark').length === 1, 1000, 'audio to Twilio');
    assert.equal(tw.of('media')[0].media.payload, chunk);
    assert.equal(tw.of('media')[0].streamSid, 'MZ1');
    await until(() => game.notes('ship/transcript').some((n) => n.params.text === 'Thank you for calling Sub-Dimensional Support.'), 1000, 'transcript');
    assert.equal(game.notes('ship/transcript').at(-1).params.role, 'agent');
    assert.equal(game.notes('ship/transcript').at(-1).params.item_id, 'item1');

    // a tool call runs on the game and its output goes back after response.done
    openai.send({ type: 'response.function_call_arguments.done', call_id: 'call_1', name: 'fly_to_feature', arguments: '{"feature_id":"#2312"}' });
    await until(() => game.calls.some((c) => c.name === 'fly_to_feature' && c.arguments.feature_id === '#2312'), 1000, 'tools/call');
    assert.equal(openai.of('conversation.item.create').filter((e) => e.item.type === 'function_call_output').length, 0, 'outputs wait for response.done');
    openai.send({ type: 'response.done', response: { id: 'r1', status: 'completed', output: [{ type: 'function_call', call_id: 'call_1', name: 'fly_to_feature', arguments: '{"feature_id":"#2312"}' }] } });
    const out = await until(() => openai.of('conversation.item.create').find((e) => e.item.type === 'function_call_output'), 1000, 'function_call_output');
    assert.equal(out.item.call_id, 'call_1');
    assert.equal(JSON.parse(out.item.output).message, 'did fly_to_feature');
    await until(() => openai.of('response.create').length === 2, 1000, 'response after tool output');
    assert.equal(game.calls.filter((c) => c.name === 'fly_to_feature').length, 2, 'the duplicate in response.done is not run twice (one /mcp call + one here)');

    // a game event the agent should hear arrives as a system message; while a
    // response is active its response.create waits
    openai.send({ type: 'response.created', response: { id: 'r2' } });
    game.sendEvent({ kind: 'pilot_input_required', summary: 'Issue #48213 needs the pilot.', notify_agent: true, issue_id: '#48213' });
    game.sendEvent({ kind: 'stage', summary: 'quiet', notify_agent: false });
    const sys = await until(() => openai.of('conversation.item.create').find((e) => e.item.role === 'system'), 1000, 'system message');
    assert.match(sys.item.content[0].text, /^SHIP EVENT \(pilot_input_required\): Issue #48213/);
    assert.equal(sys.item.content[0].type, 'input_text');
    await new Promise((r) => setTimeout(r, 50));
    assert.equal(openai.of('response.create').length, 2, 'no response.create while one is active');
    assert.equal(openai.of('conversation.item.create').filter((e) => e.item.role === 'system').length, 1, 'events without notify_agent stay out');
    openai.send({ type: 'response.done', response: { id: 'r2', status: 'completed', output: [] } });
    await until(() => openai.of('response.create').length === 3, 1000, 'deferred response.create');

    // barge-in: Twilio has played 20 ms of item2 when the caller talks over it
    openai.send({ type: 'response.created', response: { id: 'r3' } });
    openai.send({ type: 'response.output_audio.delta', item_id: 'item2', delta: chunk });
    openai.send({ type: 'response.output_audio.delta', item_id: 'item2', delta: chunk });
    await until(() => tw.of('mark').length === 3, 1000, 'marks');
    tw.send({ event: 'mark', streamSid: 'MZ1', mark: { name: tw.of('mark')[1].mark.name } });
    await new Promise((r) => setTimeout(r, 30));
    openai.send({ type: 'input_audio_buffer.speech_started', audio_start_ms: 1000, item_id: 'u1' });
    const trunc = await until(() => openai.of('conversation.item.truncate')[0], 1000, 'truncate');
    assert.deepEqual(trunc, { type: 'conversation.item.truncate', item_id: 'item2', content_index: 0, audio_end_ms: 20 });
    await until(() => tw.of('clear').length === 1, 1000, 'clear');

    // caller transcript reaches the HUD
    openai.send({ type: 'conversation.item.input_audio_transcription.completed', item_id: 'u1', content_index: 0, transcript: ' Get me out of here! ' });
    await until(() => game.notes('ship/transcript').some((n) => n.params.role === 'caller' && n.params.text === 'Get me out of here!'), 1000, 'caller transcript');

    // a second caller gets the busy message
    const busy = await post(port, '/twilio/voice', 'From=%2B15550000000', { 'Content-Type': 'application/x-www-form-urlencoded' });
    assert.match(busy.text, /All of our agents are currently assisting/);

    // hang up
    tw.send({ event: 'stop', streamSid: 'MZ1', stop: { callSid: 'CA1' } });
    await until(() => game.notes('ship/call').some((n) => n.params.state === 'ended'), 1000, 'call ended');
    await until(() => !relay.activeCall, 1000, 'call cleared');
    await until(() => openai.sockets.every((s) => s.readyState !== 1), 1000, 'openai socket closed');
  });

  test('tools the game adds mid-call reach the live session', async () => {
    const tw = await twilioCall(port);
    await until(() => relay.activeCall, 2000, 'call');
    const before = openai.events.length;
    game.tools = [...FAKE_TOOLS, { name: 'open_airlock', description: 'open it', inputSchema: { type: 'object', properties: {} } }];
    game.announceToolsChanged();
    const upd = await until(() => openai.events.slice(before).find((e) => e.type === 'session.update' && e.session.tools?.length === 3), 2000, 'tools pushed');
    assert.equal(upd.session.tools[2].name, 'open_airlock');
    assert.deepEqual(relay.gameLink.tools.map((t) => t.name), ['get_ship_status', 'fly_to_feature', 'open_airlock']);
    const listed = JSON.parse((await post(port, '/mcp', JSON.stringify({ jsonrpc: '2.0', id: 9, method: 'tools/list' }))).text);
    assert.equal(listed.result.tools.length, 3, '/mcp sees the new tool too');
    game.tools = [...FAKE_TOOLS];
    game.announceToolsChanged();
    await until(() => relay.gameLink.tools.length === 2, 2000, 'tool removed');
    tw.ws.close();
    await until(() => !relay.activeCall, 1000, 'call cleared');
  });

  test('a media stream with a bad token is refused', async () => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/twilio/media`);
    await new Promise((r) => ws.on('open', r));
    const closed = new Promise((r) => ws.on('close', (code) => r(code)));
    ws.send(JSON.stringify({ event: 'start', streamSid: 'MZ9', start: { streamSid: 'MZ9', customParameters: { token: 'forged' } } }));
    assert.equal(await closed, 1008);
    assert.equal(relay.activeCall, null);
  });

  test('a call made while the game is offline tells the agent, and recovers when it connects', async () => {
    game.close();
    await until(() => !relay.gameLink.connected, 1000, 'link down');
    const before = openai.events.length;
    const tw = await twilioCall(port);
    await until(() => openai.events.slice(before).some((e) => e.type === 'conversation.item.create' && /link is down/.test(e.item.content?.[0]?.text ?? '')), 2000, 'link-down note');
    // the last known tools are kept, so the agent knows the controls; calling
    // one while the link is down says so
    const upd = openai.events.slice(before).find((e) => e.type === 'session.update');
    assert.equal(upd.session.tools.length, 2);
    const down = JSON.parse(await relay.gameLink.callTool('get_ship_status', {}));
    assert.equal(down.ok, false);
    assert.match(down.message, /link is down/);
    game = await fakeGame(port);
    await until(() => openai.events.slice(before).filter((e) => e.type === 'session.update').length === 2, 2000, 'tools pushed when the game connects');
    await until(() => openai.events.slice(before).some((e) => e.type === 'conversation.item.create' && /link is up/.test(e.item.content?.[0]?.text ?? '')), 2000, 'link-up note');
    await until(() => game.notes('ship/call').some((n) => n.params.state === 'connected'), 1000, 'sticky call state for the new game');
    tw.ws.close();
    await until(() => !relay.activeCall, 1000, 'call cleared');
  });
});

describe('ship link token', () => {
  test('/game and /mcp require SHIP_LINK_TOKEN when it is set', async () => {
    const { relay, port } = await startRelay(null, { SHIP_LINK_TOKEN: 'sesame' });
    try {
      const refused = new WebSocket(`ws://127.0.0.1:${port}/game`);
      await assert.rejects(new Promise((r, j) => { refused.on('open', r); refused.on('error', j); }));
      const game = await fakeGame(port, { token: 'sesame' });
      await until(() => relay.gameLink.connected, 2000, 'authorised game');
      const noAuth = await post(port, '/mcp', JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }));
      assert.equal(noAuth.status, 401);
      const ok = await post(port, '/mcp', JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping' }), { Authorization: 'Bearer sesame' });
      assert.equal(ok.status, 200);
      game.close();
    } finally {
      await relay.close();
    }
  });
});

describe('realtime session', () => {
  test('a rejected optional session field is dropped and the session resent', async () => {
    const { fakeOpenAI: mk } = await import('./helpers.js');
    const { RealtimeSession } = await import('../src/realtime-session.js');
    const openai = await mk();
    const s = new RealtimeSession({
      config: { url: `ws://127.0.0.1:${openai.port}/v1/realtime`, apiKey: 'k', model: 'gpt-realtime-2.1', voice: 'cedar', transcribeModel: 'gpt-4o-mini-transcribe', reasoningEffort: 'low' },
      instructions: 'hi', tools: [], onToolCall: async () => '{}', log: { info() {}, warn() {}, error() {} },
    }).connect();
    try {
      await until(() => openai.of('session.update').length === 1, 2000, 'first session.update');
      assert.deepEqual(openai.of('session.update')[0].session.reasoning, { effort: 'low' });
      openai.send({ type: 'error', error: { type: 'invalid_request_error', code: 'unknown_parameter', message: 'Unknown parameter', param: 'session.reasoning' } });
      await until(() => openai.of('session.update').length === 2, 2000, 'resent session.update');
      const again = openai.of('session.update')[1].session;
      assert.equal(again.reasoning, undefined);
      assert.equal(again.instructions, 'hi');
      assert.ok(again.audio.input.transcription, 'other optional fields stay');
      openai.send({ type: 'error', error: { type: 'invalid_request_error', message: 'bad', param: 'session.reasoning' } });
      await new Promise((r) => setTimeout(r, 50));
      assert.equal(openai.of('session.update').length, 2, 'each field is dropped once');
    } finally {
      s.close();
      await openai.close();
    }
  });
});
