// End-to-end check: spawn server.mjs over stdio, launch the game, fly, draw and
// screenshot. Writes the screenshots next to this file in out/.
//
//   GODOT=/path/to/godot node smoke.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, "out");
fs.mkdirSync(out, { recursive: true });

const client = new Client({ name: "smoke", version: "0" });
await client.connect(
  new StdioClientTransport({ command: process.execPath, args: [path.join(here, "server.mjs")], env: process.env }),
);

let failures = 0;
async function step(name, args = {}) {
  const r = await client.callTool({ name, arguments: args });
  const text = r.content.find((c) => c.type === "text")?.text ?? "";
  const ok = !r.isError;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"} ${name} ${JSON.stringify(args)}${ok ? "" : " -> " + text}`);
  return r;
}
function save(r, file) {
  const img = r.content.find((c) => c.type === "image");
  if (img) fs.writeFileSync(path.join(out, file), Buffer.from(img.data, "base64"));
  else {
    failures++;
    console.log(`FAIL no image for ${file}`);
  }
}

const tools = (await client.listTools()).tools.map((t) => t.name);
console.log("tools:", tools.join(", "));

await step("launch_game");
await step("clear_drawings");
save(await step("screenshot", { max_width: 640 }), "1-default.png");

const hit = JSON.parse((await step("raycast")).content[0].text);
await step("draw", { type: "point", space: "world", position: hit.point, text: "centre hit", color: "#ff4080", radius: 6 });
await step("draw", { type: "polygon", points: [[20, 20], [300, 20], [300, 70], [20, 70]], color: "yellow" });
await step("draw", { type: "text", position: [32, 54], text: "drawn over MCP", size: 24, color: "yellow" });
await step("trail", { on: true });
save(await step("rotate", { yaw: 20, duration: 0.5, look: true }), "2-annotated.png");
await step("rotate", { yaw: -20 });
await step("dive", { fraction: 0.6, duration: 1 });
await step("move", { right: 1, up: 0.5, duration: 0.5 });
await step("dive", { fraction: 0.5, duration: 0.5 });
save(await step("screenshot", { max_width: 640 }), "3-dived.png");
await step("set_camera", { eye: [8.175847, 3.81246, 3.283393], look_at: [0, 0, 0], duration: 1 });
save(await step("screenshot", { max_width: 640 }), "4-trail.png");
await step("set_shape", { values: { color_mode: 3 } });
save(await step("screenshot", { max_width: 640, overlay: false }), "5-bare-mode3.png");
await step("set_shape", { values: { color_mode: 1 } });
await step("trail", { on: false });
await step("clear_drawings");

await client.close();
console.log(failures ? `${failures} failure(s)` : "smoke PASSED");
process.exit(failures ? 1 : 0);
