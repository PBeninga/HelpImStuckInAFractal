#!/usr/bin/env node
// A scripted support call, no Twilio or OpenAI needed: runs the relay, waits
// for the game to dial in, then plays a canned conversation into the HUD while
// really flying the ship through its MCP tools, answering pilot-input issues
// as they come up, all the way out of the rift. For rehearsing the demo, for
// screenshots, and as a fallback when the venue Wi-Fi gives up.
//
//   npm run demo                (then start the game: Engage Hyperdrive)
//   npm run demo -- --fast      shorter pauses

import { loadDotEnv, loadConfig } from '../src/config.js';
import { createRelay } from '../src/server.js';

loadDotEnv();
const config = loadConfig();
const fast = process.argv.includes('--fast');
const relay = createRelay({ config, log: { info() {}, warn: console.warn, error: console.error } });
const port = await relay.listen();
const link = relay.gameLink;
const agent = config.agentName;
const sleep = (s) => new Promise((r) => setTimeout(r, (fast ? s * 0.4 : s) * 1000));
let n = 0;

console.log(`Demo call relay on port ${port}. Start the game and choose Engage Hyperdrive.`);

const events = [];
const pendingIssues = [];
link.on('event', (ev) => {
  events.push(ev);
  if (ev.kind === 'pilot_input_required') pendingIssues.push(ev);
  console.log(`  [ship event] ${ev.kind}: ${ev.summary}`);
});

async function say(role, text, seconds = Math.min(7, 1.2 + text.length / 22)) {
  const id = `demo${++n}`;
  // stream the line in a few chunks, like a live transcript
  const words = text.split(' ');
  const step = Math.max(1, Math.ceil(words.length / 4));
  for (let i = step; i < words.length; i += step) {
    link.notify('ship/transcript', { role, item_id: id, text: words.slice(0, i).join(' '), final: false });
    await sleep(0.25);
  }
  link.notify('ship/transcript', { role, item_id: id, text, final: true });
  console.log(`${role === 'agent' ? agent : 'pilot'}: ${text}`);
  await sleep(seconds);
}

async function tool(name, args = {}) {
  const out = JSON.parse(await link.callTool(name, args));
  console.log(`  [tool] ${name} ${JSON.stringify(args)} -> ${out.message ?? ''}`);
  return out;
}

async function waitFor(pred, seconds = 60) {
  const t0 = Date.now();
  while (Date.now() - t0 < seconds * 1000) {
    const hit = events.find(pred);
    if (hit) {
      events.splice(events.indexOf(hit), 1);
      return hit;
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  return null;
}

const CANNED_ANSWERS = ['Sparkles', 'Forty-two', 'The left one, obviously', 'No... maybe a little', 'Smooth jazz', 'Keep them all', 'Practical'];

async function answerIssues() {
  while (pendingIssues.length) {
    const ev = pendingIssues.shift();
    if (ev.blocks_exit) {
      await say('agent', `Last bit of paperwork, sorry. The rift wants a signed egress waiver, issue ${ev.issue_id.replace('#', '')}. Can you state your full name and agree we're not liable for any extra dimensions you bring home?`);
      await say('caller', 'Ada Lovelace. And yes, I agree, just get me out of here.');
      await tool('resolve_issue', { issue_id: ev.issue_id, answer: 'Ada Lovelace' });
      await say('agent', 'Lovely, waiver signed. Rift is unlocked.');
    } else {
      await say('agent', `Quick one from diagnostics while we fly: ${ev.question}`);
      const answer = CANNED_ANSWERS[Math.floor(Math.random() * CANNED_ANSWERS.length)];
      await say('caller', `Uh... ${answer}?`);
      await tool('resolve_issue', { issue_id: ev.issue_id, answer });
      await say('agent', "Perfect, I've logged that. Moving on.", 1.5);
    }
  }
}

async function flyLeg(id, line) {
  await tool('highlight', { target: id });
  await tool('post_to_log', { message: `Identified Mandelbrought characteristic ${id}, drawing attention and configuring flight path.` });
  await say('agent', line);
  const r = await tool('fly_to_feature', { feature_id: id });
  if (!r.ok) return false;
  await waitFor((e) => e.kind === 'waypoint_reached' || e.kind === 'arrived', 40);
  await answerIssues();
  return true;
}

await new Promise((resolve) => (link.connected ? resolve() : link.once('ready', resolve)));
console.log('Game connected. Waiting for the crash report to finish...');
await waitFor((e) => e.kind === 'stage' && e.stage === 'awaiting_call', 120);
await sleep(4);

link.notify('ship/call', { state: 'ringing' }, { sticky: true });
await sleep(2);
link.notify('ship/call', { state: 'connected', agent_name: agent }, { sticky: true });
await sleep(1);
await say('agent', `Thank you for calling Sub-Dimensional Support, you're through to ${agent} in Tier 2. I can see your ticket here... ah. You've punched yourself into a fractal.`);
await say('caller', "Yeah. What happened? I just pressed the jump button.");
const status = await tool('get_ship_status');
await say('agent', `Right, so, technically: your jump vector clipped a box fold at scale minus two point oh nine, got sphere-inverted between radius ${status.fractal.min_radius} and ${status.fractal.fixed_radius}, and your running derivative went to infinity, which collapsed the Lipschitz bound. You're now living on a surface of Hausdorff dimension about two point eight. Very fashionable.`, 6);
await say('caller', 'Can you get me out?');
await tool('scan_surroundings');
await say('agent', "Absolutely. Running a sensor sweep now. This call may be recorded for quality and training purposes across all branches of the fractal.");
await flyLeg('#2312', "See characteristic twenty-three twelve, off to your left? The Recursive Cul-de-sac. It's a dead end at every scale except this one, which makes it our way out. Flying you over now.");
await say('agent', 'Lovely. Next is the Box-Fold Bypass, just around the corner. Mind the clamp.');
await flyLeg('#4096', 'Characteristic forty ninety-six, highlighted for you. Engaging autopilot.');
await flyLeg('#7071', "Now the Lipschitz Narrows. The distance estimate here is honest but unforgiving, so I'll take it.");
await say('agent', 'See that glow at the end of the tunnel? That is not a metaphor, that is the exit rift.');
await flyLeg('#8128', 'Characteristic eighty-one twenty-eight, the Outer Aperture. Normal space on the other side.');
await waitFor((e) => e.kind === 'pilot_input_required', 4);
await answerIssues();
await tool('highlight', { target: '#9001', label: 'EXIT' });
await say('agent', 'Right, that swirly hole is characteristic nine thousand and one, the Egress Rift. Hold on to something.');
await tool('fly_to_feature', { feature_id: '#9001' });
await waitFor((e) => e.kind === 'escaped', 40);
await say('agent', 'And you are out! Welcome back to ordinary three-space. Could you rate this call from one to five fractal dimensions?');
await say('caller', 'Five. Definitely five.');
await say('agent', 'Wonderful. Thank you for calling Sub-Dimensional Support, and mind the folds.', 3);
link.notify('ship/call', { state: 'ended' }, { sticky: true });
console.log('Demo call finished. Ctrl+C to stop the relay.');
