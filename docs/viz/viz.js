/* Help I'm Stuck In A Fractal systems viz — the engine behind docs/viz/index.html (ported unchanged
 * from the sibling project spellfactory; only this header differs).
 *
 * A control row picks a PANE (one per visualized system, a file under panes/), a second row picks
 * one of that pane's TABS, and the tab is drawn alone on its own pannable, zoomable canvas. Only the
 * open tab is in the render tree and only its live figures tick, so the page stays smooth however
 * many systems it holds; a tab is built the first time it is opened and keeps its own pan and zoom.
 * A pane is pure DATA: it calls VIZ.pane({...}) and this file draws it. Block types:
 *
 *   graph   zones + nodes + typed edges (who calls / owns / feeds whom)
 *   seq     a sequence diagram (participants, message rows, loop/alt/opt fragments)
 *   cards   titled boxes in a masonry (invariants, gotchas, history, open questions)
 *   table   a small table whose rows can carry tooltips
 *   figure  a custom drawing, optionally LIVE: draw(api) gets el/tip/button/slider/image/onFrame
 *
 * Every hoverable thing shows a tooltip with a blurb and file:line links to GitHub, pinned to the
 * pane's `commit`. Maths terms in the prose (glossary.js, VIZ.glossary) are highlighted wherever
 * they appear and explained in a second popup on hover. The full data contract is .claude/skills/visualize/reference.md; the checker is
 * tools/viz/check.mjs. Do not put pane content in this file.
 */
"use strict";

