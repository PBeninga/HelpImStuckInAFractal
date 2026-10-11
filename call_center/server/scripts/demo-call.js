#!/usr/bin/env node
// A scripted support call, no Twilio or OpenAI needed: runs the relay, waits
// for the game to dial in, then plays a canned conversation into the HUD while
// really flying the ship through its MCP tools: it follows whatever route the
// game exposes (get_ship_status.next_waypoint), answers pilot-input issues as
// they come up, and flies into the exit once it is unlocked. For rehearsing
// the demo, for screenshots, and as a fallback when the venue Wi-Fi gives up.
//
//   npm run demo                (then: call_center/run.sh --demo from the repo root)
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

console.log(`Demo call relay on port ${port}. Start the game: call_center/run.sh --demo (from the repo root).`);

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
      await say('agent', `Last bit of paperwork before the exit opens, sorry. ${ev.question.replace(/^Ask the pilot to /, 'Could you ').replace(/\btheir\b/g, 'your').replace(/\bthey\b/g, 'you')}`);
      await say('caller', 'Ada Lovelace. And yes, I agree, just get me out of here.');
      await tool('resolve_issue', { issue_id: ev.issue_id, answer: 'Ada Lovelace' });
      await say('agent', 'Lovely, all signed. The exit is unlocked.');
    } else {
      await say('agent', `Quick one from diagnostics while we fly: ${ev.question}`);
      const answer = CANNED_ANSWERS[Math.floor(Math.random() * CANNED_ANSWERS.length)];
      await say('caller', `Uh... ${answer}?`);
      await tool('resolve_issue', { issue_id: ev.issue_id, answer });
      await say('agent', "Perfect, I've logged that. Moving on.", 1.5);
    }
  }
}

const say_id = (id) => {
  const n = id.replace('#', '');
  return n.length === 4 ? `${n.slice(0, 2)} ${n.slice(2)}`.replace(/^0/, '') : n;
};

// One leg: point it out, log it, say something about it, fly, wait to arrive.
async function flyLeg(wp, first) {
  await tool('highlight', { target: wp.feature_id });
  await tool('post_to_log', { message: `Identified Mandelbrought characteristic ${wp.feature_id}, drawing attention and configuring flight path.` });
  const intro = first
    ? `See characteristic ${say_id(wp.feature_id)}, ${wp.direction}? ${wp.name}. ${wp.description} That's our way out. Flying you over now.`
    : `Next up, characteristic ${say_id(wp.feature_id)}, ${wp.name}, ${wp.range_m} metres ${wp.direction}. ${wp.description}`;
  await say('agent', intro);
  const r = await tool('fly_to_feature', { feature_id: wp.feature_id });
  if (!r.ok) {
    await say('agent', "Hm. The autopilot doesn't like that line. Let me find another way.");
    return false;
  }
  await waitFor((e) => ['waypoint_reached', 'arrived', 'escaped'].includes(e.kind), 60);
  await answerIssues();
  return true;
}

await new Promise((resolve) => (link.connected ? resolve() : link.once('ready', resolve)));
console.log('Game connected. Waiting for the crash report to finish...');
await waitFor((e) => e.kind === 'stage' && e.stage === 'awaiting_call', 180);
await sleep(4);

link.notify('ship/call', { state: 'ringing' }, { sticky: true });
await sleep(2);
link.notify('ship/call', { state: 'connected', agent_name: agent }, { sticky: true });
await sleep(1);
await say('agent', `Thank you for calling Sub-Dimensional Support, you're through to ${agent} in Tier 2. I can see your ticket here... ah. You've punched yourself into a fractal.`);
await say('caller', 'Yeah. What happened? I just pressed the jump button.');
const status = await tool('get_ship_status');
const w = status.world ?? {};
await say('agent', w.type === 'Mandelbox'
  ? `Right, so, technically: your jump vector clipped a box fold at scale minus ${String(Math.abs(w.scale)).replace('.', ' point ')}, got sphere-inverted between radius ${w.min_radius} and ${w.fixed_radius}, and your running derivative went to infinity, which collapsed the Lipschitz bound. You're now living on a surface of Hausdorff dimension about two point eight. Very fashionable.`
  : "Right, so, technically: your jump vector hit an iterated function system head on and your manifolds came back as animalifolds. Very fashionable.", 6);
await say('caller', 'Can you get me out?');
await tool('scan_surroundings');
await say('agent', 'Absolutely. Running a sensor sweep now. This call may be recorded for quality and training purposes across all branches of the fractal.');

let first = true;
for (let legs = 0; legs < 12; legs++) {
  const s = await tool('get_ship_status');
  if (!s.in_flight || !s.next_waypoint) break;
  const wp = s.next_waypoint;
  if (wp.kind === 'exit') {
    if (s.exit?.locked) {
      await waitFor((e) => e.kind === 'pilot_input_required', 3);
      await answerIssues();
    }
    await tool('highlight', { target: wp.feature_id, label: 'EXIT' });
    await say('agent', `Right, that's characteristic ${say_id(wp.feature_id)}, ${wp.name}. Hold on to something.`);
    await tool('fly_to_feature', { feature_id: wp.feature_id });
    const done = await waitFor((e) => e.kind === 'escaped' || e.kind === 'exit_refused', 60);
    if (done?.kind === 'escaped') break;
    await answerIssues();
    continue;
  }
  if (!(await flyLeg(wp, first))) break;
  first = false;
}
await say('agent', 'And you are out! Welcome back to ordinary three-space. Could you rate this call from one to five fractal dimensions?');
await say('caller', 'Five. Definitely five.');
await say('agent', 'Wonderful. Thank you for calling Sub-Dimensional Support, and mind the folds.', 3);
link.notify('ship/call', { state: 'ended' }, { sticky: true });
console.log('Demo call finished. Ctrl+C to stop the relay.');
