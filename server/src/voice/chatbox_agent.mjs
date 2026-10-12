// Text-only access to the same support agent and ship tools used on calls.
export function connectChatboxAgent(game, voice, config, { phoneBusy = () => false } = {}) {
  const current = () => voice.current?.transport === 'chatbox' ? voice.current : null;
  const error = (message, callSid) => game.notify({ type: 'chat_agent_error', message, callSid });
  game.on('chat_agent_control', async (msg) => {
    // A session id scopes delayed stop/error events to their original session.
    // Authentication comes from the game link, not this identifier.
    if (typeof msg.callSid !== 'string' || !/^chatbox-[\w-]{1,100}$/.test(msg.callSid)) return;
    if (msg.action === 'stop') {
      const call = current();
      if (call && msg.callSid === call.callSid) call.end('Text agent disconnected');
      return;
    }
    if (msg.action !== 'start') return;
    const callSid = msg.callSid;
    if (voice.busy || phoneBusy()) return error('A support session is already active. End it before starting text mode.', callSid);
    if (!config.openai.apiKey) return error('The server needs OPENAI_API_KEY to start the text agent.', callSid);
    const call = voice.newCall({ callSid, transport: 'chatbox', mode: 'text' });
    const timeout = setTimeout(() => call.end('Text agent connection timed out'), 15_000);
    call.on('ready', () => {
      clearTimeout(timeout);
      game.notify({ type: 'chat_agent_ready', callSid });
    });
    call.on('ended', () => clearTimeout(timeout));
    call.on('api_error', (e) => error(e.message || 'Agent API request failed.', callSid));
    try { await call.start(); } catch (e) { call.end(`Could not start the text agent: ${e.message}`); }
  });
  game.on('disconnected', () => current()?.end('Game link disconnected'));
  game.on('connected', () => current()?.end('Game link replaced'));
}
