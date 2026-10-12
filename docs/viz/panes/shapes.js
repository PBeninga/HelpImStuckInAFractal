// Pane: the KIFS and the Kleinian, the two shapes ported from Fractacular beside the Mandelbox
// (Help I'm Stuck In A Fractal). Every file:line below was read at `commit` with
// `git show <commit>:<path>`. When the code changes: re-read the lines, bump `commit`, run
// `node tools/viz/check.mjs --print --pane shapes`.
//
// The live figures run JavaScript ports of kifs.gdshaderinc and kleinian.gdshaderinc (equal to
// KifsEstimator and KleinianEstimator), checked at load against the two tests' fixtures. They run
// in doubles like the GDScript twins; the shader runs float32. The Mandelbox's own iteration, the
// march, shading and cameras are the `mandelbox` pane's; the catalogue / binding layer is the
// `console` pane's. This pane starts at the `shape` row and ends at the two distance estimates.
(function () {
const F = {
  sh: "src/fractal/mandelbox.gdshader",
  ks: "src/fractal/kifs.gdshaderinc",
  kl: "src/fractal/kleinian.gdshaderinc",
  kifsDe: "src/fractal/kifs_estimator.gd",
  klDe: "src/fractal/kleinian_estimator.gd",
  kifsShape: "src/fractal/kifs_shape.gd",
  klShape: "src/fractal/kleinian_shape.gd",
  mbShape: "src/fractal/mandelbox_shape.gd",
  cat: "src/fractal/shape_catalogue.gd",
  de: "src/fractal/distance_estimator.gd",
  params: "src/fractal/fractal_params.gd",
  view: "src/fractal/fractal_view.gd",
  ray: "src/camera/center_ray.gd",
  orbit: "src/camera/orbit_camera.gd",
  camState: "src/camera/camera_state.gd",
  inspector: "src/ui/console/attribute_inspector.gd",
  aspec: "src/attributes/attribute_spec.gd",
  ws: "src/workspace/workspace.gd",
  spec: "docs/superpowers/specs/2026-10-08-kifs-kleinian-shapes-design.md",
  plan: "docs/superpowers/plans/2026-10-08-kifs-kleinian-shapes.md",
  readme: "README.md",
  tKifs: "tests/kifs_estimator_test.gd",
  tKl: "tests/kleinian_estimator_test.gd",
  tCat: "tests/shape_catalogue_test.gd",
  tShader: "tests/shader_test.gd",
  tMarch: "tests/march_safety_test.gd",
  tFly: "tests/fly_camera_test.gd",
  tWs: "tests/workspace_test.gd",
  tConsole: "tests/console_test.gd",
};
// Link helpers: R("ks", 73) is { file, line }; RL adds a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const KS = line => R("ks", line), KL = line => R("kl", line), SH = line => R("sh", line);
const FRACTACULAR = name => ({ url: `https://github.com/Adam-G-Klein/Fractacular/blob/main/src/fields/shaders/${name}`, label: `Fractacular: ${name}` });

// ================================================================== the ports
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const PLANES = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]];   // distance_estimator.gd:22
const PLANE_NAMES = ["xy", "xz", "xw", "yz", "yw", "zw"];
const AX4 = ["x", "y", "z", "w"];
const DEFAULT_EYE = [8.175847, 3.812460, 3.283393];   // camera_state.gd:9
const DEG = Math.PI / 180;
const len4 = v => Math.hypot(v[0], v[1], v[2], v[3]);
const dot4 = v => v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];

// One plane rotation on the 4D point v: mb_rot_plane (mandelbox.gdshader:184-193), which both
// includes use; KifsEstimator._rotate (kifs_estimator.gd:99-108) runs the same six in PLANES order.
function rotPlane(v, a, b, deg) {
  const r = deg * DEG, c = Math.cos(r), s = Math.sin(r), pa = v[a], pb = v[b];
  v[a] = pa * c - pb * s; v[b] = pa * s + pb * c;
}
// kifs_rot1 / kifs_rot2 (kifs.gdshaderinc:28-46): the six planes in the fixed order.
function rot6(v, angles) { for (let k = 0; k < 6; k++) rotPlane(v, PLANES[k][0], PLANES[k][1], angles[k]); }

// ---- the KIFS. P is a record of its catalogue values: scale, fold (0 coordinate, 1 diagonal,
// 2 polyfold), poly_k, twist, offset[4], rot1[6], rot2[6] (degrees, PLANES order) and w.
// Defaults are KifsShape's (kifs_shape.gd:26-80): the Menger sponge.
function kifsParams(o) {
  const p = Object.assign({ scale: 3, fold: 0, poly_k: 5, twist: 0, offset: [1, 1, 1, 0],
    rot1: [0, 0, 0, 0, 0, 0], rot2: [0, 0, 0, 0, 0, 0], w: 0 }, o || {});
  p.offset = p.offset.slice(); p.rot1 = p.rot1.slice(); p.rot2 = p.rot2.slice();
  p.sector = 2 * Math.PI / Math.max(Math.floor(p.poly_k + 0.5), 2);          // kifs_estimator.gd:36 = kifs.gdshaderinc:60
  p.r1On = p.rot1.reduce((s, a) => s + Math.abs(a), 0) > 1e-6;                 // kifs.gdshaderinc:76-77
  p.r2On = p.rot2.reduce((s, a) => s + Math.abs(a), 0) > 1e-6;                 // kifs.gdshaderinc:78-79
  return p;
}
const withK = (P, o) => kifsParams(Object.assign({}, P, o));
// menger_fold (mandelbox.gdshader:230-236 = distance_estimator.gd:133-141): abs every component,
// then sort x >= y >= z. Returns what fired, for the stepper.
function mengerFold(v) {
  const neg = [v[0] < 0, v[1] < 0, v[2] < 0, v[3] < 0], swaps = [];
  for (let a = 0; a < 4; a++) v[a] = Math.abs(v[a]);
  if (v[0] < v[1]) { const t = v[0]; v[0] = v[1]; v[1] = t; swaps.push("x↔y"); }
  if (v[0] < v[2]) { const t = v[0]; v[0] = v[2]; v[2] = t; swaps.push("x↔z"); }
  if (v[1] < v[2]) { const t = v[1]; v[1] = v[2]; v[2] = t; swaps.push("y↔z"); }
  return { neg, swaps };
}
// kifs_diagonal_fold (kifs.gdshaderinc:49-55 = kifs_estimator.gd:113-120): reflect across
// x = −y, x = −z, y = −z, x = −w, in that order, each only when the point is on the far side.
const DIAG_PAIRS = [[0, 1], [0, 2], [1, 2], [0, 3]];
function diagonalFold(v) {
  const fired = [];
  for (const [a, b] of DIAG_PAIRS) {
    if (v[a] + v[b] < 0) { const t = v[a]; v[a] = -v[b]; v[b] = -t; fired.push(`${AX4[a]} = −${AX4[b]}`); }
  }
  return { fired };
}
// kifs_poly_fold (kifs.gdshaderinc:59-65 = kifs_estimator.gd:126-130): the xy angle mirrored into
// [0, sector / 2]. GLSL mod and GDScript fposmod both give a result with the divisor's sign.
const fposmod = (a, b) => ((a % b) + b) % b;
function polyFold(v, sector) {
  const r = Math.hypot(v[0], v[1]), a0 = Math.atan2(v[1], v[0]);
  const a = Math.abs(fposmod(a0 + 0.5 * sector, sector) - 0.5 * sector);
  v[0] = r * Math.cos(a); v[1] = r * Math.sin(a);
  return { a0, a };
}
// kifs_box_distance (kifs.gdshaderinc:68-71 = kifs_estimator.gd:134-141): signed distance to [−1, 1]⁴.
function boxDistance(v) {
  let outside = 0, inside = -1e30;
  for (let a = 0; a < 4; a++) { const q = Math.abs(v[a]) - 1; outside += Math.max(q, 0) ** 2; inside = Math.max(inside, q); }
  return Math.sqrt(outside) + Math.min(inside, 0);
}
// kifs_de (kifs.gdshaderinc:73-103) = KifsEstimator.estimate_at (kifs_estimator.gd:32-79).
const BAILOUT2 = 1e6;                                   // kifs_estimator.gd:19 = kifs.gdshaderinc:99
const _kv = new Float64Array(4);
function kifsDe(px, py, pz, iters, P) {
  const v = _kv, s = P.scale, o = P.offset;
  v[0] = px; v[1] = py; v[2] = pz; v[3] = P.w;
  let n = 0;
  for (let i = 0; i < 32; i++) {
    if (i >= iters) break;
    if (P.r1On) rot6(v, P.rot1);
    if (P.fold === 1) diagonalFold(v);
    else { if (P.fold === 2) polyFold(v, P.sector); mengerFold(v); }
    if (P.r2On) rot6(v, P.rot2);
    if (P.twist !== 0) rotPlane(v, 0, 1, P.twist * i);
    for (let a = 0; a < 4; a++) v[a] = s * v[a] - (s - 1) * o[a];
    if (P.fold === 0) { const t = o[2] * (s - 1); if (v[2] < -0.5 * t) v[2] += t; }
    n = i + 1;
    if (dot4(v) > BAILOUT2) break;
  }
  const d = P.fold === 0 ? boxDistance(v) : len4(v);
  return d * Math.pow(s, -n);
}
// The same orbit keeping every stage, for the stepper. kind: start | rot1 | fold | rot2 | twist |
// scale; rot1, rot2 and twist only appear when their knobs are non-zero, as in the code.
function kifsStages(px, py, pz, P, iters) {
  const v = Float64Array.from([px, py, pz, P.w]), s = P.scale, o = P.offset;
  const out = [{ kind: "start", it: 0, z: Array.from(v), n: 0 }];
  let n = 0;
  for (let i = 0; i < iters; i++) {
    if (P.r1On) { rot6(v, P.rot1); out.push({ kind: "rot1", it: i, z: Array.from(v), n }); }
    let info;
    if (P.fold === 1) info = diagonalFold(v);
    else { const poly = P.fold === 2 ? polyFold(v, P.sector) : null; info = mengerFold(v); info.poly = poly; }
    out.push({ kind: "fold", it: i, z: Array.from(v), n, info });
    if (P.r2On) { rot6(v, P.rot2); out.push({ kind: "rot2", it: i, z: Array.from(v), n }); }
    if (P.twist !== 0) { rotPlane(v, 0, 1, P.twist * i); out.push({ kind: "twist", it: i, z: Array.from(v), n, deg: P.twist * i }); }
    for (let a = 0; a < 4; a++) v[a] = s * v[a] - (s - 1) * o[a];
    let corr = false;
    if (P.fold === 0) { const t = o[2] * (s - 1); if (v[2] < -0.5 * t) { v[2] += t; corr = true; } }
    n = i + 1;
    const bail = dot4(v) > BAILOUT2;
    out.push({ kind: "scale", it: i, z: Array.from(v), n, corr, bail });
    if (bail) break;
  }
  return out;
}
// The estimate a stage would give if the loop stopped there: d(z) · scale^−n.
const kifsRunning = (st, P) => (P.fold === 0 ? boxDistance(st.z) : len4(st.z)) * Math.pow(P.scale, -st.n);

// ---- the Kleinian. P: box[4], radius, shift[4], thickness, view_distance, w; defaults are
// KleinianShape's (kleinian_shape.gd:12, 19-55), Knighty's.
function klParams(o) {
  const p = Object.assign({ box: [0.92436, 0.90756, 0.92436, 0.92436], radius: 1, shift: [0, 0, 0, 0],
    thickness: 0.01, view_distance: 10, w: 0 }, o || {});
  p.box = p.box.slice(); p.shift = p.shift.slice();
  p.k = p.radius * p.radius;                               // kleinian.gdshaderinc:20 = kleinian_estimator.gd:20
  return p;
}
const withL = (P, o) => klParams(Object.assign({}, P, o));
// thingy (kleinian_estimator.gd:38-41 = kleinian.gdshaderinc:31-33): half Knighty's field at the
// orbit's end, unsigned.
function thingy(v, t) {
  const rxy = Math.hypot(v[0], v[1]);
  return Math.abs(0.5 * (Math.abs(rxy * v[2]) - t) / Math.sqrt(dot4(v) + Math.abs(t)));
}
// kleinian_de (kleinian.gdshaderinc:17-34) = KleinianEstimator.estimate_at (kleinian_estimator.gd:16-34).
const _lv = new Float64Array(4), _lb = new Float64Array(4);
function klDe(px, py, pz, iters, P) {
  const v = _lv, b = P.box, sh = P.shift, k = P.k;
  v[0] = px; v[1] = py; v[2] = pz; v[3] = P.w;
  let dr = 1;
  for (let i = 0; i < 32; i++) {
    if (i >= iters) break;
    _lb.set(v);
    for (let c = 0; c < 4; c++) v[c] = clamp(v[c], -b[c], b[c]) * 2 - v[c];
    const m = Math.max(k / Math.max(dot4(v), 1e-12), 1);
    for (let c = 0; c < 4; c++) v[c] = v[c] * m + sh[c];
    dr *= m;
    if (v[0] === _lb[0] && v[1] === _lb[1] && v[2] === _lb[2] && v[3] === _lb[3]) break;
  }
  return thingy(v, P.thickness) / dr;
}
// The same orbit, every stage kept. kind: start | box | inv. An `inv` stage with `settled` is the
// one where p == before and the loop stops.
function klStages(px, py, pz, P, iters) {
  const v = Float64Array.from([px, py, pz, P.w]), b = P.box, sh = P.shift, k = P.k;
  const out = [{ kind: "start", it: 0, z: Array.from(v), dr: 1 }];
  let dr = 1;
  for (let i = 0; i < iters; i++) {
    const before = Array.from(v), folded = [];
    for (let c = 0; c < 4; c++) { const nv = clamp(v[c], -b[c], b[c]) * 2 - v[c]; if (nv !== v[c]) folded.push(AX4[c]); v[c] = nv; }
    out.push({ kind: "box", it: i, z: Array.from(v), dr, folded });
    const r2 = dot4(v), m = Math.max(k / Math.max(r2, 1e-12), 1);
    for (let c = 0; c < 4; c++) v[c] = v[c] * m + sh[c];
    dr *= m;
    const settled = v[0] === before[0] && v[1] === before[1] && v[2] === before[2] && v[3] === before[3];
    out.push({ kind: "inv", it: i, z: Array.from(v), dr, r2, m, settled });
    if (settled) break;
  }
  return out;
}

// ---- bounds and the horizon
const KLEINIAN_BOUND = 1e4;                                   // fractal_params.gd:283
// bound_half (fractal_params.gd:491-505): the Mandelbox's 2 (20 in Julia, more with a hybrid: see
// the mandelbox pane), the KIFS's max(2, 1.5 |offset|), the Kleinian's "no cube". (The Mandelbulb's,
// max(2, its escape radius), is not ported here.)
function boundHalf(shape, kp) {
  if (shape === 1) return Math.max(2, 1.5 * len4(kp.offset));
  if (shape === 2) return KLEINIAN_BOUND;
  return 2;
}
// view_limit / view_fade (mandelbox.gdshader:302-312) = FractalParams.view_distance (fractal_params.gd:510-511).
const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const viewLimit = (shape, lp) => (shape === 2 ? lp.view_distance : 0);
const viewFade = (t, vd) => (vd <= 0 ? 0 : smoothstep(0.67 * vd, vd, t));
// box_intersect (mandelbox.gdshader:398-410): [t_enter, t_exit]; a miss has t_exit < max(t_enter, 0).
function boxIntersect(ro, rd, half) {
  let tEnter = -Infinity, tExit = Infinity;
  for (let a = 0; a < 3; a++) {
    const sgn = rd[a] >= 0 ? 1 : -1, safe = sgn * Math.max(Math.abs(rd[a]), 1e-9), inv = 1 / safe;
    const n = inv * ro[a], k = Math.abs(inv) * half;
    tEnter = Math.max(tEnter, -n - k);
    tExit = Math.min(tExit, -n + k);
  }
  return [tEnter, tExit];
}
// coarse_iters (fractal_params.gd:361-371) for the KIFS: the Mandelbox's rule on kifs_scale; the
// Kleinian always gets 32 (364-365); the Mandelbulb runs it on its power (not ported here). eps = precision / detail, 2.5e-5 at the defaults.
const COARSE_BOX_HALF = 2, COARSE_ITERS_MIN = 16;            // fractal_params.gd:338-339
function coarseIters(shape, s, near, eps = 0.000025) {
  if (shape === 2) return 32;
  s = Math.abs(s);
  if (s <= 1) return 32;
  const gap = Math.max(2 * eps * Math.max(near, 0), 1e-300);
  return clamp(Math.ceil(Math.log(COARSE_BOX_HALF / gap) / Math.log(s)), COARSE_ITERS_MIN, 32);
}

