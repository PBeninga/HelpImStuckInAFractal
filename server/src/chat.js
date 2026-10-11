// Talk to the support agent by typing, with no phone: the same agent, tools
// and ship link as a call, but the Realtime session runs in text mode. Handy
// for trying the persona and the ship controls before wiring up Twilio.

import readline from 'node:readline';

export function runChat({ relay, config, input = process.stdin, output = process.stdout }) {
  return new Promise((resolve) => {
    const call = relay.newCall('text');
    if (!call) {
      output.write('A call is already in progress.\n');
      resolve();
      return;
    }
    const rl = readline.createInterface({ input, output, prompt: 'you> ' });
    call.on('transcript', (t) => {
      if (t.role === 'agent' && t.final && t.text) {
        output.write(`\r${config.agentName}> ${t.text}\n`);
        rl.prompt();
      }
    });
    call.on('tool_result', ({ name, args }) => {
      output.write(`\r  [ship] ${name} ${JSON.stringify(args)}\n`);
    });
    call.on('api_error', (e) => output.write(`\r  [openai error] ${e.message ?? JSON.stringify(e)}\n`));
    call.on('ended', (reason) => {
      output.write(`\n[call ended: ${reason}]\n`);
      rl.close();
    });
    rl.on('line', (line) => {
      const text = line.trim();
      if (text === '/quit' || text === '/hangup') {
        call.end('the pilot hung up');
        return;
      }
      if (text) call.session.sendUserText(text);
      rl.prompt();
    });
    rl.on('close', () => {
      call.end('the pilot hung up');
      resolve();
    });
    output.write(`Calling Sub-Dimensional Support (text). Type to talk; /quit to hang up.\n`);
    call.start();
  });
}
