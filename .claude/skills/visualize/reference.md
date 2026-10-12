# Systems viz — pane data contract

A pane file is one IIFE that calls `VIZ.pane(def)`. The engine (`docs/viz/viz.js`) validates it
on load: any error is listed in a red box bottom-left and in `VIZ.errors`, and a pane with an
error is not drawn at all.

## The pane

```js
VIZ.pane({
  id: "mandelbox",               // kebab-case; also the #hash and the ./viz.sh argument
  short: "Mandelbox viewer",     // pane button label in the top row (defaults to title)
  title: "Help I'm Stuck In A Fractal — how a pixel is made",
  subtitle: "Two or three plain sentences: what this system is and does.",
  commit: "<full sha>",          // every file:line in the pane was read at this commit
  pinNote: "main, unpushed: links 404 until it is pushed",   // optional
  ctx: {                         // node / participant colours, named by MEANING in this pane
    state:  { hue: 1, label: "shared resources — FractalParams, CameraState" },
    camera: { hue: 3, label: "cameras — fly, orbit, Julia marker" },
  },
  kinds: {                       // edge and message styles
    call:  { style: "solid", label: "calls · feeds" },
    signal: { style: "dash", label: "changed signal" },
    data:  { style: "dot",   label: "reads data" },
  },
  tabs: [                        // the second control row, left to right; one canvas each
    blockA,                      // a block alone: labelled by its `tab`, else its `title`
    blockB,
    { label: "Tuning", rows: [[tableA, tableB], [tableC]] },   // a group: rows top to bottom,
  ],                                                           // blocks left to right
});
```

Each tab is drawn alone on its own canvas with its own pan and zoom: it is built the first time it
is opened, hidden (out of the render tree) while another tab is open, and only the open tab's live
figures get `onFrame` calls (a hidden simulation pauses and resumes). One diagram per tab; group
blocks only when they are read against each other. The first tab also draws the pane's `title` and
`subtitle`; any tab holding a `graph` or `seq` draws the legend of `ctx` and `kinds`. The pinned
commit and `pinNote` show at the right of the tab row. Pane-level `rows` is retired (an error).

Hues: 1 blue, 2 orange, 3 green, 4 amber, 5 pink, 6 violet (light and dark variants in
`viz.css`). Styles: `solid`, `dash`, `dot`. Every block may carry `title` and `note` (a wrapped
caption under the title), and a block that is a tab on its own should carry `tab`, its short (2 to
4 word) label in the tab row.

## Links (tooltips, cards)

Anything with `file` (repo-relative path) and optional `line` becomes a GitHub link pinned to the
pane's `commit`. Extra links: `links: [{ file, line, label? }, { url, label }]`. `label` defaults
to `basename:line`. Blurbs may use `` `backticks` `` for code and `\n` for a new paragraph.

## Glossary (maths terms explained on hover)

`docs/viz/glossary.js` registers terms with `VIZ.glossary({ id: { term, body, links, match? } })`.
The engine marks each term's FIRST mention in every tooltip blurb, the pane subtitle, block notes,
card bodies, and table cells (once per table, not once per row). A mark's text is coloured (no box behind
it: WebKit measures a tspan as its whole line), and hovering one shows a popup with the body and its links. That works on the canvas and inside a tooltip, pinned
or not. Panes need no markup. `match` entries are strings (case-insensitive whole words, never part
of an identifier like `fold_limit` or a path) or RegExps. Without `match`, the term itself is
matched. Text in `` `backticks` `` is never matched. `[[id]]` or `[[id|shown text]]` in any prose
marks a mention by hand. Titles, node and message labels, and figure text are never marked.
`check.mjs` validates every entry and every `[[id]]`.

When a pane's prose leans on maths, geometry or graphics above basic calculus (a fold, a gradient,
a basis, sphere tracing...), add an entry instead of a parenthetical: a short, concrete body tied
to this project, plus one or two links (Wikipedia, then a friendlier explainer). Check that the
match doesn't catch an ordinary word: `orbit` alone would mark the orbit camera.

## graph

```js
{ type: "graph", title, note,
  zones: [{ id, label, x, y, w, h }],                 // bands; labels drawn top-left in caps
  nodes: [{ id, label?, sub?, ctx, zone?, x, y, w?, file, line, blurb, links? }],
  edges: [{ from, to, kind, label?, bow?, file, line, blurb?, links? }] }
```

- Coordinates are the block's own, origin top-left. A node is 34 px tall (46 with `sub`, a small
  second line); width comes from the label (~7.6 px/char + 34) unless `w` is given.
