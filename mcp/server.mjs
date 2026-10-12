#!/usr/bin/env node
// MCP server for Help I'm Stuck In A Fractal.
//
// Speaks MCP over stdio and relays each tool call to the running game's
// McpBridge autoload (src/mcp/mcp_bridge.gd) over a localhost TCP socket that
// carries newline-delimited JSON. `launch_game` can start the game itself.
//
//   FRACTAL_MCP_PORT  bridge port (default 9077)
//   GODOT             Godot 4 binary, passed through to tools/launch.sh

import net from "node:net";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const PORT = Number(process.env.FRACTAL_MCP_PORT || 9077);
const HOST = "127.0.0.1";
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const TIMEOUT_MS = 30_000;

// ---------------------------------------------------------------- bridge client

let socket = null;
let buffer = "";
let nextId = 1;
const pending = new Map(); // id -> {resolve, reject, timer}

function connect() {
  return new Promise((resolve, reject) => {
    const s = net.createConnection({ host: HOST, port: PORT });
    s.setEncoding("utf8");
    s.once("connect", () => {
      socket = s;
      buffer = "";
      resolve(s);
    });
    s.once("error", (err) => {
      if (socket !== s) reject(err);
    });
    s.on("data", (chunk) => {
      buffer += chunk;
      let nl;
      while ((nl = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, nl);
        buffer = buffer.slice(nl + 1);
        if (!line.trim()) continue;
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          continue;
        }
        const p = pending.get(msg.id);
        if (!p) continue;
        pending.delete(msg.id);
        clearTimeout(p.timer);
        if (msg.ok) p.resolve(msg.result);
        else p.reject(new Error(msg.error));
      }
    });
    s.on("close", () => {
      if (socket === s) socket = null;
      for (const [id, p] of pending) {
        clearTimeout(p.timer);
        p.reject(new Error("the game closed the connection"));
        pending.delete(id);
      }
    });
  });
}

async function call(cmd, args = {}, timeoutMs = TIMEOUT_MS) {
  if (!socket) {
    try {
      await connect();
    } catch {
      throw new Error(
        `The game is not running (nothing on ${HOST}:${PORT}). Call launch_game, or start it with ./run.sh.`,
      );
    }
  }
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`'${cmd}' timed out after ${timeoutMs / 1000}s`));
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    socket.write(JSON.stringify({ id, cmd, args }) + "\n");
  });
}

// ---------------------------------------------------------------- tool helpers

const json = (value) => ({ content: [{ type: "text", text: JSON.stringify(value, null, 2) }] });

const image = (shot) => ({
  type: "image",
  data: shot.data,
  mimeType: shot.format === "jpeg" ? "image/jpeg" : "image/png",
});

const fail = (err) => ({ content: [{ type: "text", text: String(err.message || err) }], isError: true });

const vec3 = z.tuple([z.number(), z.number(), z.number()]);
const vec2 = z.tuple([z.number(), z.number()]);
const color = z
  .union([z.string(), z.array(z.number()).min(3).max(4)])
  .describe('"#rrggbb[aa]", a colour name like "red", or [r, g, b(, a)] in 0..1');
const duration = z.number().min(0).max(30).optional().describe("Seconds to animate the move (0 = jump)");
const look = z
  .boolean()
  .optional()
  .describe("Also return a screenshot after the move (default false)");

const INSTRUCTIONS = `Pilots a camera through a live 3D Mandelbox fractal (the Godot game "Help I'm Stuck In A Fractal") and draws on its screen.

On launch read shape_run from status: the ordered stages, required commands, active_shape and spawn-centered escape distances. Only the gameplay-active shape is visible. Apply scripted edits with apply_shape_command, never set_shape. Only act in response to a NEW human utterance, one command per utterance. Never change shapes on startup, timers or system events. Refresh status after the person speaks and pass run_id, active_shape as shape_index, command_index, human_turn and next_command. A stage advances only after its commands and escape distance; wait for its fog transition. Only the final stage completes escape.

The person talks to you through the pilot chat on the right of the game window (typed now, voice later). To pilot for them: launch_game if needed, then loop: wait_for_message -> act on the request with the camera/shape/draw tools (look at the result with screenshot or look: true) -> say a short reply -> wait_for_message again. Keep replies brief: they appear in a narrow in-game panel and may be spoken aloud later. Prefer animated moves (duration 0.5-2 s) so the person can follow the flight.`;