(function () {
const VIZ = window.VIZ = {
  config: { title: "Systems", repo: "" },
  panes: [],
  errors: [],
  gloss: {},
  pane(def) { this.panes.push(def); },
  glossary(entries) { Object.assign(this.gloss, entries); },
};

const SVGNS = "http://www.w3.org/2000/svg";
const HUES = [1, 2, 3, 4, 5, 6];
const STYLES = ["solid", "dash", "dot"];
const PANE_PAD = 70, ROW_GAP = 110, COL_GAP = 110;
const NODE_H = 34, NODE_H2 = 46;

function el(tag, attrs, parent) {
  const e = document.createElementNS(SVGNS, tag);
  if (attrs) for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) e.setAttribute(k, v);
  if (parent) parent.appendChild(e);
  return e;
}
function text(parent, x, y, str, cls, extra) {
  const t = el("text", Object.assign({ x, y, class: cls }, extra || {}), parent);
  t.textContent = str;
  return t;
}
// Greedy word wrap for SVG text, which cannot wrap itself.
function wrapWords(s, maxChars) {
  const lines = [];
  for (const para of String(s || "").split("\n")) {
    let cur = "";
    for (const word of para.split(" ")) {
      if (cur && cur.length + 1 + word.length > maxChars) { lines.push(cur); cur = word; }
      else cur = cur ? `${cur} ${word}` : word;
    }
    lines.push(cur);
  }
  return lines;
}
// ---------------------------------------------------------------- glossary
// Terms registered with VIZ.glossary (docs/viz/glossary.js) are marked wherever pane prose
// mentions them: tooltip blurbs, the subtitle, block notes, card bodies and table cells. Each entry
// of a term's `match` (a string, matched case-insensitively as a whole word, or a RegExp) marks the
// term's FIRST mention in each piece of text; `[[id]]` or `[[id|shown text]]` marks one by hand.
// Text inside `backticks` is code and is never matched. Hovering a mark shows the entry.
let GLOSS = null;
const escRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// A whole word, not a piece of an identifier or a path (fold_limit, mandelbox.gdshader).
const phraseRe = s => new RegExp(`(?<![\\w./])${escRe(s)}(?![\\w]|[./]\\w)`, "gi");
function glossTerms() {
  if (GLOSS) return GLOSS;
  GLOSS = [];
  for (const [id, g] of Object.entries(VIZ.gloss)) {
    if (!g.term || !g.body) { err(`glossary ${id}`, "needs a term and a body"); continue; }
    const res = (g.match || [g.term]).map(m => typeof m === "string" ? phraseRe(m)
      : new RegExp(m.source, m.flags.includes("g") ? m.flags : `${m.flags}g`));
    GLOSS.push({ id, res });
  }
  return GLOSS;
}
// Prose → runs: { t } plain, { t, code: true } a `backtick` span (kept whole), { t, g: id } a mark.
// `used` holds the terms already marked in this piece of text.
function glossSegs(s, used = new Set()) {
  const out = [];
  const auto = t => {   // the earliest match first; on a tie, the longer phrase
    let at = 0;
    for (;;) {
      let best = null;
      for (const g of glossTerms()) {
        if (used.has(g.id)) continue;
        for (const re of g.res) {
          re.lastIndex = at;
          const m = re.exec(t);
          if (m && m[0] && (!best || m.index < best.i || (m.index === best.i && m[0].length > best.n)))
            best = { i: m.index, n: m[0].length, id: g.id };
        }
      }
      if (!best) break;
      if (best.i > at) out.push({ t: t.slice(at, best.i) });
      out.push({ t: t.slice(best.i, best.i + best.n), g: best.id });
      used.add(best.id);
      at = best.i + best.n;
    }
    if (at < t.length) out.push({ t: t.slice(at) });
  };
  for (const part of String(s ?? "").split(/(`[^`\n]+`)/)) {
    if (/^`[^`\n]+`$/.test(part)) { out.push({ t: part, code: true }); continue; }
    let at = 0;
    for (const m of part.matchAll(/\[\[([\w-]+)(?:\|([^\]]+))?\]\]/g)) {
      auto(part.slice(at, m.index));
      const g = VIZ.gloss[m[1]];
      if (!g) err("glossary", `unknown term [[${m[1]}]]`);
      out.push(g ? { t: m[2] || g.term, g: m[1] } : { t: m[2] || m[1] });
      used.add(m[1]);
      at = m.index + m[0].length;
    }
    auto(part.slice(at));
  }
  return out;
}
// wrapWords for prose that may carry marks: lines of runs { t, g? }, wrapped on the visible text.
function glossLines(s, maxChars, used = new Set()) {
  const lines = [];
  let line = [], len = 0, word = [], wlen = 0, mark = 0;
  const endWord = () => {
    if (!wlen) return;
    if (len && len + 1 + wlen > maxChars) { lines.push(line); line = []; len = 0; }
    if (len) {   // the space between two words of one mark belongs to the mark
      const a = line[line.length - 1], k = a.k && a.k === word[0].k ? a.k : 0;
      line.push({ t: " ", k, g: k ? a.g : undefined });
      len++;
    }
    line.push(...word); len += wlen; word = []; wlen = 0;
  };
  for (const sg of glossSegs(s, used)) {
    const k = sg.g ? ++mark : 0;
    for (const ch of sg.t) {
      if (ch === " ") endWord();
      else if (ch === "\n") { endWord(); lines.push(line); line = []; len = 0; }
      else {
        const last = word[word.length - 1];
        if (last && last.k === k) last.t += ch;
        else word.push({ t: ch, k, g: sg.g });
        wlen++;
      }
    }
  }
  endWord();
  lines.push(line);
  return lines.map(runs => runs.reduce((acc, r) => {
    const p = acc[acc.length - 1];
    if (p && p.k === r.k) p.t += r.t; else acc.push(Object.assign({}, r));
    return acc;
  }, []));
}
// One line of glossLines as SVG text. A mark is a tspan, highlighted once its tab is laid out.
function glossText(parent, x, y, runs, cls, extra) {
  const t = el("text", Object.assign({ x, y, class: cls }, extra || {}), parent);
  for (const r of runs) {
    if (!r.g) { t.appendChild(document.createTextNode(r.t)); continue; }
    const ts = el("tspan", { class: "gl", "data-gloss": r.g }, t);
    ts.textContent = r.t;
    if (building) building.marks.push(ts);
  }
  return t;
}

const hue = h => `var(--c${h})`;
const safeKey = s => String(s).replace(/[^A-Za-z0-9_-]/g, "_");
function err(where, msg) { VIZ.errors.push(`[${where}] ${msg}`); }

// ---------------------------------------------------------------- links + tooltips registry
function linkUrl(lk, commit) {
  if (lk.url) return lk.url;
  return `${VIZ.config.repo}/blob/${commit}/${lk.file}${lk.line ? `#L${lk.line}` : ""}`;
}
function linkLabel(lk) {
  if (lk.label) return lk.label;
  return `${lk.file.split("/").pop()}${lk.line ? `:${lk.line}` : ""}`;
}
// A payload's links: its own `links`, led by the file/line pair it may carry directly.
function linksOf(p) {
  const out = [];
  if (p.file) out.push({ file: p.file, line: p.line });
  for (const lk of p.links || []) out.push(lk);
  return out;
}
const tips = [];
function addTip(elem, payload, block, pane) {
  tips.push(Object.assign({ block, commit: pane.commit, hl: [] }, payload));
  elem.setAttribute("data-tip", tips.length - 1);
}
function markKeys(elem, ...keys) {
  elem.setAttribute("data-hk", keys.map(safeKey).join(" "));
  elem.classList.add("dim");
}

// ---------------------------------------------------------------- validation
// A tab is either one block (labelled by its `tab`, else its `title`) or a group
// { label, rows: [[block, ...], ...] } for blocks that are read together.
function normTabs(p, w) {
  if (p.rows) err(w, "pane-level `rows` is retired: put the blocks in `tabs` (one tab per diagram)");
  if (!Array.isArray(p.tabs) || !p.tabs.length) { err(w, "tabs must be a non-empty array"); return []; }
  return p.tabs.map((t, i) => {
    const tab = t && t.type ? { label: t.tab || t.title, rows: [[t]] } : { label: t && t.label, rows: t && t.rows };
    if (!tab.label) err(w, `tab ${i + 1}: needs a label (a block's \`tab\` or \`title\`, or a group's \`label\`)`);
    if (!Array.isArray(tab.rows) || !tab.rows.every(Array.isArray)) {
      err(w, `tab ${i + 1}: a group's rows must be an array of arrays of blocks`);
      tab.rows = [];
    }
    return tab;
  });
}
function validatePane(p) {
  const w = `pane ${p.id || "?"}`;
  if (!p.id || !/^[a-z0-9-]+$/.test(p.id)) err(w, "id must be kebab-case");
  if (!p.title) err(w, "missing title");
  if (!/^[0-9a-f]{7,40}$/.test(p.commit || "")) err(w, "commit must be a git sha (the commit every file:line was read at)");
  for (const [k, c] of Object.entries(p.ctx || {})) if (!HUES.includes(c.hue)) err(w, `ctx ${k}: hue must be 1..6`);
  for (const [k, c] of Object.entries(p.kinds || {})) if (!STYLES.includes(c.style)) err(w, `kind ${k}: style must be solid|dash|dot`);
  p._tabs = normTabs(p, w);
  for (const tab of p._tabs) for (const row of tab.rows) for (const b of row) {
    const bw = `${w} / ${b.type} "${b.title || ""}"`;
    if (!RENDER[b.type]) { err(bw, `unknown block type "${b.type}"`); continue; }
    if (b.type === "graph") {
      const ids = new Set(), zones = new Set((b.zones || []).map(z => z.id));
      for (const n of b.nodes) {
        if (ids.has(n.id)) err(bw, `duplicate node ${n.id}`);
        ids.add(n.id);
        if (!(n.ctx in (p.ctx || {}))) err(bw, `node ${n.id}: unknown ctx "${n.ctx}"`);
        if (n.zone && !zones.has(n.zone)) err(bw, `node ${n.id}: unknown zone "${n.zone}"`);
      }
      for (const e of b.edges || []) {
        for (const end of [e.from, e.to])
          if (end.startsWith("zone:") ? !zones.has(end.slice(5)) : !ids.has(end)) err(bw, `edge ${e.from}→${e.to}: unknown end "${end}"`);
        if (!(e.kind in (p.kinds || {}))) err(bw, `edge ${e.from}→${e.to}: unknown kind "${e.kind}"`);
      }
    }
    if (b.type === "seq") {
      const pids = new Set(b.participants.map(q => q.id));
      for (const q of b.participants) if (!(q.ctx in (p.ctx || {}))) err(bw, `participant ${q.id}: unknown ctx "${q.ctx}"`);
      b.rows.forEach((r, i) => {
        if (r.sec !== undefined) return;
        for (const end of [r.from, r.to]) if (!pids.has(end)) err(bw, `row ${i}: unknown participant "${end}"`);
        if (!(r.kind in (p.kinds || {}))) err(bw, `row ${i}: unknown kind "${r.kind}"`);
      });
      for (const f of b.fragments || []) {
        if (!["loop", "alt", "opt"].includes(f.type)) err(bw, `fragment type "${f.type}"`);
        if (f.rows[0] > f.rows[1] || f.rows[1] >= b.rows.length) err(bw, `fragment ${f.type}: bad row range ${f.rows}`);
      }
    }
    if (b.type === "cards") for (const c of b.cards) {
      if (c.ctx && !(c.ctx in (p.ctx || {}))) err(bw, `card "${c.title}": unknown ctx "${c.ctx}"`);
      if (c.hue !== undefined && !HUES.includes(c.hue)) err(bw, `card "${c.title}": hue must be 1..6`);
    }
    if (b.type === "figure" && typeof b.draw !== "function") err(bw, "figure needs draw(api)");
  }
}

// ---------------------------------------------------------------- block renderers
// Each draws its CONTENT into `g` with its own origin at (0,0) and returns the content width.
const RENDER = {};

RENDER.graph = function (b, g, pane, block) {
  const zoneById = Object.fromEntries((b.zones || []).map(z => [z.id, z]));
  for (const n of b.nodes) {
    n._label = n.label || n.id;
    n._h = n.sub ? NODE_H2 : NODE_H;
    n._w = n.w || Math.max(110, Math.round(34 + Math.max(n._label.length * 7.6, (n.sub || "").length * 5.9)));
  }
  const nodeById = Object.fromEntries(b.nodes.map(n => [n.id, n]));
  const center = n => ({ x: n.x + n._w / 2, y: n.y + n._h / 2 });

  const gZ = el("g", {}, g), gE = el("g", {}, g), gN = el("g", {}, g);
  for (const z of b.zones || []) {
    const zg = el("g", { class: "zone" }, gZ);
    el("rect", { x: z.x, y: z.y, width: z.w, height: z.h, rx: 12 }, zg);
    text(zg, z.x + 14, z.y + 22, z.label);
  }
  const adj = {};
  (b.edges || []).forEach((e, i) => {
    (adj[e.from] ||= []).push(i);
    (adj[e.to] ||= []).push(i);
  });
  for (const n of b.nodes) {
    const ng = el("g", { class: "node" }, gN);
    markKeys(ng, `n:${n.id}`);
    const c = hue(pane.ctx[n.ctx].hue);
    el("rect", { x: n.x, y: n.y, width: n._w, height: n._h, rx: 8, style: `stroke:${c}` }, ng);
    el("circle", { cx: n.x + 15, cy: n.y + n._h / 2, r: 5, style: `fill:${c}` }, ng);
    if (n.sub) {
      text(ng, n.x + 27, n.y + 19, n._label);
      text(ng, n.x + 27, n.y + 35, n.sub, "n-sub");
    } else {
      text(ng, n.x + 27, n.y + n._h / 2, n._label, "", { "dominant-baseline": "central" });
    }
    const hl = [`n:${n.id}`];
    for (const i of adj[n.id] || []) {
      const e = b.edges[i];
      hl.push(`e:${i}`);
      const other = e.from === n.id ? e.to : e.from;
      if (!other.startsWith("zone:")) hl.push(`n:${other}`);
    }
    addTip(ng, { title: n._label, sub: pane.ctx[n.ctx].label, blurb: n.blurb, file: n.file, line: n.line,
      links: n.links, hl: hl.map(safeKey) }, block, pane);
  }
  const rectAnchor = (n, toward) => {
    const c = center(n);
    let dx = toward.x - c.x, dy = toward.y - c.y;
    if (dx === 0 && dy === 0) dy = 1;
    const t = Math.min(dx ? (n._w / 2) / Math.abs(dx) : Infinity, dy ? (n._h / 2) / Math.abs(dy) : Infinity);
    return { x: c.x + dx * t, y: c.y + dy * t };
  };
  const zoneAnchor = (z, from) => ({
    x: Math.min(Math.max(from.x, z.x + 40), z.x + z.w - 40),
    y: from.y < z.y + z.h / 2 ? z.y : z.y + z.h,
  });
  (b.edges || []).forEach((e, i) => {
    const from = nodeById[e.from];
    let d, mid;
    if (e.from === e.to) {
      const c = center(from), y = from.y;
      d = `M ${c.x - 16} ${y} C ${c.x - 44} ${y - 52}, ${c.x + 44} ${y - 52}, ${c.x + 16} ${y}`;
      mid = { x: c.x, y: y - 42 };
    } else {
      let a, bb;
      if (e.to.startsWith("zone:")) {
        bb = zoneAnchor(zoneById[e.to.slice(5)], center(from));
        a = rectAnchor(from, bb);
      } else {
        const to = nodeById[e.to];
        a = rectAnchor(from, center(to));
        bb = rectAnchor(to, center(from));
      }
      const mx = (a.x + bb.x) / 2, my = (a.y + bb.y) / 2, dx = bb.x - a.x, dy = bb.y - a.y;
      const len = Math.hypot(dx, dy) || 1, bow = (e.bow ?? 1) * Math.min(0.14 * len, 46);
      const qx = mx - (dy / len) * bow, qy = my + (dx / len) * bow;
      d = `M ${a.x} ${a.y} Q ${qx} ${qy} ${bb.x} ${bb.y}`;
      mid = { x: (mx + qx) / 2, y: (my + qy) / 2 };
    }
    const kind = pane.kinds[e.kind];
    const path = el("path", { d, class: `edge s-${kind.style}`, "marker-end": "url(#viz-arrow)" }, gE);
    markKeys(path, `e:${i}`);
    if (e.label) {
      const lt = text(gE, mid.x, mid.y - 4, e.label, "edge-label", { "text-anchor": "middle" });
      markKeys(lt, `e:${i}`);
    }
    const hit = el("path", { d, class: "hit" }, gE);
    const toName = e.to.startsWith("zone:") ? zoneById[e.to.slice(5)].label : (nodeById[e.to]._label);
    const hl = [`e:${i}`, `n:${e.from}`];
    if (!e.to.startsWith("zone:")) hl.push(`n:${e.to}`);
    addTip(hit, { title: e.from === e.to ? `${nodeById[e.from]._label} (loop)` : `${nodeById[e.from]._label} → ${toName}`,
      sub: kind.label, blurb: e.blurb, file: e.file, line: e.line, links: e.links, hl: hl.map(safeKey) }, block, pane);
  });
  let w = 0;
  for (const z of b.zones || []) w = Math.max(w, z.x + z.w);
  for (const n of b.nodes) w = Math.max(w, n.x + n._w);
  return w;
};

RENDER.seq = function (b, g, pane, block) {
  const PAD = 110, LANE_W = b.laneWidth || 230, BGAP = 110;
  const HEAD_W = b.headWidth || 200, HEAD_H = 44, FIRST_ROW = 44, ROW_H = 44;
  const pById = Object.fromEntries(b.participants.map(q => [q.id, q]));
  const hasB = b.boundaryAfterCol !== undefined;
  const lifeXCol = c => PAD + c * LANE_W + (hasB && c > b.boundaryAfterCol ? BGAP : 0);
  const lifeX = q => lifeXCol(q.col);
  const maxX = Math.max(...b.participants.map(lifeX)) + HEAD_W / 2 + 24;
  const headTop = 22;
  const rowY = r => headTop + HEAD_H + FIRST_ROW + r * ROW_H;
  const lifeTop = headTop + HEAD_H, lifeBot = rowY(b.rows.length - 1) + 26;

  for (const f of b.fragments || []) {
    const x0 = lifeXCol(f.cols[0]) - 34, x1 = lifeXCol(f.cols[1]) + 34;
    const y0 = rowY(f.rows[0]) - 40, y1 = rowY(f.rows[1]) + 24; // guard sits clear above the first label
    const fg = el("g", { class: "frag" }, g);
    el("rect", { x: x0, y: y0, width: x1 - x0, height: y1 - y0, rx: 6 }, fg);
    const tabW = f.type.length * 7 + 16;
    el("path", { class: "frag-tabbg", d: `M ${x0} ${y0} h ${tabW} v 12 l -7 7 h ${-(tabW - 7)} z` }, fg);
    text(fg, x0 + 8, y0 + 13, f.type, "frag-tab");
    text(fg, x0 + tabW + 10, y0 + 12, `[ ${f.guard1} ]`, "frag-guard");
    if (f.type === "alt" && f.divRow !== undefined) {
      const yd = rowY(f.divRow) - 29;
      el("line", { class: "frag-div", x1: x0, y1: yd, x2: x1, y2: yd }, fg);
      text(fg, x0 + 8, yd + 12, `[ ${f.guard2} ]`, "frag-guard");
    }
  }
  if (hasB) {
    const bx = (lifeXCol(b.boundaryAfterCol) + lifeXCol(b.boundaryAfterCol + 1)) / 2;
    const bg = el("g", { class: "seq-boundary" }, g);
    el("line", { x1: bx, y1: headTop - 6, x2: bx, y2: lifeBot }, bg);
    text(bg, bx, headTop - 10, b.boundaryLabel || "", "", { "text-anchor": "middle" });
  }
  const life = id => `L:${id}`;
  for (const q of b.participants) {
    const x = lifeX(q), c = hue(pane.ctx[q.ctx].hue);
    const ll = el("line", { x1: x, y1: lifeTop, x2: x, y2: lifeBot, class: "lifeline" }, g);
    markKeys(ll, life(q.id));
    const hg = el("g", { class: "phead" }, g);
    markKeys(hg, life(q.id));
    el("rect", { x: x - HEAD_W / 2, y: headTop, width: HEAD_W, height: HEAD_H, rx: 8, style: `stroke:${c}` }, hg);
    el("circle", { cx: x - HEAD_W / 2 + 13, cy: headTop + HEAD_H / 2, r: 4.5, style: `fill:${c}` }, hg);
    text(hg, x - HEAD_W / 2 + 24, headTop + 18, q.name, "p-name");
    text(hg, x - HEAD_W / 2 + 24, headTop + 33, q.sub || "", "p-sub");
    addTip(hg, { title: q.name, sub: pane.ctx[q.ctx].label, blurb: q.blurb || q.sub || "", file: q.file, line: q.line,
      links: q.links, hl: [safeKey(life(q.id))] }, block, pane);
  }
  b.rows.forEach((row, r) => {
    const y = rowY(r);
    if (row.sec !== undefined) {
      const sg = el("g", { class: "seq-sec" }, g);
      el("line", { x1: 0, y1: y - 8, x2: maxX, y2: y - 8 }, sg);
      text(sg, 0, y + 6, row.sec);
      return;
    }
    const x1 = lifeX(pById[row.from]), x2 = lifeX(pById[row.to]);
    const self = row.from === row.to;
    const mk = `M:${r}`;
    const kind = pane.kinds[row.kind];
    const d = self ? `M ${x1} ${y - 14} h 46 v 28 h -46` : `M ${x1} ${y} L ${x2} ${y}`;
    const msg = el("path", { d, class: `msg s-${kind.style}`, "marker-end": "url(#viz-arrow)" }, g);
    markKeys(msg, mk);
    const hit = el("path", { d, class: "hit" }, g);
    const hl = [mk, life(row.from), life(row.to)].map(safeKey);
    addTip(hit, { title: row.label, sub: `${kind.label}${row.tick ? ` · ${row.tick}` : ""}`, blurb: row.blurb,
      file: row.file, line: row.line, links: row.links, hl }, block, pane);
    const lx = self ? x1 + 56 : (x1 + x2) / 2, anchor = self ? "start" : "middle";
    markKeys(text(g, lx, y - 7, row.label, "msg-label", { "text-anchor": anchor }), mk);
    if (row.tick) markKeys(text(g, lx, y + 15, row.tick, "msg-tick", { "text-anchor": anchor }), mk);
    for (const pid of self ? [row.from] : [row.from, row.to]) {
      const q = pById[pid];
      const act = el("rect", { x: lifeX(q) - 6, y: y - 13, width: 12, height: 26, rx: 3, class: "act",
        style: `stroke:${hue(pane.ctx[q.ctx].hue)}` }, g);
      markKeys(act, life(pid));
      const role = (pid === row.from ? row.fromRole : null) || (pid === row.to ? row.toRole : null)
        || `${q.name} takes part in this step.`;
      addTip(act, { title: q.name, sub: `at "${row.label}"`, blurb: role, file: row.file, line: row.line,
        links: row.links, hl: [safeKey(mk), safeKey(life(pid))] }, block, pane);
    }
  });
  return maxX;
};

RENDER.cards = function (b, g, pane, block) {
  const COLS = b.columns || 2, BOX_W = b.cardWidth || 520, GAP = 36, PAD = 14, LINE_H = 16, LINK_H = 18;
  const CHAR_W = 6.3;
  const colY = new Array(COLS).fill(0);
  for (const c of b.cards) {
    const col = colY.indexOf(Math.min(...colY));
    const bx = col * (BOX_W + GAP), by = colY[col];
    const lines = glossLines(c.body, Math.floor((BOX_W - 2 * PAD) / CHAR_W));
    const links = linksOf(c);
    const h = 50 + lines.length * LINE_H + links.length * LINK_H;
    const cg = el("g", { class: "card" }, g);
    const tint = c.hue ? hue(c.hue) : c.ctx ? hue(pane.ctx[c.ctx].hue) : null;
    el("rect", { x: bx, y: by, width: BOX_W, height: h, rx: 10, style: tint ? `stroke:${tint}` : undefined }, cg);
    text(cg, bx + PAD, by + 26, c.title, "c-title");
    if (c.tag) text(cg, bx + BOX_W - PAD, by + 26, c.tag.toUpperCase(), "c-tag",
      { "text-anchor": "end", style: `fill:${tint || "var(--muted)"}` });
    lines.forEach((ln, i) => glossText(cg, bx + PAD, by + 47 + i * LINE_H, ln, "c-body"));
    links.forEach((lk, i) => {
      const a = el("a", { href: linkUrl(lk, pane.commit), target: "_blank", rel: "noopener" }, cg);
      text(a, bx + PAD, by + 47 + lines.length * LINE_H + 6 + i * LINK_H, `↗ ${linkLabel(lk)}`);
    });
    colY[col] = by + h + GAP / 2;
  }
  return COLS * BOX_W + (COLS - 1) * GAP;
};

RENDER.table = function (b, g, pane, block) {
  const CHAR_W = 6.6, LINE_H = 16, PADX = 10;
  const W = b.columns.reduce((s, c) => s + c.w, 0);
  const tg = el("g", { class: "tbl" }, g);
  let x = 0;
  for (const c of b.columns) { text(tg, x + PADX, 16, c.label.toUpperCase(), "th"); x += c.w; }
  el("line", { x1: 0, y1: 26, x2: W, y2: 26 }, tg);
  let y = 28;
  const used = new Set();   // a glossary term is marked once per table, not in every row it recurs in
  b.rows.forEach((row, ri) => {
    const cells = Array.isArray(row) ? row : row.cells;
    const wrapped = cells.map((cell, ci) => glossLines(String(cell), Math.max(4, Math.floor((b.columns[ci].w - 2 * PADX) / CHAR_W)), used));
    const h = Math.max(...wrapped.map(l => l.length)) * LINE_H + 10;
    // A row with a tip is one hoverable group, its hit rect UNDER the text so the cells' glossary
    // marks stay reachable.
    const rg = el("g", {}, tg);
    el("rect", { x: 0, y, width: W, height: h, class: `row-bg${ri % 2 ? " zebra" : ""}` }, rg);
    if (!Array.isArray(row) && row.tip) {
      el("rect", { x: 0, y, width: W, height: h, class: "row-hit" }, rg);
      addTip(rg, Object.assign({ title: row.tip.title || String(cells[0]), sub: row.tip.sub || b.title || "" }, row.tip, { hl: [] }), block, pane);
    }
    let cx = 0;
    wrapped.forEach((lines, ci) => {
      lines.forEach((ln, li) => glossText(rg, cx + PADX, y + 17 + li * LINE_H, ln, `td${b.columns[ci].mono ? " mono" : ""}`));
      cx += b.columns[ci].w;
    });
    y += h;
  });
  el("line", { x1: 0, y1: y, x2: W, y2: y }, tg);
  return W;
};

// ---- live-figure plumbing: one rAF loop, ticking only the OPEN tab's figures (a hidden tab's
// simulation pauses where it is and resumes when its tab is opened again)
let lastT = 0;
function frameLoop(t) {
  const dt = lastT ? Math.min(0.05, (t - lastT) / 1000) : 1 / 60;
  lastT = t;
  const t0 = performance.now();
  for (const fn of active ? active.frameFns : []) {
    try { fn(dt); } catch (e) { console.error(e); }
  }
  VIZ.frameMs = 0.9 * (VIZ.frameMs || 0) + 0.1 * (performance.now() - t0); // live figures' cost, for tuning
  requestAnimationFrame(frameLoop);
}

RENDER.figure = function (b, g, pane, block) {
  const fg = el("g", { class: "fig" }, g);
  el("rect", { x: 0, y: 0, width: b.w, height: b.h, rx: 10, class: "fig-bg" }, fg);
  let hovered = false;
  fg.addEventListener("mouseenter", () => { hovered = true; });
  fg.addEventListener("mouseleave", () => { hovered = false; });
  const api = {
    g: fg, w: b.w, h: b.h, hue, wrap: wrapWords,
    el: (tag, attrs, parent) => el(tag, attrs, parent || fg),
    text: (x, y, s, cls, extra, parent) => text(parent || fg, x, y, s, cls, extra),
    tip: (elem, payload) => addTip(elem, Object.assign({ hl: [] }, payload), block, pane),
    link: (x, y, lk, parent) => {
      const a = el("a", { href: linkUrl(lk, pane.commit), target: "_blank", rel: "noopener", class: "vlink" }, parent || fg);
      text(a, x, y, `↗ ${linkLabel(lk)}`);
      return a;
    },
    // A line with its own filled head, sized to the stroke (the shared marker only suits hairlines).
    arrow(x1, y1, x2, y2, color, width = 1.6, parent) {
      const ag = el("g", {}, parent || fg);
      const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1, ux = dx / len, uy = dy / len;
      const hl = 5 + width * 2.2, hw = 3 + width * 1.4;
      el("line", { x1, y1, x2: x2 - ux * hl * 0.8, y2: y2 - uy * hl * 0.8, style: `stroke:${color};stroke-width:${width}` }, ag);
      el("path", { d: `M ${x2} ${y2} L ${x2 - ux * hl - uy * hw} ${y2 - uy * hl + ux * hw} L ${x2 - ux * hl + uy * hw} ${y2 - uy * hl - ux * hw} z`,
        style: `fill:${color}` }, ag);
      return ag;
    },
    hovered: () => hovered,
    onFrame: fn => building.frameFns.push(fn),
    // Pointer position in this figure's own coordinates, whatever the pan/zoom.
    local(evt) {
      const pt = svg.createSVGPoint();
      pt.x = evt.clientX; pt.y = evt.clientY;
      const p = pt.matrixTransform(fg.getScreenCTM().inverse());
      return { x: p.x, y: p.y };
    },
    button({ x, y, w, label, on, onClick }) {
      const bg = el("g", { class: `vbtn${on ? " on" : ""}`, "data-interactive": "" }, fg);
      el("rect", { x, y, width: w, height: 26, rx: 6 }, bg);
      const t = text(bg, x + w / 2, y + 17, label, "", { "text-anchor": "middle" });
      const handle = {
        on: !!on,
        set(v) { handle.on = v; bg.classList.toggle("on", v); },
        label(s) { t.textContent = s; },
      };
      bg.addEventListener("click", e => { e.stopPropagation(); onClick && onClick(handle); });
      return handle;
    },
    slider({ x, y, w, label, min, max, step, value, fmt, onChange }) {
      const sg = el("g", { class: "vslider", "data-interactive": "" }, fg);
      text(sg, x, y - 8, label);
      const val = text(sg, x + w, y - 8, "", "val", { "text-anchor": "end" });
      el("line", { x1: x, y1: y + 6, x2: x + w, y2: y + 6, class: "track" }, sg);
      const fill = el("line", { x1: x, y1: y + 6, x2: x, y2: y + 6, class: "fill" }, sg);
      const knob = el("circle", { cx: x, cy: y + 6, r: 7, class: "knob" }, sg);
      el("rect", { x: x - 8, y: y - 6, width: w + 16, height: 24, fill: "transparent", style: "cursor:ew-resize" }, sg);
      const show = v => {
        const kx = x + (v - min) / (max - min) * w;
        knob.setAttribute("cx", kx); fill.setAttribute("x2", kx);
        val.textContent = fmt ? fmt(v) : String(v);
      };
      let cur = value;
      const setFrom = evt => {
        const p = api.local(evt);
        let v = min + Math.min(1, Math.max(0, (p.x - x) / w)) * (max - min);
        if (step) v = Math.round(v / step) * step;
        v = +v.toFixed(6);
        if (v !== cur) { cur = v; show(v); onChange && onChange(v); }
      };
      let drag = false;
      sg.addEventListener("mousedown", e => { e.stopPropagation(); drag = true; setFrom(e); });
      window.addEventListener("mousemove", e => { if (drag) setFrom(e); });
      window.addEventListener("mouseup", () => { drag = false; });
      show(value);
      return { set(v) { cur = v; show(v); } };
    },
    // A pixel surface drawn as an SVG <image>: draw into ctx, then flush() once per frame.
    image({ x, y, w, h, pw, ph, smooth }) {
      const canvas = document.createElement("canvas");
      canvas.width = pw; canvas.height = ph;
      const ctx = canvas.getContext("2d");
      const img = el("image", { x, y, width: w, height: h, preserveAspectRatio: "none",
        style: smooth ? "" : "image-rendering:pixelated", "data-interactive": "" }, fg);
      return { ctx, canvas, img, flush() { img.setAttribute("href", canvas.toDataURL()); } };
    },
  };
  b.draw(api);
  return b.w;
};

// ---------------------------------------------------------------- panes, tabs + canvas
let svg, vp, tip;
// Every tab of every pane: { pane, idx, label, rows, g, built, bounds, view, frameFns }.
const tabsByPane = {};
let active = null;     // the open tab
const lastByPane = {}; // each pane's last open tab, which its pane button returns to
let building = null;   // the tab being built (figures register their onFrame on it)

function legend(g, pane, x0, y0, maxW) {
  const lg = el("g", { class: "legend" }, g);
  let x = x0, y = y0;
  // Measure first, then place: an item that wraps moves to the next line, text and swatch together.
  const item = (label, swatchW, swatch) => {
    const t = text(lg, 0, 0, label);
    const w = t.getComputedTextLength() + swatchW;
    if (x > x0 && x + w > x0 + maxW) { x = x0; y += 22; }
    t.setAttribute("x", x + swatchW); t.setAttribute("y", y);
    swatch(x, y - 4);
    x += w + 18;
  };
  for (const c of Object.values(pane.ctx || {}))
    item(c.label, 16, (sx, sy) => el("circle", { cx: sx + 5, cy: sy, r: 5, style: `fill:${hue(c.hue)}` }, lg));
  for (const k of Object.values(pane.kinds || {}))
    item(k.label, 34, (sx, sy) => el("line", { x1: sx, y1: sy, x2: sx + 26, y2: sy, class: `edge s-${k.style}` }, lg));
  return y + 10;
}

// Draws one tab into its own group, once, while it is displayed (getBBox and text measuring need
// it in the render tree). The pane's first tab carries its title and subtitle; any tab holding a
// graph or a sequence carries the legend its colours and line styles refer to.
function buildTab(t) {
  const pane = t.pane;
  building = t;
  t.marks = [];
  const frame = el("rect", { class: "pane-frame", rx: 24 }, t.g);
  const inner = el("g", { transform: `translate(${PANE_PAD} ${PANE_PAD})` }, t.g);
  let y = 0;
  if (t.idx === 0) {
    text(inner, 0, 30, pane.title, "pane-title");
    const subLines = glossLines(pane.subtitle || "", 190);
    subLines.forEach((ln, i) => glossText(inner, 0, 58 + i * 19, ln, "pane-sub"));
    y = 58 + subLines.length * 19 + 20;
  }
  if (t.rows.some(row => row.some(b => b.type === "graph" || b.type === "seq")))
    y = legend(inner, pane, 0, y + 12, 1800) + 40;

  let tabW = 0;
  for (const row of t.rows) {
    let x = 0, rowH = 0;
    for (const b of row) {
      const bg = el("g", { class: "block" }, inner);
      const content = el("g", {}, bg);
      let w;
      try { w = RENDER[b.type](b, content, pane, bg); }
      catch (e) { reportLate(`pane ${pane.id} / ${b.type} "${b.title || ""}"`, e); bg.remove(); continue; }
      let hy = 0;
      if (b.title) { text(bg, 0, 18, b.title, "block-title"); hy = 30; }
      if (b.note) {
        const lines = glossLines(b.note, Math.max(60, Math.floor(w / 6.7)));
        lines.forEach((ln, i) => glossText(bg, 0, hy + 12 + i * 17, ln, "block-sub"));
        hy += lines.length * 17 + 8;
      }
      content.setAttribute("transform", `translate(0 ${hy + (hy ? 14 : 0)})`);
      bg.setAttribute("transform", `translate(${x} ${y})`);
      const bb = bg.getBBox();
      x += Math.max(w, bb.x + bb.width) + COL_GAP;
      rowH = Math.max(rowH, bb.y + bb.height);
    }
    tabW = Math.max(tabW, x - COL_GAP);
    y += rowH + ROW_GAP;
  }
  // Highlight the glossary marks: measure them all, then insert (one layout, not one per mark).
  const boxes = t.marks.map(ts => ts.getBBox());
  t.marks.forEach((ts, i) => {
    const b = boxes[i], txt = ts.parentNode;
    txt.parentNode.insertBefore(el("rect", { x: b.x - 2, y: b.y, width: b.width + 4, height: b.height, rx: 3,
      class: "gl-bg", "data-gloss": ts.getAttribute("data-gloss") }), txt);
  });
  const hb = inner.getBBox();   // the header alone can be wider than the blocks
  const w = Math.max(tabW, hb.x + hb.width) + 2 * PANE_PAD, h = y - ROW_GAP + 2 * PANE_PAD;
  frame.setAttribute("x", 0); frame.setAttribute("y", 0);
  frame.setAttribute("width", w); frame.setAttribute("height", h);
  t.bounds = { x: 0, y: 0, w, h };
  t.built = true;
  building = null;
}

// ---------------------------------------------------------------- view (one per tab)
let view = { s: 1, tx: 0, ty: 0 };
let viewQueued = false;
const writeView = () => vp.setAttribute("transform", `translate(${view.tx} ${view.ty}) scale(${view.s})`);
// Pointer and wheel events outrun the display: coalesce them into one transform write per frame.
function applyView() {
  if (viewQueued) return;
  viewQueued = true;
  requestAnimationFrame(() => { viewQueued = false; writeView(); });
}
function fitBounds(b) {
  const r = svg.getBoundingClientRect();
  const s = Math.min(r.width / b.w, r.height / b.h) * 0.96;
  view.s = s;
  view.tx = (r.width - b.w * s) / 2 - b.x * s;
  view.ty = (r.height - b.h * s) / 2 - b.y * s;
  writeView();   // a fit lands at once: it is one write, and a tab switch must not show a stale view
}

// #<pane-id> opens a pane's first tab; #<pane-id>/<n> its n-th tab; #<pane-id>/<n>/<m> fits the
// m-th block of that tab (all 1-based, blocks in reading order). No hash opens the first pane.
function parseHash() {
  const [id, n, m] = decodeURIComponent(location.hash.slice(1)).split("/");
  const tabs = tabsByPane[id] || Object.values(tabsByPane)[0];
  if (!tabs) return null;
  const t = tabs[Math.min(tabs.length, Math.max(1, +n || 1)) - 1];
  return { t, block: +m || 0 };
}
function hashFor(t) { return `#${t.pane.id}${t.idx ? `/${t.idx + 1}` : ""}`; }

function fitTab(t, blockN) {
  const blk = blockN && t.g.querySelectorAll(":scope > g > .block")[blockN - 1];
  if (blk) {
    const b = blk.getBBox(), m = blk.transform.baseVal.consolidate().matrix, pad = 40;
    fitBounds({ x: PANE_PAD + m.e + b.x - pad, y: PANE_PAD + m.f + b.y - pad, w: b.width + 2 * pad, h: b.height + 2 * pad });
  } else fitBounds(t.bounds);
}

function openTab(t, blockN) {
  hideTip();
  if (active && active !== t) active.g.style.display = "none";
  t.g.style.display = "";
  const fresh = !t.built;
  if (fresh) buildTab(t);
  active = lastByPane[t.pane.id] = t;
  view = t.view;
  lastT = 0;   // a resumed simulation takes one ordinary step, not the whole time it was hidden
  if (fresh || blockN) fitTab(t, blockN);
  else writeView();
  syncNav();
}
function openFromHash() {
  const h = parseHash();
  if (h) openTab(h.t, h.block);
}

// ---- the two control rows
let paneNav, tabNav, pinLink;
function syncNav() {
  for (const b of paneNav.querySelectorAll("button"))
    b.classList.toggle("on", b.dataset.pane === active.pane.id);
  const pane = active.pane;
  if (tabNav.dataset.pane !== pane.id) {
    tabNav.dataset.pane = pane.id;
    tabNav.replaceChildren();
    for (const t of tabsByPane[pane.id]) {
      const b = document.createElement("button");
      b.textContent = t.label;
      b.title = `${hashFor(t)}  (click again to refit)`;
      b.onclick = () => {
        if (t === active) fitTab(t);
        else location.hash = hashFor(t);   // hashchange opens it, and Back returns to the last tab
      };
      t.button = b;
      tabNav.appendChild(b);
    }
    pinLink.href = `${VIZ.config.repo}/tree/${pane.commit}`;
    pinLink.textContent = `file:line links pinned @ ${pane.commit.slice(0, 9)} ↗${pane.pinNote ? `  (${pane.pinNote})` : ""}`;
  }
  for (const t of tabsByPane[pane.id]) t.button.classList.toggle("on", t === active);
}

function wirePanZoom() {
  svg.addEventListener("wheel", e => {
    e.preventDefault();
    const r = svg.getBoundingClientRect();
    const px = e.clientX - r.left, py = e.clientY - r.top;
    const s2 = Math.min(6, Math.max(0.03, view.s * Math.exp(-e.deltaY * 0.0015)));
    const k = s2 / view.s;
    view.tx = px - (px - view.tx) * k;
    view.ty = py - (py - view.ty) * k;
    view.s = s2;
    applyView();
  }, { passive: false });
  let pan = null;
  svg.addEventListener("mousedown", e => {
    dragMoved = false;
    const onContent = e.target.closest("[data-tip], [data-interactive], a");
    if (e.button === 1 || (e.button === 0 && !onContent)) {
      e.preventDefault();
      pan = { x: e.clientX, y: e.clientY };
      svg.classList.add("panning");
    }
  });
  window.addEventListener("mousemove", e => {
    if (!pan) return;
    if (Math.abs(e.clientX - pan.x) + Math.abs(e.clientY - pan.y) > 0) dragMoved = true;
    view.tx += e.clientX - pan.x;
    view.ty += e.clientY - pan.y;
    pan = { x: e.clientX, y: e.clientY };
    applyView();
  });
  window.addEventListener("mouseup", () => { pan = null; svg.classList.remove("panning"); });
  // Browser zoom (Cmd +/-) fires resize AND changes devicePixelRatio: refitting then would undo it.
  let lastDPR = window.devicePixelRatio;
  window.addEventListener("resize", () => {
    const dpr = window.devicePixelRatio;
    if (dpr !== lastDPR) { lastDPR = dpr; return; }
    const h = parseHash();
    if (active) fitTab(active, h && h.t === active ? h.block : 0);   // keep a #pane/tab/block zoom
  });
  window.addEventListener("hashchange", () => openFromHash());
}

// ---------------------------------------------------------------- tooltips + highlight
let dragMoved = false, hideTimer = null, overTip = false, pinnedKey = null, hoverKey = null;
function esc(s) { return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
const richText = s => glossSegs(s).map(r => r.code ? `<code>${esc(r.t.slice(1, -1))}</code>`
  : r.g ? `<span class="gl" data-gloss="${r.g}">${esc(r.t)}</span>` : esc(r.t)).join("");
function tipHtml(t) {
  // A live figure's tooltip reads its state when SHOWN: live() returns the fields to lay over.
  if (typeof t.live === "function") t = Object.assign({}, t, t.live());
  const links = linksOf(t).map(lk =>
    `<a href="${linkUrl(lk, t.commit)}" target="_blank" rel="noopener">${esc(linkLabel(lk))}${lk.url ? "" : " on GitHub"} ↗</a>`).join("");
  return `<div class="t-title">${esc(t.title)}</div>` +
    (t.sub ? `<div class="t-sub">${esc(t.sub)}</div>` : "") +
    (t.blurb ? `<div class="t-blurb">${richText(t.blurb)}</div>` : "") +
    (links ? `<div class="t-links">${links}</div>` : "");
}
function positionTip(e) {
  tip.style.display = "block";
  const r = tip.getBoundingClientRect();
  let x = e.clientX + 14, y = e.clientY + 12;
  if (x + r.width > window.innerWidth - 8) x = e.clientX - r.width - 10;
  if (y + r.height > window.innerHeight - 8) y = e.clientY - r.height - 10;
  tip.style.left = `${Math.max(4, x)}px`;
  tip.style.top = `${Math.max(4, y)}px`;
}
function clearHighlight() {
  for (const b of svg.querySelectorAll(".block.hovering")) b.classList.remove("hovering");
  for (const h of svg.querySelectorAll(".hl")) h.classList.remove("hl");
}
function show(t, e) {
  clearTimeout(hideTimer);
  clearHighlight();
  tip.innerHTML = tipHtml(t);
  if (t.hl.length) {
    t.block.classList.add("hovering");
    for (const k of t.hl) for (const n of t.block.querySelectorAll(`[data-hk~="${k}"]`)) n.classList.add("hl");
  }
  positionTip(e);
}
function hideTip() {
  pinnedKey = hoverKey = null;
  tip.style.display = "none";
  clearHighlight();
  hideGloss();
}
function scheduleHide() {
  clearTimeout(hideTimer);
  hideTimer = setTimeout(() => { if (!overTip && !overGloss) { tip.style.display = "none"; clearHighlight(); } }, 160);
}
function wireTips() {
  tip.addEventListener("mouseenter", () => { overTip = true; clearTimeout(hideTimer); });
  tip.addEventListener("mouseleave", () => { overTip = false; if (!pinnedKey) scheduleHide(); });
  const target = e => e.target.closest("[data-tip]");
  svg.addEventListener("mouseover", e => {
    // A glossary mark shows its own popup (wireGloss), never the tip of the row it sits in.
    if (e.target.closest("[data-gloss]")) {
      if (!pinnedKey && hoverKey !== null) { hoverKey = null; scheduleHide(); }
      return;
    }
    if (pinnedKey) return;
    const t = target(e);
    if (!t || t.dataset.tip === hoverKey) return;
    hoverKey = t.dataset.tip;
    show(tips[+hoverKey], e);
  });
  svg.addEventListener("mousemove", e => { if (!pinnedKey && hoverKey !== null && !overTip) positionTip(e); });
  svg.addEventListener("mouseout", e => {
    if (pinnedKey) return;
    const still = e.relatedTarget instanceof Element && e.relatedTarget.closest("[data-tip]");
    if (!still) { hoverKey = null; scheduleHide(); }
  });
  // Click pins a tooltip open so the pointer can reach its links; clicking empty space unpins.
  svg.addEventListener("click", e => {
    if (dragMoved) return;
    const t = target(e);
    if (t) { pinnedKey = hoverKey = t.dataset.tip; show(tips[+pinnedKey], e); }
    else if (pinnedKey) hideTip();
  });
}

// ---- the glossary popup: hovering a mark, in the canvas or inside a tooltip, explains the term
let gloss, glossTimer = null, overGloss = false;
function glossHtml(id) {
  const g = VIZ.gloss[id];
  const links = (g.links || []).map(lk =>
    `<a href="${esc(lk.url)}" target="_blank" rel="noopener">${esc(lk.label || lk.url)} ↗</a>`).join("");
  return `<div class="g-term">${esc(g.term)}</div>` +
    `<div class="g-body">${esc(g.body).replace(/`([^`]+)`/g, "<code>$1</code>")}</div>` +
    (links ? `<div class="g-links">${links}</div>` : "");
}
function showGloss(mark) {
  clearTimeout(glossTimer);
  gloss.innerHTML = glossHtml(mark.getAttribute("data-gloss"));
  gloss.style.display = "block";
  const a = mark.getBoundingClientRect(), r = gloss.getBoundingClientRect();
  let x = a.left, y = a.bottom + 6;
  if (x + r.width > window.innerWidth - 8) x = window.innerWidth - 8 - r.width;
  if (y + r.height > window.innerHeight - 8) y = a.top - r.height - 6;
  gloss.style.left = `${Math.max(4, x)}px`;
  gloss.style.top = `${Math.max(4, y)}px`;
}
function hideGloss() { clearTimeout(glossTimer); overGloss = false; if (gloss) gloss.style.display = "none"; }
function hideGlossSoon() {
  clearTimeout(glossTimer);
  glossTimer = setTimeout(() => { if (!overGloss) gloss.style.display = "none"; }, 220);
}
function wireGloss() {
  const mark = e => e.target instanceof Element && e.target.closest("[data-gloss]");
  for (const host of [svg, tip]) {
    host.addEventListener("mouseover", e => { const m = mark(e); if (m) showGloss(m); });
    host.addEventListener("mouseout", e => { if (mark(e)) hideGlossSoon(); });
  }
  gloss.addEventListener("mouseenter", () => { overGloss = true; clearTimeout(glossTimer); clearTimeout(hideTimer); });
  gloss.addEventListener("mouseleave", e => {
    overGloss = false;
    hideGlossSoon();
    const into = e.relatedTarget instanceof Element && e.relatedTarget.closest("#tooltip");
    if (!pinnedKey && !into && tip.style.display !== "none") scheduleHide();
  });
  svg.addEventListener("wheel", () => hideGloss(), { passive: true });
  svg.addEventListener("mousedown", () => hideGloss());
}

// ---------------------------------------------------------------- boot
function showErrors() {
  const box = document.getElementById("errors");
  box.textContent = `Viz data errors (a broken pane or block is not drawn):\n${VIZ.errors.join("\n")}`;
  box.style.display = VIZ.errors.length ? "block" : "none";
}
// A block that throws while its tab is built (lazily, on first open) is dropped from the tab.
function reportLate(where, e) {
  err(where, e.message);
  console.error(e);
  showErrors();
}

VIZ.render = function () {
  document.title = VIZ.config.title;
  document.getElementById("title").textContent = VIZ.config.title;
  svg = document.getElementById("world");
  tip = document.getElementById("tooltip");
  paneNav = document.getElementById("panes");
  tabNav = document.getElementById("tabs");
  pinLink = document.getElementById("pin");
  gloss = document.createElement("div");
  gloss.id = "gloss";
  document.body.appendChild(gloss);
  glossTerms();
  const defs = el("defs", {}, svg);
  const marker = el("marker", { id: "viz-arrow", viewBox: "0 0 10 8", refX: 9, refY: 4,
    markerWidth: 8, markerHeight: 6.5, orient: "auto-start-reverse" }, defs);
  el("path", { d: "M 0 0 L 10 4 L 0 8 z", style: "fill:var(--edge)" }, marker);
  vp = el("g", { id: "vp" }, svg);

  const seen = new Set();
  for (const p of VIZ.panes) {
    validatePane(p);
    if (seen.has(p.id)) err(`pane ${p.id}`, "duplicate pane id");
    seen.add(p.id);
    if (VIZ.errors.some(e => e.startsWith(`[pane ${p.id}`))) continue; // never draw a broken pane
    tabsByPane[p.id] = p._tabs.map((tab, idx) => ({
      pane: p, idx, label: tab.label, rows: tab.rows, built: false, frameFns: [],
      view: { s: 1, tx: 0, ty: 0 },
      g: el("g", { class: "tab", "data-pane": p.id, "data-tab": idx + 1, style: "display:none" }, vp),
    }));
    const b = document.createElement("button");
    b.textContent = p.short || p.title;
    b.dataset.pane = p.id;
    b.onclick = () => { if (!active || active.pane !== p) location.hash = hashFor(lastByPane[p.id] || tabsByPane[p.id][0]); };
    paneNav.appendChild(b);
  }
  wirePanZoom();
  wireTips();
  wireGloss();
  openFromHash();
  requestAnimationFrame(frameLoop);

  const nTabs = Object.values(tabsByPane).reduce((n, ts) => n + ts.length, 0);
  console.log(`[viz] ${VIZ.panes.length} pane(s), ${nTabs} tab(s), ${VIZ.errors.length} error(s)`);
  for (const e of VIZ.errors) console.error(e);
  showErrors();
};
document.addEventListener("DOMContentLoaded", () => VIZ.render());
})();