- Leave ~40 px under a zone's top edge for its label. Space nodes ≥ 60 px apart horizontally
  (measure the label) and ≥ 25 px vertically.
- `to: "zone:<id>"` points an edge at a zone's border. `from === to` draws a loop above the node.
- `bow` bends a curve: 1 default, 0 straight, negative bends the other way. Use it to pull an edge
  off a node it would otherwise run under.
- Hovering a node highlights it, its edges and its neighbours; hovering an edge highlights it and
  its two ends. Everything else in the block dims.

## seq

```js
{ type: "seq", title, note, laneWidth?: 230, headWidth?: 200,
  boundaryAfterCol?: 3, boundaryLabel?: "RENDER THREAD",   // a dashed divider between two columns
  participants: [{ id, col, ctx, name, sub, blurb?, file?, line? }],
  rows: [
    { sec: "MAIN THREAD — gather" },                       // a section band
    { from, to, kind, label, tick?, file, line, blurb, fromRole?, toRole?, links? },
  ],
  fragments: [{ type: "loop" | "alt" | "opt", rows: [first, last], cols: [first, last],
                guard1, divRow?, guard2? }] }              // alt: divRow starts the second branch
```

`from === to` draws a self-call. `tick` is a small second line under the label. Row indices in
`fragments` count section rows too. The activation marks on each lifeline take `fromRole` /
`toRole` as their tooltip: what THAT participant does at this step.

## table

```js
{ type: "table", title, note,
  columns: [{ label, w, mono? }],
  rows: [ ["a", "b"],                                      // plain row
          { cells: ["a", "b"], tip: { title?, sub?, blurb?, file?, line?, links? } } ] }
```

Cells wrap to their column width. A row with `tip` is hoverable.

## cards

```js
{ type: "cards", title, columns?: 2, cardWidth?: 520,
  cards: [{ title, tag?, hue? | ctx?, body, file?, line?, links? }] }
```

Masonry: each card lands in the shortest column. Conventions across panes: tag `invariant` hue 3,
`gotcha` hue 2, `history` hue 6, `open` hue 4.

## figure

```js
{ type: "figure", title, note, w, h, draw(api) { ... } }
```

`draw` runs once, inside the figure's own coordinates (0,0 .. w,h), on a rounded background.
`api`:

| member | does |
|---|---|
| `el(tag, attrs, parent?)` | create an SVG element (parent defaults to the figure) |
| `text(x, y, str, cls?, extra?, parent?)` | SVG text; classes `ink`, `muted`, `mono` |
| `arrow(x1, y1, x2, y2, color, width?, parent?)` | a line with a filled head sized to its width |
| `tip(elem, { title, sub?, blurb?, file?, line?, links?, live? })` | make an element hoverable. `live()` returns fields (`title`, `sub`, `blurb`...) laid over the payload each time the tooltip is shown, so a figure whose state changes tips ONCE per element instead of re-tipping on every redraw |
| `link(x, y, { file, line } or { url, label }, parent?)` | a clickable ↗ link |
| `hue(n)` | `var(--cN)` |
| `wrap(str, maxChars)` | greedy word wrap → lines |
| `button({ x, y, w, label, on?, onClick(handle) })` | toggle-style button; `handle.set(bool)`, `handle.label(str)` |
| `slider({ x, y, w, label, min, max, step, value, fmt?, onChange(v) })` | a draggable slider |
| `image({ x, y, w, h, pw, ph, smooth? })` | a `pw×ph` canvas shown as an SVG image: draw to `.ctx`, then `.flush()`; `.img` takes pointer events |
| `local(evt)` | pointer position in figure coordinates, whatever the pan and zoom |
| `hovered()` | pointer is over the figure (gate keyboard input on this) |
| `onFrame(fn(dt))` | called every animation frame; `VIZ.frameMs` tracks the total cost |
| `w`, `h`, `g` | size and root group |

Buttons, sliders and images are marked `data-interactive`, so dragging them never pans the world.
A live figure should step at a fixed rate (accumulate `dt`, cap steps per frame) and redraw once
per frame. Keep a frame well under 16 ms: a 128² grid with a few stencil reads per cell is fine.

## Deep links

`index.html#<pane-id>` opens a pane's first tab; `#<pane-id>/<n>` its n-th tab; `#<pane-id>/<n>/<m>`
fits the m-th block of that tab (reading order). All 1-based. No hash opens the first pane. Clicking
the open tab again refits it; a pane button returns to that pane's last open tab.
