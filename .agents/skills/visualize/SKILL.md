---
name: visualize
description: Visualize a Help I'm Stuck In A Fractal system or concept as a pane in the project's in-browser systems viz (docs/viz/, opened with ./viz.sh) — a control row of panes (one per system), a row of that pane's tabs, one pannable, zoomable canvas per tab (one diagram each), hover tooltips linking file:line on GitHub, architecture graphs, sequence diagrams, tables, cards and live interactive figures. Use when the user runs /visualize <concept>, or asks to visualize, diagram or map how a system works (the ray march, the distance estimator, the colour modes, the cameras, the resolution governor, saves...), or to update an existing visualization after the code changed.
---

# /visualize

Adds (or refreshes) ONE pane in the project's systems viz. The argument is the concept or system,
free text: `/visualize the orbit camera's gestures`, `/visualize how a save is written and loaded`.

**What exists:**

| Path | What it is |
|---|---|
| `docs/viz/index.html` | the page: two control rows (panes, then the open pane's tabs), one SVG canvas, one `<script src="panes/<id>.js">` line per pane |
| `docs/viz/viz.js`, `viz.css` | the engine. Panes never edit it (see "Engine changes" below) |
| `docs/viz/glossary.js` | maths terms the prose leans on, coloured wherever they appear and explained on hover (reference.md, "Glossary") |
| `docs/viz/panes/<id>.js` | one pane per system: pure data passed to `VIZ.pane({...})` |
| `tools/viz/check.mjs` | node checker: every pane loads, every `file:line` exists at the pinned commit |
| `viz.sh` | `./viz.sh [pane-id[/tab]]` opens the MAIN checkout's page in the default browser |
| `.Codex/launch.json` → `viz` | a static server for the in-app browser (file:// cannot load the pane scripts there). `autoPort`: use the URL `preview_start` returns, never assume :8765 |

`reference.md` (next to this file) is the full data contract for every block type. Read it before
writing a pane. `docs/viz/panes/mandelbox.js` is the worked example: copy its shape (its fold-by-fold
and ray-march steppers are the stepper pattern below). The engine came from the sibling project
`/Users/adam/Godot/spellfactory`, whose `docs/viz/panes/fog-sim.js` is a second, larger example
(read only: never edit that repo).

## Workflow

1. **Is there a pane already?** `ls docs/viz/panes/`. If the concept is already a pane (or a block
   inside one), UPDATE that pane: re-read the code, fix what drifted, bump its `commit`. Only a
   genuinely different system gets a new pane. A small sub-concept of an existing system becomes a
   new block in that system's pane, not a new pane.

2. **Research from the code, not from memory.** Read `README.md` (controls, saves, coordinates),
   the system's spec and plan under `docs/superpowers/specs/` and `docs/superpowers/plans/`, the
   test that pins its values (`tests/*_test.gd`), then the code itself (`src/`).
   Delegate the sweep to Explore agents when it spans many files, but read every line you will cite
   yourself. The pane is only as good as its blurbs: each says what the thing does and WHY, never
   restates its name.

3. **Pin the commit.** `commit` = `git rev-parse HEAD`. Every `file`/`line` is read AT that commit
   (`git show HEAD:<path>`), never from a working copy with uncommitted edits: `git status` first,
   and if a file you cite is dirty, read the committed version. If HEAD is not on any remote the
   links 404 until it is pushed; say so in `pinNote` (e.g. `"<branch>, unpushed: links 404 until it
   is pushed"`), and never "fix" it by pinning an older commit whose lines differ.

4. **Choose blocks, then tabs.** A pane is a list of `tabs`, and each tab is drawn ALONE on its
   own canvas: only the open tab is in the render tree and only its live figures tick. That is
   the point of tabs (the one-big-world viz got laggy), so **one diagram per tab** by default.
   Group blocks into one tab (`{ label, rows }`) only when they are read against each other:
   two figures sharing controls, a set of small tables. Give each single-block tab a short `tab`
   label (2 to 4 words; the block `title` stays the long heading). The first tab carries the
   pane's title and subtitle, so lead with the graph. Pick what explains THIS system; not every
   pane needs every type:
   - **graph, always first**: who talks to whom. Zones = layers or threads or ownership. Every
     node links its class/declaration line; every edge links the line that makes the call.
   - **seq**: the per-frame / per-event flow, when ORDER matters (a physics step, a draft pick, a
     save). Fragments for loops and branches; a boundary for a thread or process hop.
   - **table**: ladders and tuning (rungs, rarity tiers, wave windows, default rows). Rows carry
     tooltips with their source line.
   - **cards**: invariants, gotchas, history (formats and retired choices, with spec or git links) and open
     follow-ups. Tag + hue: invariant 3, gotcha 2, history 6, open 4 (keep this across panes).
   - **figure**: the core mechanism drawn (a stencil, a falloff curve, a ring layout). Make it
     **live** when the system is a simulation or an algorithm whose behaviour is best felt: port
     the real math line for line into the pane (as `mandelbox.js` ports `mandelbox.gdshader`), expose the
     real dials as sliders with their shipped defaults, and say in the block note that it is a port.
   - **Prefer the frame-by-frame stepper.** Adam (2026-09-28, in spellfactory): the fog-sim "Air
     step, with and without pressure" tab is the view that best teaches him a simulation, better
     than a free-running demo. When a new tab explains a sim or an algorithm, lean toward that shape: a
     small grid stepped by the real port, the frame the step READS beside the frame it WRITES,
     Step / Back / Reset through frames, the step's stages listed in order with their shader and
     GDScript lines, every cell hoverable for its numbers stage by stage, a switch between the fields
     it carries (dye counts or velocities), and a hypothetical variant drawn beside the shipped
     one on shared controls. Copy the fold-by-fold and ray-march figures in `mandelbox.js` (or
     `airLab` / `airFigure` in spellfactory's `fog-sim.js`).
   Keep a pane readable: 4 to 10 tabs. A graph over ~45 nodes wants splitting into two graphs
   (two tabs). Never write a figure that assumes another tab is on screen ("the figure above"
   only holds inside one tab).

5. **Write `docs/viz/panes/<id>.js`** (kebab-case id) and add its `<script>` line to `index.html`
   under the `PANES:` comment. Define file paths once in an `F` table at the top, as mandelbox does.
   Colours are the six hues only, given meaning per pane by `ctx`; never add CSS.

6. **Verify, all three, before calling it done:**
   - `node tools/viz/check.mjs --print --pane <id>` exits 0. READ the printed lines: each must be
     the line the tooltip describes (a class declaration, the call, the constant), not merely a
     line that exists. Fix every miss.
   - Open it in the in-app browser: `preview_start` with name `viz`, then `<its url>/#<id>`.
     Visit every tab with `#<id>/<n>` (n = tab number, 1-based): a tab is built the first time it
     opens, so a block that throws only shows up then. Run `VIZ.errors` (must be `[]`) after the
     last one. Screenshot every tab, and each block of a grouped tab with `#<id>/<n>/<m>` (m =
     block number in the tab, reading order), and look at each: overlapping nodes, edges running under nodes, labels running into neighbours,
     text past a frame. Fix and re-shoot. Screenshots can be a frame stale: wait a second and
     shoot again before believing a glitch. Hover a node to see the tooltip and the highlight.
   - For a live figure: check it runs (`VIZ.frameMs` stays well under 16 ms) and that its
     controls do what they say, and that `VIZ.frameMs` falls to ~0 on a tab without one (a hidden
     tab's figures must not tick). The preview pane throttles animation when in the background, so
     judge the cost by `VIZ.frameMs`, not by how fast it moves there. If the preview pane is
     hidden (screenshots time out), headless Chrome captures a tab:
     `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --window-size=1600,1000 --screenshot=<scratch>/t.png "<url>/#<id>/<n>"`.

7. **Commit** the pane, the `index.html` line and any engine change, by explicit path (never
   `git add -A`). Do not push. Tell the user: `./viz.sh <id>` (or `<id>/<n>` for a tab).

## Engine changes

Pane content never goes in `viz.js`. Change the engine only when a new block TYPE or a general
capability is genuinely needed; then update `reference.md` in the same commit, keep every
existing pane rendering (open every tab of every pane, `VIZ.errors` empty, shoot each), and keep
the per-tab cost model: nothing may render or tick outside the open tab. Keep the page a
dependency-free static file that works from `file://`.

## Audience

Adam reads this as the engineer who wrote the code. Lead with the code names, uniforms and
formulas (`min_r2 = inner_radius²`, `de(p, 32)`), give the numbers the real code would compute,
and link every claim to its `file:line`. Plain sentences still come first in a blurb: what the
thing does and WHY, then the names.

Adam is an engineer, not a mathematician (2026-10-08). Anything above basic calculus (topology,
4D geometry, linear algebra, gradients, numerical methods, rendering maths) gets an entry in
`docs/viz/glossary.js` so it is coloured and explained on hover. When a new pane brings in a term
the glossary lacks, add the entry in the same commit. Open a few tabs and check the new marks land
on the right words.