// ================================================================== the fixture self-check
// Every captured fixture of kifs_estimator_test.gd and kleinian_estimator_test.gd, with their
// tolerance (relative 1e-5, absolute 1e-9: tKifs:10, tKl:9). The ports must give the tests' numbers.
const KIFS_FIX = [
  { name: "Menger (the defaults)", P: kifsParams(), p: [1.2, -0.3, 0.8], want: 0.20000004768371582, line: 25 },
  { name: "Menger (the defaults)", P: kifsParams(), p: [3, 0, 0], want: 2.0275875100994063, line: 26 },
  { name: "Menger (the defaults)", P: kifsParams(), p: [0.1, 0.9, 1.5], want: 0.5, line: 27 },
  { name: "Sierpinski (diagonal, scale 2)", P: kifsParams({ fold: 1, scale: 2 }), p: [1.2, -0.3, 0.8], want: 0.7511259758577316, line: 40 },
  { name: "Sierpinski (diagonal, scale 2)", P: kifsParams({ fold: 1, scale: 2 }), p: [0.5, 0.5, 0.5], want: 0.30638578479824147, line: 41 },
  { name: "polyfold k 5, scale 2", P: kifsParams({ fold: 2, scale: 2 }), p: [1.2, -0.3, 0.8], want: 0.2001221448106634, line: 45 },
  { name: "polyfold k 5, scale 2", P: kifsParams({ fold: 2, scale: 2 }), p: [0.5, 0.5, 0.5], want: 5.30759802182777e-3, line: 46 },
  { name: "rotated (R1 xy 20°, R2 yz 10°, twist 5°, w 0.1, offset w 0.5)", P: kifsParams({ rot1: [20, 0, 0, 0, 0, 0], rot2: [0, 0, 0, 10, 0, 0], twist: 5, w: 0.1, offset: [1, 1, 1, 0.5] }), p: [1.2, -0.3, 0.8], want: 0.11067921857572048, line: 54 },
  { name: "rotated (R1 xy 20°, R2 yz 10°, twist 5°, w 0.1, offset w 0.5)", P: kifsParams({ rot1: [20, 0, 0, 0, 0, 0], rot2: [0, 0, 0, 10, 0, 0], twist: 5, w: 0.1, offset: [1, 1, 1, 0.5] }), p: [0.1, 0.9, 1.5], want: 0.36204328557047155, line: 55 },
];
const KL_FIX = [
  { name: "the defaults", P: klParams(), p: [1.2, -0.3, 0.8], want: 0.26070721005920766, line: 21 },
  { name: "the defaults", P: klParams(), p: [0.5, 0.5, 0.5], want: 0.20012747383496637, line: 22 },
  { name: "the defaults", P: klParams(), p: [0.1, 0.9, 1.5], want: 0.1502586040758134, line: 23 },
  { name: "shifted (shift x 0.1, radius 1.2, w 0.2)", P: klParams({ shift: [0.1, 0, 0, 0], radius: 1.2, w: 0.2 }), p: [1.2, -0.3, 0.8], want: 0.27111422070432895, line: 25 },
  { name: "shifted (shift x 0.1, radius 1.2, w 0.2)", P: klParams({ shift: [0.1, 0, 0, 0], radius: 1.2, w: 0.2 }), p: [0.1, 0.9, 1.5], want: 0.0867598083840418, line: 26 },
];
function checkFixtures(label, list, de) {
  const fails = [];
  let worst = 0;
  for (const f of list) {
    const got = de(f.p[0], f.p[1], f.p[2], 32, f.P), tol = Math.max(1e-9, 1e-5 * Math.abs(f.want));
    worst = Math.max(worst, Math.abs(got - f.want) / Math.abs(f.want));
    if (!(Math.abs(got - f.want) <= tol)) fails.push(`${f.name} (${f.p.join(", ")}): want ${f.want}, port gives ${got}`);
  }
  if (fails.length) {
    const msg = `[shapes fixtures] the ${label} port fails ${fails.length} of ${list.length} fixtures: ${fails.join("; ")}`;
    console.error(msg);
    if (typeof VIZ !== "undefined" && Array.isArray(VIZ.errors)) VIZ.errors.push(msg);
  }
  return { n: list.length, fails, worst };
}
const FIX_K = checkFixtures("kifs_de", KIFS_FIX, kifsDe);
const FIX_L = checkFixtures("kleinian_de", KL_FIX, klDe);
const sameK = (A, B) => A.scale === B.scale && A.fold === B.fold && A.poly_k === B.poly_k && A.twist === B.twist && A.w === B.w
  && A.offset.every((v, i) => v === B.offset[i]) && A.rot1.every((v, i) => v === B.rot1[i]) && A.rot2.every((v, i) => v === B.rot2[i]);
const sameL = (A, B) => A.radius === B.radius && A.thickness === B.thickness && A.w === B.w
  && A.box.every((v, i) => v === B.box[i]) && A.shift.every((v, i) => v === B.shift[i]);
const samePt = (a, b) => a[0] === b[0] && a[1] === b[1] && a[2] === b[2];

// ================================================================== shared drawing helpers
const fmt = (x, n = 3) => { if (!isFinite(x)) return String(x); const s = x.toFixed(n); return /^-0\.?0*$/.test(s) ? s.slice(1) : s; };
const sci = (x, n = 3) => (x === 0 ? "0" : !isFinite(x) ? String(x) : (Math.abs(x) >= 1e-3 && Math.abs(x) < 1e4) ? fmt(x, n + 1) : x.toExponential(n));
const vec = (v, n = 3) => `(${v.map(x => sci(x, n)).join(", ")})`;
const caps = "font-weight:600;letter-spacing:.06em";
const small = "font-size:10.5px";
const noPtr = "pointer-events:none";

