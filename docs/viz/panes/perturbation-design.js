// Pane: the perturbation deep-zoom DESIGN (Help I'm Stuck In A Fractal), explained before any of it
// is code. Every file:line below was read at `commit` with `git show <commit>:<path>`: the spec and
// the research note by line (no code exists yet), plus the existing code a part will change.
// When the spec changes: re-read the lines, bump `commit`, run
// `node tools/viz/check.mjs --print --pane perturbation-design`. Once the code lands, the spec's
// own `deep-zoom` pane (spec part 7) explains the code; this one explains the decision.
//
// The live figures run a JavaScript port of the default Mandelbox (mb_step: box fold, sphere fold,
// scale, add; Mandelbrot mode, fold order 0, no rotation) in doubles and in emulated float32
// (Math.fround after every operation, as the spec's perturbation_test will with a
// PackedFloat32Array), plus the spec's clamp and radial difference formulas.
(function () {
const F = {
  spec: "docs/superpowers/specs/2026-10-09-perturbation-deep-zoom-design.md",
  note: "docs/reference/self-similar-substitution.md",
  zoom: "docs/superpowers/specs/2026-10-08-deep-zoom-march-design.md",
  cam: "src/camera/camera_state.gd",
  fly: "src/camera/fly_camera.gd",
  center: "src/camera/center_ray.gd",
  ws: "src/workspace/workspace.gd",
  params: "src/fractal/fractal_params.gd",
  view: "src/fractal/fractal_view.gd",
  sh: "src/fractal/mandelbox.gdshader",
  de: "src/fractal/distance_estimator.gd",
  kifs: "src/fractal/kifs_estimator.gd",
  main: "src/main.gd",
  movement: "src/ui/console/movement_pane.gd",
};
// Link helpers: S(175) is a spec line, N(364) a note line, R("fly", 147) a code line; the *L forms
// add a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const S = line => R("spec", line);
const SL = (line, label) => RL("spec", line, label);
const N = line => R("note", line);
const NL = (line, label) => RL("note", line, label);

// ================================================================== the ports
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const f32 = Math.fround;
const id = x => x;
const TAN_HALF_FOV = 0.36397023426620234;            // fractal_view.gd:11
const ASPECT = 1.6;                                  // a 16:10 window
const DEFAULT_EYE = [8.175847, 3.812460, 3.283393];   // camera_state.gd:9
// The default Mandelbox: fractal_params.gd:65-71 (box_scale, fold_limit, min_radius, fixed_radius)
// and :203 (precision); detail 1, so eps = precision / detail.
const BOX = { s: -2.09, L: 1, min: 0.7, fixed: 1, eps: 0.000025 };
BOX.mr2 = BOX.min * BOX.min; BOX.fr2 = BOX.fixed * BOX.fixed;
const PERT_MAX = 20, PERT_ON = 10, PERT_HANDOFF = 1e-2, DIVISOR = 50;   // spec 221-223, fractal_params.gd:398
const BOUND_HALF = 2;                                                   // the box's half-size (spec 248)

// ulp32: fractal_params.gd:404-414, the gap between neighbouring float32s near x. ulp64 likewise for
// a 64-bit double (52 bits after the leading one).
function ulp32(x) { x = Math.abs(x); return x < Math.pow(2, -126) ? Math.pow(2, -149) : Math.pow(2, Math.floor(Math.log2(x)) - 23); }
function ulp64(x) { x = Math.abs(x); return Math.pow(2, Math.floor(Math.log2(x)) - 52); }
const maxAbs = v => Math.max(Math.abs(v[0]), Math.abs(v[1]), Math.abs(v[2]));
// floor32: today's zoom_floor (fractal_params.gd:426-428), the formula the spec keeps as `floor32`.
const floor32 = eye => ulp32(maxAbs(eye)) / (DIVISOR * BOX.eps);

// One iteration of the default Mandelbox with every arithmetic result passed through Rn (id = 64-bit,
// f32 = float32): mb_step (mandelbox.gdshader:275-282) with mb_box_fold (151-153) and
// mb_sphere_fold (157-170). Returns the new dz.
function stepR(z, dz, c, Rn) {
  for (let a = 0; a < 4; a++) z[a] = Rn(Rn(clamp(z[a], -BOX.L, BOX.L) * 2) - z[a]);
  const r2 = Rn(Rn(Rn(Rn(z[0] * z[0]) + Rn(z[1] * z[1])) + Rn(z[2] * z[2])) + Rn(z[3] * z[3]));
  let m = 1;
  if (r2 < BOX.mr2) m = Rn(BOX.fr2 / BOX.mr2);
  else if (r2 < BOX.fr2) m = Rn(BOX.fr2 / Math.max(r2, 1e-12));
  const s = Rn(BOX.s);
  for (let a = 0; a < 4; a++) z[a] = Rn(Rn(s * Rn(z[a] * m)) + c[a]);
  return Rn(Rn(Rn(dz * m) * Math.abs(s)) + 1);
}
const dot4 = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
const len4 = v => Math.sqrt(dot4(v, v));
function de64(p) {
  const z = [p[0], p[1], p[2], 0], c = z.slice();
  let dz = 1;
  for (let i = 0; i < 32; i++) dz = stepR(z, dz, c, id);
  return len4(z) / Math.abs(dz);
}

// ReferenceOrbit.build (spec 109-150) for the default box, in doubles: X_0..X_32, λ_0..λ_32 (the
// product of |scale| and the sphere factors: dz without its + 1s, spec 127-129), and per iteration
// the record (spec 135-137): the clamp gaps lo − X and hi − X, the sphere fold's input point c,
// |Xs|² − min², |Xs|² − fixed², the factor m and its regime (0 inside, 1 shell, 2 outside).
function refOrbit(e) {
  const z = [e[0], e[1], e[2], 0], c = z.slice();
  const X = [z.slice()], mag = [1], rec = [];
  let lam = 1, dz = 1;
  for (let i = 0; i < 32; i++) {
    const r = { lo: z.map(v => -BOX.L - v), hi: z.map(v => BOX.L - v) };
    for (let a = 0; a < 4; a++) z[a] = clamp(z[a], -BOX.L, BOX.L) * 2 - z[a];
    const r2 = dot4(z, z);
    let m = 1, reg = 2;
    if (r2 < BOX.mr2) { m = BOX.fr2 / BOX.mr2; reg = 0; } else if (r2 < BOX.fr2) { m = BOX.fr2 / r2; reg = 1; }
    Object.assign(r, { c: z.slice(), r2, gmin: r2 - BOX.mr2, gfix: r2 - BOX.fr2, m, reg });
    for (let a = 0; a < 4; a++) z[a] = BOX.s * (z[a] * m) + c[a];
    lam *= m * Math.abs(BOX.s);
    dz = (dz * m) * Math.abs(BOX.s) + 1;
    rec.push(r); X.push(z.slice()); mag.push(lam);
  }
  return { X, mag, rec, n: 32, distance: len4(z) / Math.abs(dz) };
}

// pert_iters (spec 225-228): 0 above PERT_ON × today's floor, else the smallest k with
// λ_k × near ≥ PERT_HANDOFF, else PERT_MAX.
function pertIters(o, near, eye) {
  if (near >= PERT_ON * floor32(eye)) return 0;
  const K = Math.min(PERT_MAX, o.n);
  for (let k = 1; k <= K; k++) if (o.mag[k] * near >= PERT_HANDOFF) return k;
  return K;
}
// The two floors of spec part 5 (245-253), from a reference orbit at the eye.
function floorPert(o) { const K = Math.min(PERT_MAX, o.n); return ulp32(Math.max(...o.X[K].map(Math.abs))) / (DIVISOR * BOX.eps * o.mag[K]); }
function floorIter(o) { return BOUND_HALF / (BOX.eps * o.mag[32]); }

// The clamp-fold difference (spec 173-178): δ' = 2 (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ.
const clampDiff = (d, glo, ghi, Rn = id) => Rn(Rn(2 * Rn(clamp(d, glo, ghi) - clamp(0, glo, ghi))) - d);
// The radial-fold factor difference m' − m per regime pair (spec 179-192), the sphere fold's
// constants as given. q = |P|² − |X|², gmin = |X|² − min², gfix = |X|² − fixed².
function dmPair(regX, regP, q, gmin, gfix, r2X, r2P, mr2, fr2, Rn = id) {
  if (regX === regP && regX !== 1) return 0;
  if (regX === 1 && regP === 1) return Rn(-Rn(fr2 * q) / Rn(r2P * r2X));
  if (regX === 0 && regP === 1) return Rn(-Rn(fr2 * Rn(gmin + q)) / Rn(r2P * mr2));
  if (regX === 1 && regP === 0) return Rn(Rn(fr2 * gmin) / Rn(mr2 * r2X));
  if (regX === 1 && regP === 2) return Rn(gfix / r2X);
  if (regX === 2 && regP === 1) return Rn(-Rn(gfix + q) / r2P);
  return regX === 0 ? Rn(1 - Rn(fr2 / mr2)) : Rn(Rn(fr2 / mr2) - 1);   // inside ↔ outside: the constant difference
}
const regimeOf = (g1, g2) => (g1 < 0 ? 0 : g2 < 0 ? 1 : 2);   // g1 = |P|² − min², g2 = |P|² − fixed²

// One perturbed iteration of the default box on the pixel's offset d (4 floats), every operation
// through Rn: the clamp formula per component, the sphere fold's m' δ + X (m' − m), then
// δ' = s δ + δc (spec 204-206; δc = the starting offset in Mandelbrot mode). The record's values
// are read through Rn as the GPU would read its float32 uniforms. Returns the pixel's new dz.
function pertStep(d, dc, rec, dz, Rn) {
  for (let a = 0; a < 4; a++) d[a] = clampDiff(d[a], Rn(rec.lo[a]), Rn(rec.hi[a]), Rn);
  const Xs = rec.c.map(Rn), gmin = Rn(rec.gmin), gfix = Rn(rec.gfix), r2X = Rn(rec.r2), m = Rn(rec.m);
  let xd = 0, dd = 0;
  for (let a = 0; a < 4; a++) { xd = Rn(xd + Rn(Xs[a] * d[a])); dd = Rn(dd + Rn(d[a] * d[a])); }
  const q = Rn(Rn(2 * xd) + dd);
  const regP = regimeOf(Rn(gmin + q), Rn(gfix + q));
  const r2P = Rn(r2X + q), mr2 = Rn(BOX.mr2), fr2 = Rn(BOX.fr2);
  const mP = regP === 0 ? Rn(fr2 / mr2) : regP === 1 ? Rn(fr2 / r2P) : 1;
  const dm = dmPair(rec.reg, regP, q, gmin, gfix, r2X, r2P, mr2, fr2, Rn);
  for (let a = 0; a < 4; a++) d[a] = Rn(Rn(mP * d[a]) + Rn(Xs[a] * dm));
  const s = Rn(BOX.s);
  for (let a = 0; a < 4; a++) d[a] = Rn(Rn(s * d[a]) + dc[a]);
  return Rn(Rn(Rn(dz * mP) * Math.abs(s)) + 1);
}

// The deep views: the default view's centre ray, marched in doubles to its surface point SURF; a
// camera at distance d is SURF − forward × d, looking along the same ray.
const norm = v => { const l = Math.hypot(v[0], v[1], v[2]); return [v[0] / l, v[1] / l, v[2] / l]; };
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const FWD = norm(DEFAULT_EYE.map(x => -x));
const RIGHT = norm(cross(FWD, [0, 0, 1])), UP = cross(RIGHT, FWD);
const SURF = (function () {
  let t = 0;
  for (let i = 0; i < 20000; i++) {
    const p = DEFAULT_EYE.map((e, a) => e + FWD[a] * t), d = de64(p);
    if (d < 1e-14) return p;
    t += d;
  }
  return DEFAULT_EYE.map((e, a) => e + FWD[a] * t);
})();
const eyeAt = d => SURF.map((s, a) => s - FWD[a] * d);
const PIXELS = { centre: [0, 0], edge: [1, 0], corner: [1, 1] };
const pixelDir = ([nx, ny]) => norm([0, 1, 2].map(a => FWD[a] + nx * ASPECT * TAN_HALF_FOV * RIGHT[a] + ny * TAN_HALF_FOV * UP[a]));

// One sample of one pixel, three ways: exact (doubles from the 64-bit eye), perturbed (float32:
// k perturbed steps on δ, then today's loop from X_k + δ_k), and direct (float32: today's
// `eye + dir × t`, then 32 ordinary steps). t = d. Per iteration, the offset each path implies and
// its relative error against the exact offset P_i − X_i.
function pixelRun(d, pix) {
  const eye = eyeAt(d), o = refOrbit(eye), near = o.distance, k = pertIters(o, near, eye);
  const dir = pixelDir(pix), off = dir.map(v => v * d);
  // exact
  const Pe = [eye[0] + off[0], eye[1] + off[1], eye[2] + off[2], 0], ce = Pe.slice(), ex = [Pe.slice()];
  let dze = 1;
  for (let i = 0; i < 32; i++) { dze = stepR(Pe, dze, ce, id); ex.push(Pe.slice()); }
  // direct float32
  const e32 = eye.map(f32), o32 = off.map(f32);
  const Pd = [f32(e32[0] + o32[0]), f32(e32[1] + o32[1]), f32(e32[2] + o32[2]), 0], cd = Pd.slice(), di = [Pd.slice()];
  let dzd = 1;
  for (let i = 0; i < 32; i++) { dzd = stepR(Pd, dzd, cd, f32); di.push(Pd.slice()); }
  // perturbed float32 (k may be 0 above PERT_ON: then it is the direct path)
  const dl = [o32[0], o32[1], o32[2], 0], dc = dl.slice(), pe = [dl.slice()];
  let dzp = 1, z = null;
  for (let i = 0; i < k; i++) { dzp = pertStep(dl, dc, o.rec[i], dzp, f32); pe.push(dl.slice()); }
  if (k > 0) {
    z = o.X[k].map((x, a) => f32(f32(x) + dl[a]));
    const cc = [f32(e32[0] + o32[0]), f32(e32[1] + o32[1]), f32(e32[2] + o32[2]), 0];   // the pixel's own c, as the loop adds it
    for (let i = k; i < 32; i++) { dzp = stepR(z, dzp, cc, f32); pe.push(z.map((v, a) => v - o.X[i + 1][a])); }
  }
  const errOf = (i, got) => { const dEx = ex[i].map((v, a) => v - o.X[i][a]); const n = len4(dEx); return n > 0 ? len4(got.map((v, a) => v - dEx[a])) / n : 0; };
  const errP = [], errD = [], exD = [];
  for (let i = 0; i <= 32; i++) {
    exD.push(ex[i].map((v, a) => v - o.X[i][a]));
    errD.push(errOf(i, di[i].map((v, a) => v - o.X[i][a])));
    errP.push(k > 0 ? errOf(i, pe[i]) : errD[i]);
  }
  const deE = len4(ex[32]) / Math.abs(dze), deD = len4(di[32]) / Math.abs(dzd), deP = k > 0 ? len4(z) / Math.abs(dzp) : deD;
  const lost = len4([f32(e32[0] + o32[0]) - (eye[0] + off[0]), f32(e32[1] + o32[1]) - (eye[1] + off[1]), f32(e32[2] + o32[2]) - (eye[2] + off[2]), 0]) / d;
  return { eye, o, near, k, off, exD, pe, di, errP, errD, deE, deD, deP, lost };
}

// ================================================================== drawing helpers
const fmt = (x, n = 3) => { if (!isFinite(x)) return String(x); const s = x.toFixed(n); return /^-0\.?0*$/.test(s) ? s.slice(1) : s; };
const sci = (x, n = 2) => (x === 0 ? "0" : !isFinite(x) ? String(x) : (Math.abs(x) >= 1e-3 && Math.abs(x) < 1e4) ? fmt(x, n + 1) : x.toExponential(n).replace("-", "−"));
const pct = x => (x >= 0.01 ? `${fmt(x * 100, 1)}%` : sci(x, 1));
const caps = "font-weight:600;letter-spacing:.06em";
const small = "font-size:10.5px";
const noPtr = "pointer-events:none";
const mono = "font-size:11.5px";
function clear(g) { while (g.firstChild) g.removeChild(g.firstChild); }
// Draggable SVG handle (the engine treats [data-interactive] as content, so dragging never pans).
function draggable(api, elem, onDrag) {
  elem.setAttribute("data-interactive", "");
  let drag = false;
  elem.addEventListener("mousedown", e => { e.stopPropagation(); e.preventDefault(); drag = true; });
  window.addEventListener("mousemove", e => { if (drag) onDrag(api.local(e)); });
  window.addEventListener("mouseup", () => { drag = false; });
}
// A log-axis frame: horizontal grid lines and labels every `ystep` of log10, x ticks given.
function logFrame(api, X, Y, W, H, y0, y1, ystep, xticks, xlab, ylab) {
  api.el("rect", { x: X, y: Y, width: W, height: H, style: "fill:var(--surface);stroke:var(--hairline)" });
  const ly = v => Y + (y0 - clamp(v, y1, y0)) / (y0 - y1) * H;
  for (let v = y1; v <= y0 + 1e-9; v += ystep) {
    api.el("line", { x1: X, y1: ly(v), x2: X + W, y2: ly(v), style: "stroke:var(--hairline);stroke-width:1" });
    api.text(X - 6, ly(v) + 4, `1e${v}`.replace("-", "−"), "muted", { "text-anchor": "end", style: "font-size:9.5px" });
  }
  for (const [x, label] of xticks) api.text(x, Y + H + 15, label, "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
  if (xlab) api.text(X + W / 2, Y + H + 32, xlab, "muted", { "text-anchor": "middle", style: small });
  if (ylab) api.text(X, Y - 10, ylab, "ink", { style: caps });
  return ly;
}
const swatch = (api, x, y, color, label, dash) => {
  api.el("line", { x1: x, y1: y - 4, x2: x + 22, y2: y - 4, style: `stroke:${color};stroke-width:2.4${dash ? `;stroke-dasharray:${dash}` : ""}` });
  api.text(x + 28, y, label, "muted", { style: small });
};

// ================================================================== 1. the problem
const problemFig = {
  type: "figure",
  tab: "The problem",
  title: "Why the camera stops at about 1e−4 today",
  note: "The shader forms every ray position as `eye + dir × t` in 32-bit floats, which near the eye can only land on a grid ulp32(max |eye|) apart: about 1.2e−7 here, where the deep camera's coordinates are around 2. Drag d. The view (2 tan 20° × d high) shrinks to a handful of grid steps, the hit threshold eps × d drops far below the grid, and today's guard stops the camera where eps × d reaches the grid ÷ 50. The eye itself is a `Vector3` on the same grid: below about 1e−5 a physics tick's move is under half a grid step and rounds to nothing. The eye here is the default view's centre-ray surface point (found by a 64-bit march in the port) backed off by d. The two squares on the right draw the view on the 32-bit grid, and the same view after the k perturbed iterations the design would run, where it is λ_k times bigger.",
  w: 1500, h: 840,
  draw(api) {
    const C = { view: api.hue(3), eps: api.hue(1), grid: api.hue(2), tick: api.hue(5), u64: api.hue(6), floor: api.hue(4) };
    const CX = 80, CY = 96, CW = 800, CH = 580;
    const XA = 0, XB = -14;
    const lx = v => CX + (v - XA) / (XB - XA) * CW;
    const xt = [];
    for (let v = 0; v >= -14; v -= 2) xt.push([lx(v), `1e${v}`.replace("-", "−")]);
    const ly = logFrame(api, CX, CY, CW, CH, 1, -17, 2, xt, "camera distance d to the surface point (deeper →)", "lengths, world units (log)");
    // samples
    const smp = [];
    for (let v = 0; v >= -14.0001; v -= 0.05) {
      const d = Math.pow(10, v), eye = eyeAt(d), m = maxAbs(eye), o = refOrbit(eye), k = pertIters(o, o.distance, eye);
      const H = 2 * TAN_HALF_FOV * d;
      smp.push({ v, d, H, ulp: ulp32(m), u64: ulp64(m), eps: BOX.eps * d, tick: d / 60, hand: k > 0 ? o.mag[k] * H : null });
    }
    const curve = (key, color, dash, w = 2.2) => {
      const pts = smp.filter(s => s[key] !== null && s[key] > 0).map(s => `${lx(s.v)},${ly(Math.log10(s[key]))}`);
      api.el("polyline", { points: pts.join(" "), style: `fill:none;stroke:${color};stroke-width:${w}${dash ? `;stroke-dasharray:${dash}` : ""};${noPtr}` });
    };
    // the floors (vertical markers)
    const deepO = refOrbit(eyeAt(1e-9));
    const F32 = floor32(eyeAt(1e-4)), FP = floorPert(deepO);
    const vline = (d, color, label, yOff, dash) => {
      const x = lx(Math.log10(d));
      api.el("line", { x1: x, y1: CY, x2: x, y2: CY + CH, style: `stroke:${color};stroke-width:1.6;stroke-dasharray:${dash || "6 4"};${noPtr}` });
      api.text(x + 5, CY + yOff, label, "", { style: `fill:${color};font-size:10.5px;font-weight:600;${noPtr}` });
    };
    vline(F32, C.floor, `today's floor ${sci(F32)}`, 16);
    vline(FP, C.u64, `floor_pert ${sci(FP)}`, 16);
    curve("H", C.view);
    curve("eps", C.eps);
    curve("ulp", C.grid);
    curve("tick", C.tick, "5 4", 1.8);
    curve("u64", C.u64);
    curve("hand", C.view, "2 4", 2);
    api.el("polyline", { points: smp.map(s => `${lx(s.v)},${ly(Math.log10(s.ulp / DIVISOR))}`).join(" "), style: `fill:none;stroke:${C.grid};stroke-width:1.4;stroke-dasharray:6 4;${noPtr}` });
    // legend
    const LY = CY + CH + 56;
    swatch(api, CX, LY, C.view, "view height 2 tan 20° × d");
    swatch(api, CX + 220, LY, C.eps, "hit threshold eps × d");
    swatch(api, CX + 420, LY, C.grid, "ulp32: the float32 grid near the eye");
    swatch(api, CX + 670, LY, C.grid, "grid ÷ 50 (today's rule)", "6 4");
    swatch(api, CX, LY + 20, C.tick, "one physics tick's move, ≈ d / 60", "5 4");
    swatch(api, CX + 220, LY + 20, C.u64, "ulp64: the 64-bit eye's grid");
    swatch(api, CX + 420, LY + 20, C.view, "the view after k perturbed iterations, λ_k × height", "2 4");
    // cursor
    const curG = api.el("g", { style: noPtr });
    // the two squares
    const SQ = 230, AX = 940, BX = 1220, SY = 110;
    api.text(AX, SY - 12, "the view at d, on the float32 grid", "ink", { style: caps });
    api.text(BX, SY - 12, "the same view after k perturbed steps", "ink", { style: caps });
    const sqA = api.el("g", {}), sqB = api.el("g", {});
    const capA = api.text(AX, SY + SQ + 18, "", "muted", { style: small }), capA2 = api.text(AX, SY + SQ + 33, "", "muted", { style: small });
    const capB = api.text(BX, SY + SQ + 18, "", "muted", { style: small }), capB2 = api.text(BX, SY + SQ + 33, "", "muted", { style: small });
    function square(g, x, y, H, ulp, thr, phase) {
      clear(g);
      api.el("rect", { x, y, width: SQ, height: SQ, style: "fill:var(--surface);stroke:var(--muted);stroke-width:1.2" }, g);
      const n = H / ulp;
      if (n <= 26) {
        const step = SQ / n, o0 = (1 - phase) * step;
        for (let i = 0; o0 + i * step <= SQ; i++) for (let j = 0; o0 + j * step <= SQ; j++)
          api.el("circle", { cx: x + o0 + i * step, cy: y + o0 + j * step, r: 2.4, style: `fill:${C.grid};${noPtr}` }, g);
      } else if (n <= 160) {
        const step = SQ / n, o0 = (1 - phase) * step;
        for (let i = 0; o0 + i * step <= SQ; i++) {
          api.el("line", { x1: x + o0 + i * step, y1: y, x2: x + o0 + i * step, y2: y + SQ, style: `stroke:${C.grid};stroke-width:.6;opacity:.7;${noPtr}` }, g);
          api.el("line", { x1: x, y1: y + o0 + i * step, x2: x + SQ, y2: y + o0 + i * step, style: `stroke:${C.grid};stroke-width:.6;opacity:.7;${noPtr}` }, g);
        }
      } else {
        api.el("rect", { x: x + 1, y: y + 1, width: SQ - 2, height: SQ - 2, style: `fill:${C.grid};opacity:.08;${noPtr}` }, g);
        api.text(x + SQ / 2, y + SQ / 2 + 4, "grid finer than the drawing:", "muted", { "text-anchor": "middle", style: small }, g);
        api.text(x + SQ / 2, y + SQ / 2 + 20, "effectively continuous", "muted", { "text-anchor": "middle", style: small }, g);
      }
      if (thr !== null) {
        const r = Math.max(thr / H * SQ, 1.6);
        api.el("circle", { cx: x + SQ / 2, cy: y + SQ / 2, r: Math.min(r, SQ / 2), style: `fill:none;stroke:${C.eps};stroke-width:2;${noPtr}` }, g);
        api.el("circle", { cx: x + SQ / 2, cy: y + SQ / 2, r: 2, style: `fill:${C.eps};${noPtr}` }, g);
      }
      return n;
    }
    const outY = SY + SQ + 66;
    api.text(AX, outY - 8, "at this d", "ink", { style: caps });
    const out = [];
    for (let i = 0; i < 15; i++) out.push(api.text(AX, outY + 14 + i * 19, "", "mono", { style: mono }));
    const S0 = { v: -5.5 };
    function render() {
      const d = Math.pow(10, S0.v), eye = eyeAt(d), m = maxAbs(eye), u = ulp32(m), H = 2 * TAN_HALF_FOV * d;
      const o = refOrbit(eye), near = o.distance, k = pertIters(o, near, eye), F = floor32(eye);
      const fp = floorPert(o), fi = floorIter(o);
      clear(curG);
      const x = lx(S0.v);
      api.el("line", { x1: x, y1: CY, x2: x, y2: CY + CH, style: "stroke:var(--ink);stroke-width:1.4" }, curG);
      api.text(x + 5, CY + CH - 8, `d = ${sci(d)}`, "ink", { style: "font-size:11px;font-weight:600" }, curG);
      const fiX = lx(Math.log10(fi));
      if (fiX >= CX && fiX <= CX + CW) {
        api.el("line", { x1: fiX, y1: CY, x2: fiX, y2: CY + CH, style: `stroke:${C.tick};stroke-width:1.4;stroke-dasharray:2 3` }, curG);
        api.text(fiX + 5, CY + 34, `floor_iter at this eye ${sci(fi)}`, "", { style: `fill:${C.tick};font-size:10.5px;font-weight:600` }, curG);
      }
      for (const [key, color] of [["H", C.view], ["eps", C.eps], ["ulp", C.grid], ["tick", C.tick]]) {
        const s = smp[Math.round(-S0.v / 0.05)];
        api.el("circle", { cx: x, cy: ly(Math.log10(s[key])), r: 4, style: `fill:${color};stroke:var(--surface);stroke-width:1.5` }, curG);
      }
      const nA = square(sqA, AX, SY, H, u, BOX.eps * d, ((SURF[1] / u) % 1 + 1) % 1);
      capA.textContent = `${sci(nA, 1)} grid steps across`;
      capA2.textContent = "blue ring: the hit threshold (≥ 1.6 px)";
      if (k > 0) {
        const HB = o.mag[k] * H, uB = ulp32(Math.max(...o.X[k].map(Math.abs)));
        const nB = square(sqB, BX, SY, HB, uB, null, 0.37);
        capB.textContent = `k = ${k}: the view is λ_k = ${sci(o.mag[k])} × bigger`;
        capB2.textContent = `${sci(nB, 1)} steps of ulp32(X_k) across`;
      } else {
        clear(sqB);
        api.el("rect", { x: BX, y: SY, width: SQ, height: SQ, style: "fill:var(--surface);stroke:var(--hairline);stroke-dasharray:4 4" }, sqB);
        api.text(BX + SQ / 2, SY + SQ / 2 - 6, "pert_iters = 0: perturbation off", "muted", { "text-anchor": "middle", style: small }, sqB);
        api.text(BX + SQ / 2, SY + SQ / 2 + 12, `(on below 10 × floor = ${sci(PERT_ON * F)})`, "muted", { "text-anchor": "middle", style: small }, sqB);
        capB.textContent = "today's path runs unchanged"; capB2.textContent = "";
      }
      const tickSteps = d / 60 / u;
      const L = [
        `eye = surface point − forward × d · max |coordinate| ${fmt(m, 3)}`,
        `ulp32 = ${sci(u)}: the float32 grid (ray positions, Vector3 eye)`,
        `view height ${sci(H)} = ${sci(H / u, 1)} grid steps`,
        `hit threshold eps × d = ${sci(BOX.eps * d)} = grid ÷ ${sci(u / (BOX.eps * d), 1)}`,
        `today's floor ulp32 / (50 eps) = ${sci(F)}: ${d >= F ? "d is above it, today's path works" : "d is below it, refused today"}`,
        `eye positions between eye and surface: d / ulp32 = ${sci(d / u, 1)}`,
        `one tick's move d / 60 = ${sci(d / 60)} = ${sci(tickSteps, 1)} grid steps${tickSteps < 0.5 ? ": rounds to nothing" : ""}`,
        `with the 64-bit eye: ulp64 = ${sci(ulp64(m))}, that move is ${sci(d / 60 / ulp64(m), 1)} steps`,
        `near = de(eye) = ${sci(near)} (the ray itself hits at d)`,
        k > 0 ? `pert_iters k = ${k}: λ_k × near = ${sci(o.mag[k] * near)} (rule: ≥ 1e−2, k ≤ 20)` : `pert_iters 0: near ≥ 10 × today's floor (${sci(PERT_ON * F)})`,
        k > 0 ? `handoff view λ_k × height = ${sci(o.mag[k] * H)} at max |X_k| ${sci(Math.max(...o.X[k].map(Math.abs)))}` : "",
        `floor_pert = ulp32(X_20) / (50 eps λ_20) = ${sci(fp)}`,
        `floor_iter = 2 / (eps λ_32) = ${sci(fi)} (λ_32 of this eye = ${sci(o.mag[32])})`,
        `zoom_floor = max of the two = ${sci(Math.max(fp, fi))}: ${near >= Math.max(fp, fi) ? "allowed here" : "below it (see Decisions)"}`,
      ];
      L.forEach((t, i) => { out[i].textContent = t; });
      out[4].style.fill = d >= F ? "" : api.hue(2);
    }
    api.slider({ x: CX, y: 34, w: 520, label: "camera distance d (log)", min: -13, max: 0, step: 0.05, value: S0.v,
      fmt: v => sci(Math.pow(10, v)), onChange: v => { S0.v = v; render(); } });
    // hoverable explanations of each line, in the legend
    const legendTip = (x, y, w, t) => { const r = api.el("rect", { x, y: y - 14, width: w, height: 18, fill: "transparent", style: "cursor:help" }); api.tip(r, t); };
    legendTip(CX, LY, 210, { title: "the view's height at the surface", ...S(29), blurb: "A pixel's sample is the eye plus δ_0 = dir × t. The whole 40° view at distance d spans 2 tan 20° × d, about 0.73 d. Today the shader adds that to the eye in float32, so the whole view has to fit on the eye's 32-bit grid: at d = 1e−6 it is about 6 grid steps tall, which is the note's 'only about 8 grid steps wide'.", links: [NL(83, "note: 8 grid steps at 1e−6"), RL("sh", 442, "pos = eye + dir * total")] });
    legendTip(CX + 220, LY, 190, { title: "the hit threshold", ...R("zoom", 128), blurb: "A ray stops when the estimate falls below eps × t (eps = precision / detail = 2.5e−5 by default, t ≈ d). Once that is much finer than the grid, rays reach the surface only by luck: speckle, shimmer, pits. Today's guard stops the camera where eps × d = ulp32 / 50.", links: [RL("params", 426, "zoom_floor"), RL("params", 398, "ZOOM_FLOOR_DIVISOR = 50"), SL(10, "spec: the problem")] });
    legendTip(CX + 420, LY, 240, { title: "ulp32: the float32 grid near the eye", ...R("params", 404), blurb: "2^(floor(log2 |x|) − 23): about 1.2e−7 for coordinates between 1 and 2, 2.4e−7 between 2 and 4, 9.5e−7 near the default eye's 8.2. WebGL 2 has nothing wider than float32, and Godot's `Vector3` is float32 too, so the camera's own position sits on this grid.", links: [SL(13, "spec: 1.2e−7 to 9.5e−7"), SL(72, "spec: Transform3D's origin is 32-bit")] });
    legendTip(CX, LY + 20, 210, { title: "one physics tick's move", ...R("fly", 150), blurb: "The fly camera's speed is about the distance to the surface (base_speed), so at 60 physics ticks a second one tick moves about d / 60. In a `Vector3` a move under half a grid step rounds to nothing: below about 1e−5 the eye cannot move at all, whatever the floor says. Hence spec part 1: the eye becomes three 64-bit doubles and the step is added in 64-bit; the speed clamp's floor drops from 1e−6 to 1e−14.", links: [RL("fly", 82, "t.origin += dir × speed × delta"), SL(91, "spec: the step in 64-bit"), SL(100, "spec: SPEED_FLOOR 1e−14")] });
    legendTip(CX + 220, LY + 20, 190, { title: "ulp64: the 64-bit eye", ...S(77), blurb: "GDScript floats are 64-bit doubles: 52 bits after the leading one, a grid of about 2.2e−16 near 1 to 2. CameraState gains eye_x, eye_y, eye_z as the truth; transform.origin becomes the rounded shadow every 32-bit consumer keeps reading.", links: [SL(80, "set_eye64"), RL("cam", 11, "today: transform")] });
    legendTip(CX + 420, LY + 20, 380, { title: "the view after k perturbed iterations", ...S(43), blurb: "After k iterations the pixel's offset has grown by the magnification λ_k (about |scale| per iteration, more when the sphere fold fires). The design hands off once λ_k × near reaches 1e−2: from there the view is big compared with the float32 grid at X_k, and X_k + δ_k in float32 is as good as exact. The dotted line is the handed-off view's height; it starts where perturbation switches on (10 × today's floor). It is jagged because k follows near, the eye's distance to the nearest surface, which jumps about as the eye passes other filaments (it can be far less than d, the distance to the point being viewed); where λ_20 × near stays under 1e−2, k sits at the cap of 20.", links: [SL(225, "pert_iters"), SL(222, "PERT_ON = 10")] });
    render();
  },
};

// ================================================================== 2. three approaches
const approachTable = {
  type: "table",
  title: "Three ways past the 32-bit floor",
  note: "The research note measured three fixes with a Python copy of the estimator, in emulated float32 against a float64 reference (81 rays × 3 views per shape and depth; a ray agrees when it lands in the same class and, for a hit, within 0.1% of the distance). Hover a row for the note's line.",
  columns: [{ label: "", w: 170 }, { label: "substitution (camera map)", w: 330 }, { label: "two-float camera", w: 330 }, { label: "perturbation (built)", w: 330 }],
  rows: [
    { cells: ["how it works", "the CPU maps the camera through k iterations in float64; the GPU marches from the image camera with the remaining 32 − k", "the GPU carries each number of the first k iterations as a pair of float32s (about 48 bits), per pixel", "the CPU runs the eye's reference orbit in float64; the GPU iterates only each pixel's small offset δ from it, then hands off"],
      tip: { title: "how each works", ...N(86), links: [NL(86, "substitution"), NL(338, "two-float"), NL(344, "perturbation")] } },
    { cells: ["rays right at d = 1e−5 … 1e−7", "68–100% at the best k, seams elsewhere", "97–100% (k = 16), 100% (k = 20)", "97–100% (k = 16), 94–100% (k = 20)"],
      tip: { title: "accuracy", ...N(364), blurb: "Today's float32 march gets 0–23% of rays right at these depths (section 3).", links: [NL(233, "the per-shape table"), NL(27, "today: 0–23%")] } },
    { cells: ["shapes", "all without noise displacement (needs c following the point in Mandelbrot mode)", "all", "all piecewise-linear folds (spec: not the octahedral or poly fold, not the Mandelbulb)"],
      tip: { title: "shapes", ...N(365), links: [SL(55, "spec: not perturbed")] } },
    { cells: ["GPU cost per ray at depth", "none extra (fewer GPU iterations)", "about 7×: a paired-float iteration costs about 13 plain ones, × 16 iterations", "about 1.5–2×: a difference iteration costs about 2 plain ones"],
      tip: { title: "cost (estimates from operation counts)", ...N(366), blurb: "Estimates, not measurements: the investigation had no GPU. They apply only below the zoom floor, where the method is switched on; normal views cost exactly what they cost now.", links: [NL(372, "the caveat")] } },
    { cells: ["CPU cost", "one orbit and its Jacobian per frame", "none", "one orbit per frame: 32 iterates, microseconds"], tip: { title: "CPU cost", ...N(367) } },
    { cells: ["GPU data", "4 vec4 + 2 floats", "the eye as two vec3s", "a record per iteration as uniform arrays (spec: 4 vec4 × 20)"], tip: { title: "GPU data", ...N(368), links: [SL(154, "spec: the uniforms")] } },
    { cells: ["shader complexity", "moderate, many special cases (normals, colour, clip, fallback)", "moderate: a small paired-float library, isolated in de", "moderate: a case analysis per fold, isolated in de"], tip: { title: "complexity", ...N(369) } },
    { cells: ["risk", "seams and pops by design: one straight-line map cannot follow a fold crease that crosses the view", "the compiler must not fuse or reorder the paired-float steps; WebGL 2 cannot forbid that (no `precise`)", "glitches if δ grows too large (k = 24, ice field: 49% at 1e−5): stop once λ_k × d reaches about 1e−2, which also sets k"],
      tip: { title: "risk", ...N(370), links: [NL(259, "why the substitution is squeezed"), NL(273, "the seam")] } },
    { cells: ["verdict", "rejected: approximate by construction", "kept as the fallback if the per-fold cases prove fiddly in GLSL", "built (this spec)"],
      tip: { title: "the recommendation", ...N(376), links: [NL(378, "do not build the substitution"), NL(382, "build C as perturbation"), NL(388, "two-float: the fallback"), SL(21, "spec: perturbation")] } },
  ],
};
const MEAS = [
  // [shape, d, today, substitution best k, substitution CPU rule, two-float k16, k20, perturbation k16, k20, note line]
  ["Julia, default box", "1e−5", "9%", "92% (k=8)", "92%", "100%", "100%", "100%", "100%", 235],
  ["Julia, default box", "1e−6", "0%", "88% (k=10)", "78%", "100%", "100%", "100%", "100%", 236],
  ["Julia, default box", "1e−7", "7%", "83% (k=10)", "97%", "100%", "100%", "100%", "100%", 237],
  ["Julia ice field + rotation", "1e−5", "10%", "98% (k=8)", "98%", "100%", "100%", "100%", "100%", 238],
  ["Julia ice field + rotation", "1e−6", "9%", "98% (k=12)", "94%", "100%", "100%", "100%", "100%", 239],
  ["Julia ice field + rotation", "1e−7", "2%", "87% (k=14)", "64%", "97%", "100%", "97%", "100%", 240],
  ["Julia x, y, z, W 0.3", "1e−5", "16%", "100% (k=10)", "94%", "100%", "100%", "100%", "100%", 241],
  ["Julia x, y, z, W 0.3", "1e−6", "16%", "100% (k=12)", "99%", "100%", "100%", "100%", "100%", 242],
  ["Julia x, y, z, W 0.3", "1e−7", "4%", "98% (k=16)", "56%", "98%", "100%", "98%", "100%", 243],
  ["Julia ice field (save)", "1e−5", "14%", "74% (k=8)", "68%", "100%", "100%", "100%", "94%", 244],
  ["Julia ice field (save)", "1e−6", "8%", "92% (k=8)", "93%", "100%", "100%", "100%", "100%", 245],
  ["Julia ice field (save)", "1e−7", "5%", "72% (k=16)", "56%", "99%", "100%", "99%", "100%", 246],
  ["Default Mandelbox", "1e−5", "19%", "68% (k=6)", "86%", "100%", "100%", "100%", "100%", 247],
  ["Default Mandelbox", "1e−6", "14%", "89% (k=12)", "67%", "100%", "100%", "100%", "100%", 248],
  ["Default Mandelbox", "1e−7", "11%", "91% (k=14)", "86%", "100%", "100%", "100%", "100%", 249],
  ["Default box, Julia x only", "1e−5", "23%", "68% (k=4)", "79%", "100%", "100%", "100%", "100%", 250],
  ["Default box, Julia x only", "1e−6", "17%", "87% (k=8)", "75%", "100%", "100%", "100%", "100%", 251],
  ["Default box, Julia x only", "1e−7", "0%", "82% (k=12)", "90%", "100%", "100%", "100%", "100%", 252],
];
const measuredTable = {
  type: "table",
  title: "Measured: share of rays right, emulated float32",
  note: "The note's section 3 table. The substitution's best k is picked with hindsight per shape; the CPU rule picks k per view as a renderer would. Today = the current float32 march.",
  columns: [{ label: "shape", w: 190 }, { label: "d", w: 50 }, { label: "today", w: 64 }, { label: "subst. best k", w: 120 }, { label: "subst. CPU rule", w: 140 }, { label: "two-float 16", w: 120 }, { label: "two-float 20", w: 120 }, { label: "pert. 16", w: 90 }, { label: "pert. 20", w: 90 }],
  rows: MEAS.map(r => ({ cells: r.slice(0, 9), tip: { title: `${r[0]} at ${r[1]}`, ...N(r[9]), blurb: "One row of the note's float32 table: 243 rays (3 views × 81), each compared with the float64 reference march." } })),
};
const whyCards = {
  type: "cards",
  title: "Why perturbation won",
  columns: 1, cardWidth: 560,
  cards: [
    { title: "Exact per pixel: no seams", tag: "decided", hue: 3, ...N(364), links: [SL(21, "spec: 94–100%"), NL(273, "the substitution's seam")],
      body: "Nothing is approximated by one straight-line map: each pixel's difference goes through every fold with the exact crossing formula, so a fold crease inside the view costs nothing. The substitution's best k left up to a third of the rays wrong, as seams that move with the camera and jump when k changes." },
    { title: "About a quarter of the two-float cost", tag: "decided", hue: 3, ...N(366), links: [NL(372, "estimates, switched on only at depth")],
      body: "A difference iteration costs about 2 plain ones, so 16 to 20 of them make a ray 1.5 to 2 times today's cost at depth; a paired-float iteration costs about 13, about 7 times overall. Both are estimates from operation counts, and both apply only below the old floor: normal views run today's code." },
    { title: "Ordinary float arithmetic", tag: "decided", hue: 3, ...N(370), links: [SL(20, "spec: depends on how a WebGL driver rounds")],
      body: "A two-float trick only works if the GPU computes each rounding step exactly as written; a WebGL 2 compiler may fuse a multiply and an add, and GLSL ES 3.0 has no `precise` to forbid it. Perturbation's formulas are plain float maths: the worst a compiler can do is the usual last-bit rounding." },
    { title: "Mandelbrot mode comes free", tag: "decided", hue: 3, ...N(355), links: [SL(204, "spec: the add step")],
      body: "In Mandelbrot mode the pixel's c differs from the reference's by exactly its starting offset, so the add is δ' = s δ + δc with δc = the offset (masked by the Julia flags per component). The substitution needed c to 'follow' the point as a separate correction." },
    { title: "A small extension of what exists", tag: "decided", hue: 3, ...N(385), links: [SL(124, "spec: reuses the fold helpers"), RL("de", 30, "estimate_at, already 64-bit")],
      body: "DistanceEstimator already runs the orbit in 64-bit scalars on the CPU. ReferenceOrbit reuses its static fold helpers and adds only the loop that records gaps, and `orbit.distance == estimate_at(...)` exactly is a test, so the fold maths has one source." },
  ],
};

// ================================================================== 3. the idea
const ideaFig = {
  type: "figure",
  tab: "The idea",
  title: "Iterate the offset, not the point",
  note: "The core trick, run live on the default Mandelbox (Mandelbrot mode). The CPU iterates the eye 32 times in 64-bit: the reference orbit X_0 … X_32 and its magnification λ_i. A pixel's sample point is the eye plus δ_0 = dir × t (here t = d). The GPU iterates only δ, using the record's gaps, until λ_k × near reaches 1e−2; then it hands off, z = X_k + δ_k in float32, and today's loop runs the remaining 32 − k iterations. The right-hand chart is the point of the design: how wrong the pixel's offset is at each iteration in float32, on the perturbed path (green) and on today's direct path, which starts from the rounded P = eye + δ (orange). Hover the circles and points for numbers. A port of mb_step in doubles and in Math.fround float32, with the spec's clamp and radial difference formulas. The X circles are coloured by the sphere fold's regime (grey outside, violet shell, orange inside; amber marks X_k). On this view the reference is almost always outside within the first 20 iterations, so the radial case here is mostly the trivial one; the Crossing a fold tab shows the others.",
  w: 1500, h: 900,
  draw(api) {
    const CG = api.hue(3), CO = api.hue(2), CB = api.hue(1), CA = api.hue(4);
    const ST = { v: -5.5, pix: "corner" };
    let run = null;
    // ---- schematic
    const X0 = 70, DX = 40, YX = 150, YD = 262;
    api.text(20, 108, "CPU · 64-BIT: THE REFERENCE ORBIT X_i (once per frame)", "ink", { style: caps });
    api.text(20, 222, "GPU · FLOAT32: THE PIXEL'S OFFSET δ_i (every pixel, every sample)", "ink", { style: caps });
    for (let i = 0; i < 20; i++) api.el("line", { x1: X0 + i * DX + 8, y1: YX, x2: X0 + (i + 1) * DX - 8, y2: YX, style: `stroke:var(--muted);stroke-width:1.2;${noPtr}` });
    api.text(X0 + 20 * DX + 22, YX + 4, "… X_32", "muted", { style: small });
    const regCol = [api.hue(2), api.hue(6), "var(--muted)"], regName = ["inside", "shell", "outside"];
    const xs = [], ds = [];
    for (let i = 0; i <= 20; i++) {
      const c = api.el("circle", { cx: X0 + i * DX, cy: YX, r: 8, style: "stroke:var(--surface);stroke-width:1.5;cursor:pointer" });
      api.tip(c, { title: `X_${i}`, ...S(119), live() {
        if (!run) return {};
        const o = run.o, X = o.X[i], r = o.rec[i];
        return { title: `X_${i} (64-bit)`, sub: i === run.k ? "the handoff point: pert_end" : i < run.k ? "perturbed past" : "",
          blurb: `X_${i} = (${X.map(v => sci(v, 6)).join(", ")})\nλ_${i} = ${sci(o.mag[i])}\n` + (r ? `record for iteration ${i}: lower gaps ${r.lo.map(v => sci(v)).join(", ")} · upper gaps ${r.hi.map(v => sci(v)).join(", ")} · |Xs|² ${sci(r.r2, 4)} (${regName[r.reg]}, m = ${sci(r.m, 4)})` : "the last point") };
      }, links: [SL(131, "the per-iteration record"), SL(127, "λ_i")] });
      xs.push(c);
      api.text(X0 + i * DX, YX + 26, String(i), "muted", { "text-anchor": "middle", style: `font-size:9.5px;${noPtr}` });
      const dcirc = api.el("circle", { cx: X0 + i * DX, cy: YD, r: 4, style: `fill:${CG};fill-opacity:.25;stroke:${CG};stroke-width:1.5;cursor:pointer` });
      api.tip(dcirc, { title: `δ_${i}`, ...S(31), live() {
        if (!run || i > run.k) return {};
        const ex = run.exD[i], pe = run.pe[i];
        return { title: `δ_${i}`, sub: `|δ_${i}| = ${sci(len4(ex))}`,
          blurb: `exact (64-bit P − X): (${ex.map(v => sci(v, 4)).join(", ")})\nperturbed float32: (${pe.map(v => sci(v, 4)).join(", ")}), relative error ${sci(run.errP[i], 1)}\ndirect float32 (rounded P − X): relative error ${pct(run.errD[i])}` };
      }, links: [SL(170, "the difference formulas")] });
      ds.push(dcirc);
    }
    const hand = api.el("g", { style: noPtr });
    // ---- readouts (right of the schematic)
    const RX = 960;
    const rd = [];
    for (let i = 0; i < 9; i++) rd.push(api.text(RX, 108 + i * 21, "", "mono", { style: mono }));
    // ---- chart L: λ_i × near
    const LX = 70, LYt = 380, LW = 610, LH = 380;
    const xt = [];
    for (let i = 0; i <= 32; i += 4) xt.push([LX + (i + 0.5) * LW / 33, String(i)]);
    const lyL = logFrame(api, LX, LYt, LW, LH, 6, -14, 2, xt, "iteration i", "λ_i × near, per iteration");
    const barsG = api.el("g", {});
    const bars = [];
    for (let i = 0; i <= 32; i++) {
      const b = api.el("rect", { x: LX + i * LW / 33 + 2, width: LW / 33 - 4, y: LYt, height: 1, style: "cursor:pointer" }, barsG);
      api.tip(b, { title: `λ_${i} × near`, ...S(43), live() { if (!run) return {}; return { title: `i = ${i}`, blurb: `λ_${i} = ${sci(run.o.mag[i])}\nλ_${i} × near = ${sci(run.o.mag[i] * run.near)}${i === run.k ? "\nthe first to reach 1e−2: k" : ""}` }; }, links: [SL(223, "PERT_HANDOFF = 1e−2")] });
      bars.push(b);
    }
    api.el("line", { x1: LX, y1: lyL(-2), x2: LX + LW, y2: lyL(-2), style: `stroke:${CA};stroke-width:1.6;stroke-dasharray:6 4;${noPtr}` });
    api.text(LX + LW - 4, lyL(-2) - 6, "handoff: 1e−2", "", { "text-anchor": "end", style: `fill:${CA};font-size:10.5px;font-weight:600;${noPtr}` });
    // ---- chart R: relative error of δ_i
    const QX = 800, QW = 660;
    const xq = [];
    for (let i = 0; i <= 32; i += 4) xq.push([QX + i / 32 * QW, String(i)]);
    const lyR = logFrame(api, QX, LYt, QW, LH, 3, -9, 1, xq, "iteration i", "how wrong the pixel's offset is, per iteration");
    const qx = i => QX + i / 32 * QW;
    api.el("line", { x1: QX, y1: lyR(0), x2: QX + QW, y2: lyR(0), style: `stroke:var(--ink);stroke-width:1;opacity:.5;${noPtr}` });
    api.text(QX + 6, lyR(0) - 5, "100% wrong", "muted", { style: `${small};${noPtr}` });
    api.el("line", { x1: QX, y1: lyR(Math.log10(6e-8)), x2: QX + QW, y2: lyR(Math.log10(6e-8)), style: `stroke:var(--ink);stroke-width:1;opacity:.35;stroke-dasharray:3 3;${noPtr}` });
    api.text(QX + 6, lyR(Math.log10(6e-8)) + 13, "float32's own precision, 6e−8", "muted", { style: `${small};${noPtr}` });
    const lineP = api.el("polyline", { style: `fill:none;stroke:${CG};stroke-width:2.4;${noPtr}` });
    const lineD = api.el("polyline", { style: `fill:none;stroke:${CO};stroke-width:2.4;${noPtr}` });
    const kLine = api.el("line", { y1: LYt, y2: LYt + LH, style: `stroke:${CA};stroke-width:1.4;stroke-dasharray:4 3;${noPtr}` });
    const kLab = api.text(0, LYt + 14, "", "", { style: `fill:${CA};font-size:10.5px;font-weight:600;${noPtr}` });
    const ptsP = [], ptsD = [];
    for (let i = 0; i <= 32; i++) {
      for (const [arr, col, key, name] of [[ptsP, CG, "errP", "perturbed"], [ptsD, CO, "errD", "direct"]]) {
        const c = api.el("circle", { r: 3.6, style: `fill:${col};stroke:var(--surface);stroke-width:1;cursor:pointer` });
        api.tip(c, { title: `${name}, iteration ${i}`, ...(key === "errP" ? S(31) : S(11)), live() { if (!run) return {}; return { blurb: `relative error of the pixel's offset after ${i} iterations: ${sci(run[key][i], 2)} (${pct(run[key][i])})${key === "errP" && i > run.k ? "\npast the handoff: today's loop, from X_k + δ_k in float32" : ""}` }; } });
        arr.push(c);
      }
    }
    swatch(api, QX, LYt + LH + 52, CG, "perturbed: δ iterated in float32 for k steps, then today's loop");
    swatch(api, QX + 380, LYt + LH + 52, CO, "direct: today, from the rounded eye + δ");
    // ---- controls
    api.slider({ x: 20, y: 44, w: 420, label: "camera distance d (log)", min: -12, max: -3, step: 0.1, value: ST.v,
      fmt: v => sci(Math.pow(10, v)), onChange: v => { ST.v = v; compute(); } });
    const pb = {};
    let bx = 500;
    api.text(bx, 36, "pixel", "ink");
    for (const name of ["centre", "edge", "corner"]) {
      pb[name] = api.button({ x: bx, y: 42, w: 80, label: name, on: name === ST.pix, onClick: () => { ST.pix = name; for (const n in pb) pb[n].set(n === name); compute(); } });
      bx += 88;
    }
    function compute() {
      run = pixelRun(Math.pow(10, ST.v), PIXELS[ST.pix]);
      const k = run.k, o = run.o;
      for (let i = 0; i <= 20; i++) {
        const reg = i < 32 ? o.rec[i].reg : 2;
        xs[i].style.fill = i === k ? CA : regCol[reg];
        xs[i].setAttribute("r", i === k ? 10 : 8);
        const on = i <= k && k > 0;
        ds[i].style.display = on ? "" : "none";
        if (on) ds[i].setAttribute("r", clamp(3 + (Math.log10(Math.max(len4(run.exD[i]), 1e-14)) + 13) * 1.25, 3, 18));
      }
      clear(hand);
      if (k > 0) {
        const x = X0 + k * DX;
        api.el("line", { x1: x, y1: YX - 26, x2: x, y2: YD + 28, style: `stroke:${CA};stroke-width:1.6;stroke-dasharray:5 4` }, hand);
        api.text(X0 - 10, YD + 44, `hand off at k = ${k}: z = pert_end + δ_k in float32, then today's loop for iterations ${k} … 31`, "", { style: `fill:${CA};font-size:11px;font-weight:600` }, hand);
      } else {
        api.text(X0, YD + 4, "pert_iters = 0 at this distance: the GPU runs today's path (no δ)", "muted", { style: small }, hand);
      }
      for (let i = 0; i <= 32; i++) {
        const v = Math.log10(Math.max(o.mag[i] * run.near, 1e-30)), top = lyL(v), base = lyL(-14);
        bars[i].setAttribute("y", Math.min(top, base)); bars[i].setAttribute("height", Math.max(1, Math.abs(base - top)));
        bars[i].style.fill = i === k && k > 0 ? CA : i < k ? CG : "var(--muted)";
        bars[i].style.opacity = i <= k ? 1 : 0.45;
      }
      const pl = (key, arr) => {
        const pts = [];
        for (let i = 0; i <= 32; i++) {
          const y = lyR(Math.log10(Math.max(run[key][i], 1e-12)));
          arr[i].setAttribute("cx", qx(i)); arr[i].setAttribute("cy", y);
          pts.push(`${qx(i)},${y}`);
        }
        return pts.join(" ");
      };
      lineP.setAttribute("points", pl("errP", ptsP));
      lineD.setAttribute("points", pl("errD", ptsD));
      kLine.style.display = kLab.style.display = k > 0 ? "" : "none";
      kLine.setAttribute("x1", qx(k)); kLine.setAttribute("x2", qx(k));
      kLab.setAttribute("x", qx(k) + 5); kLab.textContent = `k = ${k}`;
      const d = Math.pow(10, ST.v);
      const L = [
        `camera d = ${sci(d)} from the surface point · near = ${sci(run.near)}`,
        `δ_0 = dir × d, |δ_0| = ${sci(d)} (the ${ST.pix} pixel)`,
        `float32 P_0 = eye + δ_0 loses ${pct(run.lost)} of the offset`,
        k > 0 ? `k = ${k}: λ_k = ${sci(o.mag[k])}, λ_k × near = ${sci(o.mag[k] * run.near)}` : "pert_iters = 0: both paths are today's",
        "distance estimate after 32 iterations:",
        `  exact, 64-bit        ${sci(run.deE, 5)}`,
        `  perturbed, float32   ${sci(run.deP, 5)}   error ${pct(Math.abs(run.deP - run.deE) / run.deE)}`,
        `  direct, float32      ${sci(run.deD, 5)}   error ${pct(Math.abs(run.deD - run.deE) / run.deE)}`,
        `hit test: estimate < eps × t = ${sci(BOX.eps * d)}`,
      ];
      L.forEach((t, i) => { rd[i].textContent = t; });
      rd[7].style.fill = Math.abs(run.deD - run.deE) / run.deE > 0.01 ? CO : "";
      rd[6].style.fill = CG;
    }
    compute();
  },
};

// ================================================================== 4. the seven parts
const partsGraph = {
  type: "graph",
  tab: "The seven parts",
  title: "The seven parts and what flows between them",
  note: "Everything left of the bridge runs in 64-bit GDScript floats on the CPU, once per camera change; everything right of it in float32 on the GPU, per pixel. Only gaps, multipliers and one handoff point cross the bridge, never two big positions for the GPU to subtract. The number in each node's second line is the spec part. Hover a node for what the part does, its spec line and the existing code it changes.",
  zones: [
    { id: "cpu", label: "CPU · 64-BIT (GDSCRIPT DOUBLES) · ONCE PER CAMERA CHANGE", x: 0, y: 0, w: 1150, h: 570 },
    { id: "bridge", label: "THE BRIDGE · UNIFORMS", x: 1180, y: 0, w: 340, h: 570 },
    { id: "gpu", label: "GPU · FLOAT32 · EVERY PIXEL", x: 1580, y: 0, w: 790, h: 570 },
    { id: "out", label: "CONSOLE, DOCS AND THE KEYSTONE TEST", x: 0, y: 630, w: 2370, h: 130 },
  ],
  nodes: [
    { id: "center", label: "CenterRay.march(ox, oy, oz)", sub: "1 · scalar origin, march in doubles", ctx: "cpu", x: 30, y: 70, w: 270, ...S(96),
      blurb: "The probe and the fly speed's ray distance march from the camera. Today `march(origin: Vector3, …)` starts from the rounded eye; the design adds a scalar-origin overload whose loop forms `o + dir × t` in doubles, and the `Vector3` one calls it.", links: [RL("center", 69, "today: march(origin: Vector3, …)"), SL(352, "test: resolves a hit at 1e−8")] },
    { id: "ws", label: "Workspace capture / restore", sub: "1 · eye at full precision, no _tidy", ctx: "cpu", x: 30, y: 210, w: 260, ...S(103),
      blurb: "Saves write `\"eye\"` from eye64() at full precision. Today every vector goes through `_tidy`, which rounds to 7 significant figures: fine for forward and up, fatal for an eye 1e−9 from the surface. Restore reads three doubles and calls set_eye64. The save stays version 2: an old file is the same shape with fewer digits; a new file loads in an old build with the eye rounded.", links: [RL("ws", 45, "today: \"eye\": _vec_to_array(eye())"), RL("ws", 261, "_tidy: 7 significant figures"), SL(342, "test: restores 1e−9 exactly")] },
    { id: "params", label: "FractalParams", sub: "4, 5 · pert_iters(orbit, near) · zoom_floor", ctx: "cpu", x: 30, y: 350, w: 320, ...S(225),
      blurb: "Two rules. pert_iters: 0 unless the orbit is perturbable and near is under 10 × today's floor, else the smallest k ≤ 20 with λ_k × near ≥ 1e−2. zoom_floor(eye64) becomes max(floor_pert, floor_iter), both from a ReferenceOrbit at the eye: where the perturbed march runs out of float32 precision, and where 32 iterations run out of detail.", links: [SL(242, "zoom_floor = max(floor_pert, floor_iter)"), RL("params", 426, "today: zoom_floor(eye: Vector3)"), SL(221, "PERT_MAX, PERT_ON, PERT_HANDOFF")] },
    { id: "fly", label: "FlyCamera", sub: "1 · step added in 64-bit · SPEED_FLOOR 1e−14", ctx: "cpu", x: 430, y: 70, w: 310, ...S(91),
      blurb: "_physics_process adds the step in 64-bit: `set_eye64(ex + dir.x × step, …)`; `dir` stays a unit Vector3, only the add needs the precision. move_allowed takes two PackedFloat64Arrays. base_speed's clamp floor drops from 1e−6 to 1e−14: the speed is about the distance to the surface, so below 1e−6 the camera would otherwise outrun its own stop.", links: [RL("fly", 82, "today: t.origin += dir × speed × delta"), RL("fly", 95, "today: move_allowed(Vector3, Vector3)"), RL("fly", 150, "today: clampf(d, 1e-6, 20)"), SL(100, "SPEED_FLOOR")] },
    { id: "cam", label: "CameraState", sub: "1 · eye_x/y/z: the truth · transform: the shadow", ctx: "cpu", x: 430, y: 210, w: 330, ...S(77),
      blurb: "Gains @export eye_x, eye_y, eye_z (64-bit). set_eye64 sets the doubles, sets transform.origin to the rounded Vector3, emits changed when any double differs. eye() keeps returning the rounded shadow for every 32-bit consumer (the eye uniform, box_intersect, the orbit camera, the probe, project/unproject). The transform setter replaces the doubles only when the new origin differs from the shadow, so FlyCamera._set_forward, which rebuilds the transform from eye(), leaves the eye alone.", links: [RL("cam", 11, "today: transform"), RL("cam", 25, "today: eye()"), SL(86, "the setter rule"), SL(339, "test: round-trips 1e−12")] },
    { id: "view", label: "FractalView._push_near()", sub: "4 · builds the orbit, picks k, pushes", ctx: "cpu", x: 830, y: 210, w: 290, ...S(234),
      blurb: "Builds the ReferenceOrbit from eye64() (its distance is near, so the estimate is not computed twice), pushes near_dist, coarse_iters and nf_weight as today, plus pert_iters; while that is positive, the four record arrays and pert_end = X_k. The arrays are pushed only while on, so a still frame at depth pushes once.", links: [RL("view", 366, "today: _push_near()"), RL("view", 369, "today: near from the 32-bit eye"), SL(237, "arrays only while on")] },
    { id: "orbit", label: "ReferenceOrbit.build", sub: "2 · X_0..X_32 · λ_0..λ_32 · record a..d", ctx: "cpu", x: 830, y: 350, w: 290, ...S(111),
      blurb: "New RefCounted (src/fractal/reference_orbit.gd), built from the 64-bit eye for the current shape: distance (== DistanceEstimator.estimate_at exactly), n (iterations before a KIFS bailout or Kleinian fixed point), mag (λ_i, the product of the scale magnitudes and radial-fold factors), points (float32 copies; X_k is the handoff point), the record arrays a, b, c, d, and perturbable (false for the octahedral fold, the poly fold and shapes without support).", links: [SL(115, "the API"), SL(127, "λ_i"), SL(335, "test: reference_orbit_test")] },
    { id: "helpers", label: "the estimators' fold helpers", sub: "2 · _fold, _sphere_fold, _rot_plane, menger_fold…", ctx: "cpu", x: 830, y: 490, w: 290, ...S(124),
      blurb: "ReferenceOrbit reuses the estimators' static fold helpers, so the fold maths is not duplicated; only the loop body is, and the distance-equality test keeps it honest.", links: [RL("de", 108, "_fold"), RL("de", 192, "_sphere_fold"), RL("de", 208, "_rot_plane"), RL("de", 133, "menger_fold"), RL("kifs", 113, "KifsEstimator._diagonal_fold")] },
    { id: "uK", label: "pert_iters", sub: "3 · k; 0 = off: today's code", ctx: "bridge", x: 1200, y: 70, w: 300, ...S(154),
      blurb: "int. 0 means the shader runs exactly today's code, which is what keeps the default view bit-for-bit. Positive: the number of perturbed iterations before the handoff, never above PERT_MAX = 20 or the orbit's n.", links: [SL(215, "0: exactly today's code"), SL(357, "test: RENDERER_UNIFORMS gains it")] },
    { id: "uRec", label: "pert_a, pert_b, pert_c, pert_d", sub: "2, 3 · vec4[20] each: the record", ctx: "bridge", x: 1200, y: 180, w: 300, ...S(131),
      blurb: "The per-iteration record, four vec4 per iteration (see the Per-iteration record tab): for the Mandelbox the lower and upper clamp gaps, the sphere fold's input point, and (|Xs|² − min², |Xs|² − fixed², m, the cylinder's radial gap). Every value is a small gap or a multiplier that needs only relative precision, so float32 holds it well.", links: [SL(135, "the table"), SL(156, "uniform arrays compile under GL Compatibility")] },
    { id: "uEnd", label: "pert_end", sub: "3 · X_k: the handoff point", ctx: "bridge", x: 1200, y: 290, w: 300, ...S(155),
      blurb: "vec4: the reference's point after k iterations. By then the pixel's offset has grown by λ_k, so `pert_end + δ` in float32 is as good as exact and today's loop can take over.", links: [SL(161, "z = pert_end + δ")] },
    { id: "uNear", label: "near_dist · coarse_iters · nf_weight", sub: "as today", ctx: "bridge", x: 1200, y: 400, w: 300, ...S(235),
      blurb: "The existing deep-zoom uniforms (the coarse pass's iteration count and the lighting crossfade), pushed by _push_near as today.", links: [RL("view", 370, "today's pushes"), R("zoom", 74)] },
    { id: "frag", label: "fragment()", sub: "3 · pert_iters > 0: both passes call de_pert", ctx: "gpu", x: 1610, y: 70, w: 290, ...S(211),
      blurb: "When pert_iters > 0 both march passes call de_pert(dir × total, n) and the normal is calc_normal_pert; `v = eye + dir × total` is still formed in 32 bits for everything that only needs it roughly (Rainbow's radius, the probe dot, fog, the noise tint, noise_displace). When pert_iters == 0 the shader runs exactly today's code.", links: [RL("sh", 410, "today: fragment()"), RL("sh", 442, "today: pos = eye + dir * total"), SL(213, "v still formed in 32 bits")] },
    { id: "normal", label: "calc_normal_pert(off, delta)", sub: "3 · samples de_pert(off ± e)", ctx: "gpu", x: 1960, y: 350, w: 290, ...S(212),
      blurb: "The central-difference normal, with its six samples taken as offsets from the eye (off ± e) so they too never form eye + off.", links: [RL("sh", 343, "today: calc_normal(v, delta)")] },
    { id: "dePert", label: "de_pert(off, iters)", sub: "3 · min(pert_iters, iters) steps on δ", ctx: "gpu", x: 1610, y: 210, w: 290, ...S(160),
      blurb: "Runs the perturbed iterations on δ (a vec4, δ.w = 0), with off = dir × t: the shader never forms eye + off on this path. Then z = pert_end + δ, dz as accumulated, and the shape's ordinary loop continues from iteration k.", links: [SL(161, "then hand off")] },
    { id: "de", label: "de(p, iters)", sub: "pert_iters == 0: today's code", ctx: "gpu", x: 1960, y: 70, w: 280, ...S(166),
      blurb: "The direct path calls the shared loop with first = 0: the same arithmetic in the same order, so the default view stays bit-for-bit (the user's screenshot check confirms).", links: [RL("sh", 313, "today: de(p, iters)"), RL("sh", 322, "today's loop")] },
    { id: "mbOrbit", label: "mb_orbit(z, dz, c, first, iters)", sub: "3 · each shape's loop, from a start index", ctx: "gpu", x: 2010, y: 210, w: 330, ...S(164),
      blurb: "To share the loop body, each shape's loop moves into a function taking a start index (mb_orbit and its KIFS and Kleinian siblings). de_pert calls it from k, the direct de from 0.", links: [RL("sh", 275, "today: mb_step")] },
    { id: "kinds", label: "the difference formulas", sub: "3 · clamp, radial, sort, Menger, linear, add", ctx: "gpu", x: 1610, y: 350, w: 330, ...S(170),
      blurb: "One formula per step kind, each of small numbers: the clamp folds (one formula covers all nine side pairs), the radial folds (m' − m written per regime pair), the KIFS sorts and diagonal swaps, the Menger correction, the linear steps (rotation, twist, scale: the same step applied to δ) and the add (δ' = s δ + δc). See the Crossing a fold tab.", links: [SL(173, "clamp folds"), SL(179, "radial folds"), SL(193, "sorts and swaps"), SL(201, "linear steps"), SL(204, "the add")] },
    { id: "main", label: "Main._process", sub: "6 · forwards FractalView.pert_iters()", ctx: "out", x: 30, y: 690, w: 300, ...S(266),
      blurb: "Forwards pert_iters to the Movement pane each frame, the way at_zoom_limit is forwarded today.", links: [RL("main", 384, "today: show_zoom_limit(fly.at_zoom_limit)")] },
    { id: "movement", label: "MovementPane.show_deep(k)", sub: "6 · deep k=14 on the speed line", ctx: "out", x: 450, y: 690, w: 300, ...S(265),
      blurb: "Shows `deep k=14` on the speed line while pert_iters > 0; k = 0 hides it. The zoom limit readout stays, with a tooltip saying the limit is now where 32 iterations run out of detail or the perturbed march runs out of precision.", links: [RL("movement", 296, "today: show_zoom_limit"), SL(259, "the zoom limit readout")] },
    { id: "vizPane", label: "the deep-zoom viz pane", sub: "7 · after the code lands; this pane now", ctx: "out", x: 1200, y: 690, w: 300, ...S(272),
      blurb: "A ten-tab pane written with /visualize once the code lands, its links pinned to that commit. This pane is the smaller one the spec asks for now, before the code: the document itself.", links: [SL(312, "this pane")] },
    { id: "test", label: "perturbation_test.gd", sub: "the keystone: emulated float32 port", ctx: "out", x: 830, y: 690, w: 300, ...S(321),
      blurb: "Runs before any shader work: a GDScript port of the perturbed and the direct step in emulated float32, plus the 64-bit reference, over five shape fixtures × three depths × 27 rays. It proves the formulas; see the Test plan tab.", links: [SL(329, "the checks")] },
  ],
  edges: [
    { from: "fly", to: "cam", kind: "call", label: "set_eye64", ...S(91), blurb: "The step is added to the doubles, not to the Vector3.", bow: 0 },
    { from: "fly", to: "params", kind: "call", label: "zoom_floor(to64)", ...S(258), blurb: "move_allowed is unchanged in shape (accept if d_to ≥ floor(to) or d_to ≥ d_from), now in 64-bit.", bow: 0 },
    { from: "ws", to: "cam", kind: "call", ...S(105), blurb: "restore: set_eye64 with the saved doubles, then the basis with looking_at.", bow: 0 },
    { from: "center", to: "cam", kind: "data", label: "eye64()", ...S(96), bow: 0 },
    { from: "cam", to: "view", kind: "signal", label: "changed", ...S(80), blurb: "set_eye64 emits changed when any double differs, so a sub-ulp move still re-renders.", bow: 0 },
    { from: "view", to: "orbit", kind: "call", label: "build(eye64)", ...S(234), bow: 0 },
    { from: "view", to: "params", kind: "call", label: "pert_iters(orbit, near)", ...S(225), bow: 0 },
    { from: "params", to: "orbit", kind: "call", label: "a ReferenceOrbit at eye", ...S(243), bow: 0 },
    { from: "orbit", to: "helpers", kind: "call", label: "reuses", ...S(124), bow: 0 },
    { from: "view", to: "uK", kind: "data", label: "k", ...S(236), bow: 0 },
    { from: "view", to: "uRec", kind: "data", label: "record[0..k)", ...S(236), bow: 0 },
    { from: "view", to: "uEnd", kind: "data", label: "X_k", ...S(237), bow: 0 },
    { from: "view", to: "uNear", kind: "data", label: "as today", ...S(235), bow: 0 },
    { from: "uK", to: "frag", kind: "data", ...S(211), bow: 0 },
    { from: "uRec", to: "dePert", kind: "data", ...S(160), bow: 0 },
    { from: "uEnd", to: "dePert", kind: "data", ...S(161), bow: 0 },
    { from: "frag", to: "dePert", kind: "call", label: "de_pert(dir × total, n)", ...S(211), bow: 0 },
    { from: "frag", to: "normal", kind: "call", ...S(212), bow: 0 },
    { from: "normal", to: "dePert", kind: "call", label: "off ± e", ...S(212), bow: 0 },
    { from: "frag", to: "de", kind: "call", label: "k = 0", ...S(215), bow: 0 },
    { from: "dePert", to: "mbOrbit", kind: "call", label: "from k", ...S(162), bow: 0 },
    { from: "de", to: "mbOrbit", kind: "call", label: "from 0", ...S(166), bow: 0 },
    { from: "dePert", to: "kinds", kind: "call", label: "k steps", ...S(170), bow: 0 },
    { from: "view", to: "main", kind: "data", label: "pert_iters()", ...S(266), bow: 0 },
    { from: "main", to: "movement", kind: "call", label: "show_deep(k)", ...S(265), bow: 0 },
  ],
};

// ================================================================== 5. crossing a fold
const foldFig = {
  type: "figure",
  tab: "Crossing a fold",
  title: "Crossing a fold: the difference formulas",
  note: "Folds are where perturbation needs care: the reference X and the pixel P = X + δ can land on different sides of a crease, and then δ' is not the same step applied to δ. The spec writes every crossing as a formula of small numbers: the CPU sends the gaps (crease − X, computed in 64-bit), and the GPU never subtracts two nearly equal large numbers. Left: the clamp fold (the box fold, one component). Drag X and P; the 3 × 3 table lights the case the one formula reduces to. Right: the radial fold (the sphere fold), drawn along one ray from the centre so radii are enough; the regime pair picks how m' − m is written. Both check the formula against P' − X' computed directly, and again in float32 with δ shrunk a million-fold, where the direct difference falls apart.",
  w: 1560, h: 800,
  draw(api) {
    const CX = api.hue(1), CP = api.hue(2), CG = api.hue(3), CA = api.hue(4);
    const ST = { L: 1, X: 0.6, P: 1.35, min: 0.7, fixed: 1, rX: 0.85, rP: 0.62 };
    // ------------------------------------------------ left: the clamp fold
    api.text(20, 28, "CLAMP FOLD · ONE COMPONENT OF THE BOX FOLD", "ink", { style: caps });
    const A0 = 70, AW = 640, VMIN = -3.2, VMAX = 3.2;
    const ax = v => A0 + (clamp(v, VMIN, VMAX) - VMIN) / (VMAX - VMIN) * AW;
    const av = x => VMIN + (x - A0) / AW * (VMAX - VMIN);
    const Y1 = 160, Y2 = 280;
    const statL = api.el("g", { style: noPtr }), dynL = api.el("g", { style: noPtr });
    const hX = api.el("circle", { r: 9, style: `fill:${CX};stroke:var(--surface);stroke-width:2;cursor:ew-resize` });
    const hP = api.el("circle", { r: 9, style: `fill:${CP};stroke:var(--surface);stroke-width:2;cursor:ew-resize` });
    api.tip(hX, { title: "the reference X (one component)", ...S(37), blurb: "Drag. The CPU knows X in 64-bit and sends only the gaps g_lo = lo − X and g_hi = hi − X." });
    api.tip(hP, { title: "the pixel P = X + δ", ...S(31), blurb: "Drag. The GPU never holds P itself, only δ." });
    draggable(api, hX, q => { ST.X = +clamp(av(q.x), VMIN, VMAX).toFixed(3); drawL(); });
    draggable(api, hP, q => { ST.P = +clamp(av(q.x), VMIN, VMAX).toFixed(3); drawL(); });
    const outL = [];
    for (let i = 0; i < 7; i++) outL.push(api.text(20, 340 + i * 21, "", "mono", { style: mono }));
    // the case table
    const TX = 130, TY = 520, CW = 190, CHh = 58, SIDES = ["below −L", "inside", "above +L"];
    api.text(TX, TY - 30, "pixel P is …", "muted", { style: small });
    api.text(20, TY + 14, "reference X is …", "muted", { style: small });
    const CASES = [
      [["−δ", "both mirrored"], ["δ − 2 g_lo", ""], ["2 (g_hi − g_lo) − δ", "= 4L − δ"]],
      [["2 g_lo − δ", ""], ["δ", "neither moves"], ["2 g_hi − δ", ""]],
      [["2 (g_lo − g_hi) − δ", "= −4L − δ"], ["δ − 2 g_hi", ""], ["−δ", "both mirrored"]],
    ];
    const cellL = [];
    for (let c = 0; c < 3; c++) api.text(TX + c * CW + CW / 2, TY - 10, SIDES[c], "ink", { "text-anchor": "middle", style: "font-weight:600" });
    for (let r = 0; r < 3; r++) {
      api.text(TX - 10, TY + r * CHh + 34, SIDES[r], "ink", { "text-anchor": "end", style: "font-weight:600" });
      cellL.push([]);
      for (let c = 0; c < 3; c++) {
        const x = TX + c * CW, y = TY + r * CHh;
        const rect = api.el("rect", { x: x + 2, y: y + 2, width: CW - 4, height: CHh - 4, rx: 6, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:help" });
        api.text(x + CW / 2, y + 26, CASES[r][c][0], "mono", { "text-anchor": "middle", style: `font-size:12px;${noPtr}` });
        if (CASES[r][c][1]) api.text(x + CW / 2, y + 43, CASES[r][c][1], "muted", { "text-anchor": "middle", style: `${small};${noPtr}` });
        api.tip(rect, { title: `X ${SIDES[r]}, P ${SIDES[c]}`, ...S(176), blurb: `δ' = ${CASES[r][c][0]}${CASES[r][c][1] && CASES[r][c][1].startsWith("=") ? ` ${CASES[r][c][1]}` : ""}: what 2 × (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ reduces to when X and P are on these sides. On the GPU there is no branch: the one formula is evaluated for every case, and both clamps are of small numbers.`, links: [SL(175, "the formula")] });
        cellL[r].push(rect);
      }
    }
    const side = (v, L) => (v < -L ? 0 : v > L ? 2 : 1);
    function drawL() {
      const L = ST.L, X = ST.X, P = ST.P, d = P - X;
      clear(statL); clear(dynL);
      for (const [y, lab] of [[Y1, "before"], [Y2, "after"]]) {
        api.el("rect", { x: ax(-L), y: y - 18, width: ax(L) - ax(-L), height: 36, style: `fill:${CG};opacity:.08` }, statL);
        api.el("line", { x1: A0, y1: y, x2: A0 + AW, y2: y, style: "stroke:var(--muted);stroke-width:1.2" }, statL);
        api.text(20, y + 4, lab, "muted", { style: small }, statL);
        for (let v = -3; v <= 3; v++) {
          api.el("line", { x1: ax(v), y1: y - 4, x2: ax(v), y2: y + 4, style: "stroke:var(--muted)" }, statL);
          api.text(ax(v), y + 18, String(v), "muted", { "text-anchor": "middle", style: "font-size:9.5px" }, statL);
        }
      }
      for (const s of [-1, 1]) {
        api.el("line", { x1: ax(s * L), y1: Y1 - 40, x2: ax(s * L), y2: Y2 + 26, style: `stroke:${CA};stroke-width:1.6;stroke-dasharray:6 4` }, statL);
        api.text(ax(s * L), Y1 - 46, s < 0 ? "crease −L" : "crease +L", "", { "text-anchor": "middle", style: `fill:${CA};font-size:10.5px;font-weight:600` }, statL);
      }
      const fold = v => clamp(v, -L, L) * 2 - v;
      const Xf = fold(X), Pf = fold(P);
      const glo = -L - X, ghi = L - X;
      const dF = clampDiff(d, glo, ghi);
      api.el("line", { x1: ax(X), y1: Y1, x2: ax(Xf), y2: Y2, style: `stroke:${CX};stroke-width:1.2;opacity:.6` }, dynL);
      api.el("line", { x1: ax(P), y1: Y1, x2: ax(Pf), y2: Y2, style: `stroke:${CP};stroke-width:1.2;opacity:.6` }, dynL);
      if (Math.abs(d) > 1e-6) api.arrow(ax(X), Y1 - 26, ax(P), Y1 - 26, CG, 2, dynL);
      api.text((ax(X) + ax(P)) / 2, Y1 - 31, "δ", "", { "text-anchor": "middle", style: `fill:${CG};font-weight:700` }, dynL);
      if (Math.abs(dF) > 1e-6) api.arrow(ax(Xf), Y2 + 30, ax(Pf), Y2 + 30, CG, 2, dynL);
      api.text((ax(Xf) + ax(Pf)) / 2, Y2 + 47, "δ'", "", { "text-anchor": "middle", style: `fill:${CG};font-weight:700` }, dynL);
      api.el("circle", { cx: ax(Xf), cy: Y2, r: 7, style: `fill:${CX}` }, dynL);
      api.el("circle", { cx: ax(Pf), cy: Y2, r: 7, style: `fill:${CP}` }, dynL);
      hX.setAttribute("cx", ax(X)); hX.setAttribute("cy", Y1);
      hP.setAttribute("cx", ax(P)); hP.setAttribute("cy", Y1);
      const cl = clamp(d, glo, ghi), c0 = clamp(0, glo, ghi);
      // float32 with δ shrunk 1e−6: formula vs direct difference
      const ds = d * 1e-6, Ps = X + ds;
      const exact = clampDiff(ds, glo, ghi);
      const viaF = clampDiff(f32(ds), f32(glo), f32(ghi), f32);
      const direct = f32(f32(f32(clamp(f32(Ps), -L, L) * 2) - f32(Ps)) - f32(f32(clamp(f32(X), -L, L) * 2) - f32(X)));
      const rel = v => (exact !== 0 ? Math.abs(v - exact) / Math.abs(exact) : 0);
      const L7 = [
        `X = ${fmt(X)}   P = ${fmt(P)}   δ = P − X = ${fmt(d)}`,
        `gaps (64-bit, CPU): g_lo = −L − X = ${fmt(glo)}   g_hi = L − X = ${fmt(ghi)}`,
        `clamp(δ, g_lo, g_hi) = ${fmt(cl)}   clamp(0, g_lo, g_hi) = ${fmt(c0)}`,
        `δ' = 2 × (${fmt(cl)} − ${fmt(c0)}) − ${fmt(d)} = ${fmt(dF)}`,
        `direct: P' − X' = ${fmt(Pf)} − ${fmt(Xf)} = ${fmt(Pf - Xf)}   ${Math.abs(Pf - Xf - dF) < 1e-9 ? "✓ the same" : "✗"}`,
        `float32, δ × 1e−6: formula ${sci(viaF, 4)} (error ${sci(rel(viaF), 1)})`,
        `                    P' − X' from rounded P, X: ${sci(direct, 4)} (error ${pct(rel(direct))})`,
      ];
      L7.forEach((t, i) => { outL[i].textContent = t; });
      outL[6].style.fill = rel(direct) > 0.01 ? CP : "";
      const rs = side(X, L), cs = side(P, L);
      cellL.forEach((row, r) => row.forEach((rect, c) => rect.setAttribute("style", `fill:${r === rs && c === cs ? "var(--surface)" : "var(--surface)"};stroke:${r === rs && c === cs ? CG : "var(--hairline)"};stroke-width:${r === rs && c === cs ? 3 : 1.2};cursor:help`)));
    }
    api.slider({ x: 450, y: 40, w: 250, label: "fold_limit L", min: 0.4, max: 2, step: 0.05, value: ST.L, fmt: v => fmt(v, 2), onChange: v => { ST.L = v; drawL(); } });

    // ------------------------------------------------ right: the radial fold
    const RX0 = 820;
    api.text(RX0, 28, "RADIAL FOLD · THE SPHERE FOLD, ALONG ONE RAY", "ink", { style: caps });
    const B0 = RX0 + 50, BW = 640, RMAX = 1.8;
    const bx = r => B0 + clamp(r, 0, RMAX) / RMAX * BW;
    const br = x => (x - B0) / BW * RMAX;
    const statR = api.el("g", { style: noPtr }), dynR = api.el("g", { style: noPtr });
    const hXr = api.el("circle", { r: 9, style: `fill:${CX};stroke:var(--surface);stroke-width:2;cursor:ew-resize` });
    const hPr = api.el("circle", { r: 9, style: `fill:${CP};stroke:var(--surface);stroke-width:2;cursor:ew-resize` });
    api.tip(hXr, { title: "|X|: the reference's radius", ...S(137), blurb: "Drag. The CPU sends |Xs|² − min² and |Xs|² − fixed² (the gaps) and the reference's own factor m." });
    api.tip(hPr, { title: "|P|: the pixel's radius", ...S(182), blurb: "Drag. The GPU decides the pixel's regime from g + q against 0, with q = 2 X·δ + δ·δ = |P|² − |X|²: a sum of products, no cancellation." });
    draggable(api, hXr, q => { ST.rX = +clamp(br(q.x), 0.02, RMAX).toFixed(3); drawR(); });
    draggable(api, hPr, q => { ST.rP = +clamp(br(q.x), 0.02, RMAX).toFixed(3); drawR(); });
    const outR = [];
    for (let i = 0; i < 7; i++) outR.push(api.text(RX0, 340 + i * 21, "", "mono", { style: mono }));
    const UX = RX0 + 90, CWr = 210, REG = ["inside", "shell", "outside"];
    api.text(UX, TY - 30, "m' − m, with pixel P …", "muted", { style: small });
    api.text(RX0, TY + 14, "reference X …", "muted", { style: small });
    const RCASES = [
      [["0", "same constant"], ["−fixed² (g_min + q)", "÷ (|P|² min²)"], ["1 − fixed² / min²", "a constant (huge δ)"]],
      [["fixed² g_min", "÷ (min² |X|²)"], ["−fixed² q", "÷ (|P|² |X|²)"], ["g_fix / |X|²", ""]],
      [["fixed² / min² − 1", "a constant (huge δ)"], ["−(g_fix + q) / |P|²", ""], ["0", "both unchanged"]],
    ];
    const cellR = [];
    for (let c = 0; c < 3; c++) api.text(UX + c * CWr + CWr / 2, TY - 10, REG[c], "ink", { "text-anchor": "middle", style: "font-weight:600" });
    for (let r = 0; r < 3; r++) {
      api.text(UX - 10, TY + r * CHh + 34, REG[r], "ink", { "text-anchor": "end", style: "font-weight:600" });
      cellR.push([]);
      for (let c = 0; c < 3; c++) {
        const x = UX + c * CWr, y = TY + r * CHh;
        const rect = api.el("rect", { x: x + 2, y: y + 2, width: CWr - 4, height: CHh - 4, rx: 6, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:help" });
        api.text(x + CWr / 2, y + 26, RCASES[r][c][0], "mono", { "text-anchor": "middle", style: `font-size:12px;${noPtr}` });
        if (RCASES[r][c][1]) api.text(x + CWr / 2, y + 43, RCASES[r][c][1], "muted", { "text-anchor": "middle", style: `${small};${noPtr}` });
        api.tip(rect, { title: `X ${REG[r]}, P ${REG[c]}`, ...S(187), blurb: `m' − m = ${RCASES[r][c][0]}${RCASES[r][c][1] && RCASES[r][c][1].startsWith("÷") ? ` ${RCASES[r][c][1]}` : ""}. Written per regime pair so it is a small precise number over a product, never a difference of two factors. Then δ' = m' δ + X (m' − m), and the pixel's dz multiplies by m'.`, links: [SL(180, "δ' = m' δ + X (m' − m)"), SL(185, "m' − m per regime pair")] });
        cellR[r].push(rect);
      }
    }
    const R1 = 160, R2 = 280;
    function drawR() {
      const mn = ST.min, fx = Math.max(ST.fixed, mn + 0.01), mr2 = mn * mn, fr2 = fx * fx;
      const rX = ST.rX, rP = ST.rP, d = rP - rX;
      clear(statR); clear(dynR);
      for (const [y, lab] of [[R1, "before"], [R2, "after"]]) {
        api.el("rect", { x: bx(0), y: y - 18, width: bx(mn) - bx(0), height: 36, style: `fill:${CP};opacity:.10` }, statR);
        api.el("rect", { x: bx(mn), y: y - 18, width: bx(fx) - bx(mn), height: 36, style: `fill:${api.hue(6)};opacity:.12` }, statR);
        api.el("line", { x1: B0, y1: y, x2: B0 + BW, y2: y, style: "stroke:var(--muted);stroke-width:1.2" }, statR);
        api.text(RX0, y + 4, lab, "muted", { style: small }, statR);
        for (let v = 0; v <= RMAX + 1e-9; v += 0.2) {
          api.el("line", { x1: bx(v), y1: y - 4, x2: bx(v), y2: y + 4, style: "stroke:var(--muted)" }, statR);
          if (Math.abs(v * 5 - Math.round(v * 5)) < 1e-6 && Math.round(v * 10) % 4 === 0) api.text(bx(v), y + 18, fmt(v, 1), "muted", { "text-anchor": "middle", style: "font-size:9.5px" }, statR);
        }
      }
      api.text(bx(mn / 2), R1 - 48, `inside: × ${fmt(fr2 / mr2, 2)}`, "", { "text-anchor": "middle", style: `fill:${CP};${small};font-weight:600` }, statR);
      api.text(bx((mn + fx) / 2), R1 - 62, "shell: × fixed² / r²", "", { "text-anchor": "middle", style: `fill:${api.hue(6)};${small};font-weight:600` }, statR);
      api.text(bx(Math.min((fx + RMAX) / 2, RMAX - 0.15)), R1 - 48, "outside: × 1", "muted", { "text-anchor": "middle", style: `${small};font-weight:600` }, statR);
      const mOf = r2 => (r2 < mr2 ? fr2 / mr2 : r2 < fr2 ? fr2 / r2 : 1);
      const m = mOf(rX * rX), mP = mOf(rP * rP);
      const Xf = m * rX, Pf = mP * rP;
      const r2X = rX * rX, gmin = r2X - mr2, gfix = r2X - fr2, q = 2 * rX * d + d * d, r2P = r2X + q;
      const regX = regimeOf(gmin, gfix), regP = regimeOf(gmin + q, gfix + q);
      const dm = dmPair(regX, regP, q, gmin, gfix, r2X, r2P, mr2, fr2);
      const dF = mP * d + rX * dm;
      api.el("line", { x1: bx(rX), y1: R1, x2: bx(Xf), y2: R2, style: `stroke:${CX};stroke-width:1.2;opacity:.6` }, dynR);
      api.el("line", { x1: bx(rP), y1: R1, x2: bx(Pf), y2: R2, style: `stroke:${CP};stroke-width:1.2;opacity:.6` }, dynR);
      if (Math.abs(d) > 1e-6) api.arrow(bx(rX), R1 - 26, bx(rP), R1 - 26, CG, 2, dynR);
      api.text((bx(rX) + bx(rP)) / 2, R1 - 31, "δ", "", { "text-anchor": "middle", style: `fill:${CG};font-weight:700` }, dynR);
      if (Math.abs(dF) > 1e-6) api.arrow(bx(Xf), R2 + 30, bx(Pf), R2 + 30, CG, 2, dynR);
      api.text((bx(Xf) + bx(Pf)) / 2, R2 + 47, "δ'", "", { "text-anchor": "middle", style: `fill:${CG};font-weight:700` }, dynR);
      api.el("circle", { cx: bx(Xf), cy: R2, r: 7, style: `fill:${CX}` }, dynR);
      api.el("circle", { cx: bx(Pf), cy: R2, r: 7, style: `fill:${CP}` }, dynR);
      hXr.setAttribute("cx", bx(rX)); hXr.setAttribute("cy", R1);
      hPr.setAttribute("cx", bx(rP)); hPr.setAttribute("cy", R1);
      // float32 check with δ shrunk 1e−6 (same X)
      const ds = d * 1e-6, qs = 2 * rX * ds + ds * ds, regPs = regimeOf(gmin + qs, gfix + qs);
      const mPs = regPs === 0 ? fr2 / mr2 : regPs === 1 ? fr2 / (r2X + qs) : 1;
      const exact = mPs * ds + rX * dmPair(regX, regPs, qs, gmin, gfix, r2X, r2X + qs, mr2, fr2);
      const qf = f32(f32(2 * f32(f32(rX) * f32(ds))) + f32(f32(ds) * f32(ds)));
      const r2Pf = f32(f32(r2X) + qf), mPf = regPs === 0 ? f32(fr2 / mr2) : regPs === 1 ? f32(f32(fr2) / r2Pf) : 1;
      const viaF = f32(f32(mPf * f32(ds)) + f32(f32(rX) * dmPair(regX, regPs, qf, f32(gmin), f32(gfix), f32(r2X), r2Pf, f32(mr2), f32(fr2), f32)));
      const Ps32 = f32(rX + ds), X32 = f32(rX);
      const mOf32 = r => { const r2 = f32(r * r); return r2 < mr2 ? f32(fr2 / mr2) : r2 < fr2 ? f32(f32(fr2) / r2) : 1; };
      const direct = f32(f32(mOf32(Ps32) * Ps32) - f32(mOf32(X32) * X32));
      const rel = v => (exact !== 0 ? Math.abs(v - exact) / Math.abs(exact) : 0);
      const L7 = [
        `|X| = ${fmt(rX)}  |P| = ${fmt(rP)}  δ = ${fmt(d)}   regimes: X ${REG[regX]}, P ${REG[regP]}`,
        `q = 2 X·δ + δ·δ = ${fmt(q, 4)} (= |P|² − |X|², no cancellation)`,
        `gaps (CPU): g_min = |X|² − min² = ${fmt(gmin, 4)}   g_fix = |X|² − fixed² = ${fmt(gfix, 4)}`,
        `m = ${fmt(m, 4)}   m' = ${fmt(mP, 4)}   m' − m by the pair's formula = ${fmt(dm, 4)}`,
        `δ' = m' δ + X (m' − m) = ${fmt(dF, 4)}   P' − X' = ${fmt(Pf - Xf, 4)}   ${Math.abs(Pf - Xf - dF) < 1e-9 ? "✓" : "✗"}`,
        `float32, δ × 1e−6: formula ${sci(viaF, 4)} (error ${sci(rel(viaF), 1)})`,
        `                    P' − X' from rounded P, X: ${sci(direct, 4)} (error ${pct(rel(direct))})`,
      ];
      L7.forEach((t, i) => { outR[i].textContent = t; });
      outR[6].style.fill = rel(direct) > 0.01 ? CP : "";
      cellR.forEach((row, r) => row.forEach((rect, c) => rect.setAttribute("style", `fill:var(--surface);stroke:${r === regX && c === regP ? CG : "var(--hairline)"};stroke-width:${r === regX && c === regP ? 3 : 1.2};cursor:help`)));
    }
    api.slider({ x: 1240, y: 40, w: 130, label: "min_radius", min: 0.1, max: 0.95, step: 0.05, value: ST.min, fmt: v => fmt(v, 2), onChange: v => { ST.min = v; drawR(); } });
    api.slider({ x: 1405, y: 40, w: 130, label: "fixed_radius", min: 0.5, max: 1.6, step: 0.05, value: ST.fixed, fmt: v => fmt(v, 2), onChange: v => { ST.fixed = v; drawR(); } });
    api.text(20, 760, "Not drawn: the cylinder fold (the same radial template on xy, m = (2L − r) / r), the KIFS sorts and diagonal swaps (four cases: both, neither, only the pixel, only the reference), the Menger correction (a step of t when P and X cross differently).", "muted", { style: small });
    api.text(20, 778, "Hover a table cell for its spec line.", "muted", { style: small });
    drawL(); drawR();
  },
};

// ================================================================== 6. the per-iteration record
const recordTable = {
  type: "table",
  title: "What the CPU hands the GPU per iteration",
  note: "Spec part 2: four vec4 per iteration for up to PERT_MAX = 20 iterations, every value something a 32-bit float holds precisely: a gap that is small exactly when precision matters, or a multiplier that needs only relative precision. X is the reference's point at that step.",
  columns: [{ label: "shape", w: 110 }, { label: "pert_a", w: 230 }, { label: "pert_b", w: 270 }, { label: "pert_c", w: 210 }, { label: "pert_d", w: 330 }],
  rows: [
    { cells: ["Mandelbox", "lower-crease gaps lo − X, per component", "upper gaps hi − X", "the sphere fold's input point", "(|Xs|² − min_radius², |Xs|² − fixed_radius², the reference's sphere factor m, the cylinder fold's radial gap r_xy − fold_limit)"],
      tip: { title: "Mandelbox record", ...S(137), blurb: "The clamp gaps use the fold's own interval: ±fold_limit for the box fold and for the cylinder fold's z and w, or the hybrid interval [lo, hi] on a hybrid iteration. The cylinder's xy pair uses the radial gap in d.w instead. The octahedral fold is not perturbed.", links: [SL(141, "which interval"), RL("sh", 152, "today: mb_box_fold"), RL("sh", 157, "today: mb_sphere_fold")] } },
    { cells: ["Mandelbox, fold order 1", "clamp gaps of the post-sphere point", "(as fold order 0)", "always the sphere fold's input", "sphere gaps of the pre-fold point"],
      tip: { title: "sphere first", ...S(145), blurb: "With fold_order 1 (sphere first) the sphere gaps are of the pre-fold point and the clamp gaps of the post-sphere point. The GPU recovers anything else from c, m and the radial gap: the cylinder fold's pre-fold xy is c.xy scaled back by (L + gap_r) / (L − gap_r) in fold order 0, or c.xy × m in fold order 1.", links: [RL("sh", 276, "today: the two orders")] } },
    { cells: ["KIFS", "abs-fold gaps −X (after R1)", "the three sort gaps (X_x − X_y, then X_x − X_z, X_y − X_z, each from the state at that comparison), or the four diagonal gaps X_a + X_b", ".x: the Menger-correction gap X_z + t/2 after the scale", "unused"],
      tip: { title: "KIFS record", ...S(138), blurb: "The coordinate and diagonal fold sets are exclusive per shape, so b holds the three sort gaps or the four diagonal gaps, never both.", links: [RL("kifs", 113, "today: _diagonal_fold"), SL(193, "the sort and swap formulas")] } },
    { cells: ["Kleinian", "box gaps −b − X", "b − X", "the post-fold point", "(|Xs|² − radius², the reference's factor m, 0, 0)"],
      tip: { title: "Kleinian record", ...S(139), links: [SL(207, "the fixed-point exit")] } },
  ],
};
const budgetTable = {
  type: "table",
  title: "The uniform budget",
  note: "Spec part 3 says 80 vec4 plus the existing ~110 scalars stay well inside WebGL 2's 224-vector minimum. Counted at this commit: 109 `uniform` lines (71 in mandelbox.gdshader, 20 KIFS, 11 Kleinian, 7 Mandelbulb), nearly all scalars. 'Well inside' holds when scalars pack four to a row; if each took a row it would be about 191 of 224.",
  columns: [{ label: "item", w: 300 }, { label: "vec4 rows", w: 120 }, { label: "where", w: 420 }],
  rows: [
    { cells: ["pert_a, pert_b, pert_c, pert_d", "4 × 20 = 80", "the record, PERT_MAX = 20 entries each"], tip: { title: "the record arrays", ...S(154) } },
    { cells: ["pert_end", "1", "X_k, a vec4"], tip: { title: "pert_end", ...S(155) } },
    { cells: ["pert_iters", "a scalar", "int, 0 = off"], tip: { title: "pert_iters", ...S(154) } },
    { cells: ["the existing uniforms", "109 declarations", "mostly floats, ints and bools; a few vec3s (eye, the camera basis, colours)"], tip: { title: "today's uniforms", ...R("sh", 15), blurb: "71 `uniform` lines in mandelbox.gdshader, 20 in kifs.gdshaderinc, 11 in kleinian.gdshaderinc, 7 in mandelbulb.gdshaderinc, at this commit.", links: [SL(158, "spec: the budget claim")] } },
    { cells: ["total, scalars packed four to a row", "about 110", "the GLSL ES packing rules allow it; well inside 224"], tip: { title: "packed", ...S(158) } },
    { cells: ["total, one row per scalar (worst case)", "about 191", "still inside 224, with less margin: worth checking on a web export"], tip: { title: "unpacked", ...S(158), blurb: "Whether a driver packs scalar uniforms is up to it (Godot may also put material uniforms in a uniform block, whose limit is bytes, not rows). The spec checked that uniform arrays compile headless on 4.6.1; the budget itself is only checkable on a WebGL 2 browser.", links: [SL(157, "checked headless on 4.6.1")] } },
    { cells: ["WebGL 2's guaranteed minimum", "224", "MAX_FRAGMENT_UNIFORM_VECTORS"], tip: { title: "the limit", ...S(158) } },
  ],
};

// ================================================================== 7. one frame at depth
const frameSeq = {
  type: "seq",
  tab: "One frame at depth",
  title: "One frame at depth: from a key press to a pixel",
  note: "Spec part 4, once the camera is within 10 × today's floor. The CPU work is one orbit of 32 iterates (microseconds); the GPU work per sample is k perturbed iterations plus 32 − k ordinary ones. At the default view pert_iters is 0 and the GPU side is today's code.",
  laneWidth: 190, headWidth: 172,
  boundaryAfterCol: 5, boundaryLabel: "CPU → GPU",
  participants: [
    { id: "fly", col: 0, ctx: "cpu", name: "FlyCamera", sub: "physics tick", ...S(91) },
    { id: "cam", col: 1, ctx: "cpu", name: "CameraState", sub: "eye_x/y/z", ...S(77) },
    { id: "view", col: 2, ctx: "cpu", name: "FractalView", sub: "_push_near()", ...S(234) },
    { id: "orbit", col: 3, ctx: "cpu", name: "ReferenceOrbit", sub: "build()", ...S(111) },
    { id: "params", col: 4, ctx: "cpu", name: "FractalParams", sub: "pert_iters, zoom_floor", ...S(225) },
    { id: "mat", col: 5, ctx: "bridge", name: "ShaderMaterial", sub: "the uniforms", ...S(154) },
    { id: "frag", col: 6, ctx: "gpu", name: "fragment()", sub: "every pixel", ...S(211) },
    { id: "dep", col: 8, ctx: "gpu", name: "de_pert · de", sub: "+ mb_orbit(…, first, …)", ...S(160) },
  ],
  rows: [
    { sec: "PHYSICS TICK · CPU, 64-BIT" },
    { from: "fly", to: "params", kind: "call", label: "move_allowed(from64, to64)", tick: "zoom_floor(to): max of two floors", ...S(258), blurb: "Accept the move if the distance at `to` is at least the floor there, or at least the distance at `from` (backing away is always allowed). Unchanged in shape, now in 64-bit.", links: [RL("fly", 95, "today: move_allowed(Vector3, Vector3)"), SL(242, "the two floors")] },
    { from: "fly", to: "cam", kind: "call", label: "set_eye64(ex + dir.x × step, …)", ...S(91), blurb: "The step is added to the doubles; a move far below the Vector3 grid still lands.", links: [RL("fly", 82, "today: t.origin += …")] },
    { from: "cam", to: "view", kind: "signal", label: "changed", ...S(80), blurb: "Emitted when any double differs, even when the rounded transform did not change." },
    { sec: "THE PUSH · CPU" },
    { from: "view", to: "orbit", kind: "call", label: "build(params, ex, ey, ez)", tick: "32 iterates in doubles", ...S(115), toRole: "Iterates the eye 32 times in 64-bit, recording X_i, λ_i and the per-iteration gaps." },
    { from: "orbit", to: "view", kind: "data", label: "orbit (distance = near)", ...S(234), blurb: "Its distance is near, so the estimate is not computed twice." },
    { from: "view", to: "params", kind: "call", label: "pert_iters(orbit, near) → k", ...S(225), blurb: "0 unless perturbable and near < 10 × today's floor; else the smallest k ≤ 20 with λ_k × near ≥ 1e−2." },
    { from: "view", to: "mat", kind: "data", label: "near_dist, coarse_iters, nf_weight", tick: "as today", ...S(235), links: [RL("view", 370, "today")] },
    { from: "view", to: "mat", kind: "data", label: "pert_iters = k", ...S(236) },
    { from: "view", to: "mat", kind: "data", label: "pert_a..d[20], pert_end = X_k", tick: "only while k > 0", ...S(237) },
    { sec: "EVERY PIXEL · GPU, FLOAT32" },
    { from: "mat", to: "frag", kind: "data", label: "this frame's uniforms", ...S(211) },
    { from: "frag", to: "frag", kind: "call", label: "box_intersect(eye, dir)", ...S(213), blurb: "Still from the 32-bit eye: clipping to the shape's cube needs nothing like the precision of the march.", links: [RL("sh", 422, "today")] },
    { sec: "THE MARCH · PERT_ITERS > 0" },
    { from: "frag", to: "dep", kind: "call", label: "de_pert(dir × total, n)", tick: "n = n_coarse, then 32", ...S(211), blurb: "off = dir × total: the shader never forms eye + off on this path.", links: [RL("sh", 438, "n_coarse"), RL("sh", 443, "today: de(pos, n_coarse)")] },
    { from: "dep", to: "dep", kind: "call", label: "k perturbed steps on δ", tick: "gaps from pert_a..d", ...S(161) },
    { from: "dep", to: "dep", kind: "call", label: "mb_orbit(pert_end + δ, dz, c, k, n)", tick: "today's loop body, from k", ...S(164) },
    { from: "dep", to: "frag", kind: "data", label: "the distance estimate", ...S(160) },
    { from: "frag", to: "dep", kind: "call", label: "calc_normal_pert(off, delta)", tick: "six de_pert(off ± e)", ...S(212) },
    { from: "frag", to: "frag", kind: "call", label: "shade: v = eye + dir × total", tick: "32-bit, only where rough is fine", ...S(213) },
    { sec: "PERT_ITERS == 0 · TODAY'S PATH" },
    { from: "frag", to: "dep", kind: "call", label: "de(eye + dir × total, n)", tick: "mb_orbit from 0: bit for bit", ...S(215), links: [RL("sh", 313, "today: de"), SL(166, "first = 0: same arithmetic, same order")] },
  ],
  fragments: [
    { type: "opt", rows: [10, 10], cols: [2, 5], guard1: "k > 0" },
    { type: "loop", rows: [15, 18], cols: [6, 8], guard1: "each march step" },
  ],
};

// ================================================================== 8. decisions
const decisionCards = {
  type: "cards",
  tab: "Decisions",
  title: "What is decided, rejected, risky or open",
  note: "Tags: decided (green), rejected (violet: the history of the choice), risk (orange) and open (amber: left to a follow-up or to measurement). The first four risks were found while building this pane's live port; they are questions for the implementer, not settled facts.",
  columns: 3, cardWidth: 470,
  cards: [
    { title: "Perturbation, not the substitution or the two-float camera", tag: "decided", hue: 3, ...S(21), links: [NL(382, "the note's recommendation")],
      body: "94–100% of rays right at 1e−5 to 1e−7 for every shape, an estimated 1.5–2× per ray, in ordinary float arithmetic. See the Three approaches tab." },
    { title: "Everything automatic; the default view is bit-for-bit", tag: "decided", hue: 3, ...S(67), links: [SL(215, "pert_iters 0 = today's code"), SL(166, "first = 0: same order")],
      body: "No new renderer option, the save stays version 2. At the default view pert_iters is 0 and the shader runs exactly today's code; the shared loop with first = 0 is the same arithmetic in the same order." },
    { title: "The 64-bit eye is the truth; transform is the shadow", tag: "decided", hue: 3, ...S(77), links: [SL(83, "eye() stays the shadow"), SL(86, "the setter rule")],
      body: "CameraState gains eye_x/y/z doubles. Every 32-bit consumer keeps reading eye(), the rounded Vector3, so nothing outside the deep path changes." },
    { title: "Only gaps cross the bridge", tag: "decided", hue: 3, ...S(37), links: [SL(131, "the record")],
      body: "The CPU sends each crease's position minus X, computed in 64-bit. A gap is small exactly when precision matters, and a float32 holds a small number to the same relative precision as a large one. The shader never forms eye + off on the perturbed path." },
    { title: "Hand off when λ_k × near reaches 1e−2, at most 20", tag: "decided", hue: 3, ...S(223), links: [NL(386, "the note's rule"), NL(370, "too large a δ glitches")],
      body: "Big enough that X_k + δ_k in float32 is as good as exact; small enough that δ never grows into the glitch the note saw at k = 24. PERT_MAX = 20 also sizes the uniform arrays." },
    { title: "Switch on at 10 × today's floor: no pop", tag: "decided", hue: 3, ...S(222), links: [SL(231, "why")],
      body: "An order of magnitude before the 32-bit path breaks, both paths agree within the hit threshold, so switching between them shows nothing." },
    { title: "zoom_floor = max(floor_pert, floor_iter)", tag: "decided", hue: 3, ...S(242), links: [SL(245, "floor_pert"), SL(248, "floor_iter")],
      body: "floor_pert: today's formula applied at the handoff point, where the view is λ_20 times bigger (about 1e−11 for the default box). floor_iter: where 32 iterations stop resolving, bound_half / (eps × λ_32). Shapes that are not perturbable keep today's floor." },
    { title: "The self-similar substitution", tag: "rejected", hue: 6, ...N(378), links: [NL(259, "why it is squeezed"), NL(32, "self-similarity does not matter")],
      body: "Approximate by construction: one straight-line camera map is right on one side of a fold crease and a mirror image on the other, so even the best k left up to a third of the rays wrong, as seams that move and jump." },
    { title: "The two-float camera", tag: "rejected", hue: 6, ...N(388), links: [NL(370, "the compiler risk"), R("zoom", 162)],
      body: "Exact, but about 7× per ray and dependent on a WebGL compiler not fusing or reordering the paired-float steps. Kept as the fallback if the per-fold cases prove fiddly in GLSL." },
    { title: "Octahedral and poly folds keep today's floor", tag: "rejected", hue: 6, ...S(55),
      body: "Many-region piecewise maps whose crossing cases are not worth enumerating now. With them pert_iters is 0 and zoom_floor is today's." },
    { title: "The Mandelbulb is not perturbed", tag: "rejected", hue: 6, ...S(57), links: [RL("sh", 316, "its de() branch")],
      body: "Its power map is curved everywhere, not piecewise-linear, so there are no creases to hand gaps for; a follow-up spec. It keeps today's floor." },
    { title: "Noise, the orbit camera, more than 32 iterations", tag: "rejected", hue: 6, ...S(59), links: [SL(62, "orbit camera"), SL(63, "iterations past 32")],
      body: "Noise displacement stays evaluated at the 32-bit position: a displaced surface is smooth below the displacement's size. The orbit camera cannot approach the surface. Going past the 32-iteration floor needs more iterations: a follow-up." },
    { title: "floor_iter from the eye's orbit may stop the default box early", tag: "risk", hue: 2, ...S(248), links: [SL(252, "an estimate, measured by its test"), SL(347, "the bracketing test"), NL(322, "the note's 1e−15: interior points")],
      body: "From this pane's port, a question for the implementer: the eye is outside the shape, so its orbit escapes and its λ_32 is about 2.09^32 ≈ 1.8e10 (the sphere fold barely fires). floor_iter = 2 / (eps × λ_32) is then about 5e−6 on the default centre view, not 'far lower', and as the max it would stop the camera there. A 64-bit march from the same view still hits 8 or 9 of 9 rays at d = 1e−10; the hit points' λ_32 is 6e12 to 6e14. The spec's test should catch it." },
    { title: "Below 1e−6, near is clamped", tag: "risk", hue: 2, ...R("view", 369), links: [RL("params", 281, "NEAR_FLOOR = 1e-6"), SL(234, "spec: distance is near")],
      body: "Today _push_near pushes max(estimate, NEAR_FLOOR = 1e−6). The spec has the orbit's distance become near but does not say whether the clamp goes; pert_iters(orbit, near) with near held at 1e−6 would pick too small a k deeper down." },
    { title: "base_speed still estimates from the 32-bit eye", tag: "risk", hue: 2, ...R("fly", 148), links: [SL(100, "spec: only the clamp floor moves"), RL("fly", 149, "and _ray.distance()")],
      body: "The spec drops the speed clamp to 1e−14 and makes move_allowed 64-bit, but base_speed's own distance comes from `DistanceEstimator.estimate(_camera.eye())`, the rounded shadow, and from the centre ray. At 1e−9 the shadow can be 1e−7 away from the eye, possibly inside the surface." },
    { title: "Far samples carry a large δ", tag: "risk", hue: 2, ...S(160), links: [SL(223, "k sized by near"), NL(370, "the glitch at large δ")],
      body: "k is chosen so λ_k × near ≈ 1e−2, but a sample far along a ray has δ_0 = dir × total with total ≫ near, so its δ_k is much bigger than the rule assumed. The formulas are exact, so it may be harmless; the note's glitch was a δ grown too large. Worth a row in perturbation_test with a far sample." },
    { title: "Merge hazard with the Mandelbulb work on main", tag: "risk", hue: 2, ...S(164), links: [RL("sh", 313, "de(): every shape's branch"), RL("sh", 316, "the Mandelbulb branch")],
      body: "The design moves each shape's loop into a function with a start index and changes de(), fragment() and _push_near: the same places the Mandelbulb work on main touches. Land one before starting the other, or rebase this branch onto main's Mandelbulb first." },
    { title: "The WebGL 2 uniform budget", tag: "risk", hue: 2, ...S(158), links: [SL(157, "checked headless on 4.6.1")],
      body: "80 vec4 for the record plus 109 existing uniform declarations: comfortable if scalars pack, about 191 of 224 rows if they do not. Only a WebGL 2 browser can confirm; see the Per-iteration record tab." },
    { title: "The 1.5–2× cost is an estimate", tag: "open", hue: 4, ...N(372),
      body: "From operation counts, with no GPU in the investigation. It applies only below 10 × today's floor; the load shedder and governor still react to real frame times." },
    { title: "Follow-ups the spec names", tag: "open", hue: 4, ...S(58), links: [SL(63, "past 32 iterations")],
      body: "The poly and octahedral folds, the Mandelbulb, more than 32 iterations past the iteration floor, the orbit camera." },
  ],
};

// ================================================================== 9. test plan
const testCards = {
  type: "cards",
  tab: "Test plan",
  title: "The test plan, keystone first",
  columns: 3, cardWidth: 470,
  cards: [
    { title: "perturbation_test.gd (new): the keystone", tag: "keystone", hue: 3, ...S(321), links: [SL(329, "the checks"), SL(333, "runs before any shader work")],
      body: "A GDScript port of the perturbed step and of the direct step, both in emulated float32 (every result rounded through a PackedFloat32Array, as the note did with numpy), plus the 64-bit reference. Five shape fixtures × d ∈ {1e−5, 1e−6, 1e−7} × 27 rays (a 3 × 3 × 3 fan). Checks: the direct march agrees on under 30% at 1e−6 (today's failure), the perturbed march on at least 90% at every depth, and the perturbed step in 64-bit reproduces the reference exactly (the algebra check). Prints the table for the deep-zoom pane." },
    { title: "reference_orbit_test.gd", tag: "new", hue: 1, ...S(335),
      body: "distance equals DistanceEstimator.estimate_at exactly for every shape fixture; mag is non-decreasing; n is 32 for the Mandelbox and under 32 for a KIFS point that bails out; perturbable is false for the octahedral and poly folds." },
    { title: "camera_state_test.gd", tag: "extended", hue: 1, ...S(339),
      body: "set_eye64 round-trips 1e−12 and emits changed; assigning a transform whose origin is the rounded shadow keeps the doubles; a new origin replaces them; make_default is unchanged." },
    { title: "workspace_test.gd", tag: "extended", hue: 1, ...S(342),
      body: "A capture with an eye 1e−9 from a surface point restores it exactly; saves/default.json loads to the same camera as before." },
    { title: "fractal_params_test.gd", tag: "extended", hue: 1, ...S(344),
      body: "pert_iters is 0 at the default view and at 1e−3, positive at 1e−5, rising as d falls, never above 20; zoom_floor at the surface fixture is below 1e−8 for the default box; floor_iter's prediction brackets the measured stop (a 64-bit march from 10 × floor_iter hits, from floor_iter / 10 it does not)." },
    { title: "fly_camera_test.gd", tag: "extended", hue: 1, ...S(349),
      body: "A camera at 1e−6 with W held moves closer (refused today) and stops at the new floor with at_zoom_limit; the eye moves by less than 1e−9 per tick there (the speed follows the distance)." },
    { title: "center_ray_test.gd", tag: "extended", hue: 1, ...S(352),
      body: "The scalar march agrees with the Vector3 one at the default view and resolves a hit at 1e−8 that the Vector3 one cannot." },
    { title: "fractal_view_test.gd", tag: "extended", hue: 1, ...S(354),
      body: "At the default view pert_iters is 0 and no array is pushed; at a deep camera pert_iters is positive and pert_a has PERT_MAX entries." },
    { title: "shader_test.gd", tag: "extended", hue: 1, ...S(357),
      body: "RENDERER_UNIFORMS gains pert_iters, pert_a, pert_b, pert_c, pert_d, pert_end; the shader compiles." },
    { title: "console, ui_console and main tests", tag: "extended", hue: 1, ...S(359),
      body: "The `deep k=N` readout shows with k and hides at 0. deep_zoom_test.gd is unchanged." },
    { title: "README", tag: "docs", hue: 6, ...S(362),
      body: "The Deep zoom section describes the 64-bit eye, the reference orbit, the handoff and the two floors; the zoom-limit paragraph is rewritten." },
    { title: "The windowed check is the user's", tag: "manual", hue: 4, ...S(365),
      body: "tests/screenshots.sh: the default view must be pixel-identical before and after, and a flight to 1e−8 on the default box must show detail, not speckle. Everything else is headless." },
  ],
};

// The checker (tools/viz/check.mjs) verifies every { file, line } it finds in a pane's data. A
// figure's tooltips are built inside draw(), so each figure also carries `refs`: every S / SL / N /
// NL / R / RL call with literal arguments in its draw source.
function refsIn(fn) {
  const src = String(fn), out = [];
  for (const m of src.matchAll(/\bSL?\((\d+)/g)) out.push(S(+m[1]));
  for (const m of src.matchAll(/\bNL?\((\d+)/g)) out.push(N(+m[1]));
  for (const m of src.matchAll(/\bRL?\("(\w+)",\s*(\d+)/g)) out.push(R(m[1], +m[2]));
  return out;
}
problemFig.refs = refsIn(problemFig.draw);
ideaFig.refs = refsIn(ideaFig.draw);
foldFig.refs = refsIn(foldFig.draw);

VIZ.pane({
  id: "perturbation-design",
  short: "Perturbation design",
  title: "Perturbation: zooming past the 32-bit floor (the design)",
  subtitle: "An approved design, not yet code. Today the fly camera stops about 1e−4 from the surface because the shader forms every ray position in 32-bit floats. The design keeps the eye in 64-bit on the CPU, runs the eye's reference orbit there once per frame, and has the GPU iterate only each pixel's small offset from that orbit, in ordinary float32, until the offset is big enough to hand off to today's loop. Each tab explains one part of the spec with its trade-offs; tooltips link the spec and research-note lines that state each claim, and the existing code a part will change. The live figures run a JavaScript port of the default Mandelbox in doubles and in emulated float32 (Math.fround after every operation), as the spec's own keystone test will.",
  commit: "0c737112d3bdfeb0a5332b0b22f7824b8ec12984",
  pinNote: "perturbation-design-viz, unpushed: links 404 until it is pushed",
  ctx: {
    cpu: { hue: 1, label: "CPU, 64-bit: GDScript doubles, once per camera change" },
    bridge: { hue: 4, label: "the bridge: shader uniforms" },
    gpu: { hue: 6, label: "GPU, float32: the shader, every pixel" },
    out: { hue: 3, label: "console, docs and the keystone test" },
  },
  kinds: {
    call: { style: "solid", label: "calls · sets" },
    signal: { style: "dash", label: "changed signal" },
    data: { style: "dot", label: "pushes or reads a value · a uniform" },
  },
  tabs: [
    problemFig,
    { label: "Three approaches", rows: [[approachTable], [measuredTable, whyCards]] },
    ideaFig,
    partsGraph,
    foldFig,
    { label: "Per-iteration record", rows: [[recordTable], [budgetTable]] },
    frameSeq,
    decisionCards,
    testCards,
  ],
  // The ports, exposed for checking from the console or node.
  ports: { ulp32, ulp64, floor32, stepR, de64, refOrbit, pertIters, floorPert, floorIter, clampDiff, dmPair, pertStep, pixelRun, eyeAt, SURF },
});
})();