const server = new McpServer({ name: "fractal", version: "0.2.0" }, { instructions: INSTRUCTIONS });

// Registers a tool that forwards its arguments to one bridge command. With
// `withLook`, a `look: true` argument appends a screenshot of the new view.
function relay(name, cmd, description, shape, { withLook = false } = {}) {
  const inputSchema = withLook ? { ...shape, look } : shape;
  server.registerTool(name, { description, inputSchema }, async (args = {}) => {
    try {
      const { look: wantLook, ...rest } = args;
      const result = await call(cmd, rest);
      const out = json(result);
      if (withLook && wantLook) out.content.push(image(await call("screenshot", { max_width: 768 })));
      return out;
    } catch (err) {
      return fail(err);
    }
  });
}

// ---------------------------------------------------------------- lifecycle

server.registerTool(
  "launch_game",
  {
    description:
      "Start the game (Godot) with the bridge enabled, straight into the explorer, and wait until it " +
      "answers. Like Spellgraft's tools/launch.sh it stays out of the way: the window is parked off " +
      "screen bar a 4px always-on-top corner (it still renders; screenshots are full size) and focus " +
      "is handed back to whatever app had it. foreground: true opens a normal window that keeps focus, " +
      "for a person to watch. Does nothing if the game is already running.",
    inputSchema: {
      foreground: z.boolean().optional().describe("Normal, focused window instead of parked (default false)"),
      call_center: z
        .enum(["off", "on", "demo"])
        .optional()
        .describe("Start the call centre (call_center/) too: its HUD, diagnostics log and ship tools; 'demo' is a compatibility alias (default off)"),
    },
  },
  async ({ foreground = false, call_center = "off" } = {}) => {
    try {
      return json({ already_running: true, ...(await call("status")) });
    } catch {}
    const gameArgs = ["--play", foreground ? "--foreground-window" : "--background-window"];
    if (call_center === "on") gameArgs.push("--call-center");
    if (call_center === "demo") gameArgs.push("--call-center-demo");
    const child = spawn(path.join(REPO, "tools", "launch.sh"), ["--", ...gameArgs], {
      cwd: REPO,
      detached: true,
      stdio: "ignore",
      env: { ...process.env, FRACTAL_MCP_PORT: String(PORT) },
    });
    child.unref();
    const deadline = Date.now() + 60_000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 500));
      try {
        const status = await call("status");
        if (status.in_game) return json({ launched: true, parked: !foreground, ...status });
      } catch {}
    }
    return fail(new Error("The game did not answer within 60 s. Is Godot installed (set GODOT=/path/to/godot)?"));
  },
);

relay("status", "status", "Where things stand: scene, pause state, camera, window size, drawings and trail.", {});

relay(
  "start_game",
  "start_game",
  "Leave the title menu (or the pause menu) and open the fractal explorer.",
  {},
);

// ---------------------------------------------------------------- traversal

server.registerTool(
  "find_nearest_surface",
  {
    description: "Help a lost player who asks to be pointed back toward the shape. Cast rays in all directions and face the closest confirmed surface hit, keeping position and speed. Cancels any active ship manoeuvre on success. Returns ok, message, hit distance in world units and camera state; a miss leaves the view unchanged. This points at a surface, not an escape route.",
    inputSchema: {},
  },
  async () => {
    try {
      const result = await call("find_nearest_surface");
      return { ...json(result), isError: result.ok === false || Boolean(result.error) };
    } catch (err) {
      return fail(err);
    }
  },
);

const COORDS =
  "All positions are fractal coordinates (the space the distance estimator is evaluated in); " +
  "+Z is world up. The default view puts the eye at (8.18, 3.81, 3.28) looking at the origin.";