function cssRGB(name) {
  const s = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const m = /^#([0-9a-f]{6})$/i.exec(s);
  if (!m) return [128, 128, 128];
  const v = parseInt(m[1], 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}
const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
// The distance ramp: log10(d) from −6 (hue 1, at the surface) to +0.5 (the figure background).
function deRamp() {
  const near = cssRGB("--c1"), far = cssRGB("--fig-bg"), mid = mix(cssRGB("--c6"), far, 0.35);
  return (d, faint) => {
    const t = clamp((Math.log10(Math.max(d, 1e-12)) + 6) / 6.5, 0, 1);
    const c = t < 0.5 ? mix(near, mid, t * 2) : mix(mid, far, (t - 0.5) * 2);
    return faint ? mix(c, far, faint) : c;
  };
}
// A canvas filled a few rows per animation frame (about 4 ms of rows), so a recompute never costs
// a long frame. pixel(i, j) returns [r, g, b] for column i, row j (row 0 at the top).
function chunkedImage(api, opts, pixel) {
  const surf = api.image(opts), img = surf.ctx.createImageData(opts.pw, opts.ph);
  let row = -1, onDone = null, tick = 0;
  const job = { surf, busy: () => row >= 0, restart(done) { row = 0; onDone = done || null; } };
  api.onFrame(() => {
    if (row < 0) return;
    const t0 = performance.now(), data = img.data;
    while (row < opts.ph && performance.now() - t0 < 4) {
      for (let i = 0; i < opts.pw; i++) {
        const c = pixel(i, row), o = (row * opts.pw + i) * 4;
        data[o] = c[0]; data[o + 1] = c[1]; data[o + 2] = c[2]; data[o + 3] = 255;
      }
      row++;
    }
    const done = row >= opts.ph;
    if (done || ++tick % 2 === 0) { surf.ctx.putImageData(img, 0, 0); surf.flush(); }
    if (done) { row = -1; if (onDone) onDone(); }
  });
  return job;
}
// A row of stage boxes across the top of a stepper: each box tips to its lines; set(i) outlines
// the current one; dim(i, on) greys a stage the knobs have switched off.
function stageRow(api, x0, y0, boxW, gap, stages) {
  const boxes = stages.map((st, i) => {
    const x = x0 + i * (boxW + gap);
    const g = api.el("g", {});
    const r = api.el("rect", { x, y: y0, width: boxW, height: 52, rx: 6, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:pointer" }, g);
    api.text(x + 10, y0 + 19, st.n, "mono", { style: `fill:${st.color || "var(--muted)"};font-weight:700;${noPtr}` }, g);
    api.text(x + 30, y0 + 19, st.name, "ink", { style: `font-weight:600;${noPtr}` }, g);
    api.text(x + 10, y0 + 39, st.f, "mono", { style: `font-size:11px;${noPtr}` }, g);
    api.tip(r, Object.assign({ title: st.name, sub: st.f }, st.tip));
    return { r, g };
  });
  return {
    set(i) {
      boxes.forEach((b, k) => b.r.setAttribute("style", `fill:var(--surface);stroke:${k === i ? (stages[k].color || "var(--c1)") : "var(--hairline)"};stroke-width:${k === i ? 2.6 : 1.2};cursor:pointer`));
    },
    dim(i, off) { boxes[i].g.style.opacity = off ? 0.35 : 1; },
  };
}
// The plane a slice figure shows: "xy" at height z = h, or "xz" at y = h. Returns the 3D point of
// plane coordinates (a, b), and the two plane coordinates of a 4D state.
const PLANE = {
  xy: { axes: [0, 1], off: 2, label: (h, w) => `plane z = ${fmt(h, 2)}, w = ${fmt(w, 2)} · x right, y up · trail projected on x-y` },
  xz: { axes: [0, 2], off: 1, label: (h, w) => `plane y = ${fmt(h, 2)}, w = ${fmt(w, 2)} · x right, z up · trail projected on x-z` },
};
function planePoint(pl, a, b, h) { const p = [0, 0, 0]; p[PLANE[pl].axes[0]] = a; p[PLANE[pl].axes[1]] = b; p[PLANE[pl].off] = h; return p; }
const planeProj = (pl, z) => [z[PLANE[pl].axes[0]], z[PLANE[pl].axes[1]]];

// ================================================================== 1. architecture graph
const arch = {
  type: "graph",
  tab: "Architecture",
  title: "Who talks to whom: one `shape` row, one estimator per shape",
  note: "One ENUM catalogue row, `shape`, chooses the fractal. ShapeCatalogue concatenates the shapes' spec lists (four of them since the Mandelbulb landed on 2026-10-09; this pane follows the two Fractacular ports) and wraps each shape's rows in a show_when on that row, so the console shows one shape's knobs at a time. The resolved value lands in FractalParams.shape, from where three things fan out: the shader's `de()` switches to `kifs_de` or `kleinian_de` (two included files with their own uniforms); DistanceEstimator.estimate_at switches to the matching 64-bit CPU twin; and `bound_half()` / `view_distance()` give the cube the rays march in and, for the Kleinian, the distance at which they stop. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "cat", label: "CATALOGUE — SPECS, THE CONSOLE, SAVES", x: 0, y: 0, w: 740, h: 320 },
    { id: "state", label: "STATE — FRACTALPARAMS AND WHAT IT DERIVES FROM `shape`", x: 790, y: 0, w: 460, h: 320 },
    { id: "shader", label: "SHADER — mandelbox.gdshader AND ITS TWO INCLUDES", x: 1300, y: 0, w: 760, h: 320 },
    { id: "tests", label: "TESTS — THE CATALOGUE AND THE SHADER", x: 0, y: 370, w: 740, h: 130 },
    { id: "cpu", label: "CPU ESTIMATORS — THE 64-BIT TWINS", x: 790, y: 370, w: 760, h: 200 },
    { id: "cameras", label: "CAMERAS — THE CPU MARCHES", x: 1600, y: 370, w: 460, h: 200 },
    { id: "tests2", label: "TESTS — THE ESTIMATORS", x: 790, y: 620, w: 760, h: 130 },
  ],
  nodes: [
    { id: "cat", label: "ShapeCatalogue", sub: "specs() · SHAPE_GROUPS · self_similarity", ctx: "catalogue", zone: "cat", x: 30, y: 60, ...R("cat", 1),
      blurb: "Owns the full knob list in inspector order: the Fractal group (`shape`, `w`), then MandelboxShape's, KifsShape's, KleinianShape's and MandelbulbShape's lists, each limited to its shape by `_only_on`, then the shared Render, Colour, Lighting and Palette rows. 90 ids, each a shader uniform name and a FractalParams field. Also the group heading tooltips and the Shape tab's Self-similar line.",
      links: [RL("cat", 72, "specs()"), RL("cat", 94, "the three append_array calls"), RL("cat", 66, "_only_on"), RL("cat", 37, "SHAPE_GROUPS"), RL("cat", 252, "self_similarity")] },
    { id: "shapeRow", label: "the `shape` row, and w", sub: "0 Mandelbox · 1 KIFS · 2 Kleinian · 3 Mandelbulb", ctx: "catalogue", zone: "cat", x: 350, y: 60, ...R("cat", 77),
      blurb: "The switch itself: an ordinary catalogue row (saved in the view's shape table, pushed as the `shape` uniform, read by FractalParams), so it can even be bound to an axis. `w` moved out of the Box group beside it: every shape but the Mandelbulb is 4D, and the viewer draws its w slice (the row hides on the Mandelbulb, which is 3D). The camera stays where it is when the fractal changes, so the row's effects text says to fly out or Reset camera.",
      links: [RL("cat", 87, "the w row"), RL("cat", 84, "\"the camera stays put\""), RL("spec", 14, "spec: Shape switch")] },
    { id: "mbShape", label: "MandelboxShape", sub: "Box · Julia · Iteration rotation", ctx: "catalogue", zone: "cat", x: 30, y: 160, ...R("mbShape", 1),
      blurb: "The Mandelbox's own knobs (the mandelbox pane), now including the fold shape, the hybrid fold and the scale drift added in the same change. Only its `PLANE_PAIRS` matter here: KifsShape reuses them for its rotation rows.",
      links: [RL("mbShape", 24, "PLANE_PAIRS"), RL("mbShape", 35, "specs()")] },
    { id: "kifsShape", label: "KifsShape", sub: "KIFS · KIFS rotation (20 rows)", ctx: "catalogue", zone: "cat", x: 300, y: 160, ...R("kifsShape", 1),
      blurb: "Scale, Fold set, Polyfold k (shown only with the Polyfold), Twist, the 4D Offset, then R1's and R2's six angles. Defaults (scale 3, coordinate fold, offset 1, 1, 1, 0) make the Menger sponge. Each row's tooltip and effects text is what the console shows; tab 4 lists them.",
      links: [RL("kifsShape", 23, "specs()"), RL("kifsShape", 18, "_polyfold_shown"), RL("kifsShape", 72, "the rotation rows"), RL("kifsShape", 97, "self_similarity: no twist")] },
    { id: "klShape", label: "KleinianShape", sub: "Kleinian (11 rows)", ctx: "catalogue", zone: "cat", x: 570, y: 160, ...R("klShape", 1),
      blurb: "The fold box's four half-widths (Knighty's 0.92436, 0.90756, 0.92436, 0.92436), the inversion radius, the 4D shift, the sheet thickness and the view distance that ends its rays, a Kleinian knob because only the Kleinian fills space.",
      links: [RL("klShape", 15, "specs()"), RL("klShape", 12, "BOX_DEFAULTS"), RL("klShape", 49, "the view distance row"), RL("klShape", 72, "self_similarity: always")] },
    { id: "inspector", label: "AttributeInspector", sub: "show_when hides rows AND headings", ctx: "catalogue", zone: "cat", x: 30, y: 250, ...R("inspector", 99),
      blurb: "Every row re-reads `spec.is_shown(values)` on a table change; a group heading is shown only while one of its rows is. So choosing the KIFS hides Box, Julia and Iteration rotation with their headings and shows KIFS and KIFS rotation; console_test pins it.",
      links: [RL("inspector", 104, "is_shown per row"), RL("aspec", 104, "AttributeSpec.is_shown"), RL("cat", 44, "shown_for: the predicate"), RL("tConsole", 193, "the heading test")] },
    { id: "ws", label: "Workspace", sub: "a file without `shape` → Mandelbox", ctx: "catalogue", zone: "cat", x: 400, y: 250, ...R("ws", 62),
      blurb: "Saves stay version 2: `shape` is just another id in shape.defaults. Restoring a file from before the row existed first sets `shape` to the Mandelbox, whatever is showing, because every such view was one.",
      links: [RL("ws", 65, "set_default(shape, MANDELBOX)"), RL("tWs", 170, "the test"), RL("readme", 343, "README: the save format")] },

    { id: "params", label: "FractalParams", sub: "shape · kifs_* · kleinian_*", ctx: "state", zone: "state", x: 820, y: 60, ...R("params", 14),
      blurb: "`enum Shape { MANDELBOX, KIFS, KLEINIAN, MANDELBULB }` and one exported field per catalogue id, written each frame by apply_resolved. The three helpers below read `shape`.",
      links: [RL("params", 61, "the shape field"), RL("params", 121, "kifs_scale …"), RL("params", 163, "kleinian_box_0 …"), RL("params", 478, "julia_enabled: Mandelbox only")] },
    { id: "bound", label: "bound_half()", sub: "2 · max(2, 1.5 |offset|) · 1e4", ctx: "state", zone: "state", x: 820, y: 131, ...R("params", 491),
      blurb: "Half the side of the cube the rays march in and the orbit camera aims into. Mandelbox: 2, or 20 in Julia mode, more with a hybrid fold. KIFS: 1.5 × |offset|, never under 2: the attractor of p → s·p − (s−1)·offset under distance-preserving folds lies within |offset| of the origin, and the margin covers the rotations. Kleinian: 1e4, a cube too big to matter, because its set fills space and view_distance ends the rays instead. (Mandelbulb: max(2, its escape radius).) Replaced the hard-coded 2 / 20 in the view and the orbit camera.",
      links: [RL("params", 482, "the comment"), RL("params", 495, "KIFS"), RL("params", 499, "Kleinian"), RL("tKifs", 65, "2.598 for the default offset")] },
    { id: "vdist", label: "view_distance()", sub: "Kleinian: kleinian_view_distance, else 0", ctx: "state", zone: "state", x: 820, y: 202, ...R("params", 510),
      blurb: "How far from the eye a ray may go before it stops, 0 for no limit. Only the Kleinian has one (10 by default); the CPU marches clamp their cube exit to it exactly as the shader does.",
      links: [RL("tKl", 41, "the test")] },
    { id: "coarse", label: "coarse_iters(near)", sub: "KIFS: the rule on its Scale · Kleinian: 32", ctx: "state", zone: "state", x: 820, y: 273, ...R("params", 361),
      blurb: "The march's first-phase iteration count (the deep-zoom rule, mandelbox pane tab 5). The KIFS shrinks its detail by its own scale each iteration, so the same formula runs on kifs_scale. The Kleinian has no steady rate (its inversion magnifies only inside the sphere, by a varying amount), so it always marches its coarse pass at 32; its loop stops early anyway once the point settles. (The Mandelbulb runs the rule on its power.)",
      links: [RL("params", 353, "the comment"), RL("params", 364, "the Kleinian's 32"), RL("params", 367, "the KIFS: its own scale"), RL("readme", 112, "README")] },

    { id: "view", label: "FractalView._push_params", sub: "every id as a uniform · box_half", ctx: "shader", zone: "shader", x: 1330, y: 60, ...R("view", 380),
      blurb: "Pushes every RESOLVED_KEYS field under its own name, `shape` and the two shapes' knobs among them, then `box_half` = bound_half(). `_push_near` pushes near_dist = D(eye) through DistanceEstimator (which dispatches on shape), coarse_iters(near) and nf_weight.",
      links: [RL("view", 385, "the loop over RESOLVED_KEYS"), RL("view", 390, "box_half"), RL("view", 422, "_push_near"), RL("view", 427, "coarse_iters")] },
    { id: "deSh", label: "de(p, iters)", sub: "switch on `shape`, + noise_displace", ctx: "shader", zone: "shader", x: 1330, y: 150, ...SH(316),
      blurb: "The one distance estimate the march and the normal call. `shape == 1` returns kifs_de(vec4(p, w), iters), `shape == 2` kleinian_de, `shape == 3` the Mandelbulb's mandelbulb_de(p, iters) (3D, no w); otherwise the Mandelbox loop below it. The noise editor's displacement is added for every shape. The includes come after mb_rot_plane and menger_fold, which the KIFS reuses.",
      links: [RL("sh", 317, "the KIFS branch"), RL("sh", 318, "the Kleinian branch"), RL("sh", 297, "the #include lines"), RL("sh", 51, "uniform int shape")] },
    { id: "kifsSh", label: "kifs_de(vec4 p, int iters)", sub: "kifs.gdshaderinc", ctx: "shader", zone: "shader", x: 1660, y: 110, ...KS(73),
      blurb: "Tab 2, stage by stage: R1, the fold set, R2, the twist, p = s·p − (s−1)·offset, the Menger correction, bailout at |p|² > 1e6; then the box distance to [−1, 1]⁴ (coordinate fold) or |p|, times s⁻ⁿ. Its 20 uniforms are the catalogue ids.",
      links: [RL("ks", 7, "the uniforms"), RL("ks", 81, "the loop"), RL("ks", 101, "the distance")] },
    { id: "klSh", label: "kleinian_de(vec4 p, int iters)", sub: "kleinian.gdshaderinc", ctx: "shader", zone: "shader", x: 1660, y: 200, ...KL(17),
      blurb: "Tab 3, stage by stage: fold each component back into its box, push a point inside the inversion sphere out through it, shift, dr ·= m, stop once a step leaves p unchanged; then Knighty's thingy at the end point, over dr. Its 11 uniforms are the catalogue ids; kleinian_view_distance is also read by view_limit().",
      links: [RL("kl", 5, "the uniforms"), RL("kl", 22, "the loop"), RL("kl", 33, "the thingy")] },
    { id: "limit", label: "view_limit() · view_fade(t)", sub: "rays stop at vd · fade from 0.67 vd", ctx: "shader", zone: "shader", x: 1330, y: 240, ...SH(302),
      blurb: "view_limit() is kleinian_view_distance on the Kleinian, 0 otherwise. fragment() clamps t_exit to it (after the cube and the fog), so a Kleinian ray that reaches it is a miss, drawn as background; and view_fade(t) = smoothstep(0.67 vd, vd, t) mixes every hit colour toward the background over the last third, a soft horizon instead of a wall. Tab 5 draws both.",
      links: [RL("sh", 308, "view_fade"), RL("sh", 433, "t_exit = min(…, view_limit())"), RL("sh", 563, "the mix on a lit hit"), RL("sh", 475, "and on a Grayscale hit")] },

    { id: "de", label: "DistanceEstimator.estimate_at", sub: "match params.shape", ctx: "cpu", zone: "cpu", x: 820, y: 440, ...R("de", 30),
      blurb: "The CPU side of `de(p, iters)`: KIFS → KifsEstimator, KLEINIAN → KleinianEstimator, MANDELBULB → MandelbulbEstimator, else the Mandelbox core (mandelbox_at). Everything on the CPU that needs a distance goes through here: fly speed, the centre ray, orbit clicks, near_dist, the self-check tests.",
      links: [RL("de", 32, "the match"), RL("de", 42, "mandelbox_at"), RL("de", 133, "menger_fold, shared with the KIFS")] },
    { id: "kifsCpu", label: "KifsEstimator", sub: "64-bit twin of kifs_de", ctx: "cpu", zone: "cpu", x: 1180, y: 420, ...R("kifsDe", 1),
      blurb: "estimate_at in scalar 64-bit floats, the orbit as a 4-element Array, mirroring kifs_de line for line. Its header holds the two changes from Fractacular (the diagonal fold on the point itself; the mirror polyfold). The R1 / R2 angles are prebuilt as cos/sin pairs because the fly camera's centre ray calls this every estimate.",
      links: [RL("kifsDe", 32, "estimate_at"), RL("kifsDe", 10, "the two changes"), RL("kifsDe", 86, "_angles"), RL("kifsDe", 22, "FoldSet")] },
    { id: "klCpu", label: "KleinianEstimator", sub: "64-bit twin of kleinian_de", ctx: "cpu", zone: "cpu", x: 1180, y: 500, ...R("klDe", 1),
      blurb: "estimate_at and `thingy`, mirroring kleinian_de. The header explains the formula: the distance to the thickened sheets |r_xy z| = thickness whose images under the folds make the limit set, halved because the thingy's own field is steeper than 1, divided by dr.",
      links: [RL("klDe", 16, "estimate_at"), RL("klDe", 38, "thingy"), RL("klDe", 3, "the header")] },

    { id: "ray", label: "CenterRay.march", sub: "bound_half() · view_distance()", ctx: "camera", zone: "cameras", x: 1630, y: 420, ...R("ray", 69),
      blurb: "The fly camera's centre ray (its speed and the probe dot): a CPU sphere trace in the shape's own cube, clamped to the view distance so a Kleinian ray that would pass it is a miss, just as the picture shows. The step is DistanceEstimator.estimate_at, whichever shape is drawn.",
      links: [RL("ray", 70, "bound_half"), RL("ray", 71, "the view-distance clamp"), RL("ray", 79, "estimate_at"), RL("tFly", 134, "fly test: Menger, Sierpinski, Kleinian")] },
    { id: "orbit", label: "OrbitCamera._march", sub: "the same two", ctx: "camera", zone: "cameras", x: 1630, y: 500, ...R("orbit", 156),
      blurb: "The click-to-centre march reads the same bound_half() and view_distance(), so a click on the Kleinian's horizon re-centres nowhere rather than on a point the shader never drew.",
      links: [RL("orbit", 157, "the view-distance clamp")] },

    { id: "tKifs", label: "kifs_estimator_test", sub: "9 fixtures · Menger facts · symmetry", ctx: "test", zone: "tests2", x: 1080, y: 670, ...R("tKifs", 1),
      blurb: "Captured values for the Menger defaults, the Sierpinski, the polyfold and a rotated set (this pane's port runs all nine at load), plus the geometry the defaults must honour: faces at ±1, the first-level holes empty, solid corners, cube symmetry, and bound_half = 1.5 |offset|.",
      links: [RL("tKifs", 25, "the fixtures"), RL("tKifs", 28, "the Menger facts"), RL("tKifs", 65, "bound_half")] },
    { id: "tKl", label: "kleinian_estimator_test", sub: "5 fixtures · D(p) = D(−p) · view distance", ctx: "test", zone: "tests2", x: 1340, y: 670, ...R("tKl", 1),
      blurb: "Captured values at the defaults and a shifted set (run at load here), the box fold's mirror symmetry with no shift, every knob changing the distance, and that only the Kleinian has a view distance, no real cube, and no Julia marker.",
      links: [RL("tKl", 21, "the fixtures"), RL("tKl", 28, "D(p) = D(−p)"), RL("tKl", 40, "the view distance")] },
    { id: "tMarch", label: "march_safety_test", sub: "no full step jumps a surface", ctx: "test", zone: "tests2", x: 820, y: 670, ...R("tMarch", 1),
      blurb: "Each shape and option is safe to sphere-trace: 40 rays marched with full steps never jump a surface the same rays marched with quarter steps find, and some rays hit. Menger, Sierpinski, polyfold, a rotated Menger and the Kleinian are among the cases.",
      links: [RL("tMarch", 61, "the KIFS cases"), RL("tMarch", 70, "the Kleinian"), RL("spec", 140, "spec: why not a Lipschitz bound")] },
    { id: "tCat", label: "shape_catalogue_test", sub: "90 ids · rows hide off their shape", ctx: "test", zone: "tests", x: 30, y: 420, ...R("tCat", 1),
      blurb: "The catalogue ids are the expected 90 in order; each shape's rows show only while it is drawn (and keep their own condition, like Polyfold k and the Julia constants); the two console tabs show every group exactly once.",
      links: [RL("tCat", 38, "the 90 ids"), RL("tCat", 120, "the shape switch block"), RL("tCat", 160, "Polyfold k hides for the coordinate fold")] },
    { id: "tShader", label: "shader_test", sub: "shape uniforms = catalogue ids", ctx: "test", zone: "tests", x: 330, y: 420, ...R("tShader", 1),
      blurb: "The shader compiles headless and its non-renderer uniforms equal ShapeCatalogue.catalogue_ids() exactly, includes and all. Fractacular's technique-schema check, ported.",
      links: [RL("tShader", 43, "the equality")] },
  ],
  edges: [
    { from: "cat", to: "shapeRow", kind: "call", ...R("cat", 77), blurb: "The `shape` row and `w` are appended first, in their own Fractal group." },
    { from: "cat", to: "mbShape", kind: "call", label: "MandelboxShape.specs()", ...R("cat", 94), bow: 0 },
    { from: "cat", to: "kifsShape", kind: "call", label: "KifsShape.specs()", ...R("cat", 95), bow: 1.1 },
    { from: "cat", to: "klShape", kind: "call", label: "KleinianShape.specs()", ...R("cat", 96), bow: 0.3 },
    { from: "shapeRow", to: "inspector", kind: "data", ...R("cat", 44), bow: 1.0,
      blurb: "Every per-shape row's show_when is `shown_for(shape, inner)`: shown while the table's `shape` equals the row's shape and the row's own condition (if any) also holds." },
    { from: "ws", to: "shapeRow", kind: "data", ...R("ws", 65), blurb: "A file from before the row existed has no `shape` id: restore() sets the table's `shape` to the Mandelbox before applying the file, whatever was showing." },
    { from: "shapeRow", to: "params", kind: "data", label: "params.shape", ...R("params", 61), bow: 0,
      blurb: "Main resolves the table each frame (the console pane); the `shape` value lands in FractalParams.shape like every other id." },
    { from: "params", to: "bound", kind: "data", label: "shape · offset", ...R("params", 492) },
    { from: "params", to: "vdist", kind: "data", label: "shape", ...R("params", 511), bow: 0.5 },
    { from: "params", to: "coarse", kind: "data", label: "shape · kifs_scale", ...R("params", 364), bow: 0.9 },
    { from: "view", to: "params", kind: "data", label: "every RESOLVED_KEYS field", ...R("view", 385), bow: -0.5 },
    { from: "bound", to: "view", kind: "data", label: "box_half", ...R("view", 390) },
    { from: "coarse", to: "view", kind: "data", label: "coarse_iters", ...R("view", 427), bow: 0.6 },
    { from: "view", to: "deSh", kind: "data", label: "`shape` + the shape uniforms", ...R("view", 387) },
    { from: "deSh", to: "kifsSh", kind: "call", label: "shape == 1", ...SH(317) },
    { from: "deSh", to: "klSh", kind: "call", label: "shape == 2", ...SH(318) },
    { from: "klSh", to: "limit", kind: "data", label: "kleinian_view_distance", ...SH(303), bow: 0.6,
      blurb: "view_limit() reads the include's uniform directly: the one Kleinian knob the march reads besides the estimate." },
    { from: "params", to: "de", kind: "data", label: "params.shape", ...R("de", 32) },
    { from: "de", to: "kifsCpu", kind: "call", label: "Shape.KIFS", ...R("de", 34) },
    { from: "de", to: "klCpu", kind: "call", label: "Shape.KLEINIAN", ...R("de", 36) },
    { from: "ray", to: "bound", kind: "data", label: "bound_half", ...R("ray", 70), bow: -0.5 },
    { from: "ray", to: "vdist", kind: "data", label: "view_distance", ...R("ray", 71), bow: -0.3 },
    { from: "orbit", to: "vdist", kind: "data", label: "view_distance", ...R("orbit", 157), bow: 0.3 },
    { from: "ray", to: "de", kind: "call", label: "estimate_at", ...R("ray", 79) },
    { from: "tKifs", to: "kifsCpu", kind: "data", label: "estimate_at", ...R("tKifs", 9), bow: 0 },
    { from: "tKl", to: "klCpu", kind: "data", label: "estimate_at", ...R("tKl", 8), bow: 0 },
    { from: "tMarch", to: "de", kind: "data", label: "estimate_at", ...R("tMarch", 18), bow: 0 },
  ],
};

// ================================================================== 2. the KIFS, fold by fold
const kifsFig = {
  type: "figure",
  tab: "KIFS fold by fold",
  title: "The KIFS, fold by fold: a port of kifs_de",
  note: "A port of `kifs_de` (equal to KifsEstimator.estimate_at), stage by stage, on the 4D orbit point p = (x, y, z, w). Click the plane to pick a point; Step walks its orbit. Each iteration: R1 (six plane angles, only when any is non-zero), the fold set, R2, the twist (iteration i turns the xy plane by twist × i), then p = s·p − (s − 1)·offset, which scales everything away from the offset. The folds are mirrors: the Coordinate fold takes |p| and sorts x ≥ y ≥ z (cube symmetry, with the Menger correction that reflects the far z layer back), the Diagonal fold reflects across x = −y, x = −z, y = −z, x = −w (the Sierpinski fold), the Polyfold mirrors the xy angle into one half-wedge of 2π/k and then runs the Coordinate fold. The orbit bails out once |p|² > 1e6. The estimate is the distance from the last p to the base cell, the box [−1, 1]⁴ for the Coordinate fold or the origin for the others, shrunk by s⁻ⁿ for the n iterations run. The background is that estimate on the plane (blue at the surface). Doubles here; the shader runs float32.",
  w: 1560, h: 1110,
  draw(api) {
    const GX = 20, GY = 96, VS = 600, RW = 2.0, RES = 120;
    const S = { P: kifsParams(), p: [1.2, -0.3, 0.8], h: 0.8, pl: "xy", k: 0 };
    const ITERS = 32;
    const sx = x => GX + (x + RW) / (2 * RW) * VS, sy = y => GY + (RW - y) / (2 * RW) * VS;
    const C = { start: api.hue(3), rot1: api.hue(6), fold: api.hue(2), rot2: api.hue(6), twist: api.hue(5), scale: api.hue(1) };
    const STAGE_IDX = { rot1: 0, fold: 1, rot2: 2, twist: 3, scale: 4 };
    const STAGE_NAMES = { start: "start", rot1: "after R1", fold: "after the fold", rot2: "after R2", twist: "after the twist", scale: "after the scale toward the offset" };
    const FOLD_NAMES = ["Coordinate", "Diagonal", "Polyfold"];
    let orbit = [];
    const LAST = () => orbit.length - 1;
    const fixture = () => KIFS_FIX.find(f => samePt(f.p, S.p) && sameK(f.P, S.P));

    // ---- stage list across the top
    const stages = stageRow(api, 20, 16, 244, 10, [
      { n: "1", name: "R1", f: "six planes, before the fold", color: C.rot1,
        tip: { ...KS(83), blurb: "Only when some kifs_rot1_* angle is non-zero (`rot1`, decided once per estimate): p is rotated in the xy, xz, xw, yz, yw and zw planes in that order, each by mb_rot_plane. Rotating BEFORE the fold changes which part of space each fold sees, so the copies turn against each other.", links: [RL("ks", 28, "kifs_rot1"), RL("ks", 76, "the rot1 flag"), RL("kifsDe", 45, "GDScript"), RL("kifsDe", 99, "_rotate")] } },
      { n: "2", name: "Fold set", f: "Coordinate · Diagonal · Polyfold", color: C.fold,
        tip: { ...KS(84), blurb: "Coordinate (kifs_fold 0): menger_fold, |p| then sort x ≥ y ≥ z, the Menger sponge's symmetry. Diagonal (1): kifs_diagonal_fold, four reflections across diagonal planes, the Sierpinski tetrahedron's. Polyfold (2): kifs_poly_fold mirrors the xy angle into [0, sector/2], sector = 2π / round(k), then menger_fold too (the polyfold alone leaves dust too sparse to hit). Hover the current dot for which reflections fired.", links: [RL("sh", 230, "menger_fold"), RL("ks", 49, "kifs_diagonal_fold"), RL("ks", 59, "kifs_poly_fold"), RL("kifsDe", 47, "GDScript: the three branches")] } },
      { n: "3", name: "R2", f: "six planes, after the fold", color: C.rot2,
        tip: { ...KS(90), blurb: "Only when some kifs_rot2_* angle is non-zero: the same six-plane rotation AFTER the fold, which turns the copies themselves before they are scaled, so the detail spins at every scale at once.", links: [RL("ks", 38, "kifs_rot2"), RL("kifsDe", 54, "GDScript")] } },
      { n: "4", name: "Twist", f: "xy by twist × i", color: C.twist,
        tip: { ...KS(91), blurb: "Only when kifs_twist is non-zero: iteration i rotates the xy plane by twist × i degrees, so each iteration turns by a different angle. That is why a twisted KIFS is no longer exactly self-similar (the Shape tab's line says so).", links: [RL("kifsDe", 56, "GDScript"), RL("kifsShape", 100, "self_similarity: the twist disqualifies")] } },
      { n: "5", name: "Scale toward the offset", f: "p = s·p − (s−1)·o ; Menger fix", color: C.scale,
        tip: { ...KS(92), blurb: "Every component: p = s·p − (s − 1)·offset, which fixes the offset and stretches everything else away from it by s, so the folded copy becomes s times smaller in the final shape. With the Coordinate fold the Menger correction follows: t = offset.z·(s − 1), and p.z < −t/2 gets t added, which reflects the far z layer back so the sponge's z tunnels line up. Then n = i + 1 and the bailout test |p|² > 1e6.", links: [RL("ks", 93, "the Menger correction"), RL("ks", 99, "the bailout"), RL("kifsDe", 64, "GDScript: the scale"), RL("kifsDe", 66, "GDScript: the correction")] } },
      { n: "D", name: "The estimate", f: "d(p) · s⁻ⁿ", color: "var(--ink)",
        tip: { ...KS(101), blurb: "d is the signed box distance to [−1, 1]⁴ for the Coordinate fold (so the sponge's faces and edges stay crisp) or plain |p| for the other two; n is the iterations actually run, fewer after a bailout. Each iteration magnified space by s, so a distance measured in the last p is s⁻ⁿ of a distance at the start. The fixtures pin it.", links: [RL("ks", 68, "kifs_box_distance"), RL("kifsDe", 74, "GDScript: d"), RL("kifsDe", 79, "GDScript: return"), RL("tKifs", 25, "the fixtures")] } },
    ]);

    // ---- the plane: heat image, geometry, trail
    const ramp = { f: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VS, h: VS, pw: RES, ph: RES }, (i, j) => {
      const a = -RW + (i + 0.5) / RES * 2 * RW, b = RW - (j + 0.5) / RES * 2 * RW, q = planePoint(S.pl, a, b, S.h);
      return ramp.f(kifsDe(q[0], q[1], q[2], 32, S.P), 0.45);
    });
    const clipId = "kifs-fold-clip";
    api.el("rect", { x: GX, y: GY, width: VS, height: VS }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const geo = api.el("g", { "clip-path": `url(#${clipId})`, style: noPtr });
    const trailG = api.el("g", { "clip-path": `url(#${clipId})` });
    api.el("rect", { x: GX, y: GY, width: VS, height: VS, style: "fill:none;stroke:var(--muted);stroke-width:1.2;pointer-events:none" });
    for (const t of [-2, -1, 0, 1, 2]) {
      api.text(sx(t), GY + VS + 14, String(t), "muted", { "text-anchor": "middle", style: small });
      api.text(GX - 4, sy(t) + 4, String(t), "muted", { "text-anchor": "end", style: small });
    }
    const axisLbl = api.text(GX + VS, GY + VS + 30, "", "muted", { "text-anchor": "end", style: small });
    function drawGeo() {
      while (geo.firstChild) geo.removeChild(geo.firstChild);
      api.el("line", { x1: sx(-RW), y1: sy(0), x2: sx(RW), y2: sy(0), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      api.el("line", { x1: sx(0), y1: sy(-RW), x2: sx(0), y2: sy(RW), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      // the base cell [−1, 1] (the coordinate fold's distance box) and the bound cube
      api.el("rect", { x: sx(-1), y: sy(1), width: sx(1) - sx(-1), height: sy(-1) - sy(1), style: `fill:none;stroke:${C.fold};stroke-width:1.6;stroke-dasharray:7 4` }, geo);
      const bh = boundHalf(1, S.P);
      if (bh < RW) api.el("rect", { x: sx(-bh), y: sy(bh), width: sx(bh) - sx(-bh), height: sy(-bh) - sy(bh), style: "fill:none;stroke:var(--muted);stroke-width:1;stroke-dasharray:2 4" }, geo);
      // the offset, the fixed point of the scale
      const o = planeProj(S.pl, S.P.offset);
      api.el("circle", { cx: sx(o[0]), cy: sy(o[1]), r: 6, style: `fill:none;stroke:${C.scale};stroke-width:1.8` }, geo);
      api.el("line", { x1: sx(o[0]) - 10, y1: sy(o[1]), x2: sx(o[0]) + 10, y2: sy(o[1]), style: `stroke:${C.scale};stroke-width:1` }, geo);
      api.el("line", { x1: sx(o[0]), y1: sy(o[1]) - 10, x2: sx(o[0]), y2: sy(o[1]) + 10, style: `stroke:${C.scale};stroke-width:1` }, geo);
      // the polyfold's wedge edges (xy plane only)
      if (S.P.fold === 2 && S.pl === "xy") {
        const kk = Math.max(Math.floor(S.P.poly_k + 0.5), 2);
        for (let m = 0; m < 2 * kk; m++) {
          const a = m * Math.PI / kk;
          api.el("line", { x1: sx(0), y1: sy(0), x2: sx(RW * 2 * Math.cos(a)), y2: sy(RW * 2 * Math.sin(a)), style: `stroke:${C.fold};stroke-width:0.8;opacity:.5;stroke-dasharray:3 3` }, geo);
        }
      }
      // the diagonal fold's mirror x = −y (xy plane only)
      if (S.P.fold === 1 && S.pl === "xy") api.el("line", { x1: sx(-RW), y1: sy(RW), x2: sx(RW), y2: sy(-RW), style: `stroke:${C.fold};stroke-width:0.8;opacity:.6;stroke-dasharray:3 3` }, geo);
    }
    // trail: one segment + dot per state (pooled at the most stages an orbit can have: 5 per iteration)
    const MAXK = ITERS * 5;
    const segs = [], dots = [];
    for (let k = 1; k <= MAXK; k++) segs.push(api.el("line", { style: `stroke-width:1.8;${noPtr}` }, trailG));
    const DOT_REFS = { start: KS(73), rot1: KS(83), fold: KS(84), rot2: KS(90), twist: KS(91), scale: KS(92) };
    for (let k = 0; k <= MAXK; k++) {
      const c = api.el("circle", { r: k === 0 ? 6 : 3.4, style: "cursor:pointer" }, trailG);
      dots.push(c);
      api.tip(c, { title: "a state of the orbit", ...KS(81), live() {
        const st = orbit[k];
        if (!st) return {};
        const lines = [`\`p\` = ${vec(st.z)}`, `|p| = ${sci(len4(st.z))}`, `n = ${st.n} · running d·s⁻ⁿ = ${sci(kifsRunning(st, S.P))}`];
        if (st.kind === "fold") lines.push(foldLine(st));
        if (st.kind === "twist") lines.push(`xy turned by ${fmt(st.deg, 2)}° (twist ${fmt(S.P.twist, 2)}° × i ${st.it})`);
        if (st.kind === "scale") lines.push(`${st.corr ? "the Menger correction fired (p.z += t)" : "no Menger correction"}${st.bail ? " · BAILOUT: |p|² > 1e6, the loop stops" : ""}`);
        return { title: k === 0 ? "p, the start of the orbit" : `iteration ${st.it + 1}, ${STAGE_NAMES[st.kind]}`, sub: `state ${k} of ${LAST()}`, ...DOT_REFS[st.kind], blurb: lines.join("\n") };
      } });
    }
    const curRing = api.el("circle", { r: 9, style: `fill:none;stroke:var(--ink);stroke-width:2;${noPtr}` }, trailG);
    function foldLine(st) {
      const I = st.info;
      if (S.P.fold === 1) return `diagonal fold: ${I.fired.length ? I.fired.join(", ") + " fired" : "no reflection fired (already on the near side of all four)"}`;
      const parts = [];
      if (I.poly) parts.push(`polyfold: angle ${fmt(I.poly.a0 / DEG, 1)}° → ${fmt(I.poly.a / DEG, 1)}° (sector ${fmt(S.P.sector / DEG, 1)}°)`);
      parts.push(`abs: ${AX4.filter((_, a) => I.neg[a]).join(", ") || "nothing"} negated`);
      parts.push(`sort: ${I.swaps.length ? I.swaps.join(", ") : "already x ≥ y ≥ z"}`);
      return parts.join(" · ");
    }

    // ---- readouts on the right
    const RX = 660;
    const head = api.text(RX, 112, "", "ink", { style: caps });
    const lines = [];
    for (let i = 0; i < 8; i++) lines.push(api.text(RX, 140 + i * 21, "", "mono"));
    // components against the base cell ±1
    const CB = 356, CMAX = 3, cx_ = v => RX + 260 + clamp(v / CMAX, -1, 1) * 260;
    api.text(RX, CB - 14, "components against the base cell [−1, 1]⁴ (the coordinate fold's distance box)", "ink", { style: caps });
    const cBand = [], cMark = [], cVal = [];
    AX4.forEach((a, i) => {
      const y = CB + i * 22;
      api.text(RX - 16, y + 4, a, "mono", { "text-anchor": "end" });
      api.el("line", { x1: RX, y1: y, x2: RX + 520, y2: y, style: "stroke:var(--hairline);stroke-width:6;stroke-linecap:round" });
      cBand.push(api.el("line", { y1: y, y2: y, x1: cx_(-1), x2: cx_(1), style: `stroke:${C.fold};stroke-width:6;opacity:.45` }));
      cMark.push(api.el("circle", { cy: y, r: 5.5, style: "fill:var(--ink)" }));
      cVal.push(api.text(RX + 536, y + 4, "", "mono", { style: small }));
    });
    api.el("line", { x1: RX + 260, y1: CB - 8, x2: RX + 260, y2: CB + 74, style: "stroke:var(--muted);stroke-width:1" });
    // |p| against the bailout, log scale
    const GZ = 480, GW = 520, gx = v => RX + clamp((Math.log10(Math.max(v, 1e-3)) + 3) / 6, 0, 1) * GW;
    api.text(RX, GZ - 12, "|p| on a log scale, against the bailout |p| = 1000", "ink", { style: caps });
    api.el("line", { x1: RX, y1: GZ + 10, x2: RX + GW, y2: GZ + 10, style: "stroke:var(--hairline);stroke-width:8;stroke-linecap:round" });
    api.el("line", { x1: gx(1000), y1: GZ, x2: gx(1000), y2: GZ + 20, style: `stroke:${C.scale};stroke-width:2.4` });
    api.text(gx(1000), GZ + 34, "bailout", "", { "text-anchor": "middle", style: `${small};fill:${C.scale}` });
    for (const t of [0.001, 0.01, 0.1, 1, 10, 100, 1000]) api.text(gx(t), GZ - 2, String(t), "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
    const gMark = api.el("circle", { cy: GZ + 10, r: 7, style: "fill:var(--ink)" });
    const gNote = api.text(RX + GW + 16, GZ + 14, "", "mono", { style: small });
    // per-iteration table
    const TY = 560;
    api.text(RX, TY, "iteration", "ink", { style: caps });
    ["|p| after", "fold detail", "n", "d · s⁻ⁿ"].forEach((h, i) => api.text(RX + [90, 190, 440, 500][i], TY, h, "ink", { style: caps }));
    const trows = [];
    for (let r = 0; r < 8; r++) trows.push([0, 90, 190, 440, 500].map(dx => api.text(RX + dx, TY + 22 + r * 19, "", "mono", { style: small })));

    function recompute() { orbit = kifsStages(S.p[0], S.p[1], S.p[2], S.P, ITERS); }
    function render() {
      const k = S.k, st = orbit[k], last = LAST();
      stages.set(k === last && st.kind === "scale" && (st.bail || st.n === ITERS) ? 5 : k === 0 ? -1 : STAGE_IDX[st.kind]);
      stages.dim(0, !S.P.r1On); stages.dim(2, !S.P.r2On); stages.dim(3, S.P.twist === 0);
      for (let j = 1; j <= MAXK; j++) {
        const on = j <= k && j <= last, seg = segs[j - 1];
        seg.style.display = on ? "" : "none";
        if (on) {
          const a = planeProj(S.pl, orbit[j - 1].z), b = planeProj(S.pl, orbit[j].z);
          seg.setAttribute("x1", sx(a[0])); seg.setAttribute("y1", sy(a[1]));
          seg.setAttribute("x2", sx(b[0])); seg.setAttribute("y2", sy(b[1]));
          seg.style.stroke = C[orbit[j].kind];
          seg.style.opacity = j === k ? 1 : 0.55;
        }
      }
      for (let j = 0; j <= MAXK; j++) {
        const on = j <= k && j <= last, d = dots[j];
        d.style.display = on ? "" : "none";
        if (on) { const q = planeProj(S.pl, orbit[j].z); d.setAttribute("cx", sx(q[0])); d.setAttribute("cy", sy(q[1])); d.style.fill = C[orbit[j].kind]; }
      }
      const cq = planeProj(S.pl, st.z);
      curRing.setAttribute("cx", sx(cq[0])); curRing.setAttribute("cy", sy(cq[1]));
      // readouts
      head.textContent = k === 0 ? "the start: p = (x, y, z, w), n = 0" : `iteration ${st.it + 1} of ${ITERS} · ${STAGE_NAMES[st.kind]}`;
      const pl = len4(st.z), D = kifsDe(S.p[0], S.p[1], S.p[2], 32, S.P), fx = fixture();
      const r1 = S.P.rot1.map((r, i) => (r ? `${PLANE_NAMES[i]} ${fmt(r, 1)}°` : "")).filter(Boolean).join(", ");
      const r2 = S.P.rot2.map((r, i) => (r ? `${PLANE_NAMES[i]} ${fmt(r, 1)}°` : "")).filter(Boolean).join(", ");
      const L = [
        `p₀ = ${vec(S.p, 3)}  w = ${fmt(S.P.w, 2)}   ${FOLD_NAMES[S.P.fold]} fold, s = ${fmt(S.P.scale, 2)}, offset ${vec(S.P.offset, 2)}`,
        `p = ${vec(st.z)}`,
        `|p| = ${sci(pl)}    n = ${st.n}    s⁻ⁿ = ${sci(Math.pow(S.P.scale, -st.n))}`,
        st.kind === "fold" ? foldLine(st)
          : st.kind === "rot1" ? `R1 turned the six planes (${r1})`
          : st.kind === "rot2" ? `R2 turned the six planes (${r2})`
          : st.kind === "twist" ? `twist: xy turned by ${fmt(st.deg, 2)}° = ${fmt(S.P.twist, 2)}° × ${st.it}`
          : st.kind === "scale" ? `p = ${fmt(S.P.scale, 2)}·p − ${fmt(S.P.scale - 1, 2)}·offset${st.corr ? " ; Menger correction fired" : ""}${st.bail ? " ; BAILOUT" : ""}`
          : `Step ▶ runs ${S.P.r1On ? "R1" : "the fold"} first`,
        `running d(p)·s⁻ⁿ = ${sci(kifsRunning(st, S.P))}   (${S.P.fold === 0 ? "d = box distance to [−1, 1]⁴" : "d = |p|"})`,
        `kifs_de(p, 32) = ${sci(D, 6)}${fx ? `   = the test's ${fx.want} (${fx.name})` : ""}`,
        `kifs_de(p, 16) = ${sci(kifsDe(S.p[0], S.p[1], S.p[2], 16, S.P), 6)}   (coarse_iters at the default view: ${coarseIters(1, S.P.scale, Math.max(kifsDe(DEFAULT_EYE[0], DEFAULT_EYE[1], DEFAULT_EYE[2], 32, S.P), 1e-6))})`,
        pl > 1000 ? "the orbit bailed out: the point is outside, and D is about its distance to the surface" : D < 1e-6 ? "D ≈ 0: the point is in the shape (the orbit never escapes)" : "",
      ];
      L.forEach((s, i) => { lines[i].textContent = s; });
      lines[5].style.fill = fx ? api.hue(3) : "";
      for (let a = 0; a < 4; a++) {
        cMark[a].setAttribute("cx", cx_(st.z[a]));
        cMark[a].style.fill = C[st.kind];
        cVal[a].textContent = `${sci(st.z[a])}${Math.abs(st.z[a]) > 1 ? "  outside the cell" : ""}`;
      }
      cBand.forEach(b => { b.style.display = S.P.fold === 0 ? "" : "none"; });
      gMark.setAttribute("cx", gx(pl)); gMark.style.fill = C[st.kind];
      gNote.textContent = `|p| = ${sci(pl)}`;
      // table: the last 8 finished iterations
      const ends = orbit.filter((o, j) => o.kind === "scale" && j <= k);
      const first = Math.max(0, ends.length - 8);
      for (let r = 0; r < 8; r++) {
        const end = ends[first + r], cells = trows[r];
        if (!end) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const fo = orbit.find(o => o.kind === "fold" && o.it === end.it), I = fo.info;
        const detail = S.P.fold === 1 ? `${I.fired.length} reflection${I.fired.length === 1 ? "" : "s"}` : `${I.swaps.length} swap${I.swaps.length === 1 ? "" : "s"}${I.poly ? `, ∠ ${fmt(I.poly.a / DEG, 0)}°` : ""}${end.corr ? ", z fix" : ""}`;
        const vals = [String(end.it + 1), sci(len4(end.z)), detail, String(end.n), sci(kifsRunning(end, S.P))];
        cells.forEach((c, i) => { c.textContent = vals[i]; });
      }
      axisLbl.textContent = PLANE[S.pl].label(S.h, S.P.w);
    }
    function refreshAll(geoToo) {
      recompute();
      if (geoToo) { ramp.f = deRamp(); heat.restart(); drawGeo(); }
      S.k = Math.min(S.k, LAST());
      render();
    }

    // ---- input: click the plane to pick p
    heat.surf.img.style.cursor = "crosshair";
    heat.surf.img.addEventListener("click", e => {
      const q = api.local(e);
      const a = +(-RW + (q.x - GX) / VS * 2 * RW).toFixed(3), b = +(RW - (q.y - GY) / VS * 2 * RW).toFixed(3);
      S.p = planePoint(S.pl, a, b, S.h);
      S.k = 0; refreshAll(false);
    });

    // ---- controls
    const BY = 756;
    let bx = GX, by = BY;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: by, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, by + 17, "Orbit", "ink"); bx += 48;
    btn("◀ Back", 74, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn("Step ▶", 74, () => { S.k = Math.min(LAST(), S.k + 1); render(); });
    btn("+1 iteration", 100, () => { const n = orbit.findIndex((o, j) => j > S.k && o.kind === "scale"); S.k = n < 0 ? LAST() : n; render(); });
    btn("All 32 ▶▶", 90, () => { S.k = LAST(); render(); });
    btn("Reset", 66, () => { S.k = 0; render(); });
    bx += 20;
    api.text(bx, by + 17, "Presets", "ink"); bx += 62;
    const preset = (o, p) => { S.P = kifsParams(o); if (p) { S.p = p; S.h = S.pl === "xy" ? p[2] : p[1]; } S.k = LAST(); syncSliders(); refreshAll(true); };
    btn("Menger sponge", 118, () => preset({}, [1.2, -0.3, 0.8]));
    btn("Sierpinski (diagonal, s 2)", 190, () => preset({ fold: 1, scale: 2 }, [1.2, -0.3, 0.8]));
    btn("Polyfold k 5 (s 2)", 136, () => preset({ fold: 2, scale: 2 }, [1.2, -0.3, 0.8]));
    btn("Rotated fixture", 124, () => preset({ rot1: [20, 0, 0, 0, 0, 0], rot2: [0, 0, 0, 10, 0, 0], twist: 5, w: 0.1, offset: [1, 1, 1, 0.5] }, [1.2, -0.3, 0.8]));
    bx = GX; by = BY + 40;
    api.text(bx, by + 17, "Fold set", "ink"); bx += 62;
    const setP = o => { S.P = withK(S.P, o); syncSliders(); refreshAll(true); };
    const foldBtns = FOLD_NAMES.map((nm, i) => btn(nm, 96, () => setP({ fold: i })));
    bx += 20;
    api.text(bx, by + 17, "Plane", "ink"); bx += 48;
    const plBtns = [btn("x-y at z = h", 104, () => { S.pl = "xy"; S.p = planePoint("xy", S.p[0], S.p[1], S.h); syncToggles(); refreshAll(true); }),
      btn("x-z at y = h", 104, () => { S.pl = "xz"; S.p = planePoint("xz", S.p[0], S.p[2], S.h); syncToggles(); refreshAll(true); })];
    const sliders = [];
    const SL = [
      ["Scale (kifs_scale)", "scale", 1.05, 4, 0.01], ["Polyfold k", "poly_k", 2, 12, 1], ["Twist (°/iteration)", "twist", -45, 45, 0.1],
      ["plane height h", "h", -2, 2, 0.05], ["W (the 4th coordinate)", "w", -4, 4, 0.01],
      ["Offset x", "o0", -3, 3, 0.01], ["Offset y", "o1", -3, 3, 0.01], ["Offset z", "o2", -3, 3, 0.01], ["Offset w", "o3", -3, 3, 0.01],
      ["R1 xy (°)", "a0", -180, 180, 0.5], ["R1 xz (°)", "a1", -180, 180, 0.5], ["R1 xw (°)", "a2", -180, 180, 0.5],
      ["R2 xy (°)", "b0", -180, 180, 0.5], ["R2 yz (°)", "b3", -180, 180, 0.5], ["R2 zw (°)", "b5", -180, 180, 0.5],
    ];
    const getV = key => (key === "h" ? S.h : key[0] === "o" ? S.P.offset[+key[1]] : key[0] === "a" ? S.P.rot1[+key[1]] : key[0] === "b" ? S.P.rot2[+key[1]] : S.P[key]);
    SL.forEach(([label, key, min, max, step], i) => {
      const h = api.slider({ x: GX + (i % 5) * 300, y: BY + 110 + Math.floor(i / 5) * 62, w: 260, label, min, max, step, value: getV(key), fmt: v => fmt(v, step >= 1 ? 0 : step >= 0.5 ? 1 : 2),
        onChange: v => {
          if (key === "h") { S.h = v; S.p = planePoint(S.pl, ...planeProj(S.pl, S.p), S.h); }
          else if (key[0] === "o") { const o = S.P.offset.slice(); o[+key[1]] = v; S.P = withK(S.P, { offset: o }); }
          else if (key[0] === "a") { const r = S.P.rot1.slice(); r[+key[1]] = v; S.P = withK(S.P, { rot1: r }); }
          else if (key[0] === "b") { const r = S.P.rot2.slice(); r[+key[1]] = v; S.P = withK(S.P, { rot2: r }); }
          else S.P = withK(S.P, { [key]: v });
          syncToggles();
          refreshAll(true);
        } });
      sliders.push([key, h]);
    });
    function syncToggles() { foldBtns.forEach((b, i) => b.set(S.P.fold === i)); plBtns[0].set(S.pl === "xy"); plBtns[1].set(S.pl === "xz"); }
    function syncSliders() { for (const [key, h] of sliders) h.set(getV(key)); syncToggles(); }
    api.text(GX, BY + 300, "Legend: orange dashed square = the base cell ±1 (the Coordinate fold's distance box; the Menger sponge's faces sit on it) · grey dotted square = the march's cube (bound_half, when inside the view) · blue ring = the offset, the fixed point of the scale · orange dotted rays = the polyfold's wedge edges, or the diagonal fold's mirror x = −y · trail colours = the stage that moved p.", "muted", { style: small });
    api.text(GX, BY + 318, "Hover any dot for its numbers. With a preset's knobs (or the defaults) and the point (1.2, −0.3, 0.8), kifs_de(p, 32) turns green with the test's value. The sponge's first-level holes (the centre, the tunnel along z) read D > 0.3; a corner cell like (0.5, 0.5, 0.5) reads D ≈ 0.", "muted", { style: small });
    api.link(GX, BY + 338, RL("kifsDe", 10, "the two changes from Fractacular's kifs.gdshader"));
    api.link(GX + 400, BY + 338, RL("tKifs", 28, "the Menger facts the defaults must honour"));
    refreshAll(true);
  },
};

// ================================================================== 3. the Kleinian, fold by fold
const klFig = {
  type: "figure",
  tab: "Kleinian fold by fold",
  title: "The pseudo-Kleinian, fold by fold: a port of kleinian_de",
  note: "A port of `kleinian_de` (equal to KleinianEstimator.estimate_at), stage by stage. Knighty's pseudo-Kleinian in 4D: each iteration folds every component back inside its own box (clamp(p, −b, b)·2 − p, the box fold with a half-width per axis), then pushes a point inside the inversion sphere of radius r out through it (m = max(r²/|p|², 1): an inversion, but never pulling an outside point in), adds the shift, and multiplies the running scale dr by m. The loop stops early once a step leaves p unchanged: a point outside the box and the sphere, with no shift, has settled. The estimate is Knighty's thingy at the end point, the distance to the thickened sheets |r_xy·z| = thickness whose images under the folds make the limit set, halved because that field is steeper than 1, divided by dr. Click the plane to pick a point; the x-z plane shows the rings best. The background is the estimate on the plane (blue at the surface); the Kleinian's rays stop at the View distance (tab 5), which this figure does not draw.",
  w: 1560, h: 1060,
  draw(api) {
    const GX = 20, GY = 96, VS = 600, RW = 2.0, RES = 120;
    const S = { P: klParams(), p: [1.2, 0, 0.8], h: 0, pl: "xz", k: 0 };
    const ITERS = 32;
    const sx = x => GX + (x + RW) / (2 * RW) * VS, sy = y => GY + (RW - y) / (2 * RW) * VS;
    const C = { start: api.hue(3), box: api.hue(2), inv: api.hue(5) };
    const STAGE_IDX = { box: 0, inv: 1 };
    const STAGE_NAMES = { start: "start", box: "after the box fold", inv: "after the inversion and shift" };
    let orbit = [];
    const LAST = () => orbit.length - 1;
    const fixture = () => KL_FIX.find(f => samePt(f.p, S.p) && sameL(f.P, S.P));

    const stages = stageRow(api, 20, 16, 300, 12, [
      { n: "1", name: "Box fold", f: "p = clamp(p, −b, b)·2 − p", color: C.box,
        tip: { ...KL(25), blurb: "Each component past its own half-width b_c (kleinian_box_0..3, Knighty's 0.92436, 0.90756, 0.92436, 0.92436) is reflected back inside: x = 1.3 with b = 0.92436 becomes 0.549. A component inside does not move. The same rule as the Mandelbox's box fold, with a half-width per axis. This is what tiles space with the cells of the lattice.", links: [RL("klDe", 25, "GDScript"), RL("klShape", 19, "the Box rows")] } },
      { n: "2", name: "Inversion, shift, dr", f: "m = max(r²/|p|², 1); p = p·m + shift", color: C.inv,
        tip: { ...KL(26), blurb: "k = radius². A point inside the inversion sphere (|p|² < k) is scaled by m = k / |p|², which is the inversion in that sphere: it lands outside, at distance k / |p|. A point outside gets m = 1 and is left alone (the cap; an uncapped inversion shrinks every far point differently and turns the estimate to noise). Then the shift is added to every component and dr is multiplied by m, the running magnification. If the step left p exactly as it was, the loop stops.", links: [RL("kl", 27, "p·m + shift"), RL("kl", 28, "dr"), RL("kl", 29, "the early exit"), RL("klDe", 28, "GDScript: m"), RL("klDe", 32, "GDScript: the early exit")] } },
      { n: "D", name: "The estimate: the thingy", f: "|0.5·(|r_xy·z| − T) / √(|p|² + |T|)| / dr", color: "var(--ink)",
        tip: { ...KL(31), blurb: "r_xy = |p.xy|, T = thickness. |r_xy·z| = T is a pair of thickened sheets around the z axis and the xy plane; the folds and inversions copy them everywhere, and the limit set is what the copies keep returning to. The thingy's own field is steeper than a true distance, so it is halved; dividing by dr undoes the magnification the inversions applied along the way. Unsigned, so the estimate is 0 on the sheets and positive either side.", links: [RL("klDe", 38, "GDScript: thingy"), RL("klDe", 3, "the header's explanation"), RL("tKl", 21, "the fixtures")] } },
    ]);

    const ramp = { f: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VS, h: VS, pw: RES, ph: RES }, (i, j) => {
      const a = -RW + (i + 0.5) / RES * 2 * RW, b = RW - (j + 0.5) / RES * 2 * RW, q = planePoint(S.pl, a, b, S.h);
      return ramp.f(klDe(q[0], q[1], q[2], 32, S.P), 0.45);
    });
    const clipId = "kl-fold-clip";
    api.el("rect", { x: GX, y: GY, width: VS, height: VS }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const geo = api.el("g", { "clip-path": `url(#${clipId})`, style: noPtr });
    const trailG = api.el("g", { "clip-path": `url(#${clipId})` });
    api.el("rect", { x: GX, y: GY, width: VS, height: VS, style: "fill:none;stroke:var(--muted);stroke-width:1.2;pointer-events:none" });
    for (const t of [-2, -1, 0, 1, 2]) {
      api.text(sx(t), GY + VS + 14, String(t), "muted", { "text-anchor": "middle", style: small });
      api.text(GX - 4, sy(t) + 4, String(t), "muted", { "text-anchor": "end", style: small });
    }
    const axisLbl = api.text(GX + VS, GY + VS + 30, "", "muted", { "text-anchor": "end", style: small });
    function drawGeo() {
      while (geo.firstChild) geo.removeChild(geo.firstChild);
      api.el("line", { x1: sx(-RW), y1: sy(0), x2: sx(RW), y2: sy(0), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      api.el("line", { x1: sx(0), y1: sy(-RW), x2: sx(0), y2: sy(RW), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      const [ia, ib] = PLANE[S.pl].axes, ba = S.P.box[ia], bb = S.P.box[ib];
      api.el("rect", { x: sx(-ba), y: sy(bb), width: sx(ba) - sx(-ba), height: sy(-bb) - sy(bb), style: `fill:none;stroke:${C.box};stroke-width:1.6;stroke-dasharray:7 4` }, geo);
      api.el("circle", { cx: sx(0), cy: sy(0), r: S.P.radius * VS / (2 * RW), style: `fill:none;stroke:${C.inv};stroke-width:1.6` }, geo);
      const shq = planeProj(S.pl, S.P.shift);
      if (shq[0] || shq[1]) api.arrow(sx(0), sy(0), sx(shq[0]), sy(shq[1]), C.inv, 1.4, geo);
    }
    const MAXK = ITERS * 2;
    const segs = [], dots = [];
    for (let k = 1; k <= MAXK; k++) segs.push(api.el("line", { style: `stroke-width:1.8;${noPtr}` }, trailG));
    const DOT_REFS = { start: KL(17), box: KL(25), inv: KL(26) };
    for (let k = 0; k <= MAXK; k++) {
      const c = api.el("circle", { r: k === 0 ? 6 : 3.4, style: "cursor:pointer" }, trailG);
      dots.push(c);
      api.tip(c, { title: "a state of the orbit", ...KL(22), live() {
        const st = orbit[k];
        if (!st) return {};
        const lines = [`\`p\` = ${vec(st.z)}`, `|p| = ${sci(len4(st.z))}`, `\`dr\` = ${sci(st.dr)}`];
        if (st.kind === "box") lines.push(`folded: ${st.folded.join(", ") || "nothing (inside the box)"}`);
        if (st.kind === "inv") lines.push(`|p|² = ${sci(st.r2)} → m = ${sci(st.m)} (${st.m > 1 ? "inside the sphere: pushed out" : "outside: left alone"})${st.settled ? " · SETTLED: p == before, the loop stops" : ""}`);
        lines.push(`thingy(p) / dr here = ${sci(thingy(st.z, S.P.thickness) / st.dr)}`);
        return { title: k === 0 ? "p, the start of the orbit" : `iteration ${st.it + 1}, ${STAGE_NAMES[st.kind]}`, sub: `state ${k} of ${LAST()}`, ...DOT_REFS[st.kind], blurb: lines.join("\n") };
      } });
    }
    const curRing = api.el("circle", { r: 9, style: `fill:none;stroke:var(--ink);stroke-width:2;${noPtr}` }, trailG);

    const RX = 660;
    const head = api.text(RX, 112, "", "ink", { style: caps });
    const lines = [];
    for (let i = 0; i < 8; i++) lines.push(api.text(RX, 140 + i * 21, "", "mono"));
    // components against their own box
    const CB = 356, CMAX = 2, cx_ = v => RX + 260 + clamp(v / CMAX, -1, 1) * 260;
    api.text(RX, CB - 14, "components against the fold box ±b (one half-width per axis)", "ink", { style: caps });
    const cBand = [], cMark = [], cVal = [];
    AX4.forEach((a, i) => {
      const y = CB + i * 22;
      api.text(RX - 16, y + 4, a, "mono", { "text-anchor": "end" });
      api.el("line", { x1: RX, y1: y, x2: RX + 520, y2: y, style: "stroke:var(--hairline);stroke-width:6;stroke-linecap:round" });
      cBand.push(api.el("line", { y1: y, y2: y, style: `stroke:${C.box};stroke-width:6;opacity:.45` }));
      cMark.push(api.el("circle", { cy: y, r: 5.5, style: "fill:var(--ink)" }));
      cVal.push(api.text(RX + 536, y + 4, "", "mono", { style: small }));
    });
    api.el("line", { x1: RX + 260, y1: CB - 8, x2: RX + 260, y2: CB + 74, style: "stroke:var(--muted);stroke-width:1" });
    // |p| against the inversion sphere
    const GZ = 480, GW = 520, ZMAX = 2.5, gx = v => RX + clamp(v / ZMAX, 0, 1) * GW;
    api.text(RX, GZ - 12, "|p| (4D) against the inversion sphere", "ink", { style: caps });
    api.el("line", { x1: RX, y1: GZ + 10, x2: RX + GW, y2: GZ + 10, style: "stroke:var(--hairline);stroke-width:8;stroke-linecap:round" });
    const gR = api.el("line", { y1: GZ, y2: GZ + 20, style: `stroke:${C.inv};stroke-width:2.4` });
    const gRT = api.text(0, GZ + 34, "", "", { "text-anchor": "middle", style: `${small};fill:${C.inv}` });
    for (const t of [0, 0.5, 1, 1.5, 2, 2.5]) api.text(gx(t), GZ - 2, String(t), "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
    const gMark = api.el("circle", { cy: GZ + 10, r: 7, style: "fill:var(--ink)" });
    const gNote = api.text(RX + GW + 16, GZ + 14, "", "mono", { style: small });
    const TY = 560;
    api.text(RX, TY, "iteration", "ink", { style: caps });
    ["|p| after", "folded", "m", "dr", "thingy / dr"].forEach((h, i) => api.text(RX + [90, 190, 300, 400, 500][i], TY, h, "ink", { style: caps }));
    const trows = [];
    for (let r = 0; r < 8; r++) trows.push([0, 90, 190, 300, 400, 500].map(dx => api.text(RX + dx, TY + 22 + r * 19, "", "mono", { style: small })));

    function recompute() { orbit = klStages(S.p[0], S.p[1], S.p[2], S.P, ITERS); }
    function render() {
      const k = S.k, st = orbit[k], last = LAST();
      stages.set(k === last && k > 0 ? 2 : k === 0 ? -1 : STAGE_IDX[st.kind]);
      for (let j = 1; j <= MAXK; j++) {
        const on = j <= k && j <= last, seg = segs[j - 1];
        seg.style.display = on ? "" : "none";
        if (on) {
          const a = planeProj(S.pl, orbit[j - 1].z), b = planeProj(S.pl, orbit[j].z);
          seg.setAttribute("x1", sx(a[0])); seg.setAttribute("y1", sy(a[1]));
          seg.setAttribute("x2", sx(b[0])); seg.setAttribute("y2", sy(b[1]));
          seg.style.stroke = C[orbit[j].kind];
          seg.style.opacity = j === k ? 1 : 0.55;
        }
      }
      for (let j = 0; j <= MAXK; j++) {
        const on = j <= k && j <= last, d = dots[j];
        d.style.display = on ? "" : "none";
        if (on) { const q = planeProj(S.pl, orbit[j].z); d.setAttribute("cx", sx(q[0])); d.setAttribute("cy", sy(q[1])); d.style.fill = C[orbit[j].kind]; }
      }
      const cq = planeProj(S.pl, st.z);
      curRing.setAttribute("cx", sx(cq[0])); curRing.setAttribute("cy", sy(cq[1]));
      head.textContent = k === 0 ? "the start: p = (x, y, z, w), dr = 1" : `iteration ${st.it + 1} of ${ITERS} · ${STAGE_NAMES[st.kind]}`;
      const pl = len4(st.z), D = klDe(S.p[0], S.p[1], S.p[2], 32, S.P), fx = fixture();
      const lastSt = orbit[last];
      const L = [
        `p₀ = ${vec(S.p, 3)}  w = ${fmt(S.P.w, 2)}   box ${vec(S.P.box, 3)}  r = ${fmt(S.P.radius, 3)}  shift ${vec(S.P.shift, 2)}  T = ${fmt(S.P.thickness, 3)}`,
        `p = ${vec(st.z)}`,
        `|p| = ${sci(pl)}    dr = ${sci(st.dr)}`,
        st.kind === "box" ? `box fold: ${st.folded.length ? st.folded.join(", ") + " reflected back inside" : "no component outside its box"}`
          : st.kind === "inv" ? `|p|² = ${sci(st.r2)} ${st.m > 1 ? `< r² = ${sci(S.P.k)}: m = ${sci(st.m)}, pushed out through the sphere` : `≥ r² = ${sci(S.P.k)}: m = 1, left alone`}; + shift; dr ·= m${st.settled ? " ; p == before: SETTLED, the loop stops" : ""}`
          : "Step ▶ runs the box fold first",
        `thingy(p) = ${sci(thingy(st.z, S.P.thickness))}   thingy / dr = ${sci(thingy(st.z, S.P.thickness) / st.dr)}`,
        `kleinian_de(p, 32) = ${sci(D, 6)}${fx ? `   = the test's ${fx.want} (${fx.name})` : ""}`,
        `the loop ran ${lastSt.it + 1} iteration${lastSt.it ? "s" : ""}${lastSt.settled ? " and settled" : " to the full 32"}   (coarse_iters is always 32 on the Kleinian)`,
        D < 1e-6 ? "D ≈ 0: the point is on the set (a sheet of the lattice)" : "",
      ];
      L.forEach((s, i) => { lines[i].textContent = s; });
      lines[5].style.fill = fx ? api.hue(3) : "";
      for (let a = 0; a < 4; a++) {
        const b = S.P.box[a];
        cBand[a].setAttribute("x1", cx_(-b)); cBand[a].setAttribute("x2", cx_(b));
        cMark[a].setAttribute("cx", cx_(st.z[a]));
        cMark[a].style.fill = C[st.kind];
        cVal[a].textContent = `${sci(st.z[a])}${Math.abs(st.z[a]) > b ? "  past the fold" : ""}`;
      }
      gR.setAttribute("x1", gx(S.P.radius)); gR.setAttribute("x2", gx(S.P.radius));
      gRT.setAttribute("x", gx(S.P.radius)); gRT.textContent = `radius ${fmt(S.P.radius, 2)}`;
      gMark.setAttribute("cx", gx(pl)); gMark.style.fill = C[st.kind];
      gNote.textContent = `|p| = ${sci(pl)}${pl > ZMAX ? " (off the gauge)" : ""}`;
      const ends = orbit.filter((o, j) => o.kind === "inv" && j <= k);
      const first = Math.max(0, ends.length - 8);
      for (let r = 0; r < 8; r++) {
        const end = ends[first + r], cells = trows[r];
        if (!end) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const bx = orbit.find(o => o.kind === "box" && o.it === end.it);
        const vals = [String(end.it + 1), sci(len4(end.z)), bx.folded.join("") || "—", sci(end.m), sci(end.dr), sci(thingy(end.z, S.P.thickness) / end.dr)];
        cells.forEach((c, i) => { c.textContent = vals[i]; });
      }
      axisLbl.textContent = PLANE[S.pl].label(S.h, S.P.w);
    }
    function refreshAll(geoToo) {
      recompute();
      if (geoToo) { ramp.f = deRamp(); heat.restart(); drawGeo(); }
      S.k = Math.min(S.k, LAST());
      render();
    }
    heat.surf.img.style.cursor = "crosshair";
    heat.surf.img.addEventListener("click", e => {
      const q = api.local(e);
      const a = +(-RW + (q.x - GX) / VS * 2 * RW).toFixed(3), b = +(RW - (q.y - GY) / VS * 2 * RW).toFixed(3);
      S.p = planePoint(S.pl, a, b, S.h);
      S.k = 0; refreshAll(false);
    });

    const BY = 756;
    let bx = GX, by = BY;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: by, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, by + 17, "Orbit", "ink"); bx += 48;
    btn("◀ Back", 74, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn("Step ▶", 74, () => { S.k = Math.min(LAST(), S.k + 1); render(); });
    btn("+1 iteration", 100, () => { const n = orbit.findIndex((o, j) => j > S.k && o.kind === "inv"); S.k = n < 0 ? LAST() : n; render(); });
    btn("All ▶▶", 70, () => { S.k = LAST(); render(); });
    btn("Reset", 66, () => { S.k = 0; render(); });
    bx += 20;
    api.text(bx, by + 17, "Presets", "ink"); bx += 62;
    const preset = (o, p, pl) => { S.P = klParams(o); if (p) S.p = p; if (pl) { S.pl = pl; S.h = pl === "xy" ? S.p[2] : S.p[1]; } S.k = LAST(); syncSliders(); refreshAll(true); };
    btn("Knighty's defaults, fixture (1.2, −0.3, 0.8)", 300, () => preset({}, [1.2, -0.3, 0.8], "xz"));
    btn("Shifted fixture", 124, () => preset({ shift: [0.1, 0, 0, 0], radius: 1.2, w: 0.2 }, [1.2, -0.3, 0.8], "xz"));
    bx += 20;
    api.text(bx, by + 17, "Plane", "ink"); bx += 48;
    const plBtns = [btn("x-y at z = h", 104, () => { S.pl = "xy"; S.p = planePoint("xy", S.p[0], S.p[1], S.h); syncToggles(); refreshAll(true); }),
      btn("x-z at y = h", 104, () => { S.pl = "xz"; S.p = planePoint("xz", S.p[0], S.p[2], S.h); syncToggles(); refreshAll(true); })];
    const sliders = [];
    const SL = [
      ["Box x", "k0", 0.1, 2, 0.001], ["Box y", "k1", 0.1, 2, 0.001], ["Box z", "k2", 0.1, 2, 0.001], ["Box w", "k3", 0.1, 2, 0.001], ["Inversion radius", "radius", 0.1, 2, 0.001],
      ["Shift x", "s0", -1, 1, 0.001], ["Shift y", "s1", -1, 1, 0.001], ["Shift z", "s2", -1, 1, 0.001], ["Shift w", "s3", -1, 1, 0.001], ["Thickness", "thickness", 0, 0.2, 0.001],
      ["plane height h", "h", -2, 2, 0.05], ["W (the 4th coordinate)", "w", -4, 4, 0.01],
    ];
    const getV = key => (key === "h" ? S.h : key[0] === "k" ? S.P.box[+key[1]] : key[0] === "s" ? S.P.shift[+key[1]] : S.P[key]);
    SL.forEach(([label, key, min, max, step], i) => {
      const h = api.slider({ x: GX + (i % 5) * 300, y: BY + 70 + Math.floor(i / 5) * 62, w: 260, label, min, max, step, value: getV(key), fmt: v => fmt(v, 3),
        onChange: v => {
          if (key === "h") { S.h = v; S.p = planePoint(S.pl, ...planeProj(S.pl, S.p), S.h); }
          else if (key[0] === "k") { const b = S.P.box.slice(); b[+key[1]] = v; S.P = withL(S.P, { box: b }); }
          else if (key[0] === "s") { const s = S.P.shift.slice(); s[+key[1]] = v; S.P = withL(S.P, { shift: s }); }
          else S.P = withL(S.P, { [key]: v });
          refreshAll(true);
        } });
      sliders.push([key, h]);
    });
    function syncToggles() { plBtns[0].set(S.pl === "xy"); plBtns[1].set(S.pl === "xz"); }
    function syncSliders() { for (const [key, h] of sliders) h.set(getV(key)); syncToggles(); }
    api.text(GX, BY + 236, "Legend: orange dashed rectangle = the fold box ±b on this plane · pink circle = the inversion sphere's equator · pink arrow = the shift · trail colours = the stage that moved p (orange: the box fold, pink: inversion and shift).", "muted", { style: small });
    api.text(GX, BY + 254, "Hover any dot for its numbers. With the defaults or the shifted preset and the point (1.2, −0.3, 0.8), kleinian_de(p, 32) turns green with the test's value. At the defaults D(p) = D(−p): the box fold mirrors and nothing shifts.", "muted", { style: small });
    api.link(GX, BY + 274, RL("klDe", 3, "the header: why the thingy, and why half of it"));
    api.link(GX + 400, BY + 274, RL("tKl", 28, "D(p) = D(−p), tested"));
    refreshAll(true);
  },
};

// ================================================================== 4. every knob
const KNOBS = [
  { id: "shape", label: "Fractal", def: "Mandelbox", range: "Mandelbox · KIFS · Kleinian · Mandelbulb", group: "Fractal", ...R("cat", 77),
    tip: "Which fractal is drawn. Each has its own rows below; only the chosen one's are shown.",
    effects: "Mandelbox is the site's box-and-sphere-fold solid. KIFS is the kaleidoscopic family: the Menger sponge, the Sierpinski tetrahedron and their rotated, twisted relatives. Kleinian is a pseudo-Kleinian limit set, an endless lattice of curved sheets and rings whose rays stop at its View distance. Mandelbulb is the 3D cousin of the Mandelbrot set: a lobed, budding ball about 2.2 across. The camera stays put, so fly out (or Reset camera) to frame the new shape." },
  { id: "w", label: "W", def: "0", range: "−4 … 4", group: "Fractal", ...R("cat", 87),
    tip: "The fourth coordinate of the sample point. Every shape but the Mandelbulb is a 4D field; the viewer flies through the w = 0 slice by default. Hidden on the Mandelbulb, which is 3D.",
    effects: "0 is the familiar 3D shape. Moving w slides the whole view to a different 3D slice of the 4D shape, which can reveal entirely new structure. Bind it to an axis or Time to glide between slices." },
  { id: "kifs_scale", label: "Scale", def: "3", range: "1.05 … 4 (hard 1.01 … 6)", group: "KIFS", ...R("kifsShape", 26),
    tip: "The scale s every iteration multiplies by, away from the offset: p = s·p − (s − 1)·offset.",
    effects: "3 with the Coordinate fold is the Menger sponge; 2 with the Diagonal fold is the Sierpinski tetrahedron. Lower values overlap the copies into a dense, blobby solid; higher values thin them to dust. It stops above 1, where there is no fractal." },
  { id: "kifs_fold", label: "Fold set", def: "Coordinate", range: "Coordinate · Diagonal · Polyfold", group: "KIFS", ...R("kifsShape", 33),
    tip: "The fold every iteration applies, which sets the shape's symmetry.",
    effects: "Coordinate folds into the positive corner and sorts x >= y >= z: cube symmetry, the Menger sponge. Diagonal reflects across x = −y, x = −z, y = −z (and x = −w): tetrahedral symmetry, the Sierpinski tetrahedron at scale 2. Polyfold mirrors the xy angle into k-fold wedges before the Coordinate fold; it is sparser, so try a scale of 2 to 2.5." },
  { id: "kifs_poly_k", label: "Polyfold k", def: "5", range: "2 … 12, step 1 (hard 2 … 32); Polyfold only", group: "KIFS", ...R("kifsShape", 42),
    tip: "The Polyfold's symmetry: the xy plane is folded into 2k mirror-image wedges. Rounded to a whole number (floor(k + 0.5)); a FLOAT so it can be bound.",
    effects: "3 gives a triangular cross-section, 5 a five-pointed star, high values approach a cylinder. Bound to an axis it steps from one symmetry to the next." },
  { id: "kifs_twist", label: "Twist", def: "0", range: "−45 … 45 ° (hard ±180)", group: "KIFS", ...R("kifsShape", 50),
    tip: "Degrees of extra rotation in the xy plane that grows with the iteration: iteration i turns by twist × i.",
    effects: "0 keeps the copies aligned. A few degrees spirals the fine detail about the z axis while the large shape barely moves; larger values shred it. Any twist makes the shape no longer exactly self-similar." },
  { id: "kifs_offset_0 … 3", label: "Offset x, y, z, w", def: "1, 1, 1, 0", range: "−3 … 3 each (hard ±8)", group: "KIFS", ...R("kifsShape", 59),
    tip: "The components of the offset: the fixed point every iteration scales away from.",
    effects: "(1, 1, 1, 0) is the corner of the unit cube, which makes the Menger sponge and the Sierpinski tetrahedron. Small changes move where the copies sit and reshape everything; the w component lifts the shape off the w = 0 slice. bound_half follows it: max(2, 1.5 |offset|)." },
  { id: "kifs_rot1_xy … zw", label: "R1 xy … zw", def: "0 × 6", range: "−180 … 180 °, wrap", group: "KIFS rotation", ...R("kifsShape", 72),
    tip: "Degrees of rotation in each of the six planes, applied BEFORE the fold in every iteration.",
    effects: "Rotating before the fold changes which part of space each fold sees: the copies turn against each other and the sponge breaks into twisted, asymmetric towers. Small angles go a long way; bind one to Time for a slow churn." },
  { id: "kifs_rot2_xy … zw", label: "R2 xy … zw", def: "0 × 6", range: "−180 … 180 °, wrap", group: "KIFS rotation", ...R("kifsShape", 72),
    tip: "Degrees of rotation in each of the six planes, applied AFTER the fold in every iteration.",
    effects: "Rotating after the fold turns the copies themselves before they are scaled, so the detail spins at every scale at once. 0 keeps the classic shapes." },
  { id: "kleinian_box_0 … 3", label: "Box x, y, z, w", def: "0.92436, 0.90756, 0.92436, 0.92436", range: "0.1 … 2 each (hard 0.01 … 4)", group: "Kleinian", ...R("klShape", 19),
    tip: "Half-width of the fold box along each axis: a component outside ± this is reflected back inside, every iteration.",
    effects: "Knighty's defaults (about 0.92) give the classic lattice of rings. Raising one axis stretches the cells along it; equal values give a cubic lattice; lowering a value packs the structure tighter." },
  { id: "kleinian_radius", label: "Inversion radius", def: "1", range: "0.1 … 2 (hard 0.01 … 4)", group: "Kleinian", ...R("klShape", 26),
    tip: "Radius of the inversion sphere: points inside it are pushed out through it, points outside are left alone.",
    effects: "1 is the default. Larger values invert more of each cell, so the rings fatten and the gaps close; smaller values leave mostly the bare box lattice." },
  { id: "kleinian_shift_0 … 3", label: "Shift x, y, z, w", def: "0 × 4", range: "−1 … 1 each (hard ±4)", group: "Kleinian", ...R("klShape", 35),
    tip: "The component added after the inversion, every iteration.",
    effects: "0 keeps the lattice symmetric. Small shifts slide each generation of rings off the last, so the structure tilts and spirals; the w component moves to a different 3D slice of the 4D set." },
  { id: "kleinian_thickness", label: "Thickness", def: "0.01", range: "0 … 0.2 (hard 0 … 1)", group: "Kleinian", ...R("klShape", 42),
    tip: "How thick the base sheets are before the folds copy them everywhere.",
    effects: "0.01 is Knighty's. Thicker sheets give solid, chunky walls; 0 leaves surfaces a pixel thick, like lace." },
  { id: "kleinian_view_distance", label: "View distance", def: "10", range: "1 … 100, log (hard 0.5 … 1000)", group: "Kleinian", ...R("klShape", 49),
    tip: "How far a ray goes from the camera before it stops. The Kleinian fills space, so without a limit every ray would march on through it.",
    effects: "10 shows a few cells in every direction. The last third fades into the background, a soft horizon. Raising it shows more of the lattice at more cost per frame; lowering it is the cheapest way to speed up a slow view. The slider is logarithmic." },
];
const knobTable = {
  type: "table",
  tab: "Every knob",
  title: "Every KIFS and Kleinian knob: id, default, range, what it does",
  note: "The 33 catalogue rows this pane covers (the Fractal group's two, KifsShape's 20, KleinianShape's 11), with the six-angle and four-component sets collapsed to one row each. The id is the uniform name and the FractalParams field; the tooltip and effects text are what the console shows on hover. Hover a row for its effects and the line that declares it. The Mandelbox's own rows are in the mandelbox and console panes.",
  columns: [{ label: "id", w: 190, mono: true }, { label: "label", w: 120 }, { label: "default", w: 150, mono: true }, { label: "range", w: 220 }, { label: "group", w: 100 }, { label: "what it does", w: 560 }],
  rows: KNOBS.map(k => ({ cells: [k.id, k.label, k.def, k.range, k.group, k.tip],
    tip: { title: `${k.label} (\`${k.id}\`)`, sub: `${k.group} · default ${k.def}`, file: k.file, line: k.line, blurb: `Effects: ${k.effects}`,
      links: k.group === "Fractal" ? [RL("cat", 72, "ShapeCatalogue.specs")] : k.group.startsWith("KIFS") ? [RL("kifsShape", 84, "the group tooltip"), RL("ks", 7, "the uniform")] : [RL("klShape", 60, "the group tooltip"), RL("kl", 5, "the uniform")] } })),
};

// ================================================================== 5. bounds and the horizon
const horizonFig = {
  type: "figure",
  tab: "Bounds and horizon",
  title: "Where a ray starts and stops: bound_half, view_limit, view_fade",
  note: "Every ray marches inside a cube of half-side `box_half` = FractalParams.bound_half(): it starts at the cube's entry and is a miss past its exit. The Mandelbox's cube is ±2 (±20 in Julia mode). The KIFS's is max(2, 1.5·|offset|): its attractor lies within |offset| of the origin, and the margin covers the rotations. The Kleinian fills space, so its cube is a token 1e4 and `view_limit()` ends its rays at kleinian_view_distance from the eye instead; `view_fade(t)` = smoothstep(0.67·vd, vd, t) then mixes every hit in the last third toward the background, so the lattice ends in a soft horizon, not a wall. The CPU marches (the fly camera's centre ray, the orbit click) clamp to the same two numbers. A top-down view of the x-y plane: the eye at the default position, the ray aimed at the origin.",
  w: 1400, h: 740,
  draw(api) {
    const GX = 20, GY = 60, VS = 480, RW = 12;
    const S = { shape: 2, kp: kifsParams(), lp: klParams(), eyeK: 1 };
    const sx = x => GX + (x + RW) / (2 * RW) * VS, sy = y => GY + (RW - y) / (2 * RW) * VS;
    const C = { mb: api.hue(1), kifs: api.hue(2), kl: api.hue(5), eye: api.hue(3) };
    const NAMES = ["Mandelbox", "KIFS", "Kleinian"];
    api.el("rect", { x: GX, y: GY, width: VS, height: VS, style: "fill:none;stroke:var(--muted);stroke-width:1.2" });
    for (const t of [-10, -5, 0, 5, 10]) {
      api.text(sx(t), GY + VS + 14, String(t), "muted", { "text-anchor": "middle", style: small });
      api.text(GX - 4, sy(t) + 4, String(t), "muted", { "text-anchor": "end", style: small });
    }
    api.text(GX, GY - 8, "top-down: the x-y plane, the eye's ray toward the origin", "ink", { style: caps });
    const clipId = "horizon-clip";
    api.el("rect", { x: GX, y: GY, width: VS, height: VS }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const geo = api.el("g", { "clip-path": `url(#${clipId})` });
    // the fade curve on the right
    const FX = 560, FY = 80, FW = 560, FH = 200;
    api.text(FX, FY - 12, "view_fade(t) along the ray", "ink", { style: caps });
    api.el("rect", { x: FX, y: FY, width: FW, height: FH, style: "fill:none;stroke:var(--hairline)" });
    const curveG = api.el("g", {});
    const RX = 560, RY = 330;
    const lines = [];
    for (let i = 0; i < 9; i++) lines.push(api.text(RX, RY + i * 21, "", "mono", { style: small }));

    function draw() {
      while (geo.firstChild) geo.removeChild(geo.firstChild);
      while (curveG.firstChild) curveG.removeChild(curveG.firstChild);
      api.el("line", { x1: sx(-RW), y1: sy(0), x2: sx(RW), y2: sy(0), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      api.el("line", { x1: sx(0), y1: sy(-RW), x2: sx(0), y2: sy(RW), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      const eye = DEFAULT_EYE.map(v => v * S.eyeK), dirv = eye.map(v => -v), dl = Math.hypot(...dirv), dir = dirv.map(v => v / dl);
      const bh = boundHalf(S.shape, S.kp), vd = viewLimit(S.shape, S.lp);
      const col = [C.mb, C.kifs, C.kl][S.shape];
      // the cubes: the two finite ones always drawn faintly, the chosen one in its colour
      const sq = (h, c, w, dash) => api.el("rect", { x: sx(-h), y: sy(h), width: sx(h) - sx(-h), height: sy(-h) - sy(h), style: `fill:none;stroke:${c};stroke-width:${w};${dash ? "stroke-dasharray:4 4" : ""}` }, geo);
      sq(2, C.mb, S.shape === 0 ? 2 : 1, S.shape !== 0);
      sq(boundHalf(1, S.kp), C.kifs, S.shape === 1 ? 2 : 1, S.shape !== 1);
      // the ray, and its stops
      const tb = boxIntersect(eye, dir, bh);
      const tEnter = Math.max(tb[0], 0);
      let tExit = tb[1];
      if (vd > 0) tExit = Math.min(tExit, vd);
      const at = t => [eye[0] + dir[0] * t, eye[1] + dir[1] * t];
      const far = at(Math.min(tExit, 60)), ent = at(tEnter);
      api.el("line", { x1: sx(eye[0]), y1: sy(eye[1]), x2: sx(far[0]), y2: sy(far[1]), style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:2 3" }, geo);
      api.el("line", { x1: sx(ent[0]), y1: sy(ent[1]), x2: sx(far[0]), y2: sy(far[1]), style: `stroke:${col};stroke-width:3` }, geo);
      if (vd > 0) {
        const a = at(0.67 * vd), b = at(vd);
        api.el("line", { x1: sx(a[0]), y1: sy(a[1]), x2: sx(b[0]), y2: sy(b[1]), style: `stroke:${col};stroke-width:9;opacity:.3` }, geo);
        api.el("circle", { cx: sx(b[0]), cy: sy(b[1]), r: 5, style: `fill:${col}` }, geo);
        api.text(sx(b[0]) + 8, sy(b[1]) + 4, "view distance", "", { style: `${small};fill:${col}` }, geo);
      } else {
        api.el("circle", { cx: sx(far[0]), cy: sy(far[1]), r: 5, style: `fill:${col}` }, geo);
        api.text(sx(far[0]) + 8, sy(far[1]) + 4, "cube exit", "", { style: `${small};fill:${col}` }, geo);
      }
      api.el("circle", { cx: sx(ent[0]), cy: sy(ent[1]), r: 4, style: `fill:none;stroke:${col};stroke-width:2` }, geo);
      api.el("circle", { cx: sx(eye[0]), cy: sy(eye[1]), r: 6, style: `fill:${C.eye}` }, geo);
      api.text(sx(eye[0]) + 9, sy(eye[1]) - 6, "eye", "", { style: `${small};fill:${C.eye}` }, geo);
      // the fade curve
      const tMax = vd > 0 ? vd * 1.15 : Math.max(tExit * 1.15, 1);
      const fx = t => FX + t / tMax * FW, fy = v => FY + FH - v * (FH - 20) - 10;
      let d = "";
      for (let i = 0; i <= 200; i++) { const t = i / 200 * tMax; d += `${i ? "L" : "M"} ${fx(t)} ${fy(viewFade(t, vd))} `; }
      api.el("path", { d, style: `fill:none;stroke:${col};stroke-width:2.2` }, curveG);
      if (vd > 0) {
        api.el("line", { x1: fx(0.67 * vd), y1: FY, x2: fx(0.67 * vd), y2: FY + FH, style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3" }, curveG);
        api.text(fx(0.67 * vd), FY + FH + 14, `0.67 vd = ${fmt(0.67 * vd, 2)}`, "muted", { "text-anchor": "middle", style: small }, curveG);
        api.el("line", { x1: fx(vd), y1: FY, x2: fx(vd), y2: FY + FH, style: `stroke:${col};stroke-width:1` }, curveG);
        api.text(fx(vd), FY + FH + 14, `vd = ${fmt(vd, 2)}`, "", { "text-anchor": "middle", style: `${small};fill:${col}` }, curveG);
      } else {
        api.text(FX + FW / 2, FY + FH / 2, "view_limit() = 0: no fade on this shape (rays end at the cube, or in the fog while shedding)", "muted", { "text-anchor": "middle", style: small }, curveG);
      }
      api.text(FX, FY + FH + 14, "0", "muted", { style: small }, curveG);
      api.text(FX + FW, FY + FH + 14, `t = ${fmt(tMax, 1)}`, "muted", { "text-anchor": "end", style: small }, curveG);
      api.text(FX - 4, fy(1) + 4, "1", "muted", { "text-anchor": "end", style: small }, curveG);
      api.text(FX - 4, fy(0) + 4, "0", "muted", { "text-anchor": "end", style: small }, curveG);
      // readouts
      const near = S.shape === 1 ? Math.max(kifsDe(eye[0], eye[1], eye[2], 32, S.kp), 1e-6) : S.shape === 2 ? Math.max(klDe(eye[0], eye[1], eye[2], 32, S.lp), 1e-6) : NaN;
      const L = [
        `${NAMES[S.shape]} · eye ${vec(eye, 2)} (|eye| = ${fmt(Math.hypot(...eye), 2)})`,
        `bound_half() = ${S.shape === 1 ? `max(2, 1.5 × |offset| ${fmt(len4(S.kp.offset), 3)}) = ${fmt(bh, 3)}` : S.shape === 2 ? `KLEINIAN_BOUND = ${bh} (no real cube)` : "2 (20 in Julia mode; more with a hybrid fold: the mandelbox pane)"}`,
        `box_intersect: t_enter = ${fmt(tEnter, 3)}, cube exit = ${tb[1] > 1e3 ? sci(tb[1]) : fmt(tb[1], 3)}`,
        `view_limit() = ${vd > 0 ? fmt(vd, 2) : "0 (none)"}  →  t_exit = min(cube exit, fog, view limit) = ${fmt(tExit, 3)}`,
        vd > 0 ? `view_fade: 0 until t = ${fmt(0.67 * vd, 2)}, then smoothstep to 1 at ${fmt(vd, 2)}; a hit at t = ${fmt(0.8 * vd, 2)} is ${fmt(viewFade(0.8 * vd, vd) * 100, 0)}% background` : "view_fade(t) = 0 everywhere on this shape",
        S.shape === 0 ? "near_dist, coarse_iters: the Mandelbox pane (tab 5 there)" : `near_dist = D(eye) = ${sci(near)}  →  coarse_iters = ${coarseIters(S.shape, S.kp.scale, near)}${S.shape === 2 ? " (always 32 on the Kleinian)" : ` (the Mandelbox's rule on kifs_scale ${fmt(S.kp.scale, 2)})`}`,
        S.shape === 2 ? "the centre ray and the orbit click clamp their march to view_distance() too, so a click on the horizon re-centres nowhere" : S.shape === 1 ? "the centre ray marches in this cube: fly_camera_test holds W at the Menger and the Sierpinski" : "",
        vd > 0 && vd > RW * 2 ? "(the view distance is off the drawing; the curve on the right still shows it)" : "",
      ];
      L.forEach((s, i) => { lines[i].textContent = s; });
    }
    const BY = 590;
    let bx = GX, by = BY;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: by, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, by + 17, "Shape", "ink"); bx += 52;
    const sb = NAMES.map((nm, i) => btn(nm, 96, () => { S.shape = i; sb.forEach((b, j) => b.set(j === i)); draw(); }, i === S.shape));
    bx += 20;
    api.slider({ x: bx, y: by + 12, w: 220, label: "kleinian_view_distance", min: 1, max: 40, step: 0.5, value: S.lp.view_distance, fmt: v => fmt(v, 1),
      onChange: v => { S.lp = withL(S.lp, { view_distance: v }); draw(); } });
    bx += 260;
    api.slider({ x: bx, y: by + 12, w: 220, label: "kifs_offset_0 (x), y and z at 1", min: -3, max: 3, step: 0.01, value: 1, fmt: v => fmt(v, 2),
      onChange: v => { S.kp = withK(S.kp, { offset: [v, 1, 1, 0] }); draw(); } });
    bx += 260;
    api.slider({ x: bx, y: by + 12, w: 220, label: "eye distance ×", min: 0.2, max: 1.5, step: 0.01, value: 1, fmt: v => fmt(v, 2),
      onChange: v => { S.eyeK = v; draw(); } });
    api.text(GX, BY + 70, "Legend: blue square = the Mandelbox's ±2 · orange square = the KIFS's max(2, 1.5 |offset|) · the Kleinian's 1e4 cube is off the drawing · green dot = the eye.", "muted", { style: small });
    api.text(GX, BY + 88, "Thick line = the marched part of the ray, from the cube entry (ring) to its stop (dot) · wide band = the last third, where view_fade runs 0 → 1 · dotted = the ray past its stop.", "muted", { style: small });
    api.text(GX, BY + 106, "Sources: bound_half fractal_params.gd:491-505 · view_distance :510-511 · the shader's view_limit / view_fade mandelbox.gdshader:302-312 and the t_exit clamp :433-434 · the hit mix :563-564 · the CPU clamps center_ray.gd:70-72 and orbit_camera.gd:156-158.", "muted", { style: small });
    api.link(GX, BY + 126, RL("params", 491, "bound_half"));
    api.link(GX + 130, BY + 126, RL("sh", 302, "view_limit · view_fade"));
    api.link(GX + 330, BY + 126, RL("sh", 433, "t_exit clamp"));
    api.link(GX + 480, BY + 126, RL("ray", 71, "center_ray clamp"));
    api.link(GX + 650, BY + 126, RL("orbit", 157, "orbit clamp"));
    api.link(GX + 790, BY + 126, RL("spec", 111, "spec: bounds"));
    draw();
  },
};
horizonFig.refs = [R("params", 491), R("params", 510), SH(302), SH(433), SH(563), R("ray", 70), R("orbit", 156)];

// ================================================================== 6. cards
const okK = FIX_K.fails.length === 0, okL = FIX_L.fails.length === 0;
const cards = {
  type: "cards",
  tab: "Invariants, gotchas, history",
  title: "Invariants, gotchas, history, open",
  columns: 3, cardWidth: 480,
  cards: [
    { title: okK && okL ? `CPU twins = shader: the ${FIX_K.n} + ${FIX_L.n} fixtures` : `✗ THIS PAGE'S PORTS FAIL ${FIX_K.fails.length + FIX_L.fails.length} FIXTURES`,
      tag: okK && okL ? "invariant" : "port broken", hue: okK && okL ? 3 : 2, ...R("tKifs", 25), links: [RL("tKl", 21, "the Kleinian fixtures"), RL("tKifs", 10, "the tolerance"), RL("kifsDe", 3, "\"CPU copy of kifs_de\""), RL("klDe", 3, "\"CPU copy of kleinian_de\"")],
      body: okK && okL
        ? `KifsEstimator and KleinianEstimator must give the shader's numbers, pinned by nine captured KIFS fixtures (the Menger defaults, the Sierpinski, the polyfold, a rotated set) and five Kleinian ones (the defaults, a shifted set), at relative 1e−5 or absolute 1e−9. This pane runs all fourteen through its own ports at load and they pass (worst relative error ${Math.max(FIX_K.worst, FIX_L.worst).toExponential(1)}), so its figures show the real shapes. A failure turns this card orange and shows in the red error box.`
        : `The figures on this page are NOT the real shapes until the ports are fixed (fix the port, never the fixtures): ${FIX_K.fails.concat(FIX_L.fails).join("; ")}` },
    { title: "The defaults are the Menger sponge, as geometry", tag: "invariant", hue: 3, ...R("tKifs", 28), links: [RL("kifsShape", 6, "\"defaults make the Menger sponge\""), RL("tKifs", 33, "cube symmetry"), RL("tMarch", 62, "march safety: Menger")],
      body: "Not just numbers: at scale 3, the coordinate fold and offset (1, 1, 1, 0), a corner cell like (0.5, 0.5, 0.5) is solid (D < 1e−9), the +x face sits at x = 1 (D(1.5, 0.2, −0.4) = 0.5), the centre and the tunnel along z are empty (D > 0.3), D is mirror-symmetric in x and unchanged by cycling x → y → z. The Sierpinski's (1, 1, 1) vertex is on it and the opposite corner is not. Tab 2 reproduces each with a click." },
    { title: "Kleinian: D(p) = D(−p) at the defaults, unsigned", tag: "invariant", hue: 3, ...R("tKl", 28), links: [RL("klDe", 37, "thingy is unsigned")],
      body: "With no shift the iteration is a box fold (a mirror in each axis) and an inversion (symmetric under p → −p), so the estimate is even. The thingy is wrapped in abs, so the estimate is never negative: zero on the sheets, positive either side. The test also checks that every knob changes the distance, so no uniform is dead." },
    { title: "One `shape` value, three places that must agree", tag: "invariant", hue: 3, ...SH(316), links: [RL("de", 32, "the CPU match"), RL("params", 491, "bound_half"), RL("tShader", 43, "uniforms = catalogue ids"), RL("tCat", 38, "the 90 ids")],
      body: "The shader's de() switch, DistanceEstimator's match and FractalParams' bound_half / view_distance / coarse_iters / julia_enabled all read the same `shape`. The knobs reach each side under the same name (catalogue id = uniform = field), and shader_test checks the uniform set equals the 90 ids exactly, includes and all, so a knob cannot reach the GPU and miss the CPU or the reverse." },
    { title: "Rows and headings hide off their shape", tag: "invariant", hue: 3, ...R("cat", 44), links: [RL("tCat", 120, "the catalogue test"), RL("tConsole", 193, "the heading test"), RL("inspector", 99, "_refresh_headings")],
      body: "`shown_for(shape, inner)` wraps every per-shape row, keeping the row's own condition (Polyfold k needs the Polyfold; a Julia constant needs its toggle) on top. The inspector hides a group's heading when every row in it is hidden. The two console tabs still show every group exactly once between them." },
    { title: "Every shape is safe to sphere-trace", tag: "invariant", hue: 3, ...R("tMarch", 2), links: [RL("tMarch", 61, "the KIFS cases"), RL("tMarch", 70, "the Kleinian"), RL("spec", 140, "spec: the Lipschitz bound that was rejected")],
      body: "Forty rays marched with full steps never jump a surface that the same rays marched with quarter steps find, within ten hit thresholds of the hit, and some rays must hit so no default is empty. The spec tried a plain Lipschitz bound first (|D(a) − D(b)| ≤ |a − b|) and rejected it: even the site's Mandelbox estimate exceeds 1 by a few percent, and the escape-time estimators jump by about 1e−4 far from any surface, both harmless to the march." },
    { title: "Fractacular's diagonal fold never fired", tag: "gotcha", hue: 2, ...R("kifsDe", 10), links: [RL("ks", 49, "here: on the point itself"), RL("spec", 82, "spec: the two fixes"), FRACTACULAR("kifs.gdshader")],
      body: "Fractacular's kifs.gdshader runs `p = abs(p)` before every fold set, and then its Sierpinski test `x + y < 0` can never hold, so its Diagonal fold was a Coordinate fold with no sort. Here the diagonal fold runs on the point itself (no abs), and the Sierpinski tetrahedron appears at scale 2. The fixture for it was captured from this corrected code." },
    { title: "The polyfold mirrors; the Menger fold follows it", tag: "gotcha", hue: 2, ...R("kifsDe", 12), links: [RL("ks", 57, "the comment"), RL("ks", 62, "abs(mod(…) − sector/2)"), RL("kifsDe", 123, "why menger_fold follows")],
      body: "Fractacular's polyfold rotated the xy angle into one wedge of 2π/k, which is discontinuous across the wedge edges: two neighbouring points can land far apart, and a distance estimate built on that lies to the march. Here the angle is reflected into a half-wedge, a triangle wave in the angle, continuous everywhere. The polyfold alone leaves dust too sparse to hit at scale 3, so the Coordinate fold runs after it (and the effects text suggests scale 2 to 2.5)." },
    { title: "The Kleinian fills space: the View distance is a shape knob", tag: "gotcha", hue: 2, ...R("klShape", 49), links: [RL("sh", 302, "view_limit"), RL("sh", 433, "t_exit"), RL("ray", 71, "the centre ray stops there too"), RL("spec", 10, "spec: the decision")],
      body: "There is no cube that contains the lattice, so a ray with no limit would march through cell after cell until its step budget ran out, every pixel at full cost. kleinian_view_distance ends the rays (10 by default: a few cells each way) and view_fade blends the last third into the background. It sits in the Kleinian group because it is meaningless elsewhere; the spec recorded that choice. Lowering it is the cheapest way to speed up a slow Kleinian view." },
    { title: "The Kleinian's early exit is an exact float compare", tag: "gotcha", hue: 2, ...KL(29), links: [RL("klDe", 32, "GDScript: `p == before`"), RL("params", 364, "why coarse_iters is 32 for it")],
      body: "`if (p == before) break;`: a point outside its box and the sphere, with no shift, is left exactly where it was, so the loop ends after one wasted iteration rather than 31. Any non-zero shift defeats the test (p moves every time), and float32 on the GPU agrees with the 64-bit CPU here only because both compare exact bit patterns of the same operations. The coarse pass still asks for 32 iterations: the Kleinian has no steady magnification per iteration for the deep-zoom rule to use." },
    { title: "Polyfold k is a FLOAT rounded to an int on both sides", tag: "gotcha", hue: 2, ...R("kifsShape", 42), links: [RL("ks", 60, "shader: floor(k + 0.5)"), RL("kifsDe", 36, "GDScript: the same"), RL("tCat", 160, "hidden off the Polyfold")],
      body: "The catalogue only binds floats, so k is a FLOAT row (2 … 12, step 1) and the shader and the CPU both take floor(k + 0.5), floored at 2. Bound to an axis it steps from one symmetry to the next. The row is shown only while the Fold set is Polyfold." },
    { title: "Off the Mandelbox: no Julia marker, no NF normal", tag: "gotcha", hue: 2, ...R("params", 478), links: [RL("sh", 488, "shape == 0 && … && !julia_all"), RL("tKl", 44, "no marker, tested"), RL("spec", 120, "spec")],
      body: "julia_enabled() is false unless the shape is the Mandelbox, so the Julia ring hides on the KIFS and the Kleinian even with Julia (all) left on in the table. The Ice Fractal colour modes' field normal (calc_nf) is the Mandelbox's own orbit, so the other two shapes always light with the true gradient normal (calc_normal)." },
    { title: "KIFS bound: 1.5 |offset|, never under 2", tag: "gotcha", hue: 2, ...R("params", 495), links: [RL("tKifs", 65, "2.598 for the default"), RL("tKifs", 67, "and never under 2"), RL("spec", 111, "spec: bounds")],
      body: "p → s·p − (s−1)·offset with distance-preserving folds has its attractor within |offset| of the origin; the march's cube is 1.5 times that, a margin for the rotations, and at least 2 so a tiny offset still leaves room to fly. The default offset gives 2.598. The cube is pushed as box_half from bound_half(), replacing the hard-coded 2 / 20 the view and the orbit camera used to carry separately." },
    { title: "The camera stays put when the fractal changes", tag: "gotcha", hue: 2, ...R("cat", 84), links: [RL("readme", 225, "README: the Fractal row")],
      body: "Switching the shape row re-renders in place; the camera is wherever it was, possibly inside the new shape. The row's effects text says so: fly out, or Reset camera. Nothing in the shape layer touches CameraState." },
    { title: "Ported from Fractacular's two techniques, with changes", tag: "history", hue: 6, ...R("spec", 1), links: [FRACTACULAR("kifs.gdshader"), FRACTACULAR("kleinian.gdshader"), RL("readme", 7, "README"), RL("plan", 1, "the implementation plan")],
      body: "Fractacular (the sibling 2D slice app) has six techniques; two have a distance estimate that fits a sphere tracer and came across: its kifs technique (same R1 / fold / R2 / twist / scale loop, same Menger correction, the two fold fixes above) and its kleinian one. Fractacular's Kleinian returned |p| / dr, an escape-style estimate that colours a 2D slice; a ray march needs a surface, so this one returns Knighty's thingy over dr, and its shift defaults to 0 where Fractacular's was (−0.5, −0.5, 0, 0). Newton, Lyapunov and the ℂ² quadratic map stayed behind: no distance estimate." },
    { title: "Decisions taken on 2026-10-08", tag: "history", hue: 6, ...R("spec", 10), links: [RL("spec", 14, "the shape switch"), RL("spec", 146, "the one windowed screenshot batch")],
      body: "The shape switch is a catalogue row at the top of the Shape tab (not a menu); the Kleinian's render distance is a Kleinian knob; the Mandelbox's hybrid is a mix plus a period; one windowed screenshot batch at the end (default KIFS, Sierpinski, polyfold, Kleinian, and the three Mandelbox options). The same change added the Mandelbox's fold shape, hybrid fold and scale drift." },
    { title: "Saves: still version 2; an old file is a Mandelbox", tag: "history", hue: 6, ...R("ws", 62), links: [RL("tWs", 161, "the test"), RL("readme", 343, "README: the save format")],
      body: "`shape` is one more id in shape.defaults, so a KIFS view saves and loads like any other. A file from before the row existed has no `shape` id and loads as the Mandelbox, whatever shape was showing when it was loaded, and without a warning." },
    { title: "Self-similar: the KIFS without a twist, the Kleinian always", tag: "history", hue: 6, ...R("kifsShape", 91), links: [RL("klShape", 66, "the Kleinian's reasoning"), RL("cat", 252, "ShapeCatalogue.self_similarity"), RL("readme", 213, "README: the Shape tab's line")],
      body: "The Shape tab's read-only line. The KIFS iteration is one fixed map magnifying by Scale away from a fixed offset, so the attractor is made of magnified copies of itself; a twist turns every iteration by a different angle and breaks that. The Kleinian's inversion bends as it magnifies, but over a small region it is an even scale plus a mirror (conformal), as the Mandelbox's sphere fold is, so it qualifies; a noise displacement disqualifies either." },
    { title: "The mandelbox pane predates the shape switch", tag: "open", hue: 4, file: "docs/viz/panes/mandelbox.js", line: 1, links: [RL("mbShape", 73, "fold_shape"), RL("mbShape", 82, "hybrid_mix"), RL("mbShape", 97, "scale_drift")],
      body: "It is pinned before this change: its line numbers into mandelbox.gdshader are a commit behind, its uniform count (66) is now 83 + the renderer's, and its \"any fractal but the Mandelbox\" non-goal card is no longer true. The three Mandelbox options added in the same change (fold shape, hybrid fold, scale drift) have no viz yet. A /visualize of the Mandelbox would refresh it." },
    { title: "The Mandelbulb landed a day later, and has no pane", tag: "open", hue: 4, file: "src/fractal/mandelbulb_shape.gd", line: 1, links: [{ file: "src/fractal/mandelbulb.gdshaderinc", line: 1, label: "mandelbulb.gdshaderinc" }, { file: "src/fractal/mandelbulb_estimator.gd", line: 1, label: "MandelbulbEstimator" }, { file: "tests/mandelbulb_estimator_test.gd", line: 1, label: "its fixtures" }, RL("readme", 255, "README: the Mandelbulb rows")],
      body: "A fourth shape (`shape` 3), White and Nylander's triplex power, not from Fractacular: 3D (the w row hides), its own include and 64-bit twin, a bound of max(2, its escape radius), coarse_iters on its power. It arrived on main while this pane was being written, so the dispatch nodes here name it and nothing else does. A /visualize of the Mandelbulb would give it its own fold-by-fold tab." },
    { title: "Not ported: Newton, Lyapunov, the ℂ² quadratic map", tag: "open", hue: 4, ...R("spec", 7),
      body: "Fractacular's other three techniques have no distance estimate that fits the sphere tracer, so they are out of scope here, and nothing is designed around them." },
  ],
};

// The checker verifies every { file, line } it finds in a pane's data; a figure's tooltips are built
// inside draw(), so each figure also carries `refs`: every R / RL / KS / KL / SH call with literal
// arguments in its draw source.
function refsIn(fn, extra) {
  const src = String(fn), out = [];
  for (const m of src.matchAll(/\b(SH|KS|KL)\((\d+)\)/g)) out.push(({ SH, KS, KL })[m[1]](+m[2]));
  for (const m of src.matchAll(/\bRL?\("(\w+)",\s*(\d+)/g)) out.push(R(m[1], +m[2]));
  return out.concat(extra || []);
}
kifsFig.refs = refsIn(kifsFig.draw);
klFig.refs = refsIn(klFig.draw);
horizonFig.refs = refsIn(horizonFig.draw, horizonFig.refs);

VIZ.pane({
  id: "shapes",
  short: "KIFS & Kleinian",
  title: "KIFS and Kleinian — the two other shapes",
  subtitle: "Beside the Mandelbox (and, since 2026-10-09, the Mandelbulb) the viewer draws two shapes ported from Fractacular: a kaleidoscopic IFS (the Menger sponge, the Sierpinski tetrahedron and their rotated, twisted kin) and Knighty's pseudo-Kleinian limit set, an endless lattice of curved sheets and rings. One catalogue row, `shape`, picks the fractal; each shape's knobs live in its own spec list and GLSL include, with a 64-bit CPU twin behind DistanceEstimator. The KIFS folds space into one wedge and scales it away from an offset, so the shape is made of smaller copies of itself; the Kleinian folds each point back into a box and inverts it through a sphere, and what the folds keep returning is the set. The Kleinian fills space, so its rays stop at a View distance and fade into a horizon. The live figures run line-for-line ports of both estimators, checked at load against the tests' fourteen fixtures.",
  commit: "26c3b3d5c72254b6fbd92e5ebd7b68ed6a3958e7",
  pinNote: "main, unpushed: links 404 until it is pushed",
  ctx: {
    catalogue: { hue: 5, label: "catalogue — ShapeCatalogue, the three spec lists, the inspector, saves" },
    state: { hue: 1, label: "state — FractalParams and what it derives from `shape`" },
    shader: { hue: 6, label: "shader — de() and the two includes" },
    cpu: { hue: 4, label: "CPU estimators — the 64-bit twins" },
    camera: { hue: 3, label: "cameras — the CPU marches" },
    test: { hue: 2, label: "tests" },
  },
  kinds: {
    call: { style: "solid", label: "calls · appends" },
    data: { style: "dot", label: "reads a value · a uniform" },
  },
  tabs: [arch, kifsFig, klFig, knobTable, horizonFig, cards],
  // The ports, exposed for checking from the console (VIZ.panes[2].ports.kifsDe(...)).
  ports: { kifsParams, kifsDe, kifsStages, mengerFold, diagonalFold, polyFold, boxDistance, klParams, klDe, klStages, thingy, boundHalf, viewFade, boxIntersect, coarseIters, FIX_K, FIX_L },
});
})();