relay(
  "get_camera",
  "get_camera",
	"The camera: eye, forward/up/right unit vectors, speed factor, surface_distance, facing direction, and " +
	"a low-fidelity multidirectional estimate of nearby geometry (ray count is tunable in Gameplay). " +
    COORDS,
  {},
);

relay(
  "get_depth_scan",
  "get_depth_scan",
  "Read the cached screen depth scan. Compact summary by default; set include_grid for a bounded 2D " +
    "distance array and status mask. Local capture runs every few frames, but agent delivery is request-only, " +
    "rate-limited to once per two seconds. Use after_frame to avoid repeats. Respect captured pose, age and censored cells.",
  {
    include_grid: z.boolean().optional(),
    after_frame: z.number().int().nonnegative().optional(),
    max_columns: z.number().int().min(8).max(64).optional(),
  },
);

relay(
  "scan_ship_depth",
  "scan_ship_depth",
  "EXPENSIVE on-demand raycast scan. Supply direction for a wide cone around a candidate (default 90 degrees); " +
    "omit it for the full ship sphere. Compact depth recommendations and status counts by default; " +
    "include_rays=true requests per-ray depths. Pass recommended directions to the ship tool " +
    "plan_escape.candidate_directions for travel-time ranking. CPU geometry excludes shader-only " +
    "displacement. 96 rays by default; max 256, 8-second work budget, 5-second cooldown. " +
    "Partial coverage and stale pose are explicit. Do not poll; nothing is streamed. " +
    "Recommended look_at points are for turning, not flight destinations.",
  {
    direction: vec3.optional().describe("Nonzero world direction, not a destination point"),
    cone_degrees: z.number().min(15).max(180).optional().describe("Full cone angle, default 90; requires direction"),
    include_rays: z.boolean().optional(),
    ray_count: z.number().int().min(24).max(256).optional(),
    max_distance: z.number().positive().optional().describe("World units; defaults to twice the exit-sphere radius"),
  },
);

relay(
  "set_camera",
  "set_camera",
  "Place the camera. Give any of eye, look_at (a point to face) or forward (a direction), and up " +
    "(default +Z). Omitted parts keep their current value. " +
    COORDS,
  {
    eye: vec3.optional(),
    look_at: vec3.optional(),
    forward: vec3.optional(),
    up: vec3.optional(),
    speed_factor: z.number().optional().describe("The fly camera's speed multiplier (0.01..100)"),
    duration,
  },
  { withLook: true },
);

relay(
  "move",
  "move",
	"Move the camera in its own frame, ignoring geometry and movement bounds by default. By default distances are in 'surface' units: multiples of the " +
    "current distance to the nearest surface, so forward: 0.5 always closes half the gap whatever the " +
    "zoom depth. This is how to travel deeper into the fractal. Set safe: true only when you want a " +
    "raycast to stop short of surfaces along the path.",
  {
    forward: z.number().optional(),
    right: z.number().optional(),
    up: z.number().optional(),
    units: z.enum(["surface", "world"]).optional().describe("Default 'surface'"),
    safe: z.boolean().optional(),
    duration,
  },
  { withLook: true },
);

relay(
  "rotate",
  "rotate",
  "Turn the camera, in degrees: yaw (positive = left, about world +Z), pitch (positive = up), roll " +
    "(positive = clockwise).",
  {
    yaw: z.number().optional(),
    pitch: z.number().optional(),
    roll: z.number().optional(),
    duration,
  },
  { withLook: true },
);

relay(
  "dive",
  "dive",
  "Fly toward the surface under a window pixel (default: the centre of the view), covering `fraction` " +
    "of the way (default 0.5) and turning to face that point. Repeat to zoom into a feature.",
  {
    x: z.number().optional().describe("Window pixel x (logical units, see status.view_size)"),
    y: z.number().optional(),
    fraction: z.number().min(0).max(0.99).optional(),
    duration,
  },
  { withLook: true },
);

relay(
  "raycast",
  "raycast",
  "What is under a window pixel (default: centre): the surface point, its distance from the eye and " +
    "its normal, or hit: false. Use the point to anchor world-space drawings or as a set_camera target.",
  { x: z.number().optional(), y: z.number().optional() },
);

relay(
  "probe",
  "probe",
  "The distance estimate at a world point: roughly how far it is from the nearest surface (0 or tiny = on it).",
  { point: vec3 },
);

relay(
  "project",
  "project",
  "The window pixel a world point appears at, or visible: false if it is behind the camera.",
  { point: vec3 },
);

// ---------------------------------------------------------------- shape / views

relay(
  "apply_shape_command", "apply_shape_command",
  "Apply only the active stage's next scripted command in response to a new human utterance, never unprompted. Read shape_run from fresh status and copy its run_id, active_shape as shape_index, command_index, human_turn and next_command. One command per utterance; rejects stale or duplicate requests.",
  { command: z.string(), run_id: z.string(), shape_index: z.number().int().min(0),
    command_index: z.number().int().min(0), human_turn: z.number().int().min(1) },
);


relay(
  "get_shape",
  "get_shape",
  "Every Mandelbox parameter: id, group, type, current value, range or options, and what it does " +
    "(box_scale, fold_limit, min_radius, fixed_radius, Julia mode and constants, iteration rotations, " +
    "w, color_mode, precision).",
  {},
);

relay(
  "set_shape",
  "set_shape",
  "Change Mandelbox parameters by id, e.g. {values: {box_scale: -1.5, color_mode: 3}}. Values are " +
    "sanitised to each parameter's hard range; the result shows what was applied.",
  { values: z.record(z.string(), z.union([z.number(), z.boolean()])) },
  { withLook: true },
);

relay("list_views", "list_views", "Saved views (camera + shape) in the saves folder.", {});

relay(
  "load_view",
  "load_view",
  "Load a saved view by name (see list_views), e.g. 'juliaIceField'.",
  { name: z.string() },
  { withLook: true },
);

relay(
  "save_view",
  "save_view",
  "Save the current camera, shape and noise field as a named view in the saves folder.",
  { name: z.string() },
);

// ---------------------------------------------------------------- seeing

server.registerTool(
  "screenshot",
  {
    description:
      "See the screen. Waits for the full-quality still frame, then returns the window as an image. " +
      "overlay=false returns the bare fractal without drawings or UI.",
    inputSchema: {
      overlay: z.boolean().optional().describe("Include drawings and UI (default true)"),
      max_width: z.number().int().min(64).max(4096).optional().describe("Downscale to this width (default 1024)"),
      format: z.enum(["png", "jpeg"]).optional(),
    },
  },
  async (args = {}) => {
    try {
      const shot = await call("screenshot", args);
      return {
        content: [image(shot), { type: "text", text: `${shot.width}x${shot.height} ${shot.format}` }],
      };
    } catch (err) {
      return fail(err);
    }
  },
);

// ---------------------------------------------------------------- pilot chat

server.registerTool(
  "wait_for_message",
  {
    description:
      "Wait for the person to say something in the in-game pilot chat, and return the messages you have " +
      "not seen yet (each {id, text, source: 'typed' | 'voice'}). While you wait the chat shows you as " +
      "listening; after this returns messages it shows you as working until you wait again. Returns " +
      "timed_out: true with no messages if nothing arrives in `timeout` seconds: just call it again.",
    inputSchema: {
      timeout: z.number().min(0).max(300).optional().describe("Seconds to wait (default 25)"),
    },
  },
  async ({ timeout = 25 } = {}) => {
    try {
      return json(await call("chat_wait", { timeout }, (timeout + 15) * 1000));
    } catch (err) {
      return fail(err);
    }
  },
);

relay(
  "say",
  "chat_say",
  "Post your reply in the in-game pilot chat. Keep it short (a sentence or two): the panel is narrow and " +
    "replies may be spoken aloud later.",
  { text: z.string().min(1) },
);

relay(
  "chat_history",
  "chat_history",
  "The recent pilot chat, both sides, oldest first.",
  { limit: z.number().int().min(1).max(500).optional().describe("Default 50") },
);

server.registerPrompt(
  "pilot",
  {
    description: "Fly the fractal for the person, taking requests from the in-game pilot chat.",
  },
  () => ({
    messages: [
      {
        role: "user",
        content: {
          type: "text",
          text:
            "Pilot the fractal for me. Launch the game if it is not running, say hello in the pilot chat, " +
            "then keep looping: wait_for_message, carry out what I ask (fly, dive, turn, change the shape, " +
            "draw or point things out, take screenshots to check), and say a short reply. When " +
            "wait_for_message times out, just wait again. Stop only when I say stop or goodbye in the chat.",
        },
      },
    ],
  }),
);

// ---------------------------------------------------------------- the call centre's ship

server.registerTool(
  "ship_tools",
  {
    description:
      "The call centre's ship tools (when the game runs with it: launch_game {call_center: 'on'}): " +
      "high-level controls built for a support agent, each with its JSON input schema: get_ship_status, " +
      "scan_surroundings (multidirectional geometry), get_depth_scan (on-demand cached screen depth), scan_ship_depth (expensive full-sphere depth), plan_escape, turn_ship, thrust, " +
      "fly_to_point (coordinate navigation at Gameplay speed), resolve_issue (answer a diagnostics question with " +
      "the person's words), post_to_log, and any the game adds. Run one with `ship`.",
    inputSchema: {},
  },
  async () => {
    try {
      return json(await call("ship_tools"));
    } catch (err) {
      return fail(err);
    }
  },
);

server.registerTool(
  "ship",
  {
    description: "Run one of the call centre's ship tools (see ship_tools), e.g. {name: 'fly_to_point', arguments: {point: [12, 3, 2]}}.",
    inputSchema: {
      name: z.string(),
      arguments: z.record(z.string(), z.any()).optional(),
    },
  },
  async ({ name, arguments: args = {} }) => {
    try {
      const r = await call("ship_tool", { name, arguments: args });
      return { ...json(r), isError: r.ok === false };
    } catch (err) {
      return fail(err);
    }
  },
);

relay(
  "ship_events",
  "ship_events",
  "Compact call-centre events: instruction completion/cancellation, throttled autopilot slowdown " +
    "with motion direction and speed change, and escape. No depth arrays. Without `after` returns just the newest id; with it, " +
    "waits up to `timeout` seconds for events after that id.",
  {
    after: z.number().int().optional(),
    timeout: z.number().min(0).max(25).optional().describe("Seconds to wait (default 20, at most 25)"),
  },
);

// ---------------------------------------------------------------- drawing

relay(
  "draw",
  "draw",
  "Draw on the screen over the fractal. type: line (points, 2+), polygon (closed points), circle " +
    "(center, radius in px, filled), text (position, text, size), point (position, a dot with an " +
    "optional text label). space 'screen' (default) takes window pixels [x, y]; space 'world' takes " +
    "fractal coordinates [x, y, z] and keeps the drawing attached to the fractal as the camera moves " +
    "(drawn on top, not occluded). Returns an id; pass the same id to replace a drawing.",
  {
    type: z.enum(["line", "polygon", "circle", "text", "point"]),
    space: z.enum(["screen", "world"]).optional(),
    points: z.array(z.union([vec2, vec3])).optional(),
    center: z.union([vec2, vec3]).optional(),
    position: z.union([vec2, vec3]).optional(),
    radius: z.number().optional(),
    filled: z.boolean().optional(),
    text: z.string().optional(),
    size: z.number().int().optional().describe("Font size for text"),
    color: color.optional(),
    width: z.number().optional().describe("Line width in px (default 2)"),
    id: z.string().optional(),
  },
);

relay(
  "clear_drawings",
  "clear_drawings",
  "Remove one drawing by id, or every drawing (and the trail) when no id is given.",
  { id: z.string().optional() },
);

relay("list_drawings", "list_drawings", "The drawings on screen.", {});

relay(
  "trail",
  "trail",
  "Record the camera's path as a world-space line (id 'trail'), so you can see where you have flown.",
  { on: z.boolean(), color: color.optional(), width: z.number().optional() },
);

await server.connect(new StdioServerTransport());
