// Pane: the Mandelbox viewer (Help I'm Stuck In A Fractal). Every file:line below was read at
// `commit` with `git show <commit>:<path>`. When the code changes: re-read the lines, bump `commit`,
// run `node tools/viz/check.mjs --print --pane mandelbox`.
//
// The live figures run JavaScript ports of the real maths, each a small named function below with
// the source file and lines it was ported from. They run in doubles, like DistanceEstimator's
// scalar orbit; the shader itself runs float32 (see the gotcha cards in the last tab).
// The attribute / binding / axes layer that writes the shape values each frame has its own pane,
// `console`; this one starts at FractalParams, the resolved values.
(function () {
const F = {
  main: "src/main.gd",
  mainScn: "src/main.tscn",
  params: "src/fractal/fractal_params.gd",
  shape: "src/fractal/mandelbox_shape.gd",
  de: "src/fractal/distance_estimator.gd",
  sh: "src/fractal/mandelbox.gdshader",
  view: "src/fractal/fractal_view.gd",
  viewScn: "src/fractal/fractal_view.tscn",
  cam: "src/camera/camera_state.gd",
  fly: "src/camera/fly_camera.gd",
  orbit: "src/camera/orbit_camera.gd",
  marker: "src/camera/julia_marker.gd",
  gov: "src/perf/resolution_governor.gd",
  shed: "src/perf/load_shedder.gd",
  table: "src/attributes/attribute_table.gd",
  resolver: "src/attributes/binding_resolver.gd",
  keymap: "src/axes/keymap.gd",
  axisCtl: "src/axes/axis_controller.gd",
  clock: "src/axes/clock.gd",
  console: "src/ui/console/console_window.gd",
  ctrlTap: "src/ui/ctrl_tap.gd",
  textFocus: "src/ui/text_focus.gd",
  noise: "src/ui/noise_window.gd",
  uiScale: "src/ui/ui_scale.gd",
  renderer: "src/ui/renderer_options.gd",
  viewPane: "src/ui/console/view_pane.gd",
  ws: "src/workspace/workspace.gd",
  wsf: "src/workspace/workspace_files.gd",
  proj: "project.godot",
  readme: "README.md",
  spec: "docs/superpowers/specs/2026-10-06-mandelbox-explorer-design.md",
  consoleSpec: "docs/superpowers/specs/2026-10-07-debug-console-design.md",
  shedSpec: "docs/superpowers/specs/2026-10-07-load-shedding-design.md",
  saveDef: "saves/default.json",
  saveField: "saves/juliaIceField.json",
  saveTer: "saves/juliaIceTerraces.json",
  tDE: "tests/distance_estimator_test.gd",
  tGov: "tests/resolution_governor_test.gd",
  tShed: "tests/load_shedder_test.gd",
  tView: "tests/fractal_view_test.gd",
  tFly: "tests/fly_camera_test.gd",
  tParams: "tests/fractal_params_test.gd",
  tOrbit: "tests/orbit_camera_test.gd",
  tMarker: "tests/julia_marker_test.gd",
  tMain: "tests/main_test.gd",
  tWs: "tests/workspace_test.gd",
  tShader: "tests/shader_test.gd",
  tCam: "tests/camera_state_test.gd",
  tDeep: "tests/deep_zoom_test.gd",
  movement: "src/ui/console/movement_pane.gd",
  zoomSpec: "docs/superpowers/specs/2026-10-08-deep-zoom-march-design.md",
};
// Link helpers: R("sh", 62) is { file, line }; RL adds a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const SH = line => R("sh", line);

// ================================================================== the ports
// The maths, ported line for line. P is a flat parameter record built by params(): every resolved
// shape value under its catalogue id (FractalParams' field = the uniform's name), the renderer
// options, the load-shed level, and the values the shader derives once per fragment.
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const TAN_HALF_FOV = 0.36397023426620234;          // fractal_view.gd:11
const DEFAULT_EYE = [8.175847, 3.812460, 3.283393]; // camera_state.gd:9
const C_DEFAULT = [-0.23, 1.512, 1.892, 0];         // mandelbox_shape.gd:116 (c_0..c_3)
const PLANES = [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]];   // distance_estimator.gd:19
const PLANE_NAMES = ["xy", "xz", "xw", "yz", "yw", "zw"];
const AX4 = ["x", "y", "z", "w"];

// LoadShedder.LEVELS (load_shedder.gd:14-20): fog in multiples of near_dist, then multipliers.
const SHED_LEVELS = [
  { fog: 0, detail: 1, steps: 1, speed: 1 },
  { fog: 400, detail: 0.75, steps: 1, speed: 1 },
  { fog: 150, detail: 0.55, steps: 0.75, speed: 1 },
  { fog: 60, detail: 0.4, steps: 0.5, speed: 1 },
  { fog: 40, detail: 0.35, steps: 0.5, speed: 0.4 },
];
// FractalParams.FOG_COLORS (fractal_params.gd:180-195), by colour-mode id.
const FOG_COLORS = { 0: [0.22, 0.22, 0.22], 1: [0.14, 0.22, 0.36], 2: [0.10, 0.17, 0.10], 3: [0.24, 0.14, 0.30],
  4: [0.20, 0.10, 0.24], 8: [0.14, 0.18, 0.30], 15: [0.20, 0.20, 0.27], 5: [0.82, 0.88, 1.00], 6: [0.85, 0.90, 1.00],
  7: [0.30, 0.14, 0.27], 16: [0.12, 0.26, 0.34], 9: [0.12, 0.26, 0.34], 14: [0.28, 0.20, 0.06], 20: [0.18, 0.18, 0.22] };

// The colour, lighting and palette defaults (fractal_params.gd:102-156; the site's lighting constants).
// pal is the cosine palette's A, B, C, D vectors (palette_a_r … palette_d_b).
const LOOK_DEFAULTS = { palette_source: 0, palette_frequency: 1, palette_offset: 0, palette_occlusion: 0.5,
  light_ambient: 0.1, light_diffuse: 0.5, light_specular: 1, light_shininess: 160, light_yaw: 0, light_pitch: 0, exposure: 1, saturation: 1,
  pal: [[0.5, 0.5, 0.5], [0.5, 0.5, 0.5], [1, 1, 1], [0, 0.33, 0.67]] };
// params(o): FractalParams' defaults (fractal_params.gd:51-216) overridden by o, then what
// FractalView._push_params (fractal_view.gd:331-368) and the shader derive from them:
//   precU   = precision / (detail · shed detail)        the `precision` uniform (line 314)
//   budget  = max(32, round(max_steps · shed steps))    split ¾ coarse, the rest fine (320-322)
//   boxHalf = 20 when julia_all, else 2                 (line 317)
//   mr2/fr2 = max(radius², 1e-12)                        mb_sphere_fold (mandelbox.gdshader:151-152)
//   jOn[i]  = julia_all || julia_i                       mb_constant (153-159)
//   rotating = Σ|angle| > 1e-6                           mb_rotating (137-140)
// julia (4 bools), c (4 floats) and rot (six degrees, xy xz xw yz yw zw) are arrays for julia_0..3,
// c_0..3 and iter_rot_*.
function params(o) {
  const p = Object.assign({ box_scale: -2.09, fold_limit: 1.0, min_radius: 0.7, fixed_radius: 1.0, fold_order: 0, w: 0,
    julia_all: false, julia: [false, false, false, false], c: C_DEFAULT.slice(), rot: [0, 0, 0, 0, 0, 0],
    color_mode: 1, precision: 0.000025, detail: 1, detail_range: 10, detail_falloff: 0, max_steps: 128, shed: 0 }, LOOK_DEFAULTS, o || {});
  p.julia = p.julia.slice(); p.c = p.c.slice(); p.rot = p.rot.slice(); p.pal = p.pal.map(v => v.slice());
  const L = SHED_LEVELS[clamp(p.shed, 0, 4)];
  p.precU = p.precision / (p.detail * L.detail);
  p.budget = Math.max(32, Math.round(p.max_steps * L.steps));
  p.coarse = Math.floor(p.budget * 3 / 4);          // coarse_steps(budget): fractal_params.gd:311-312
  p.fine = p.budget - p.coarse;                     // fine_steps(budget): fractal_params.gd:315-317
  p.fog = L.fog;
  p.fogColor = FOG_COLORS[p.color_mode] || [0.2, 0.2, 0.2];
  p.boxHalf = p.julia_all ? 20 : 2;
  p.mr2 = Math.max(p.min_radius * p.min_radius, 1e-12);
  p.fr2 = Math.max(p.fixed_radius * p.fixed_radius, 1e-12);
  p.jOn = p.julia.map(j => p.julia_all || j);
  p.rotating = p.rot.reduce((s, a) => s + Math.abs(a), 0) > 1e-6;
  p.cosv = p.rot.map(a => Math.cos(a * Math.PI / 180));
  p.sinv = p.rot.map(a => Math.sin(a * Math.PI / 180));
  return p;
}
// A copy of P with some fields changed, every derived value recomputed.
const withP = (P, o) => params(Object.assign({}, P, o));
const LOOK_P = Object.assign({}, LOOK_DEFAULTS);     // shade()'s default look: the site's

// hitEps: the hit threshold at ray distance t for a camera `near` from the nearest surface,
// mandelbox.gdshader:113-120 (hit_eps, with precision / detail folded into the `precision` uniform)
// = fractal_params.gd:221-227 (hit_epsilon) at shed level 0. Falloff 0 is the plain cone precision · t.
const NEAR_FLOOR = 1e-6;                            // fractal_params.gd:177
function hitEps(P, t, near) {
  let e = P.precU * t;
  if (P.detail_falloff > 0) {
    const start = P.detail_range * Math.max(near, NEAR_FLOOR);
    if (t > start) e *= Math.pow(t / start, P.detail_falloff);
  }
  return e;
}
// fog_amount: mandelbox.gdshader:123-127, 0 clear .. 1 fully fogged at fog · near_dist.
const smoothstep = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
function fogAmount(P, t, near) {
  if (P.fog <= 0) return 0;
  const tf = P.fog * near;
  return smoothstep(0.35 * tf, tf, t);
}
// nearDist: what FractalView._push_near pushes as `near_dist` (fractal_view.gd:388).
function nearDist(eye, P) { return Math.max(de(eye[0], eye[1], eye[2], 32, P), NEAR_FLOOR); }
// coarseIters: fractal_params.gd:246-251 (coarse_iters), the march's coarse-pass iteration count
// for a camera `near` from the surface: the fewest n whose smoother surface (rough by about
// 2 / |box_scale|^n) sits inside the coarse threshold 2 · eps · near, eps = precision / detail
// (unshed), kept in [16, 32]. 16 at the default view; |box_scale| ≤ 1 gives 32.
function coarseIters(P, near) {
  const s = Math.abs(P.box_scale);
  if (s <= 1) return 32;
  const gap = Math.max(2 * P.precision / P.detail * Math.max(near, 0), 1e-300);
  return clamp(Math.ceil(Math.log(2 / gap) / Math.log(s)), 16, 32);
}
// nfWeight: fractal_params.gd:269-270 (nf_weight) = smoothstep(0.1, 2, near): how much of the Ice
// Fractal normal the probe-lit modes use, 1 from near = 2 out, 0 inside 0.1.
function nfWeight(near) { const x = clamp((near - 0.1) / (2 - 0.1), 0, 1); return x * x * (3 - 2 * x); }
// zoomFloor: fractal_params.gd:282-306 (ulp32, zoom_floor): the closest the fly camera may come.
function ulp32(x) { x = Math.abs(x); return x < Math.pow(2, -126) ? Math.pow(2, -149) : Math.pow(2, Math.floor(Math.log2(x)) - 23); }
function zoomFloor(eye, P) { return ulp32(Math.max(...eye.map(Math.abs))) / (50 * Math.max(P.precision / P.detail, 1e-30)); }

// One Mandelbox iteration on the 4D orbit point v (a Float64Array of x, y, z, w), returning the new
// dz: mb_step, mandelbox.gdshader:201-207 = the loop body of distance_estimator.gd:62-76.
//   mb_box_fold   (85-87)    every component outside ±fold_limit reflected back inside
//   mb_sphere_fold (91-104)  ×fr2/mr2 inside min_radius, ×fr2/r2 between the radii, dz the same
//   mb_iter_rotate (127-135) the six planes in order, each mb_rot_plane (115-124)
//   then z = box_scale · z + c ; dz = dz · |box_scale| + 1
function boxFold(v, L) { for (let a = 0; a < 4; a++) v[a] = clamp(v[a], -L, L) * 2 - v[a]; }
function sphereFold(v, P) {
  const r2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];
  let f = 1;
  if (r2 < P.mr2) f = P.fr2 / P.mr2;
  else if (r2 < P.fr2) f = P.fr2 / Math.max(r2, 1e-12);
  v[0] *= f; v[1] *= f; v[2] *= f; v[3] *= f;
  return f;
}
function iterRotate(v, P) {
  for (let k = 0; k < 6; k++) {
    const a = PLANES[k][0], b = PLANES[k][1], c = P.cosv[k], s = P.sinv[k], va = v[a], vb = v[b];
    v[a] = va * c - vb * s; v[b] = va * s + vb * c;
  }
}
function mbStep(v, dz, c, P) {
  if (P.fold_order === 0) { boxFold(v, P.fold_limit); dz *= sphereFold(v, P); }
  else { dz *= sphereFold(v, P); boxFold(v, P.fold_limit); }
  if (P.rotating) iterRotate(v, P);
  const s = P.box_scale;
  v[0] = s * v[0] + c[0]; v[1] = s * v[1] + c[1]; v[2] = s * v[2] + c[2]; v[3] = s * v[3] + c[3];
  return dz * Math.abs(s) + 1;
}
// mb_constant: mandelbox.gdshader:211-217, per component the Julia constant or the point's own.
function mbConstant(z0, P) { return [0, 1, 2, 3].map(a => (P.jOn[a] ? P.c[a] : z0[a])); }

// de(p, iters): mandelbox.gdshader:220-231, equal to distance_estimator.gd:27-78 (estimate_at).
const _v = new Float64Array(4), _c = new Float64Array(4);
function de(px, py, pz, iters, P) {
  _v[0] = px; _v[1] = py; _v[2] = pz; _v[3] = P.w;
  for (let a = 0; a < 4; a++) _c[a] = P.jOn[a] ? P.c[a] : _v[a];
  let dz = 1;
  for (let i = 0; i < 32; i++) {
    if (i >= iters) break;
    dz = mbStep(_v, dz, _c, P);
  }
  return Math.hypot(_v[0], _v[1], _v[2], _v[3]) / Math.abs(dz);
}

// The same orbit, keeping every stage (for the fold-by-fold stepper). Entry 0 is the start; then per
// iteration: the two folds in fold_order, the rotation (only when rotating), then scale-and-add.
// kind: "start" | "box" | "sphere" | "rot" | "add".
function orbitStages(px, py, pz, P, iters) {
  const z0 = [px, py, pz, P.w], c = mbConstant(z0, P), v = Float64Array.from(z0);
  let dz = 1;
  const out = [{ kind: "start", it: 0, z: z0.slice(), dz, c }];
  const box = it => {
    const before = Array.from(v);
    boxFold(v, P.fold_limit);
    out.push({ kind: "box", it, z: Array.from(v), dz, folded: before.map((b, a) => b !== v[a]) });
  };
  const sph = it => {
    const r2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];
    const f = sphereFold(v, P);
    dz *= f;
    out.push({ kind: "sphere", it, z: Array.from(v), dz, r2, f, branch: r2 < P.mr2 ? 0 : r2 < P.fr2 ? 1 : 2 });
  };
  for (let i = 0; i < iters; i++) {
    if (P.fold_order === 0) { box(i); sph(i); } else { sph(i); box(i); }
    if (P.rotating) { iterRotate(v, P); out.push({ kind: "rot", it: i, z: Array.from(v), dz }); }
    for (let a = 0; a < 4; a++) v[a] = P.box_scale * v[a] + c[a];
    dz = dz * Math.abs(P.box_scale) + 1;
    out.push({ kind: "add", it: i, z: Array.from(v), dz });
  }
  return out;
}

// field(q): mandelbox.gdshader:235-244, the Ice Fractal field F(q) = |z16| − 8: the same mb_step from
// z = 0 with c = (q, w), dz carried but unused.
const _fv = new Float64Array(4), _fc = new Float64Array(4);
function field(qx, qy, qz, P) {
  _fv.fill(0);
  _fc[0] = qx; _fc[1] = qy; _fc[2] = qz; _fc[3] = P.w;
  let dz = 1;
  for (let i = 0; i < 16; i++) dz = mbStep(_fv, dz, _fc, P);
  return Math.hypot(_fv[0], _fv[1], _fv[2], _fv[3]) - 8;
}

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const norm = v => { const l = Math.hypot(v[0], v[1], v[2]); return l > 0 ? [v[0] / l, v[1] / l, v[2] / l] : [0, 0, 0]; };
const add = (a, b, k = 1) => [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

// calcNormal: mandelbox.gdshader:247-253, central differences of de(·, 32).
function calcNormal(v, delta, P) {
  const [x, y, z] = v;
  return norm([de(x + delta, y, z, 32, P) - de(x - delta, y, z, 32, P),
    de(x, y + delta, z, 32, P) - de(x, y - delta, z, 32, P),
    de(x, y, z + delta, 32, P) - de(x, y, z - delta, 32, P)]);
}

// calcNF: mandelbox.gdshader:257-264. Base sample at the HALF-scale h = v/2, offsets at v + 0.01.
function calcNF(v, h, P) {
  const lw = field(h[0], h[1], h[2], P);
  return norm([(field(v[0] + 0.01, v[1], v[2], P) - lw) / 0.01,
    (field(v[0], v[1] + 0.01, v[2], P) - lw) / 0.01,
    (field(v[0], v[1], v[2] + 0.01, P) - lw) / 0.01]);
}

// hue: mandelbox.gdshader:267-277 (GLSL mod(x, 2) = x − 2·floor(x/2)).
function hue(q) {
  q = clamp(q, 0, 0.999999);
  const h6 = q * 6, x = 1 - Math.abs(h6 - 2 * Math.floor(h6 / 2) - 1);
  if (h6 < 1) return [1, x, 0];
  if (h6 < 2) return [x, 1, 0];
  if (h6 < 3) return [0, 1, x];
  if (h6 < 4) return [0, x, 1];
  if (h6 < 5) return [x, 0, 1];
  return [1, 0, x];
}

// boxIntersect: mandelbox.gdshader:299-312. Returns [t_enter, t_exit]; a miss has t_exit < max(t_enter, 0).
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

// march: the two phases of fragment(), mandelbox.gdshader:326-369. With `rec`, every de() call is
// recorded ({ phase, i, total, d, th, p, stop }) for the ray stepper. `near` is near_dist for this eye.
// Under a load-shed fog the march ends at fog · near_dist (255-257): nothing past it is marched.
function march(eye, dir, P, rec) {
  const tb = boxIntersect(eye, dir, P.boxHalf), near = nearDist(eye, P);
  const out = { tEnter: tb[0], tExit: tb[1], tEnd: tb[1], miss: false, left: false, fogged: false, n1: P.coarse, n2: P.fine,
    total: 0, start: 0, ce: 1, near, lodStart: P.detail_range * near, nc: coarseIters(P, near), steps: rec || null };
  if (tb[1] < Math.max(tb[0], 0)) { out.miss = true; return out; }
  let tExit = tb[1];
  if (P.fog > 0) tExit = Math.min(tExit, P.fog * near);
  out.tEnd = tExit;
  let total = Math.max(tb[0], 0);
  out.start = total;
  let left = total > tExit;
  for (let i = 0; i < P.coarse && !left; i++) {                          // phase 1: de(p, coarse_iters), coarse_steps
    const p = add(eye, dir, total), d = de(p[0], p[1], p[2], out.nc, P), th = hitEps(P, total, near) * 2;
    if (rec) rec.push({ phase: 1, i, total, d, th, p, stop: d < th });
    if (d < th) { out.n1 = i; break; }
    total += d;
    if (total > tExit) { left = true; break; }
  }
  if (!left) {
    for (let i = 0; i < P.fine; i++) {                                     // phase 2: de(p, 32), fine_steps
      const p = add(eye, dir, total), d = de(p[0], p[1], p[2], 32, P), th = hitEps(P, total, near);
      if (rec) rec.push({ phase: 2, i, total, d, th, p, stop: d < th });
      if (d < th) { out.n2 = i; break; }
      total += d;
      if (total > tExit) { left = true; break; }
    }
  }
  out.left = left;
  out.fogged = left && P.fog > 0 && tExit < tb[1];
  out.total = total;
  // ce stays on the original 128-step scale; a ray that ran out of phase 2 is 1 (mandelbox.gdshader:369).
  out.ce = out.n2 === P.fine ? 1 : Math.min((out.n1 + out.n2) / 128, 1);
  return out;
}

// palette: mandelbox.gdshader:281-287 (= Palette.color_at), A + B·cos(2π(C·t + D)), clamped.
function palette(t, P) {
  const [A, B, C, D] = P.pal;
  return [0, 1, 2].map(k => clamp(A[k] + B[k] * Math.cos(6.283185307179586 * (C[k] * t + D[k])), 0, 1));
}
// lightTerm: mandelbox.gdshader:405, diffuse·nl + specular·nl^shininess + ambient (the site's 0.5, 1, 160, 0.1).
const lightTerm = (nl, P) => P.light_diffuse * nl + P.light_specular * Math.pow(nl, P.light_shininess) + P.light_ambient;
// shade: the colour branches of fragment(), mandelbox.gdshader:371-458, from ce, the raw nl =
// |dot(n, ldir)|, the normal n, h = v/2, the camera basis (modes 14 and 15 use view space) and the look
// knobs in P (lighting, the Palette mode, then exposure and saturation, each skipped at its default).
function shade(mode, ce, lgtRaw, n, h, cam, P = LOOK_P) {
  const inv = 1 - ce;
  if (mode === 0) return [inv, inv, inv];
  const col = shadeMode(mode, ce, lightTerm(lgtRaw, P), n, h, cam, P);
  let c = col;
  if (P.exposure !== 1) c = c.map(v => v * P.exposure);
  if (P.saturation !== 1) { const l = c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114; c = c.map(v => l + (v - l) * P.saturation); }
  return c;
}
function shadeMode(mode, ce, lgt, n, h, cam, P) {
  const inv = 1 - ce;
  const base = [lgt * (-n[0] * 0.25 + 0.75), lgt * (-n[1] * 0.25 + 0.75), lgt * (-n[2] * 0.25 + 0.75) + 0.2];
  const avg = (base[0] + base[1] + base[2]) / 3;
  switch (mode) {
    case 1: return [base[0] * (inv + 0.5), base[1] * (2 * inv * inv + 0.5), base[2] * (5 * Math.pow(inv, 4) + 0.5)];
    case 2: return [base[0] * Math.max(lgt * ce, inv), base[1] * Math.max(ce, inv), base[2] * Math.max(0.5 * lgt * ce, inv)];
    case 3: { const c = hue(dot(h, h) / 4); return c.map(v => v * ce + 0.5 * lgt); }
    case 4: { const c = hue(dot(h, h) / 4); return c.map(v => v * inv); }
    case 8: { const c = hue(n[2] * 0.5 + 0.5 - 0.1); return c.map(v => v * inv); }
    case 5: return [base[0] * lgt * Math.max(lgt * ce, inv), base[1] * (lgt + avg), base[2] * (inv + lgt)];
    case 6: return [base[0] * lgt * Math.max(lgt * ce, inv) + ce * ce, base[1] * (lgt + avg) + ce * ce, base[2] * (inv + lgt) + ce * ce];
    case 7: return [1 - 2 * ce * (lgt + 0.5), avg * inv, inv * (lgt + 0.5)];
    case 9: return [inv * inv, 1 - 1.9 * ce * ce, 1.17 - ce * ce];
    case 16: return [inv * inv, 1 - 1.9 * ce * ce, 1.17 - ce * ce].map(v => clamp(v, 0, 1) * (lgt + 0.5));
    case 15: {
      const nv = [dot(n, cam.right), dot(n, cam.up), -dot(n, cam.fwd)], lv = Math.pow(Math.max(0, nv[2]), 4);
      const n2v = norm([nv[0] + 0.5, nv[1] + 0.5, nv[2]]), m = lv - 2 * ce + 0.5;
      return n2v.map(v => (v + 1) * 0.5 * m);
    }
    case 14: {
      const nv = [dot(n, cam.right), dot(n, cam.up), -dot(n, cam.fwd)], lv = Math.pow(Math.max(0, nv[2]), 4);
      const m = (0.75 - ce) * 2;
      return [m * lv, m * lv * lv, m * lv * ce];
    }
    case 20: {
      const src = P.palette_source === 1 ? dot(h, h) / 4 : P.palette_source === 2 ? n[2] * 0.5 + 0.5 : ce;
      const x = src * P.palette_frequency + P.palette_offset, pt = x - Math.floor(x);
      const occ = 1 + (inv - 1) * P.palette_occlusion;
      return palette(pt, P).map(v => v * (lgt + 0.5) * occ);
    }
    default: return [inv, inv, inv];
  }
}
// rotate_about: mandelbox.gdshader:290-295, Rodrigues' rotation of v by deg about the unit axis k.
function rotateAbout(v, k, deg) {
  const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r), kv = dot(k, v), kx = cross(k, v);
  return [0, 1, 2].map(i => v[i] * c + kx[i] * s + k[i] * kv * (1 - c));
}
const mixRGB = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];

// One pixel of fragment(), mandelbox.gdshader:314-463: the ray from UV (239-243), the background
// (245-248), the march, then normal choice (303), light (309-312), colour and the fog mix (353).
function renderPixel(cam, P, ux, uy, aspect) {
  const nx = (ux - 0.5) * 2, ny = -(uy - 0.5) * 2;
  const dir = norm([0, 1, 2].map(a => cam.fwd[a] + nx * aspect * TAN_HALF_FOV * cam.right[a] + ny * TAN_HALF_FOV * cam.up[a]));
  const bg = P.fog > 0 ? P.fogColor : P.color_mode === 5 || P.color_mode === 6 ? [1, 1, 1] : [0, 0, 0];
  const m = march(cam.eye, dir, P);
  if (m.miss || m.left) return { rgb: bg, m, bg: true };
  const fa = fogAmount(P, m.total, m.near);
  if (P.color_mode === 0) return { rgb: mixRGB([1 - m.ce, 1 - m.ce, 1 - m.ce], P.fogColor, fa), m, fa };
  const v = add(cam.eye, dir, m.total), h = v.map(x => x * 0.5), eh = cam.eye.map(x => x * 0.5);
  const delta = hitEps(P, m.total, m.near) * 40;
  const useNF = P.color_mode >= 1 && P.color_mode <= 9 && !P.julia_all;
  const n = useNF ? calcNF(v, h, P) : calcNormal(v, delta, P);
  let ldir = norm([2 * eh[0] - h[0], 2 * eh[1] - h[1], 2 * eh[2] - h[2]]);
  if (P.light_yaw !== 0 || P.light_pitch !== 0) ldir = rotateAbout(rotateAbout(ldir, cam.up, P.light_yaw), cam.right, P.light_pitch);
  return { rgb: mixRGB(shade(P.color_mode, m.ce, Math.abs(dot(n, ldir)), n, h, cam, P), P.fogColor, fa), m, n, useNF, fa };
}

// Transform3D.looking_at(target, +Z) as CameraState.make_default builds it (camera_state.gd:42-46):
// forward = −basis.z, right = basis.x, up = basis.y.
function lookAt(eye, target, upHint) {
  const fwd = norm([target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]]);
  const z = fwd.map(v => -v), right = norm(cross(upHint || [0, 0, 1], z)), up = cross(z, right);
  return { eye: eye.slice(), fwd, right, up };
}
const DEFAULT_CAM = lookAt(DEFAULT_EYE, [0, 0, 0]);

// flySpeed: fly_camera.gd:139-144, speed = clamp(D(eye), 1e-6, 20) · speed_factor · speed_limit,
// ×SPRINT_MULTIPLIER (2, line 16) while Shift is held. speed_limit is the shed level's `speed`.
function flySpeed(eye, P, speedFactor, limit = 1, sprint = false) {
  return clamp(de(eye[0], eye[1], eye[2], 32, P), 1e-6, 20) * speedFactor * limit * (sprint ? 2 : 1);
}
// The wheel: fly_camera.gd:153-155, ×1.25 per tick up, ÷1.25 down, clamped to [0.01, 100].
function scrollFactor(f, up) { return clamp(f * (up ? 1.25 : 1 / 1.25), 0.01, 100); }

// apply_look: fly_camera.gd:106-118 (yaw about world +Z keeps pitch; pitch clamped to ±89°).
const MAX_FORWARD_Z = 0.9998476951563913;
function rotZ(v, a) { const c = Math.cos(a), s = Math.sin(a); return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]]; }
function applyLook(cam, dx, dy, sens) {
  if (dx === 0 && dy === 0) return cam;                       // line 70: a zero delta is no change
  const fwd = rotZ(cam.fwd, -dx * sens * Math.PI / 180);
  const maxPitch = Math.asin(MAX_FORWARD_Z);
  const pitchNew = clamp(Math.asin(clamp(fwd[2], -1, 1)) + (-dy * sens * Math.PI / 180), -maxPitch, maxPitch);
  let horiz = [fwd[0], fwd[1], 0];
  const hl = Math.hypot(horiz[0], horiz[1]);
  horiz = hl > 1e-9 ? [horiz[0] / hl, horiz[1] / hl, 0] : norm([cam.right[1], -cam.right[0], 0]);
  const f = add(horiz.map(v => v * Math.cos(pitchNew)), [0, 0, 1], Math.sin(pitchNew));
  return lookAt(cam.eye, add(cam.eye, f), [0, 0, 1]);
}

// LoadShedder.step: load_shedder.gd:62-91, on a plain record (level, restoreDwell, slow, fast and the
// three "since" timers). Returns "shed", "restored" or "".
const SHED = { SHED_FPS: 24, RESTORE_FPS: 40, SHED_DWELL: 0.5, SHED_COOLDOWN: 1, RESTORE_DWELL: 2, RESTORE_DWELL_MAX: 16,
  FLAP_WINDOW: 5, CALM_RESET: 10, EPS: 1e-6 };                      // load_shedder.gd:22-30
function newShedder() { return { level: 0, restoreDwell: SHED.RESTORE_DWELL, slow: 0, fast: 0, sinceChange: SHED.SHED_COOLDOWN, sinceRestore: Infinity, sinceShed: Infinity }; }
function shedderStep(S, ft, ema, canShed) {
  S.sinceChange += ft; S.sinceRestore += ft; S.sinceShed += ft;
  const fps = 1 / Math.max(ema, 1e-6);
  S.slow = fps < SHED.SHED_FPS && canShed && S.level < 4 ? S.slow + ft : 0;
  S.fast = fps > SHED.RESTORE_FPS && S.level > 0 ? S.fast + ft : 0;
  if (S.sinceRestore < S.sinceShed && S.sinceRestore >= SHED.CALM_RESET - SHED.EPS) S.restoreDwell = SHED.RESTORE_DWELL;
  const changed = () => { S.slow = 0; S.fast = 0; S.sinceChange = 0; };
  if (S.slow >= SHED.SHED_DWELL - SHED.EPS && S.sinceChange >= SHED.SHED_COOLDOWN - SHED.EPS) {
    if (S.sinceRestore < SHED.FLAP_WINDOW) S.restoreDwell = Math.min(S.restoreDwell * 2, SHED.RESTORE_DWELL_MAX);
    S.level++; S.sinceShed = 0; changed();
    return "shed";
  }
  if (S.fast >= S.restoreDwell - SHED.EPS) { S.level--; S.sinceRestore = 0; changed(); return "restored"; }
  return "";
}

// governorStep: resolution_governor.gd:96-131, on a plain record G. Modes as the enum at line 15.
// minScale is min_scale (line 24), which follows FractalParams.min_render_scale (lines 49-51).
const MODE = { CONTINUOUS: 0, SETTLING: 1, FINAL_FRAME: 2, IDLE: 3 }, MODE_NAMES = ["CONTINUOUS", "SETTLING", "FINAL_FRAME", "IDLE"];
const GOV = { TARGET: 1 / 30, EMA_ALPHA: 0.2, STEP: 0.8 };
function newGovernor() {
  return { scale: 1, mode: MODE.IDLE, fast: true, minScale: 0.25, cooldown: 0.5, settle: 0.15, ema: GOV.TARGET, since: 0.5,
    idlePending: false, quiet: 0, moving: 1, shed: newShedder() };
}
function governorStep(G, ft, changing) {
  const why = [];
  G.since += ft;
  if (changing) {
    if (G.mode === MODE.FINAL_FRAME || G.mode === MODE.IDLE) G.scale = G.moving;   // resume, not 1.0 (99-100)
    G.scale = Math.max(G.scale, G.minScale);
    G.mode = MODE.CONTINUOUS;
    G.idlePending = true;
    G.quiet = 0;
    if (G.fast) {
      G.ema = G.ema * (1 - GOV.EMA_ALPHA) + ft * GOV.EMA_ALPHA;
      if (G.since >= G.cooldown) {
        if (G.ema > 1.2 * GOV.TARGET && G.scale > G.minScale) { G.scale = clamp(G.scale * GOV.STEP, G.minScale, 1); G.since = 0; why.push("lowered"); }
        else if (G.ema < 0.6 * GOV.TARGET && G.scale < 1 && G.shed.level === 0) { G.scale = clamp(G.scale / GOV.STEP, G.minScale, 1); G.since = 0; why.push("raised"); }
      } else why.push("cooling down");
      const s = shedderStep(G.shed, ft, G.ema, G.scale <= G.minScale);
      if (s) why.push(s === "shed" ? `shed to level ${G.shed.level}` : `restored to level ${G.shed.level}`);
    } else {
      G.scale = 1;
      if (G.shed.level !== 0) { G.shed = newShedder(); why.push("shedder reset"); }
    }
    G.moving = G.scale;
  } else if (G.idlePending) {
    G.quiet += ft;
    if (G.quiet >= G.settle) { G.mode = MODE.FINAL_FRAME; G.scale = 1; G.idlePending = false; }
    else G.mode = MODE.SETTLING;
  } else {
    G.scale = Math.max(G.scale, G.minScale);
    G.mode = MODE.IDLE;
  }
  return why;
}
// applied_level: resolution_governor.gd:60-63, the shed level the view renders at.
const appliedLevel = G => (G.mode === MODE.CONTINUOUS || G.mode === MODE.SETTLING ? G.shed.level : 0);

// ================================================================== the fixture self-check
// Every fixture tests/distance_estimator_test.gd pins, with the same tolerance (line 12): relative
// 1e-5, absolute 1e-9. The 24 site-measured ones (lines 18-51), then the five that pin the 4D knobs
// (lines 73-88): a positive scale, Sphere → Box, one iteration rotation, a non-zero w, a Julia mix.
const FIX_POINTS = [[0, 0, 0], [0.5, 0.5, 0.5], [1.2, -0.3, 0.8], [2, 2, 2], [3, 0, 0], [8.18, 3.81, 3.28], [0.1, 0.9, 1.5], [-1.5, 1.5, -1.5]];
const FIXTURES = [
  { name: "defaults", P: params(), line: 18,
    want: [0, 1.67e-15, 4.536385e-5, 1.84e-20, 1.0000000, 6.5655845, 1.2707534e-5, 7.2696999e-3] },
  { name: "alternative shape", P: params({ box_scale: -3, min_radius: 0.5, fold_limit: 0.8, fixed_radius: 0.9 }), line: 29,
    want: [0, 3.9589733e-3, 7.3684211e-2, 0.69282032, 1.4000000, 7.1416315, 1.2998357e-2, 3.5649260e-3] },
  { name: "Julia (all)", P: params({ julia_all: true }), line: 41,
    want: [4.9979908e-3, 1.0887837e-2, 4.5308936e-3, 4.9979908e-3, 8.0696204e-3, 2.3521820, 3.6647735e-3, 0.25217396] },
].flatMap(set => set.want.map((want, i) => ({ name: set.name, P: set.P, p: FIX_POINTS[i], want, line: set.line }))).concat([
  { name: "positive scale", P: params({ box_scale: 2 }), p: [1.2, -0.3, 0.8], want: 2.5e-13, line: 75 },
  { name: "positive scale", P: params({ box_scale: 2 }), p: [0.5, 0.5, 0.5], want: 1.0e-14, line: 76 },
  { name: "Sphere → Box", P: params({ fold_order: 1 }), p: [1.2, -0.3, 0.8], want: 1.280467e-8, line: 79 },
  { name: "iter_rot_xy 30°", P: params({ rot: [30, 0, 0, 0, 0, 0] }), p: [1.2, -0.3, 0.8], want: 2.062593788e-4, line: 82 },
  { name: "w = 0.5", P: params({ w: 0.5 }), p: [1.2, -0.3, 0.8], want: 6.280428097e-5, line: 85 },
  { name: "Julia x and z", P: params({ julia: [true, false, true, false] }), p: [1.2, -0.3, 0.8], want: 2.02335288439e-3, line: 88 },
]);
const FIX = (function () {
  const fails = [];
  let worst = 0;
  for (const f of FIXTURES) {
    const got = de(f.p[0], f.p[1], f.p[2], 32, f.P), tol = Math.max(1e-9, 1e-5 * Math.abs(f.want));
    if (Math.abs(f.want) > 1e-6) worst = Math.max(worst, Math.abs(got - f.want) / Math.abs(f.want));
    if (!(Math.abs(got - f.want) <= tol)) fails.push(`${f.name} (${f.p.join(", ")}): want ${f.want}, port gives ${got}`);
  }
  if (fails.length) {
    const msg = `[mandelbox fixtures] the de() port fails ${fails.length} of ${FIXTURES.length} fixtures: ${fails.join("; ")}`;
    console.error(msg);
    if (typeof VIZ !== "undefined" && Array.isArray(VIZ.errors)) VIZ.errors.push(msg);
  }
  return { n: FIXTURES.length, fails, worst };
})();

// ================================================================== shared drawing helpers
const fmt = (x, n = 3) => { if (!isFinite(x)) return String(x); const s = x.toFixed(n); return /^-0\.?0*$/.test(s) ? s.slice(1) : s; };
const sci = (x, n = 3) => (x === 0 ? "0" : !isFinite(x) ? String(x) : (Math.abs(x) >= 1e-3 && Math.abs(x) < 1e4) ? fmt(x, n + 1) : x.toExponential(n));
const vec = (v, n = 3) => `(${v.map(x => sci(x, n)).join(", ")})`;
const caps = "font-weight:600;letter-spacing:.06em";
const small = "font-size:10.5px";
const noPtr = "pointer-events:none";

// Theme colours for canvas pixels: read the page's CSS variables when drawing.
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

// A canvas filled a few rows per animation frame (about 4 ms of rows, then a flush every other
// frame), so a 160² recompute never costs a long frame. pixel(i, j) returns [r, g, b] (0..255) for
// column i, row j (row 0 at the top).
function chunkedImage(api, opts, pixel) {
  const surf = api.image(opts), img = surf.ctx.createImageData(opts.pw, opts.ph);
  let row = -1, gen = 0, onDone = null, tick = 0;
  const job = {
    surf,
    busy: () => row >= 0,
    restart(done) { row = 0; gen++; onDone = done || null; },
    progress: () => (row < 0 ? 1 : row / opts.ph),
  };
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

// A row of stage boxes across the top of a stepper (fog-sim's pattern): each box tips to its lines;
// set(i) outlines the current one.
function stageRow(api, x0, y0, boxW, gap, stages) {
  const boxes = stages.map((st, i) => {
    const x = x0 + i * (boxW + gap);
    const r = api.el("rect", { x, y: y0, width: boxW, height: 52, rx: 6, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:pointer" });
    api.text(x + 10, y0 + 19, st.n, "mono", { style: `fill:${st.color || "var(--muted)"};font-weight:700;${noPtr}` });
    api.text(x + 30, y0 + 19, st.name, "ink", { style: `font-weight:600;${noPtr}` });
    api.text(x + 10, y0 + 39, st.f, "mono", { style: `font-size:11px;${noPtr}` });
    api.tip(r, Object.assign({ title: st.name, sub: st.f }, st.tip));
    return r;
  });
  return {
    set(i) {
      boxes.forEach((r, k) => r.setAttribute("style", `fill:var(--surface);stroke:${k === i ? (stages[k].color || "var(--c1)") : "var(--hairline)"};stroke-width:${k === i ? 2.6 : 1.2};cursor:pointer`));
    },
  };
}

// Draggable SVG handle (the engine treats [data-interactive] as content, so dragging never pans).
function draggable(api, elem, onDrag) {
  elem.setAttribute("data-interactive", "");
  let drag = false;
  elem.addEventListener("mousedown", e => { e.stopPropagation(); e.preventDefault(); drag = true; });
  window.addEventListener("mousemove", e => { if (drag) onDrag(api.local(e)); });
  window.addEventListener("mouseup", () => { drag = false; });
}

// Plane slices. axisPlane: the X-Y / X-Z / Y-Z planes at an offset; (a, b) are the plane's two axes.
const AXES = { xy: ["x", "y", "z"], xz: ["x", "z", "y"], yz: ["y", "z", "x"] };
function axisPoint(axes, a, b, off) {
  const p = { x: 0, y: 0, z: 0 };
  p[AXES[axes][0]] = a; p[AXES[axes][1]] = b; p[AXES[axes][2]] = off;
  return [p.x, p.y, p.z];
}
// The vertical plane through the default eye and the world Z axis: u along the eye's heading, w = z.
const SLICE_U = norm([DEFAULT_EYE[0], DEFAULT_EYE[1], 0]);
const toSlice = p => [p[0] * SLICE_U[0] + p[1] * SLICE_U[1], p[2]];
const fromSlice = (u, w) => [SLICE_U[0] * u, SLICE_U[1] * u, w];

// ================================================================== 1. architecture graph
const arch = {
  type: "graph",
  tab: "Architecture",
  title: "Who talks to whom",
  note: "Everything that draws reads two Resources, FractalParams and CameraState. The shape values in FractalParams are no longer edited directly: each frame Main resolves the AttributeTable (defaults + bindings), the axis values and the clock into them with one `apply_resolved` (the console pane opens that layer up). Cameras write CameraState; the console's View tab writes FractalParams' preference fields; `changed` fans out to the view, the governor, the marker and Main. The shader never knows about the console and the console never knows about the shader. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "input", label: "INPUT — MAIN, THE VIEW TAB, THE FILE PANELS", x: 0, y: 0, w: 700, h: 230 },
    { id: "files", label: "FILES", x: 0, y: 280, w: 700, h: 220 },
    { id: "shape", label: "SHAPE — RESOLVED EVERY FRAME (THE CONSOLE PANE)", x: 0, y: 550, w: 700, h: 330 },
    { id: "state", label: "STATE — THE TWO SHARED RESOURCES", x: 760, y: 0, w: 380, h: 430 },
    { id: "render", label: "RENDER", x: 1200, y: 0, w: 900, h: 430 },
    { id: "cameras", label: "CAMERAS", x: 760, y: 480, w: 1000, h: 170 },
    { id: "math", label: "CPU MATHS", x: 760, y: 700, w: 1000, h: 130 },
  ],
  nodes: [
    { id: "console", label: "ConsoleWindow", sub: "Shape inspector | Movement pane", ctx: "shape", zone: "shape", x: 330, y: 790, ...R("console", 1),
      blurb: "The debug console, a separate native OS window (`force_native`) on the desktop, embedded on the web and headless. Its Shape pane edits the table's defaults and bindings row by row; its Movement pane edits the keymap. It never writes FractalParams. Opened by a Ctrl tap; its View tab now holds what the pause menu did.",
      links: [RL("console", 62, "force_native"), RL("console", 58, "setup(table, keymap, clock, …)"), RL("main", 146, "Main builds it")] },
    { id: "table", label: "AttributeTable", sub: "MandelboxShape specs · defaults · bindings", ctx: "shape", zone: "shape", x: 30, y: 610, ...R("table", 1),
      blurb: "The canonical shape: one AttributeSpec per catalogue id (MandelboxShape: box, Julia, iteration rotation, render), a default each, and a Binding on every bindable knob. Saves store it; the console and the Julia marker write it.",
      links: [RL("shape", 56, "MandelboxShape.specs()"), RL("main", 68, "built from the catalogue"), RL("table", 51, "set_default")] },
    { id: "clock", label: "Clock", sub: "t, seconds since opening", ctx: "shape", zone: "shape", x: 520, y: 700, ...R("clock", 1),
      blurb: "`t += delta` every `_process`, never saved (nothing pauses the tree any more). The source a `Time` binding reads.",
      links: [RL("clock", 11, "t += delta")] },
    { id: "keymap", label: "Keymap · Axes", sub: "key pairs → InputMap · axis values", ctx: "shape", zone: "shape", x: 30, y: 700, ...R("keymap", 1),
      blurb: "The virtual axes (unbounded floats) and the key pair that pushes each, loaded from saves/keymap.json (Q/E push Axis A by default). Each pair is registered as two InputMap actions, so held keys need no special code.",
      links: [RL("keymap", 23, "axes()"), RL("keymap", 113, "load_file"), RL("main", 70, "loaded at startup")] },
    { id: "axisCtl", label: "AxisController", sub: "steps axes from held keys", ctx: "shape", zone: "shape", x: 30, y: 790, ...R("axisCtl", 1),
      blurb: "Every `_process`: for each axis, the strength of its two actions → `axes().step(id, direction, delta)`, unless a text field has focus in any window.",
      links: [RL("axisCtl", 28, "step"), RL("main", 163, "given the focus viewports")] },
    { id: "resolve", label: "Main._resolve_once", sub: "resolve → apply_resolved", ctx: "shape", zone: "shape", x: 420, y: 610, ...R("main", 264),
      blurb: "Every frame (`_process`), and straight after a load: `BindingResolver.resolve(table, axes.values(), clock.t)` gives every catalogue id its value (default + gain × wave(source) for an active binding), and `params.apply_resolved(values)` writes them. About thirty scalars, so it runs unconditionally.",
      links: [RL("main", 253, "_process"), RL("resolver", 13, "resolve"), RL("main", 295, "after a load")] },

    { id: "dispatch", label: "Main._unhandled_input", sub: "the one input dispatcher", ctx: "input", zone: "input", x: 280, y: 150, ...R("main", 410),
      blurb: "The only mouse and shortcut dispatcher, in a fixed order: a Ctrl tap toggles the console, Escape frees the mouse, Cmd/Ctrl+P copies a screenshot, N toggles the noise editor, a Julia marker drag, a click while free in FLY recaptures, everything else to the active camera. The next tab walks the order." },
    { id: "mode", label: "Main._apply_mode", sub: "camera + mouse capture", ctx: "input", zone: "input", x: 500, y: 150, ...R("main", 357),
      blurb: "Runs on every FractalParams change: enables exactly one camera from `camera_mode`, calls the orbit's `enter()` only on a real switch (not on every resolved frame), then `_update_mouse`: captured in FLY unless Escape, a Ctrl tap or a file panel has freed it, or the noise editor is open. The console's visibility does not gate capture, and nothing pauses.",
      links: [RL("main", 362, "enter() only on a real switch"), RL("main", 368, "_update_mouse")] },
    { id: "viewPane", label: "ViewPane", sub: "console View tab: Save/Load · Camera · Renderer", ctx: "input", zone: "input", x: 30, y: 60, ...R("viewPane", 1),
      blurb: "The console's View tab took everything the old pause menu held (which had taken it from the retired Q panel): Save view… / Load view… with the current file and the status line, the Camera mode, the mouse sensitivity, Noise editor…, the Renderer options (with Fast Controls and Reset camera) and Back to Menu. It hands each choice back through signals; Main owns the files, the noise window and the scene change.",
      links: [RL("main", 191, "_build_view_pane"), RL("viewPane", 148, "the Camera row"), RL("viewPane", 101, "the Renderer options")] },
    { id: "renderer", label: "RendererOptions", sub: "View tab ▸ Renderer options", ctx: "input", zone: "input", x: 380, y: 60, ...R("renderer", 1),
      blurb: "Edits the open view's level of detail (`detail`, `detail_range`, `detail_falloff`), the step budget `max_steps`, `min_render_scale` and Fast Controls, all saved with the view, plus Reset camera. It lives in the console's View tab now (the title menu's Settings lost its Renderer tab), so every edit renders live behind the console.",
      links: [RL("renderer", 62, "the writes"), RL("viewPane", 101, "in the View tab"), RL("main", 195, "Reset camera")] },
    { id: "wsf", label: "WorkspaceFiles", sub: "file panels · current file · ⌘S", ctx: "input", zone: "input", x: 30, y: 150, ...R("wsf", 1),
      blurb: "Owns the two file panels and the current file's path, nothing else: it never reads or writes a save. The View tab's Save / Load buttons open them; picking a file emits `save_to` / `load_from`; ⌘S saves over the current file. It keeps processing while the tree is paused, or Godot's own panel would ignore every key.",
      links: [RL("wsf", 11, "signals"), RL("wsf", 114, "quick_save")] },

    { id: "msave", label: "Main save / load", sub: "save_view_to · load_view_from", ctx: "input", zone: "files", x: 30, y: 340, ...R("main", 273),
      blurb: "Main does the saving and loading the file panels ask for, through Workspace, and only then marks the file current. After a load it resolves once (so the loaded table reaches FractalParams this frame), applies the noise section, and in ORBIT re-runs `enter()`.",
      links: [RL("main", 284, "load_view_from"), RL("main", 295, "resolve after a load"), RL("main", 301, "re-centre after a load")] },
    { id: "ws", label: "Workspace", sub: "capture · restore · JSON v2", ctx: "input", zone: "files", x: 290, y: 340, ...R("ws", 1),
      blurb: "Saves and loads a view as version-2 JSON: the table (defaults + active bindings), the axis values, the non-shape `fractal` keys and the camera. Unknown ids warn and are skipped; a version-1 file is migrated to the new ids without a warning.",
      links: [RL("ws", 31, "capture"), RL("ws", 56, "restore"), RL("ws", 181, "_migrate_v1")] },
    { id: "saves", label: "saves/*.json", sub: "the committed views", ctx: "input", zone: "files", x: 30, y: 420, ...R("saveDef", 1),
      blurb: "default.json, juliaIceField.json, juliaIceTerraces.json (tab 4 loads their values), noiseRidges.json and keymap.json. A source build saves into `res://saves/`; an exported build cannot write into its PCK, so it uses `user://saves/`.",
      links: [RL("saveField", 1, "juliaIceField.json"), RL("saveTer", 1, "juliaIceTerraces.json"), RL("wsf", 19, "REPO_DIR / EXPORT_DIR")] },

    { id: "params", label: "FractalParams", sub: "Resource · resolved shape + renderer options", ctx: "state", zone: "state", x: 800, y: 110, ...R("params", 1),
      blurb: "Every value the renderer, the cameras and the governor read. The shape fields are the RESOLVED knob values, named by catalogue id (= the uniform names) and written once per frame by `apply_resolved`, which emits `changed` at most once and only when something differed. The preference and renderer fields are still set directly, each setter emitting.",
      links: [RL("params", 24, "RESOLVED_KEYS"), RL("params", 334, "apply_resolved"), RL("params", 207, "the renderer options"), RL("tParams", 62, "emits once test")] },
    { id: "camState", label: "CameraState", sub: "Resource · Transform3D + speed_factor", ctx: "state", zone: "state", x: 800, y: 300, ...R("cam", 1),
      blurb: "The camera as a Transform3D in Godot's convention: forward = −basis.z, right = basis.x, up = basis.y. Plus the fly speed multiplier. Both setters emit `changed` only when the value actually differs, so stray input that re-assigns the same transform never wakes the governor.",
      links: [RL("cam", 13, "the equality guard"), RL("cam", 29, "forward()"), RL("cam", 42, "make_default")] },

    { id: "view", label: "FractalView", sub: "uniforms · project / unproject", ctx: "render", zone: "render", x: 1230, y: 80, ...R("view", 1),
      blurb: "Pushes the two Resources into the shader as uniforms (each shape field under its own name), sizes the SubViewport in physical pixels from `render_scale` and the window's HiDPI factor, applies the governor's load-shed level, and owns the ray maths (`project` / `unproject`) so the marker and the orbit camera agree with the shader exactly.",
      links: [RL("view", 331, "_push_params"), RL("view", 385, "_push_near: near_dist = D(eye)"), RL("view", 223, "set_load_level"), RL("view", 249, "project"), RL("view", 264, "unproject")] },
    { id: "noise", label: "NoiseWindow", sub: "noise graph → spliced shader", ctx: "render", zone: "render", x: 1230, y: 205, ...R("noise", 1),
      blurb: "The noise editor (N). Its graph is compiled into the shader between the NOISE markers (displacement, step scale, tint); with nothing wired to the Output the view swaps back to the original shader resource, so the picture and cost are as if it did not exist.",
      links: [RL("view", 110, "set_noise_graph"), RL("view", 147, "_rebuild_noise"), RL("sh", 103, "the NOISE stub")] },
    { id: "sub", label: "SubViewport", sub: "window × render_scale × HiDPI", ctx: "render", zone: "render", x: 1500, y: 80, ...R("viewScn", 22),
      blurb: "The render target, sized in physical pixels: the window × `render_scale` × the window's content scale (UiScale), so a still frame is sharp on a Retina screen. Its update mode (ALWAYS / ONCE / DISABLED) is how the governor freezes rendering.",
      links: [RL("view", 282, "_apply_size"), RL("view", 298, "_content_scale")] },
    { id: "rect", label: "ColorRect + mandelbox.gdshader", sub: "fragment(): march + shade", ctx: "render", zone: "render", x: 1500, y: 230, ...SH(314),
      blurb: "A canvas_item shader on a ColorRect filling the SubViewport: one fragment per pixel builds its ray, marches the 4D Mandelbox slice in two phases and colours the hit, fading into fog when the governor has shed load. All of it float32 (WebGL 2).",
      links: [RL("viewScn", 28, "the ColorRect in the scene"), RL("sh", 201, "mb_step"), RL("sh", 220, "de")] },
    { id: "tex", label: "TextureRect (Display)", sub: "stretched to the window", ctx: "render", zone: "render", x: 1800, y: 80, ...R("view", 57),
      blurb: "Shows the SubViewport's texture stretched to fill the window (`EXPAND_IGNORE_SIZE`, `STRETCH_SCALE`), so a quarter-scale render still covers the screen while you move.",
      links: [RL("viewScn", 16, "the Display node")] },
    { id: "gov", label: "ResolutionGovernor", sub: "render_scale · update mode · shed level", ctx: "render", zone: "render", x: 1230, y: 330, ...R("gov", 1),
      blurb: "While anything changes it renders continuously and adapts `render_scale` to hold ~30 fps; with the scale at its floor its LoadShedder brings in fog and cheaper detail. After 0.15 s of quiet it renders one full-scale, full-quality frame, then freezes. Its `step()` is pure and is stepped live in tab 9.",
      links: [RL("gov", 96, "step()"), RL("gov", 29, "settle"), RL("tGov", 5, "the test")] },
    { id: "shedder", label: "LoadShedder", sub: "fog · detail · steps · speed rungs", ctx: "render", zone: "render", x: 1580, y: 340, ...R("shed", 1),
      blurb: "Four rungs below full quality: fog at 400 → 40 × near_dist, detail ×0.75 → ×0.35, the step budget down to half, and at the top a Fly speed cap of 0.4. Sticky: shedding needs 0.5 s under 24 fps, restoring 2 s over 40 fps, doubling after a flap.",
      links: [RL("shed", 14, "LEVELS"), RL("shed", 62, "step"), RL("tShed", 24, "the test")] },

    { id: "fly", label: "FlyCamera", sub: "mouse-look · WASD · distance-scaled speed", ctx: "camera", zone: "cameras", x: 790, y: 540, ...R("fly", 1),
      blurb: "Yaw about world +Z, pitch about its own right clamped 1° off ±Z, never roll. Moves every physics tick at `clamp(D(eye), 1e-6, 20) · speed_factor · speed_limit`, ×2 while Shift sprints, so a second of flight covers about the gap to the nearest surface. Refuses a move that would end closer to the surface than `zoom_floor` (the 32-bit limit) unless it is no closer than now, and raises `at_zoom_limit` for the console. Silent while a text field has focus.",
      links: [RL("fly", 106, "apply_look"), RL("fly", 139, "current_speed"), RL("fly", 127, "TextFocus"), RL("fly", 95, "move_allowed: the zoom guard")] },
    { id: "orbit", label: "OrbitCamera", sub: "drag to orbit · click to re-centre", ctx: "camera", zone: "cameras", x: 1120, y: 540, ...R("orbit", 1),
      blurb: "The site's orbit controller: keeps a `center`; left-drag orbits it, Shift pans, right/Alt dollies, the wheel moves toward the cursor, a click re-centres on a CPU-marched hit. The mouse is never captured.",
      links: [RL("orbit", 9, "the gesture constants"), RL("orbit", 155, "_march")] },
    { id: "marker", label: "JuliaMarker", sub: "drags the Julia constant", ctx: "camera", zone: "cameras", x: 1450, y: 540, ...R("marker", 1),
      blurb: "A ring drawn at `project(julia_point())` (c_0..c_2) while Julia (all) is on. A press on it captures the point's camera depth; dragging writes `unproject(mouse, depth)` into the TABLE's c_0..c_2 defaults (so the next resolve keeps it) and mirrors it into FractalParams at once.",
      links: [RL("marker", 41, "begin_drag"), RL("marker", 53, "update_drag")] },

    { id: "de", label: "DistanceEstimator", sub: "estimate_at · 64-bit scalar 4D orbit", ctx: "math", zone: "math", x: 1020, y: 760, ...R("de", 1),
      blurb: "The CPU copy of the shader's `de(p, 32)`: the same mb_step (folds in fold_order, the six-plane rotation, per-component Julia, w) in scalar 64-bit floats, not Vector math (32-bit), because lost input precision near the surface broke the near-boundary fixtures. Used for fly speed, orbit clicks and near_dist.",
      links: [RL("de", 10, "why scalars"), RL("tDE", 17, "the fixtures")] },
  ],
  edges: [
    { from: "console", to: "table", kind: "call", label: "defaults · bindings", ...R("table", 51), bow: 1,
      blurb: "Every Shape-pane row writes the table, never FractalParams: a slider or spin box `set_default`, a binding edit `set_binding`. The row re-reads itself on the table's `changed`.",
      links: [{ file: "src/ui/console/attribute_row.gd", line: 334, label: "attribute_row: set_default" }] },
    { from: "console", to: "keymap", kind: "call", label: "rebind · speed", ...R("keymap", 1), bow: -0.4,
      blurb: "The Movement pane writes through the Keymap API (`bind`, `set_speed`, `add_axis`, `remove_axis`, Save / Load) and refreshes on `changed`.",
      links: [{ file: "src/ui/console/movement_pane.gd", line: 268, label: "movement_pane: bind" }] },
    { from: "axisCtl", to: "keymap", kind: "call", label: "step", ...R("axisCtl", 28),
      blurb: "`axes().step(id, direction, delta)`: direction is the positive action's strength minus the negative's; the axis moves at its speed (units per second)." },
    { from: "table", to: "resolve", kind: "data", label: "defaults · bindings", ...R("main", 265) },
    { from: "keymap", to: "resolve", kind: "data", label: "axes().values()", ...R("main", 265) },
    { from: "clock", to: "resolve", kind: "data", label: "t", ...R("main", 265), bow: 0.5 },
    { from: "resolve", to: "params", kind: "call", label: "apply_resolved", ...R("main", 266),
      blurb: "Every resolved value in one batch: the setters are suppressed and `changed` fires once at the end, only if a value differed. A view with no active binding costs no signal per frame; one bound to Time changes every frame, which the governor rightly sees as animating.",
      links: [RL("params", 334, "apply_resolved")] },
    { from: "resolve", to: "console", kind: "call", label: "set_resolved", ...R("main", 268), bow: 0.6,
      blurb: "Only while the console is visible: bound rows show their live value under the slider." },
    { from: "marker", to: "table", kind: "call", label: "c_0..c_2", ...R("marker", 61), bow: -3,
      blurb: "The drag writes the table's defaults (the canonical shape), then mirrors them into FractalParams with `apply_resolved` so the picture follows this frame.",
      links: [RL("marker", 64, "the mirror"), RL("tMarker", 37, "the test")] },
    { from: "dispatch", to: "console", kind: "call", label: "Ctrl tap", ...R("main", 413), bow: -10,
      blurb: "`CtrlTap.feed` fires on a bare Ctrl press-and-release; `_on_console_toggle` frees the mouse and opens the console when captured, toggles it when free.",
      links: [RL("main", 384, "_on_console_toggle"), RL("ctrlTap", 21, "CtrlTap.feed")] },
    { from: "viewPane", to: "wsf", kind: "signal", label: "Save / Load view…", ...R("main", 197),
      blurb: "`save_requested` → `prompt_save`, `load_requested` → `prompt_load`.", links: [RL("main", 198, "load")] },
    { from: "renderer", to: "params", kind: "call", label: "LOD · steps · min scale", ...R("renderer", 62), bow: -0.5,
      blurb: "Each slider assigns one FractalParams field; the setters clamp to the documented ranges (fractal_params.gd:207-216)." },
    { from: "wsf", to: "msave", kind: "signal", label: "save_to / load_from", ...R("main", 240),
      blurb: "A picked file (or ⌘S on a current file) emits `save_to(path)` or `load_from(path)`; Main does the work." },
    { from: "msave", to: "ws", kind: "call", label: "save_file / load_file", ...R("main", 275), bow: 0,
      blurb: "`Workspace.save_file(path, table, axes, params, camera, noise)` and `load_file`; the result's warnings go to the View tab's status line.",
      links: [RL("main", 286, "load_file")] },
    { from: "ws", to: "saves", kind: "data", label: "JSON", ...R("ws", 108),
      blurb: "Written as indented JSON with `store_string`; read back with `JSON.new().parse()` so a bad file is a warning, not an engine error.",
      links: [RL("ws", 124, "the parse")] },
    { from: "ws", to: "table", kind: "call", label: "shape", ...R("ws", 61), bow: -0.6,
      blurb: "`table.apply_dict(shape)`: known ids set their default (sanitized), known bindings replace theirs; unknown ids warn. Axis values go to the keymap's axes the same way." },
    { from: "ws", to: "params", kind: "call", label: "fractal keys", ...R("ws", 91), bow: 0.4,
      blurb: "Only the non-shape keys (`fast_controls`, `camera_mode`, `mouse_sensitivity`, the renderer options) are written with `params.set`; the shape reaches FractalParams through the next resolve." },
    { from: "ws", to: "camState", kind: "call", ...R("ws", 241), bow: 0.6,
      blurb: "The camera is rebuilt with `looking_at(eye + forward, up)`, after rejecting a zero or degenerate orientation." },
    { from: "dispatch", to: "fly", kind: "call", label: "handle_event", ...R("main", 477),
      blurb: "The last step of the dispatcher: whatever is left goes to the active camera. In FLY: mouse-look while captured, the wheel scales the speed factor." },
    { from: "dispatch", to: "orbit", kind: "call", ...R("main", 477),
      blurb: "In ORBIT: drags, the wheel and clicks." },
    { from: "dispatch", to: "marker", kind: "call", label: "drag", ...R("main", 450), bow: 0.3,
      blurb: "While Julia (all) is on and the mouse is free, a left press that lands on the ring starts a drag, and motion during it moves the point.",
      links: [RL("main", 456, "update_drag")] },
    { from: "mode", to: "fly", kind: "call", label: "enabled", ...R("main", 359), bow: 0.5,
      blurb: "`fly.enabled = is_fly`. A disabled camera ignores events and its `_physics_process` returns at once." },
    { from: "mode", to: "orbit", kind: "call", label: "enter()", ...R("main", 363),
      blurb: "Only on a real switch into ORBIT: `enter()` centres on the surface hit by the centre ray (or the origin).",
      links: [RL("orbit", 76, "enter")] },
    { from: "fly", to: "camState", kind: "call", label: "transform", ...R("fly", 87),
      blurb: "Movement writes `transform.origin` every physics tick; mouse-look rebuilds the basis with `looking_at(eye + fwd, +Z)` (no roll). A zero mouse delta is ignored, so a resting captured mouse never re-renders.",
      links: [RL("fly", 162, "_set_forward"), RL("fly", 107, "zero delta ignored")] },
    { from: "orbit", to: "camState", kind: "call", label: "transform", ...R("orbit", 150),
      blurb: "Every gesture ends in `_look_from(eye)` (looking at `center`, +Z up), or moves the origin directly (pan, wheel)." },
    { from: "fly", to: "de", kind: "data", label: "D(eye)", ...R("fly", 148),
      blurb: "`base_speed()` asks the CPU estimator for the distance from the eye (the cap on the centre-ray speed), and while moving `move_allowed()` asks once more, at the candidate position, to hold the camera above `zoom_floor`.",
      links: [RL("fly", 148, "base_speed: D(eye)"), RL("fly", 96, "move_allowed: D(candidate)")] },
    { from: "orbit", to: "de", kind: "data", label: "CPU march", ...R("orbit", 164),
      blurb: "`_march` steps a single high-precision phase (up to 200 steps) for clicks and `enter()`." },
    { from: "view", to: "de", kind: "data", label: "near_dist", ...R("view", 388), bow: -0.4,
      blurb: "`near_dist = max(D(eye), 1e-6)`, refreshed on every camera and params push: the unit the level-of-detail range and the fog are measured in." },
    { from: "params", to: "view", kind: "signal", label: "uniforms", ...R("view", 91),
      blurb: "`_on_params_changed` → `_push_params` + `request_frame`.", links: [RL("view", 305, "_on_params_changed")] },
    { from: "params", to: "marker", kind: "signal", ...R("marker", 23), bow: 2,
      blurb: "Shows or hides the ring with Julia (all) and redraws it at the new point." },
    { from: "params", to: "mode", kind: "signal", label: "_apply_mode", ...R("main", 105),
      blurb: "Main re-applies the camera mode on every FractalParams change; `_last_mode` keeps it from re-centring the orbit on an animated frame or a slider move." },
    { from: "params", to: "gov", kind: "signal", label: "_dirty", ...R("gov", 46),
      blurb: "Any FractalParams change marks the governor dirty (this frame is 'changing') and re-reads `fast_controls` and `min_render_scale`." },
    { from: "camState", to: "view", kind: "signal", label: "eye, basis", ...R("view", 93),
      blurb: "`_on_camera_changed` → `_push_camera` (eye, right, up, forward, near_dist) + `request_frame`." },
    { from: "camState", to: "marker", kind: "signal", ...R("marker", 24),
      blurb: "The ring is re-projected whenever the camera moves." },
    { from: "camState", to: "gov", kind: "signal", label: "mark_changed", ...R("main", 106), bow: -0.3,
      blurb: "Main connects CameraState.changed to `governor.mark_changed()`: any camera move is a 'changing' frame." },
    { from: "gov", to: "view", kind: "call", label: "scale · mode · load level", ...R("gov", 78),
      blurb: "Every `_process`, only where something differs: `set_load_level(applied_level())`, `set_render_scale(scale)`, then by mode `set_continuous(true)`, or `set_continuous(false)` + `request_frame()`, or `set_continuous(false)`.",
      links: [RL("gov", 80, "render scale"), RL("gov", 82, "match mode")] },
    { from: "gov", to: "shedder", kind: "call", label: "step", ...R("gov", 115),
      blurb: "Fed the smoothed frame time while moving, with `can_shed` = the scale is at its floor, so resolution is always the first lever." },
    { from: "gov", to: "fly", kind: "signal", label: "speed_limit", ...R("main", 338), bow: -0.6,
      blurb: "`shed_level_changed` → Main sets `fly.speed_limit` to the level's `speed` (0.4 only at the top rung) and shows the level in the Movement pane.",
      links: [RL("gov", 74, "the signal")] },
    { from: "noise", to: "view", kind: "call", label: "set_noise_graph", ...R("noise", 134),
      blurb: "The editor hands the view its graph; the view recompiles on structural edits and only pushes uniforms on live ones." },
    { from: "view", to: "sub", kind: "call", label: "size · mode", ...R("view", 291),
      blurb: "`_apply_size` sets the viewport to the physical pixel size (and the `aspect` uniform); `request_frame` / `set_continuous` set its update mode.",
      links: [RL("view", 237, "UPDATE_ONCE"), RL("view", 244, "ALWAYS / DISABLED")] },
    { from: "view", to: "rect", kind: "data", label: "61 uniforms", ...R("view", 334),
      blurb: "`set_shader_parameter` for every uniform; the last tab lists each with where it comes from." },
    { from: "sub", to: "rect", kind: "call", label: "renders", ...R("viewScn", 28),
      blurb: "The ColorRect is the SubViewport's only child: rendering the viewport runs the shader once per pixel." },
    { from: "sub", to: "tex", kind: "data", label: "texture", ...R("view", 57),
      blurb: "`_display.texture = _viewport.get_texture()`." },
  ],
};

// ================================================================== 2. one input, one frame
const seq = {
  type: "seq",
  tab: "One input, one frame",
  title: "One input, one frame",
  note: "From an input event to pixels on screen, in order. Main dispatches input once; a camera writes CameraState. Then the frame's `_process` calls run in tree order: Main first, resolving the table, the axes and the clock into FractalParams with one `apply_resolved`; the governor next, deciding the render scale, the load-shed level and whether the SubViewport renders; the Clock and the AxisController last (their new values are resolved on the next frame). Every `changed` pushes uniforms and marks the governor dirty. When the motion stops, 0.15 s of quiet, one full-scale frame, then nothing renders.",
  laneWidth: 196, headWidth: 186,
  participants: [
    { id: "ev", col: 0, ctx: "input", name: "input event", sub: "mouse / key", blurb: "An InputEvent no Control consumed. A key the focused console or noise window did not use is forwarded to Main by `_on_window_key`, so the shortcuts work from either window.", ...R("main", 399) },
    { id: "main", col: 1, ctx: "input", name: "Main", sub: "_unhandled_input · _process", ...R("main", 410), blurb: "The single dispatcher, and the per-frame resolve." },
    { id: "cam", col: 2, ctx: "camera", name: "active camera", sub: "FlyCamera or OrbitCamera", ...R("main", 405), blurb: "`_active_camera()`: FlyCamera in FLY, OrbitCamera in ORBIT." },
    { id: "res", col: 3, ctx: "shape", name: "BindingResolver", sub: "table + axes + clock", ...R("resolver", 13), blurb: "A static function: every catalogue id's value from its default and binding (the console pane steps it)." },
    { id: "cs", col: 4, ctx: "state", name: "CameraState", sub: "Resource", ...R("cam", 1) },
    { id: "pa", col: 5, ctx: "state", name: "FractalParams", sub: "Resource", ...R("params", 1) },
    { id: "view", col: 6, ctx: "render", name: "FractalView", sub: "uniforms, viewport size", ...R("view", 1) },
    { id: "gov", col: 7, ctx: "render", name: "ResolutionGovernor", sub: "_process every frame", ...R("gov", 66) },
    { id: "sv", col: 8, ctx: "render", name: "SubViewport", sub: "runs the shader", ...R("viewScn", 22) },
    { id: "ax", col: 9, ctx: "shape", name: "Clock · AxisController", sub: "last in tree order", ...R("axisCtl", 19), blurb: "Children Main adds in `_ready`, after the scene's own nodes, so they process after Main and the governor." },
  ],
  rows: [
    { sec: "INPUT — Main._unhandled_input, in order; each step returns once it consumes the event" },
    { from: "ev", to: "main", kind: "call", label: "_unhandled_input(event)", ...R("main", 410),
      blurb: "Every unhandled event comes here first." },
    { from: "main", to: "main", kind: "call", label: "1 · Ctrl tap toggles the console", tick: "bare Ctrl down then up, not while typing", ...R("main", 412),
      blurb: "`CtrlTap.feed`: a bare non-echo Ctrl press arms, any other key disarms, the Ctrl release fires (so Ctrl+S still quick-saves). Captured: free the mouse and open the console. Free: toggle it, and recapture if that closed it. Its `typing_guard` ignores the tap while a text field has focus in any window.",
      links: [RL("ctrlTap", 21, "CtrlTap.feed"), RL("main", 103, "typing_guard"), RL("main", 384, "_on_console_toggle")] },
    { from: "main", to: "main", kind: "call", label: "2 · Escape · ⌘P · N", tick: "free the mouse · screenshot · noise editor", ...R("main", 419),
      blurb: "Escape (the `cancel` action) only frees the mouse: nothing pauses and the console and the noise window stay as they are, so a click in the view recaptures; Cmd/Ctrl+P copies the fractal to the clipboard; N toggles the noise editor unless a text field has focus.",
      links: [RL("main", 425, "copy_screenshot"), RL("main", 431, "N")] },
    { from: "main", to: "main", kind: "call", label: "3 · Julia marker drag", tick: "Julia (all) on, mouse free", ...R("main", 447),
      blurb: "A left press on the ring starts a drag (`begin_drag`), motion during it calls `update_drag` (which writes the table), a release ends it.",
      links: [RL("marker", 41, "begin_drag")] },
    { from: "main", to: "main", kind: "call", label: "4 · click to capture", tick: "FLY, mouse free · the console stays open", ...R("main", 464),
      blurb: "A left click on the view while the mouse is free in FLY recaptures it and closes the noise editor, leaving the console open so its readouts stay in sight. On the web, pointer lock only works from inside such a user gesture.",
      links: [RL("spec", 358, "spec: mouse capture")] },
    { from: "main", to: "cam", kind: "call", label: "5 · handle_event(event)", ...R("main", 477),
      blurb: "Everything else goes to the active camera; a consumed event is marked handled." },
    { from: "cam", to: "cs", kind: "call", label: "apply_look → transform", tick: "mouse motion while captured", ...R("fly", 106),
      blurb: "Yaw about world +Z, pitch about the camera's right clamped to ±89°, basis rebuilt with +Z as up (no roll). A zero delta (macOS sends them while a captured mouse rests) returns before touching the transform.",
      links: [RL("fly", 162, "looking_at"), RL("fly", 107, "zero delta")] },
    { from: "cam", to: "cs", kind: "call", label: "rotate / pan / dolly / zoom", tick: "drag · wheel · click", ...R("orbit", 150),
      blurb: "The orbit's gestures all end by writing the transform." },
    { from: "cs", to: "view", kind: "signal", label: "changed → _push_camera", tick: "only when the value differs · + request_frame()", ...R("view", 311),
      blurb: "Eye and basis become the `eye`, `cam_right`, `cam_up`, `cam_forward` uniforms, and `near_dist` is recomputed; `request_frame` asks for one render (unless already continuous). CameraState emits only on a real change.",
      links: [RL("view", 371, "_push_camera"), RL("cam", 13, "the equality guard")] },
    { from: "cs", to: "gov", kind: "signal", label: "changed → mark_changed()", ...R("main", 106),
      blurb: "Sets `_dirty`; the governor reads and clears it once per frame." },
    { sec: "PHYSICS — FlyCamera._physics_process, every physics tick" },
    { from: "cam", to: "cam", kind: "call", label: "move_direction() · current_speed()", tick: "clamp(D(eye), 1e-6, 20) · factor · limit · (4 if Shift)", ...R("fly", 76),
      blurb: "The six actions in camera axes, normalised; nothing while Cmd/Ctrl is held or a text field has focus. Speed from the CPU estimator, capped by the shed level's `speed_limit`: tab 8.",
      links: [RL("fly", 124, "move_direction"), RL("fly", 139, "current_speed")] },
    { from: "cam", to: "cs", kind: "call", label: "origin += dir · speed · delta", ...R("fly", 82),
      blurb: "Each tick's move emits `changed` again, so a held key keeps the frame 'changing'." },
    { sec: "PROCESS — Main._process: resolve the shape" },
    { from: "main", to: "res", kind: "call", label: "resolve(table, axes.values(), clock.t)", tick: "default + gain × wave(source) per active binding", ...R("main", 265),
      blurb: "Every catalogue id gets a value: its default if unbound, otherwise default + gain × waveform(source), sanitized to the spec's range. A source is the clock (`time`) or an axis id; an unknown axis reads 0.",
      links: [RL("resolver", 13, "resolve"), RL("main", 253, "_process")] },
    { from: "main", to: "pa", kind: "call", label: "apply_resolved(values)", tick: "one changed, only on a difference", ...R("main", 266),
      blurb: "Writes every resolved field with its setter's signal suppressed, then emits `changed` once if anything differed. With no active binding nothing differs, so a still view stays still.",
      links: [RL("params", 334, "apply_resolved"), RL("main", 268, "+ console.set_resolved while visible")] },
    { from: "pa", to: "view", kind: "signal", label: "changed → _push_params", tick: "+ request_frame()", ...R("view", 305),
      blurb: "Each shape field under its own uniform name, plus the precision folded with detail and the shed level, the step budget, box_half, the fog.",
      links: [RL("view", 331, "_push_params")] },
    { from: "pa", to: "gov", kind: "signal", label: "changed → _dirty", ...R("gov", 46),
      blurb: "Also re-reads `fast_controls` and `min_render_scale`." },
    { sec: "FRAME — ResolutionGovernor._process" },
    { from: "gov", to: "gov", kind: "call", label: "step(delta, changing = _dirty)", ...R("gov", 72),
      blurb: "Pure logic: updates `scale`, `mode` and the shed level from this frame's time. Stepped live in tab 9.",
      links: [RL("gov", 96, "step")] },
    { from: "gov", to: "view", kind: "call", label: "set_load_level(applied_level())", tick: "fog · detail · step budget", ...R("gov", 79),
      blurb: "The shedder's level while moving or settling, 0 otherwise; the view re-pushes its params only when the level differs.",
      links: [RL("view", 223, "set_load_level"), RL("gov", 60, "applied_level")] },
    { from: "gov", to: "view", kind: "call", label: "set_render_scale(scale)", tick: "min_render_scale (0.25) … 1", ...R("gov", 81),
      blurb: "Only when the scale differs; resizes the SubViewport before this frame renders.",
      links: [RL("view", 216, "set_render_scale")] },
    { from: "gov", to: "view", kind: "call", label: "set_continuous(true)", tick: "CONTINUOUS", ...R("gov", 85),
      blurb: "UPDATE_ALWAYS while changing; `request_frame` then refuses to downgrade it to UPDATE_ONCE mid-motion.",
      links: [RL("view", 235, "the guard")] },
    { from: "view", to: "sv", kind: "call", label: "size = window × scale × HiDPI", tick: "physical pixels", ...R("view", 291),
      blurb: "`round(size × render_scale × content_scale)`, at least 1; a new size requests a frame. The `aspect` uniform follows.",
      links: [RL("view", 286, "rounding")] },
    { from: "sv", to: "sv", kind: "call", label: "fragment() for every pixel", tick: "march · normal · colour · fog", ...SH(314),
      blurb: "Tabs 3 to 7 open this up: the estimator, the march, the colour modes and the two normals." },
    { sec: "LAST IN TREE ORDER — Clock, AxisController" },
    { from: "ax", to: "ax", kind: "call", label: "t += delta · axes.step(id, dir, delta)", tick: "resolved on the next frame", ...R("axisCtl", 28),
      blurb: "Main adds the Clock and the AxisController in `_ready`, after the scene's own children, so they process after Main has resolved: a key held this frame moves the shape on the next one. Skipped while a text field has focus.",
      links: [RL("clock", 11, "t += delta"), RL("main", 84, "built after the scene's nodes")] },
    { sec: "STOPPING — settle, one full frame, then nothing" },
    { from: "gov", to: "gov", kind: "call", label: "SETTLING", tick: "still, under 0.15 s of quiet", ...R("gov", 128),
      blurb: "The last moving frame stays on screen (at its scale and shed level) until `settle` seconds pass with no change, so a resting mouse's stray events never buy a full-resolution frame.",
      links: [RL("gov", 29, "settle")] },
    { from: "gov", to: "gov", kind: "call", label: "FINAL_FRAME: scale 1, level 0", tick: "0.15 s of quiet", ...R("gov", 124),
      blurb: "Full scale and full quality; the moving scale is kept for when motion resumes." },
    { from: "gov", to: "view", kind: "call", label: "set_continuous(false)", tick: "+ request_frame()", ...R("gov", 87),
      blurb: "UPDATE_DISABLED, then one UPDATE_ONCE: exactly one full-resolution render of the final view." },
    { from: "view", to: "sv", kind: "call", label: "one frame at full scale", ...R("view", 237) },
    { from: "gov", to: "gov", kind: "call", label: "IDLE: nothing renders", tick: "zero GPU cost while still", ...R("gov", 131),
      blurb: "Every later still frame stays IDLE with updates disabled; the TextureRect keeps showing the last image.",
      links: [RL("spec", 498, "spec: idle freeze")] },
  ],
  fragments: [
    { type: "alt", rows: [7, 8], cols: [2, 4], guard1: "FLY", divRow: 8, guard2: "ORBIT" },
    { type: "loop", rows: [12, 13], cols: [2, 4], guard1: "each physics tick while a move key is held (FLY)" },
  ],
};

// ================================================================== 3. building the shape, fold by fold
// The shape knobs the fixture comparison looks at.
const KNOBS = ["box_scale", "fold_limit", "min_radius", "fixed_radius", "fold_order", "w", "julia_all"];
const sameKnobs = (A, B) => KNOBS.every(k => A[k] === B[k]) && [0, 1, 2, 3].every(a => A.julia[a] === B.julia[a] && A.c[a] === B.c[a]) && A.rot.every((r, i) => r === B.rot[i]);
const foldFig = {
  type: "figure",
  tab: "Fold by fold",
  title: "Building the shape, fold by fold",
  note: "A port of the shader's `mb_step` (equal to DistanceEstimator.estimate_at), stage by stage, on the 4D orbit point z = (x, y, z, w). Click the plane to pick a point p; Step walks its orbit one stage at a time. Each iteration runs the two folds in `fold_order` (Box → Sphere by default): the box fold reflects any component past ±fold_limit back inside; the sphere fold scales z by fixed_radius²/min_radius² inside the min sphere and inverts it between the spheres. Then, only when an iteration angle is non-zero, the six-plane rotation; then z = box_scale·z + c, with c per component the Julia constant (where julia_i or Julia (all) is on) or p's own coordinate. `dz` carries the derivative, dz·|box_scale| + 1; the estimate is |z| / |dz| after 32 iterations. The sample point starts at (p, w): w = 0 is the familiar 3D box. The background is the estimate on the plane (blue at the surface). The port runs in 64-bit doubles like DistanceEstimator's scalar orbit; the shader runs float32.",
  w: 1560, h: 1010,
  draw(api) {
    const GX = 20, GY = 96, VS = 600, RW = 3.0, RES = 120;
    const S = { P: params(), p: [1.0, 0.5, 0], k: 0, cloud: false };
    const ITERS = 32;
    const sx = x => GX + (x + RW) / (2 * RW) * VS, sy = y => GY + (RW - y) / (2 * RW) * VS;
    const C = { start: api.hue(3), box: api.hue(2), sphere: api.hue(5), rot: api.hue(6), add: api.hue(1) };
    const STAGE_IDX = { box: 0, sphere: 1, rot: 2, add: 3 };
    const STAGE_NAMES = { start: "start", box: "after the box fold", sphere: "after the sphere fold", rot: "after the iteration rotation", add: "after scale and add" };
    let orbit = [], cloud = [];
    const LAST = () => orbit.length - 1;
    const fixture = () => FIXTURES.find(f => f.p[0] === S.p[0] && f.p[1] === S.p[1] && f.p[2] === S.p[2] && sameKnobs(f.P, S.P));

    // ---- stage list across the top
    const stages = stageRow(api, 20, 16, 290, 12, [
      { n: "1", name: "Box fold", f: "z = clamp(z, −L, L)·2 − z", color: C.box,
        tip: { ...SH(143), blurb: "Each of the four components past ±fold_limit is reflected back inside: x = 1.3 with L = 1 becomes 0.7. Inside the box nothing moves. The fold keeps the orbit near the origin and makes the shape's box-like walls.", links: [RL("de", 81, "GDScript: _box_fold"), RL("spec", 156, "spec, step 1")] } },
      { n: "2", name: "Sphere fold", f: "f = fr2/mr2 · fr2/r2 · 1", color: C.sphere,
        tip: { ...SH(149), blurb: "r2 = |z|² over all four components. Inside the min sphere (r2 < mr2 = min_radius²) z is scaled by the constant fr2/mr2; between the spheres it is inverted (f = fr2/r2, so |z|·f·|z| = fr2); outside, f = 1. dz is scaled by the same f. Both squares are floored at 1e-12 so a zero radius never divides by zero.", links: [RL("sh", 151, "mr2, fr2"), RL("sh", 157, "the inversion"), RL("de", 88, "GDScript: _sphere_fold")] } },
      { n: "3", name: "Iteration rotation", f: "six planes, xy xz xw yz yw zw", color: C.rot,
        tip: { ...SH(185), blurb: "Only when some iter_rot_* angle is non-zero (`mb_rotating`, decided once per fragment): z is rotated in the xy, xz, xw, yz, yw and zw planes in that fixed order, each `a' = a cos − b sin, b' = a sin + b cos`. A rotation leaves |z| alone, so dz does not change. It compounds once per iteration, so a few degrees already twist the lattice.", links: [RL("sh", 173, "mb_rot_plane"), RL("sh", 195, "mb_rotating"), RL("de", 69, "GDScript: the six planes")] } },
      { n: "4", name: "Scale and add", f: "z = s·z + c ;  dz = dz·|s| + 1", color: C.add,
        tip: { ...SH(205), blurb: "z is stretched by box_scale (negative: it also flips through the origin) and the constant c is added back, per component: c_i where julia_i or Julia (all) is on, else the start point's own coordinate. dz = dz·|s| + 1 is Fractacular's derivative; the old −dz·s + 1 equals it for every negative scale.", links: [RL("sh", 206, "dz"), RL("sh", 211, "mb_constant"), RL("de", 72, "GDScript: scale and add")] } },
      { n: "D", name: "The estimate", f: "D = |z| / |dz| after 32", color: "var(--ink)",
        tip: { ...SH(230), blurb: "A point inside the set keeps |z| bounded while |dz| grows like |s|ⁿ, so D → 0. A point outside escapes and D settles near its distance to the surface. The march (tab 5) steps by exactly this number.", links: [RL("de", 77, "GDScript: return"), RL("tDE", 17, "the fixtures")] } },
    ]);

    // ---- the plane: heat image, geometry, trail, cloud
    const ramp = { f: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VS, h: VS, pw: RES, ph: RES }, (i, j) => {
      const x = -RW + (i + 0.5) / RES * 2 * RW, y = RW - (j + 0.5) / RES * 2 * RW;
      return ramp.f(de(x, y, S.p[2], 32, S.P), 0.45);
    });
    const clipId = "mb-fold-clip";
    api.el("rect", { x: GX, y: GY, width: VS, height: VS }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const geo = api.el("g", { "clip-path": `url(#${clipId})`, style: noPtr });
    const trailG = api.el("g", { "clip-path": `url(#${clipId})` });
    const cloudG = api.el("g", { "clip-path": `url(#${clipId})` });
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
      const bh = S.P.boxHalf;
      if (bh < RW) api.el("rect", { x: sx(-bh), y: sy(bh), width: sx(bh) - sx(-bh), height: sy(-bh) - sy(bh), style: "fill:none;stroke:var(--muted);stroke-width:1;stroke-dasharray:2 4" }, geo);
      const f = S.P.fold_limit;
      api.el("rect", { x: sx(-f), y: sy(f), width: sx(f) - sx(-f), height: sy(-f) - sy(f), style: `fill:none;stroke:${C.box};stroke-width:1.6;stroke-dasharray:7 4` }, geo);
      const scaleR = VS / (2 * RW);
      api.el("circle", { cx: sx(0), cy: sy(0), r: S.P.min_radius * scaleR, style: `fill:none;stroke:${C.sphere};stroke-width:1.4;stroke-dasharray:3 3` }, geo);
      api.el("circle", { cx: sx(0), cy: sy(0), r: S.P.fixed_radius * scaleR, style: `fill:none;stroke:${C.sphere};stroke-width:1.6` }, geo);
      if (S.P.jOn[0] || S.P.jOn[1]) {
        const jx = S.P.jOn[0] ? S.P.c[0] : null, jy = S.P.jOn[1] ? S.P.c[1] : null;
        if (jx !== null && jy !== null) api.el("circle", { cx: sx(jx), cy: sy(jy), r: 6, style: "fill:none;stroke:var(--ink);stroke-width:1.6" }, geo);
        else if (jx !== null) api.el("line", { x1: sx(jx), y1: sy(-RW), x2: sx(jx), y2: sy(RW), style: "stroke:var(--ink);stroke-width:1;stroke-dasharray:2 3" }, geo);
        else api.el("line", { x1: sx(-RW), y1: sy(jy), x2: sx(RW), y2: sy(jy), style: "stroke:var(--ink);stroke-width:1;stroke-dasharray:2 3" }, geo);
      }
    }
    // trail: one segment + dot per state (pooled at the most stages an orbit can have: 4 per iteration)
    const MAXK = ITERS * 4;
    const segs = [], dots = [];
    for (let k = 1; k <= MAXK; k++) segs.push(api.el("line", { style: `stroke-width:1.8;${noPtr}` }, trailG));
    const DOT_REFS = { start: SH(221), box: SH(143), sphere: SH(149), rot: SH(185), add: SH(205) };
    for (let k = 0; k <= MAXK; k++) {
      const c = api.el("circle", { r: k === 0 ? 6 : 3.4, style: "cursor:pointer" }, trailG);
      dots.push(c);
      api.tip(c, { title: "a state of the orbit", ...SH(201), live() {
        const st = orbit[k];
        if (!st) return {};
        const lines = [`\`z\` = ${vec(st.z)}`, `|z| = ${sci(Math.hypot(...st.z))}`, `\`dz\` = ${sci(st.dz)}`];
        if (st.kind === "sphere") lines.push(`r2 = ${sci(st.r2)}, f = ${sci(st.f)} (${["inside the min sphere", "between the spheres: inversion", "outside: f = 1"][st.branch]})`);
        if (st.kind === "box") lines.push(`folded: ${AX4.filter((_, a) => st.folded[a]).join(", ") || "nothing (inside the box)"}`);
        return { title: k === 0 ? "p, the start of the orbit" : `iteration ${st.it + 1}, ${STAGE_NAMES[st.kind]}`, sub: `state ${k} of ${LAST()}`, ...DOT_REFS[st.kind], blurb: lines.join("\n") };
      } });
    }
    const curRing = api.el("circle", { r: 9, style: `fill:none;stroke:var(--ink);stroke-width:2;${noPtr}` }, trailG);
    // sample cloud: an 11 × 11 grid of starting points, all at the same stage as p's orbit
    const CL = [];
    for (let j = 0; j < 11; j++) for (let i = 0; i < 11; i++) {
      const p = [-2.5 + i * 0.5, 2.5 - j * 0.5];
      const color = p[0] < 0 ? api.hue(1) : p[0] > 0 ? api.hue(2) : api.hue(3);
      const ln = api.el("line", { style: `stroke:${color};stroke-width:1;opacity:.5;${noPtr}` }, cloudG);
      const dot = api.el("circle", { r: 3.2, style: `fill:${color};stroke:var(--surface);stroke-width:.8;cursor:pointer` }, cloudG);
      const idx = CL.length;
      CL.push({ p, ln, dot });
      api.tip(dot, { title: `sample from (${fmt(p[0], 1)}, ${fmt(p[1], 1)})`, ...SH(220), live() {
        const o = cloud[idx]; if (!o) return {};
        const st = o[S.k], prev = o[Math.max(0, S.k - 1)];
        return { sub: S.k === 0 ? "start" : `iteration ${st.it + 1}, ${STAGE_NAMES[st.kind]}`,
          blurb: `start (${fmt(p[0], 2)}, ${fmt(p[1], 2)}, ${fmt(S.p[2], 2)}, w ${fmt(S.P.w, 2)})\nprevious stage ${vec(prev.z)}\nnow ${vec(st.z)}\nD at the start = ${sci(de(p[0], p[1], S.p[2], 32, S.P))}` };
      } });
    }

    // ---- readouts on the right
    const RX = 660;
    const head = api.text(RX, 112, "", "ink", { style: caps });
    const lines = [];
    for (let i = 0; i < 8; i++) lines.push(api.text(RX, 140 + i * 21, "", "mono"));
    // |z| gauge against the two spheres
    const GW = 520, GZ = 340, ZMAX = 2.5, gx = v => RX + clamp(v / ZMAX, 0, 1) * GW;
    api.text(RX, GZ - 12, "|z| (4D) against the spheres", "ink", { style: caps });
    api.el("line", { x1: RX, y1: GZ + 10, x2: RX + GW, y2: GZ + 10, style: "stroke:var(--hairline);stroke-width:8;stroke-linecap:round" });
    const gInner = api.el("line", { y1: GZ, y2: GZ + 20, style: `stroke:${C.sphere};stroke-width:2;stroke-dasharray:3 2` });
    const gOuter = api.el("line", { y1: GZ, y2: GZ + 20, style: `stroke:${C.sphere};stroke-width:2.4` });
    const gInnerT = api.text(0, GZ + 34, "", "", { "text-anchor": "middle", style: `${small};fill:${C.sphere}` });
    const gOuterT = api.text(0, GZ + 48, "", "", { "text-anchor": "middle", style: `${small};fill:${C.sphere}` });
    const gMark = api.el("circle", { cy: GZ + 10, r: 7, style: "fill:var(--ink)" });
    for (const t of [0, 0.5, 1, 1.5, 2, 2.5]) api.text(gx(t), GZ - 2, String(t), "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
    const gNote = api.text(RX + GW + 16, GZ + 14, "", "mono", { style: small });
    // components against ±fold_limit
    const CB = 440, CMAX = 3, cx_ = v => RX + GW / 2 + clamp(v / CMAX, -1, 1) * GW / 2;
    api.text(RX, CB - 14, "components against the fold box ±fold_limit", "ink", { style: caps });
    const cBand = [], cMark = [], cVal = [];
    AX4.forEach((a, i) => {
      const y = CB + i * 22;
      api.text(RX - 16, y + 4, a, "mono", { "text-anchor": "end" });
      api.el("line", { x1: RX, y1: y, x2: RX + GW, y2: y, style: "stroke:var(--hairline);stroke-width:6;stroke-linecap:round" });
      cBand.push(api.el("line", { y1: y, y2: y, style: `stroke:${C.box};stroke-width:6;opacity:.45` }));
      cMark.push(api.el("circle", { cy: y, r: 5.5, style: "fill:var(--ink)" }));
      cVal.push(api.text(RX + GW + 16, y + 4, "", "mono", { style: small }));
    });
    api.el("line", { x1: RX + GW / 2, y1: CB - 8, x2: RX + GW / 2, y2: CB + 74, style: "stroke:var(--muted);stroke-width:1" });
    // per-iteration table
    const TY = 560;
    api.text(RX, TY, "iteration", "ink", { style: caps });
    ["|z|", "dz", "f (sphere)", "|z| / |dz|"].forEach((h, i) => api.text(RX + 120 + i * 160, TY, h, "ink", { style: caps }));
    const trows = [];
    for (let r = 0; r < 8; r++) trows.push([0, 1, 2, 3, 4].map(c => api.text(RX + (c ? 120 + (c - 1) * 160 : 0), TY + 22 + r * 19, "", "mono", { style: small })));

    function recompute() {
      orbit = orbitStages(S.p[0], S.p[1], S.p[2], S.P, ITERS);
      cloud = CL.map(o => orbitStages(o.p[0], o.p[1], S.p[2], S.P, ITERS));
    }
    function render() {
      const k = S.k, st = orbit[k], last = LAST();
      stages.set(k === last ? 4 : k === 0 ? -1 : STAGE_IDX[st.kind]);
      for (let j = 1; j <= MAXK; j++) {
        const on = j <= k && j <= last, seg = segs[j - 1];
        seg.style.display = on ? "" : "none";
        if (on) {
          const a = orbit[j - 1].z, b = orbit[j].z;
          seg.setAttribute("x1", sx(a[0])); seg.setAttribute("y1", sy(a[1]));
          seg.setAttribute("x2", sx(b[0])); seg.setAttribute("y2", sy(b[1]));
          seg.style.stroke = C[orbit[j].kind];
          seg.style.opacity = j === k ? 1 : 0.55;
        }
      }
      for (let j = 0; j <= MAXK; j++) {
        const on = j <= k && j <= last, d = dots[j];
        d.style.display = on ? "" : "none";
        if (on) {
          d.setAttribute("cx", sx(orbit[j].z[0])); d.setAttribute("cy", sy(orbit[j].z[1]));
          d.style.fill = C[orbit[j].kind];
        }
      }
      curRing.setAttribute("cx", sx(st.z[0])); curRing.setAttribute("cy", sy(st.z[1]));
      cloudG.style.display = S.cloud ? "" : "none";
      if (S.cloud) CL.forEach((o, i) => {
        const a = cloud[i][Math.max(0, k - 1)].z, b = cloud[i][k].z;
        o.ln.setAttribute("x1", sx(a[0])); o.ln.setAttribute("y1", sy(a[1]));
        o.ln.setAttribute("x2", sx(b[0])); o.ln.setAttribute("y2", sy(b[1]));
        o.dot.setAttribute("cx", sx(b[0])); o.dot.setAttribute("cy", sy(b[1]));
      });
      // readouts
      head.textContent = k === 0 ? "the start: z = (p, w), dz = 1" : `iteration ${st.it + 1} of ${ITERS} · ${STAGE_NAMES[st.kind]}`;
      const zl = Math.hypot(...st.z), D = de(S.p[0], S.p[1], S.p[2], 32, S.P), fx = fixture();
      const cTxt = orbit[0].c.map((v, a) => (S.P.jOn[a] ? `c_${a}` : `p.${AX4[a]}`)).join(", ");
      const rotOn = S.P.rot.map((r, i) => (r ? `${PLANE_NAMES[i]} ${fmt(r, 1)}°` : "")).filter(Boolean).join(", ");
      const L = [
        `p = ${vec(S.p, 3)}  w = ${fmt(S.P.w, 2)}   c = (${cTxt})`,
        `z = ${vec(st.z)}`,
        `|z| = ${sci(zl)}    dz = ${sci(st.dz)}`,
        st.kind === "sphere" ? `r2 = ${sci(st.r2)} → f = ${sci(st.f)}  (${["r2 < mr2: constant fr2/mr2", "mr2 ≤ r2 < fr2: inversion fr2/r2", "r2 ≥ fr2: f = 1"][st.branch]})`
          : st.kind === "box" ? `box fold: ${AX4.filter((_, a) => st.folded[a]).join(", ") || "no component"} past ±${fmt(S.P.fold_limit, 2)} reflected`
          : st.kind === "rot" ? `rotated in the six planes (${rotOn})`
          : st.kind === "add" ? `z = ${fmt(S.P.box_scale, 2)}·z + c,  dz = dz·${fmt(Math.abs(S.P.box_scale), 2)} + 1`
          : `Step ▶ runs the first ${S.P.fold_order === 0 ? "box" : "sphere"} fold`,
        `running |z| / |dz| = ${sci(zl / Math.abs(st.dz))}`,
        `de(p, 32) = ${sci(D, 6)}${fx ? `   = the test's ${fx.want} (${fx.name})` : ""}`,
        `de(p, 16) = ${sci(de(S.p[0], S.p[1], S.p[2], 16, S.P), 6)}   (the march's first phase)`,
        zl > RW * 1.4 ? "z has left the view: the point escapes, so D is its distance to the surface" : "",
      ];
      L.forEach((s, i) => { lines[i].textContent = s; });
      lines[5].style.fill = fx ? api.hue(3) : "";
      const ir = S.P.min_radius, or = S.P.fixed_radius;
      gInner.setAttribute("x1", gx(ir)); gInner.setAttribute("x2", gx(ir));
      gOuter.setAttribute("x1", gx(or)); gOuter.setAttribute("x2", gx(or));
      gInnerT.setAttribute("x", gx(ir)); gInnerT.textContent = `min ${fmt(ir, 2)}`;
      gOuterT.setAttribute("x", gx(or)); gOuterT.textContent = `fixed ${fmt(or, 2)}`;
      gMark.setAttribute("cx", gx(zl));
      gMark.style.fill = C[st.kind];
      gNote.textContent = `|z| = ${sci(zl)}${zl > ZMAX ? " (off the gauge)" : ""}`;
      const f = S.P.fold_limit;
      for (let a = 0; a < 4; a++) {
        cBand[a].setAttribute("x1", cx_(-f)); cBand[a].setAttribute("x2", cx_(f));
        cMark[a].setAttribute("cx", cx_(st.z[a]));
        cMark[a].style.fill = C[st.kind];
        cVal[a].textContent = `${sci(st.z[a])}${Math.abs(st.z[a]) > f ? "  past the fold" : ""}`;
      }
      // table: the last 8 finished iterations
      const adds = orbit.filter((o, j) => o.kind === "add" && j <= k);
      const first = Math.max(0, adds.length - 8);
      for (let r = 0; r < 8; r++) {
        const end = adds[first + r], cells = trows[r];
        if (!end) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const sph = orbit.find(o => o.kind === "sphere" && o.it === end.it);
        const vals = [String(end.it + 1), sci(Math.hypot(...end.z)), sci(end.dz), sci(sph.f), sci(Math.hypot(...end.z) / Math.abs(end.dz))];
        cells.forEach((c, i) => { c.textContent = vals[i]; });
      }
      axisLbl.textContent = `plane z = ${fmt(S.p[2], 2)}, w = ${fmt(S.P.w, 2)} · x right, y up · trail projected on x-y`;
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
      S.p = [+(-RW + (q.x - GX) / VS * 2 * RW).toFixed(3), +(RW - (q.y - GY) / VS * 2 * RW).toFixed(3), S.p[2]];
      S.k = 0; refreshAll(false);
    });

    // ---- controls
    const BY = 736;
    let bx = GX, by = BY;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: by, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, by + 17, "Orbit", "ink"); bx += 48;
    btn("◀ Back", 74, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn("Step ▶", 74, () => { S.k = Math.min(LAST(), S.k + 1); render(); });
    btn("+1 iteration", 100, () => { const n = orbit.findIndex((o, j) => j > S.k && o.kind === "add"); S.k = n < 0 ? LAST() : n; render(); });
    btn("All 32 ▶▶", 90, () => { S.k = LAST(); render(); });
    btn("Reset", 66, () => { S.k = 0; render(); });
    bx += 20;
    const cb = btn("Sample cloud", 112, b => { S.cloud = !S.cloud; b.set(S.cloud); render(); });
    btn("Fixture point (1.2, −0.3, 0.8)", 214, () => { S.p = [1.2, -0.3, 0.8]; S.k = LAST(); syncSliders(); refreshAll(true); });
    btn("Reset knobs", 104, () => { S.P = params(); syncSliders(); refreshAll(true); });
    void cb;
    // knob toggles
    bx = GX; by = BY + 40;
    api.text(bx, by + 17, "Knobs", "ink"); bx += 48;
    const setP = o => { S.P = withP(S.P, o); syncSliders(); refreshAll(true); };
    const ob = btn("Sphere → Box", 112, () => setP({ fold_order: 1 - S.P.fold_order }));
    const jab = btn("Julia (all)", 94, () => setP({ julia_all: !S.P.julia_all }));
    const jbs = AX4.map((a, i) => btn(`julia_${i} (${a})`, 96, () => { const j = S.P.julia.slice(); j[i] = !j[i]; setP({ julia: j }); }));
    const sliders = [];
    const SL = [
      ["Scale (box_scale)", "box_scale", -5, 3, 0.01], ["Min radius", "min_radius", 0, 2, 0.01], ["Fold limit", "fold_limit", 0, 3, 0.01],
      ["Fixed radius", "fixed_radius", 0, 4, 0.01], ["plane height z", "h", -2.5, 2.5, 0.05],
      ["W (the 4th coordinate)", "w", -4, 4, 0.01], ["iter_rot_xy (°)", "r0", -180, 180, 0.5], ["iter_rot_xw (°)", "r2", -180, 180, 0.5],
      ["iter_rot_yz (°)", "r3", -180, 180, 0.5], ["iter_rot_zw (°)", "r5", -180, 180, 0.5],
    ];
    const getV = key => (key === "h" ? S.p[2] : key[0] === "r" && key.length === 2 ? S.P.rot[+key[1]] : S.P[key]);
    SL.forEach(([label, key, min, max, step], i) => {
      const h = api.slider({ x: GX + (i % 5) * 300, y: BY + 110 + Math.floor(i / 5) * 62, w: 260, label, min, max, step, value: getV(key), fmt: v => fmt(v, key[0] === "r" ? 1 : 2),
        onChange: v => {
          if (key === "h") S.p = [S.p[0], S.p[1], v];
          else if (key[0] === "r" && key.length === 2) { const r = S.P.rot.slice(); r[+key[1]] = v; S.P = withP(S.P, { rot: r }); }
          else S.P = withP(S.P, { [key]: v });
          syncToggles();
          refreshAll(true);
        } });
      sliders.push([key, h]);
    });
    function syncToggles() {
      ob.set(S.P.fold_order === 1); jab.set(S.P.julia_all); jbs.forEach((b, i) => b.set(S.P.julia[i]));
    }
    function syncSliders() { for (const [key, h] of sliders) h.set(getV(key)); syncToggles(); }
    api.text(GX, BY + 214, "Legend: orange box = ±fold_limit · pink dashed / solid circles = the min and fixed spheres (their equators on this plane) · grey dotted square = the march's cube (box_half) · ink ring or line = the Julia constant where c_0 / c_1 are on · trail colours = the stage that moved z (violet: the rotation).", "muted", { style: small });
    api.text(GX, BY + 232, "The trail and the cloud are drawn in x-y; z and w are in the readout. Hover any dot for its numbers. Fixture point: with the knobs matching a fixture set (defaults, Sphere → Box, xy 30°, w 0.5, julia_0 + julia_2, scale 2…) de(p, 32) turns green with the test's value.", "muted", { style: small });
    api.link(GX, BY + 252, RL("de", 10, "why the GDScript copy runs scalar 64-bit floats"));
    refreshAll(true);
  },
};

// ================================================================== 4. what each dial does
// The shape.defaults of each committed save (version 2), from its box_scale line on.
const PRESETS = [
  { name: "default.json", ...R("saveDef", 5), o: { box_scale: -2.09, fold_limit: 1.0, min_radius: 0.7, fixed_radius: 1.0, precision: 0.000025, julia_all: false } },
  { name: "juliaIceField.json", ...R("saveField", 5), o: { box_scale: -2.29, fold_limit: 0.72, min_radius: 0.0, fixed_radius: 0.29, precision: 0.00002, julia_all: true } },
  { name: "juliaIceTerraces.json", ...R("saveTer", 5), o: { box_scale: -1.88, fold_limit: 0.81, min_radius: 0.49, fixed_radius: 0.53, precision: 0.0001, julia_all: true } },
];
const EYE_DIST = Math.hypot(...DEFAULT_EYE);
const dialsFig = {
  type: "figure",
  tab: "What each dial does",
  title: "What each dial does",
  note: "The distance estimate de(p, 32) on a plane through the shape, 160 × 160 cells, shaded by log10(d): blue at the surface, fading with distance. Cells whose d is under the hit threshold are drawn in ink: that is the surface the march would stop on. The sliders are the console's Shape rows with the catalogue's slider ranges (MandelboxShape). The threshold is precision × 9.62 (what the phase-2 stop test `d < hit_eps(total)` uses, at the default detail 1 and falloff 0, for a ray that has travelled the default eye's distance), so Precision moves the ink edge a hair and never the shape. The figure recomputes a few rows per frame after each change. Presets load the values in saves/.",
  w: 1500, h: 850,
  draw(api) {
    const N = 160, GX = 20, GY = 50, VS = 640;
    const S = { P: params(), axes: "xy", off: 0, range: 2.4 };
    const dvals = new Float64Array(N * N);
    const th = () => S.P.precU * EYE_DIST;
    const cellPoint = (i, j) => {
      const a = -S.range + (i + 0.5) / N * 2 * S.range, b = S.range - (j + 0.5) / N * 2 * S.range;
      return axisPoint(S.axes, a, b, S.off);
    };
    const col = { ramp: null, ink: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VS, h: VS, pw: N, ph: N }, (i, j) => {
      const p = cellPoint(i, j), d = de(p[0], p[1], p[2], 32, S.P);
      dvals[j * N + i] = d;
      return d < th() ? col.ink : col.ramp(d);
    });
    api.el("rect", { x: GX, y: GY, width: VS, height: VS, style: "fill:none;stroke:var(--muted);stroke-width:1.2;pointer-events:none" });
    const axisText = api.text(GX, GY + VS + 18, "", "muted", { style: small });
    const hoverText = api.text(GX, GY + VS + 40, "hover the plane for d at a cell", "mono");
    const status = api.text(GX + VS, GY + VS + 18, "", "muted", { "text-anchor": "end", style: small });
    // hover: a 40 × 40 grid of hit cells with live tooltips, plus an exact readout on mousemove
    const HG = 40, HS = VS / HG, hitG = api.el("g", {});
    for (let j = 0; j < HG; j++) for (let i = 0; i < HG; i++) {
      const r = api.el("rect", { x: GX + i * HS, y: GY + j * HS, width: HS, height: HS, style: "fill:transparent;cursor:crosshair" }, hitG);
      api.tip(r, { title: "de(p, 32) on this patch", ...SH(220), live() {
        let lo = Infinity, hi = 0, hits = 0;
        for (let y = j * 4; y < j * 4 + 4; y++) for (let x = i * 4; x < i * 4 + 4; x++) {
          const d = dvals[y * N + x]; lo = Math.min(lo, d); hi = Math.max(hi, d); if (d < th()) hits++;
        }
        const c = cellPoint(i * 4 + 2, j * 4 + 2);
        return { sub: `4 × 4 cells around ${vec(c, 2)}${heat.busy() ? " · still computing" : ""}`, blurb: `d from ${sci(lo)} to ${sci(hi)}\n${hits} of 16 cells under the threshold ${sci(th())} (inked)\nThe estimate is a lower bound on the distance to the surface: the march can step this far and not pass through it.` };
      } });
    }
    hitG.addEventListener("mousemove", e => {
      const q = api.local(e), i = Math.floor((q.x - GX) / VS * N), j = Math.floor((q.y - GY) / VS * N);
      if (i < 0 || j < 0 || i >= N || j >= N) return;
      const p = cellPoint(i, j), d = dvals[j * N + i];
      hoverText.textContent = `p = ${vec(p, 3)}   d = ${sci(d, 4)}${d < th() ? "   under the threshold: surface" : ""}`;
    });

    // ---- controls on the right
    const RX = 720, SW = 300;
    let y = GY + 6;
    api.text(RX, y + 12, "Plane", "ink", { style: caps });
    const axisBtns = [["xy", "X-Y"], ["xz", "X-Z"], ["yz", "Y-Z"]].map(([k, label], i) =>
      [k, api.button({ x: RX + 70 + i * 74, y, w: 66, label, on: S.axes === k, onClick: () => { S.axes = k; for (const [kk, b] of axisBtns) b.set(kk === k); recompute(); } })]);
    y += 66;
    const offS = api.slider({ x: RX, y, w: SW, label: "offset along the third axis", min: -2.5, max: 2.5, step: 0.01, value: S.off, fmt: v => fmt(v, 2), onChange: v => { S.off = v; recompute(); } });
    api.slider({ x: RX + SW + 60, y, w: 220, label: "view half-width", min: 0.5, max: 8, step: 0.1, value: S.range, fmt: v => fmt(v, 1), onChange: v => { S.range = v; recompute(); } });
    y += 62;
    api.text(RX, y, "Shape rows → FractalParams → uniforms", "ink", { style: caps });
    y += 34;
    const capt = (txt, yy, ref) => {
      api.text(RX + SW + 24, yy + 2, txt[0], "", { style: small });
      if (txt[1]) api.text(RX + SW + 24, yy + 17, txt[1], "", { style: small });
      if (ref) api.link(RX + SW + 24, yy + 33, ref);
    };
    const shapeSliders = {};
    const SL = [
      ["Scale (box_scale)", "box_scale", -5, 3, 0.01, ["Stretches every fold by |s| (negative also flips through the", "origin): the primary topology knob. |s| < 1 collapses to dust."], RL("view", 334, "uniform box_scale")],
      ["Min radius", "min_radius", 0, 2, 0.01, ["The sphere fold's dead zone: inside it z is scaled by fr2/mr2.", "Pushed as is; the shader squares it (mr2 = max(r², 1e-12))."], RL("view", 336, "uniform min_radius")],
      ["Fold limit", "fold_limit", 0, 3, 0.01, ["The box fold's half-size: components past ±L reflect back.", "Smaller folds carve the walls into thinner plates."], RL("view", 335, "uniform fold_limit")],
      ["Fixed radius", "fixed_radius", 0, 4, 0.01, ["The inversion radius: inside it z is inverted through", "the sphere (f = fr2/r2). Below min radius: no inversion."], RL("view", 337, "uniform fixed_radius")],
    ];
    for (const [label, key, min, max, step, txt, ref] of SL) {
      shapeSliders[key] = api.slider({ x: RX, y, w: SW, label, min, max, step, value: S.P[key], fmt: v => fmt(v, 2),
        onChange: v => { S.P = withP(S.P, { [key]: v }); recompute(); } });
      capt(txt, y - 6, ref);
      y += 64;
    }
    const wS = api.slider({ x: RX, y, w: 200, label: "W", min: -4, max: 4, step: 0.01, value: S.P.w, fmt: v => fmt(v, 2),
      onChange: v => { S.P = withP(S.P, { w: v }); recompute(); } });
    const rS = api.slider({ x: RX + 230, y, w: 200, label: "iter_rot_xy (°)", min: -180, max: 180, step: 0.5, value: S.P.rot[0], fmt: v => fmt(v, 1),
      onChange: v => { const r = S.P.rot.slice(); r[0] = v; S.P = withP(S.P, { rot: r }); recompute(); } });
    const ob = api.button({ x: RX + 460, y: y - 14, w: 120, label: "Sphere → Box", on: false, onClick: b => { S.P = withP(S.P, { fold_order: 1 - S.P.fold_order }); b.set(S.P.fold_order === 1); recompute(); } });
    api.link(RX + 600, y, RL("view", 338, "fold_order, w"));
    y += 64;
    const precS = api.slider({ x: RX, y, w: SW, label: "Precision (log10)", min: -6, max: -3, step: 0.01, value: Math.log10(S.P.precision),
      fmt: v => sci(Math.pow(10, v), 2), onChange: v => { S.P = withP(S.P, { precision: +Math.pow(10, v).toPrecision(3) }); recolour(); } });
    capt(["Not a shape knob: only the hit threshold moves (ink edge).", "A smaller value marches closer and takes more steps."], y - 6, RL("sh", 358, "the stop test"));
    y += 70;
    api.text(RX, y + 12, "Julia", "ink", { style: caps });
    const jb = api.button({ x: RX + 60, y, w: 100, label: "Julia (all)", on: false, onClick: b => { S.P = withP(S.P, { julia_all: !S.P.julia_all }); b.set(S.P.julia_all); recompute(); } });
    api.text(RX + 176, y + 12, "c = (c_0, c_1, c_2, c_3) on every component, and the march's cube grows to ±20", "", { style: small });
    api.link(RX + 176, y + 28, RL("sh", 211, "mb_constant: per component"));
    y += 66;
    const jS = [0, 1, 2].map(a => api.slider({ x: RX + a * 200, y, w: 170, label: `c_${a} (${AX4[a]})`, min: -4, max: 4, step: 0.001, value: S.P.c[a], fmt: v => fmt(v, 3),
      onChange: v => { const c = S.P.c.slice(); c[a] = v; S.P = withP(S.P, { c }); if (S.P.julia_all) recompute(); } }));
    y += 56;
    api.text(RX, y + 12, "Presets", "ink", { style: caps });
    PRESETS.forEach((pr, i) => {
      api.button({ x: RX + 80 + i * 186, y, w: 178, label: pr.name, onClick: () => {
        S.P = params(pr.o);
        for (const k of ["box_scale", "min_radius", "fold_limit", "fixed_radius"]) shapeSliders[k].set(S.P[k]);
        precS.set(Math.log10(S.P.precision)); jb.set(S.P.julia_all); jS.forEach((s, a) => s.set(S.P.c[a]));
        wS.set(S.P.w); rS.set(S.P.rot[0]); ob.set(false);
        recompute();
      } });
    });
    y += 40;
    PRESETS.forEach((pr, i) => api.link(RX + 80 + i * 186, y, { file: pr.file, line: pr.line, label: `${pr.name.replace(".json", "")}:${pr.line}` }));

    function recolour() { col.ramp = deRamp(); col.ink = cssRGB("--ink"); heat.restart(() => { status.textContent = `done · threshold ${sci(th())}`; }); status.textContent = "computing…"; }
    function recompute() {
      const [a, b, c] = AXES[S.axes];
      axisText.textContent = `${a} right, ${b} up, ${c} = ${fmt(S.off, 2)}, w = ${fmt(S.P.w, 2)} · ±${fmt(S.range, 1)} · ${S.P.julia_all ? `Julia (${S.P.c.slice(0, 3).map(v => fmt(v, 3)).join(", ")})` : "Mandelbox"}`;
      recolour();
    }
    recompute();
  },
};

// ================================================================== 5. marching one ray
const marchFig = {
  type: "figure",
  tab: "Marching one ray",
  title: "Marching one ray",
  note: "The ray march from fragment(), ported. The plane is the vertical slice through the default eye and the world Z axis (u along the eye's heading, w = z), so the default centre ray lies in it. Drag the eye (ink) and the aim point (green). Step walks the march: clip to the cube, phase 1 with de(p, coarse_iters) for up to coarse_steps (16 iterations from the default eye, more as the eye nears the surface), phase 2 with de(p, 32) for up to fine_steps, then ce = (n1 + n2)/128. Each step draws its unbounding circle of radius d (the sphere-tracing picture: no surface is closer than d, so the ray hops d) and the hop. Near the surface the hops shrink geometrically: zoom in to see them. Both phases stop on hit_eps(total): the pixel cone precision / detail · total, coarsened by (total / start)^falloff past start = detail_range · near_dist, where near_dist = de(eye, 32) is the eye's distance to the nearest surface (the solid ring round the eye; the dashed ring is start). The defaults (falloff 0, 128 steps) are the plain cone and 96 + 32 steps. A ray that runs out of steps without meeting the threshold is NOT a miss; it is shaded with ce = 1 (the dust around the fractal). The misses are leaving the cube and, under a load-shed level, reaching the fog: the governor's LoadShedder ends every ray at fog · near_dist (the amber ring), lowers detail and cuts the step budget, and the hit colour fades into the fog colour from 0.35 of that distance on.",
  w: 1560, h: 960,
  draw(api) {
    const GX = 20, GY = 96, VW = 900, VH = 540, PW = 180, PH = 108;
    const C1 = api.hue(2), C2 = api.hue(1), CHIT = api.hue(3);
    const eye0 = toSlice(DEFAULT_EYE);
    const S = { P: params(), eye: eye0.slice(), aim: [0, 0], s: 0, zoom: 1, follow: true, play: false };
    let M = null, steps = [];
    const view = { cu: 3.75, cw: 0.6, hw: 6.75 };      // the whole-ray view, in slice units
    const scale = () => VW / (2 * view.hw);
    const px = u => GX + VW / 2 + (u - view.cu) * scale(), py = w => GY + VH / 2 - (w - view.cw) * scale();
    const toWorld = q => [view.cu + (q.x - GX - VW / 2) / scale(), view.cw - (q.y - GY - VH / 2) / scale()];

    const stages = stageRow(api, 20, 16, 360, 14, [
      { n: "0", name: "Box intersect", f: "total = max(0, t_enter)", color: "var(--muted)",
        tip: { ...SH(326), blurb: "The ray is clipped to the cube of half-size box_half (2, or 20 in Julia mode). Missing it outputs the background; otherwise the march starts at the entry (or at the eye, inside the cube). `total` is measured from the eye, not from the entry, so precision behaves as on the site. Under fog the exit is pulled in to fog · near_dist.", links: [RL("sh", 299, "box_intersect"), RL("sh", 334, "total = max(tb.x, 0)"), RL("sh", 332, "the fog exit"), RL("spec", 239, "spec: bounds")] } },
      { n: "1", name: "Phase 1 · de(p, coarse_iters)", f: "≤ coarse_steps · stop d < hit_eps(total)·2", color: C1,
        tip: { ...SH(337), blurb: "Cheaper estimates, up to coarse_steps (¾ of max_steps: 96 by default), with a threshold twice as loose. Their iteration count, coarse_iters, follows near_dist: fewer iterations describe a smoother surface (rough by about 2 / |box_scale|^n), and once the eye is close the threshold 2 · eps · near gets finer than that gap, so a fixed 16 would creep toward a surface it can never reach and spend all 96 steps (darker shading, then dark pits). coarse_iters = ceil(log(2 / (2 · eps · near)) / log|box_scale|) kept in [16, 32] (eps = precision / detail): 16 from the default eye, so the site's picture is unchanged; 24 at near 1e−3; 32 by about 3e−6. n1 = the step index of the stop, or coarse_steps if it never stopped. Crossing t_exit is a miss. The loop is bounded at 384 so `coarse_steps` can be a uniform.", links: [RL("sh", 344, "de(pos, n_coarse)"), RL("sh", 339, "n_coarse = clamp(coarse_iters, 16, 32)"), RL("params", 246, "coarse_iters()"), RL("view", 390, "pushed with near_dist"), RL("tDeep", 38, "the deep-zoom regression"), RL("sh", 345, "the stop test"), RL("sh", 113, "hit_eps"), RL("sh", 347, "left the cube"), RL("params", 311, "coarse_steps()")] } },
      { n: "2", name: "Phase 2 · de(p, 32)", f: "≤ fine_steps · stop d < hit_eps(total)", color: C2,
        tip: { ...SH(350), blurb: "Runs even when phase 1 stopped: it refines the hit with the full 32-iteration estimate and the tight threshold, continuing from the same point. n2 = the stop index or fine_steps (max_steps − coarse_steps: 32 by default).", links: [RL("sh", 357, "de(pos, 32)"), RL("sh", 358, "the stop test"), RL("params", 315, "fine_steps()"), RL("spec", 247, "spec: march")] } },
      { n: "ce", name: "Step count → shade", f: "ce = min((n1 + n2) / 128, 1)", color: CHIT,
        tip: { ...SH(369), blurb: "ce is the share of the original 128-step budget used, whatever max_steps is, so a ray that hits looks the same under any budget; a ray that ran out of phase 2 is ce = 1. Every colour mode is built on it (inv = 1 − ce): rays that needed many steps (grazing, in crevices, or never converging) are darker. Leaving the cube (or reaching the fog) is the only miss.", links: [RL("sh", 364, "left_cube → background"), RL("spec", 256, "spec: the dust")] } },
    ]);

    const col = { ramp: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VW, h: VH, pw: PW, ph: PH }, (i, j) => {
      const u = view.cu + ((i + 0.5) / PW - 0.5) * 2 * view.hw, w = view.cw - ((j + 0.5) / PH - 0.5) * 2 * view.hw * VH / VW;
      const p = fromSlice(u, w);
      return col.ramp(de(p[0], p[1], p[2], 32, S.P), 0.5);
    });
    const clipId = "mb-march-clip";
    api.el("rect", { x: GX, y: GY, width: VW, height: VH }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const dyn = api.el("g", { "clip-path": `url(#${clipId})`, style: noPtr });
    const poolG = api.el("g", { "clip-path": `url(#${clipId})` });
    api.el("rect", { x: GX, y: GY, width: VW, height: VH, style: "fill:none;stroke:var(--muted);stroke-width:1.2;pointer-events:none" });
    const viewText = api.text(GX, GY + VH + 18, "", "muted", { style: small });
    const MAXS = 512, rings = [], hops = [], dots = [];     // MAX_STEPS_MAX (fractal_params.gd:205)
    for (let k = 0; k < MAXS; k++) {
      rings.push(api.el("circle", { style: `fill:none;stroke-width:1.2;${noPtr}` }, poolG));
      hops.push(api.el("line", { style: `stroke-width:2;${noPtr}` }, poolG));
    }
    const stepTip = k => ({ title: `step ${k + 1}`, ...SH(343), live() {
      const st = steps[k]; if (!st) return {};
      return { sub: `phase ${st.phase}, i = ${st.i}`, title: `step ${k + 1}: phase ${st.phase}, i = ${st.i}`,
        blurb: `total = ${sci(st.total, 6)}\nd = de(p, ${st.phase === 1 ? 16 : 32}) = ${sci(st.d)}\nthreshold = hit_eps(total)${st.phase === 1 ? " · 2" : ""} = ${sci(st.th)}${S.P.detail_falloff > 0 && st.total > M.lodStart ? ` (past start ${sci(M.lodStart)}: × (total / start)^${fmt(S.P.detail_falloff, 2)} = ×${sci(Math.pow(st.total / M.lodStart, S.P.detail_falloff), 2)})` : ""}\n${st.stop ? "d < threshold: the phase stops here" : `d ≥ threshold: hop d to total = ${sci(st.total + st.d, 6)}`}\np = ${vec(st.p)}` };
    } });
    for (let k = 0; k < MAXS; k++) {
      const d = api.el("circle", { r: 3.2, style: "cursor:pointer" }, poolG);
      dots.push(d);
      api.tip(d, stepTip(k));
    }
    // eye and aim handles
    const eyeH = api.el("circle", { r: 8, style: "fill:var(--ink);stroke:var(--surface);stroke-width:2;cursor:move" });
    const aimH = api.el("circle", { r: 7, style: `fill:${CHIT};stroke:var(--surface);stroke-width:2;cursor:move` });
    api.tip(eyeH, { title: "the eye", ...R("cam", 9), blurb: "Drag to move it. Starts at DEFAULT_EYE, which lies in this plane." });
    api.tip(aimH, { title: "the aim point", ...SH(317), blurb: "The ray points from the eye through here (dir = normalize(aim − eye)). Starts at the origin: the default view's centre ray." });
    draggable(api, eyeH, q => { S.eye = toWorld(q); remarch(); });
    draggable(api, aimH, q => { S.aim = toWorld(q); remarch(); });

    // ---- right panel: readouts and the per-step chart
    const RX = 950;
    const outHead = api.text(RX, 112, "", "ink", { style: caps });
    const outL = [];
    for (let i = 0; i < 10; i++) outL.push(api.text(RX, 138 + i * 20, "", "mono", { style: "font-size:11.5px" }));
    const CX = RX, CY = 366, CW = 580, CH = 220;
    api.text(CX, CY - 14, "log10 d per step, against the threshold", "ink", { style: caps });
    api.el("rect", { x: CX, y: CY, width: CW, height: CH, style: "fill:var(--surface);stroke:var(--hairline)" });
    const LMIN = -9, LMAX = 1, ly = v => CY + CH - (clamp(v, LMIN, LMAX) - LMIN) / (LMAX - LMIN) * CH;
    for (let v = LMIN; v <= LMAX; v += 2) {
      api.el("line", { x1: CX, y1: ly(v), x2: CX + CW, y2: ly(v), style: "stroke:var(--hairline);stroke-width:1" });
      api.text(CX - 6, ly(v) + 4, String(v), "muted", { "text-anchor": "end", style: "font-size:9.5px" });
    }
    const chartG = api.el("g", {});
    const bars = [];
    for (let k = 0; k < MAXS; k++) {
      const b = api.el("rect", { y: CY, width: 3, height: 1, style: "cursor:pointer" }, chartG);
      bars.push(b);
      api.tip(b, stepTip(k));
    }
    const thLine = api.el("polyline", { style: `fill:none;stroke:var(--ink);stroke-width:1.4;stroke-dasharray:4 3;${noPtr}` }, chartG);
    const cursor = api.el("line", { y1: CY, y2: CY + CH, style: `stroke:var(--ink);stroke-width:1;${noPtr}` }, chartG);
    api.text(CX, CY + CH + 16, "bars: d (orange phase 1, blue phase 2) · dashed: the threshold · x: step number", "muted", { style: small });

    function remarch() {
      const e = fromSlice(S.eye[0], S.eye[1]), a = fromSlice(S.aim[0], S.aim[1]);
      const dir = norm([a[0] - e[0], a[1] - e[1], a[2] - e[2]]);
      steps = [];
      M = march(e, dir, S.P, steps);
      M.eye3 = e; M.dir = dir;
      S.s = Math.min(S.s, steps.length + 1);
      render(true);
    }
    function updateView() {
      const prev = `${view.cu},${view.cw},${view.hw}`;
      if (S.zoom <= 1.0001) { view.cu = 3.75; view.cw = 0.6; view.hw = 6.75 * (S.P.julia_all ? 3.4 : 1); }
      else {
        const k = S.s - 1, st = steps[clamp(k, 0, steps.length - 1)];
        const c = S.follow && st && S.s > 0 ? toSlice(st.p) : (steps.length ? toSlice(steps[steps.length - 1].p) : S.eye);
        view.cu = c[0]; view.cw = c[1]; view.hw = 6.75 / S.zoom;
      }
      return prev !== `${view.cu},${view.cw},${view.hw}`;
    }
    function render(force) {
      if (updateView() || force) { col.ramp = deRamp(); heat.restart(); }
      while (dyn.firstChild) dyn.removeChild(dyn.firstChild);
      const n = steps.length, s = S.s, sc = scale();
      // the cube's cross-section and the ray
      const bh = S.P.boxHalf, uh = bh / Math.max(Math.abs(SLICE_U[0]), Math.abs(SLICE_U[1]));
      api.el("rect", { x: px(-uh), y: py(bh), width: 2 * uh * sc, height: 2 * bh * sc, style: "fill:none;stroke:var(--ink);stroke-width:1.4;stroke-dasharray:6 4;opacity:.7" }, dyn);
      const e3 = M.eye3, far = add(e3, M.dir, Math.min(60, Math.max(M.tExit, 1) + 2));
      const es = toSlice(e3), fs = toSlice(far);
      api.el("line", { x1: px(es[0]), y1: py(es[1]), x2: px(fs[0]), y2: py(fs[1]), style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:2 4" }, dyn);
      if (!M.miss) for (const t of [Math.max(M.tEnter, 0), M.tExit]) {
        const q = toSlice(add(e3, M.dir, t));
        api.el("line", { x1: px(q[0]) - 6, y1: py(q[1]) - 6, x2: px(q[0]) + 6, y2: py(q[1]) + 6, style: "stroke:var(--ink);stroke-width:2" }, dyn);
        api.el("line", { x1: px(q[0]) - 6, y1: py(q[1]) + 6, x2: px(q[0]) + 6, y2: py(q[1]) - 6, style: "stroke:var(--ink);stroke-width:2" }, dyn);
      }
      // near_dist (solid) and the full-detail range start = detail_range · near_dist (dashed), round the eye
      api.el("circle", { cx: px(es[0]), cy: py(es[1]), r: Math.min(M.near * sc, 8000), style: `fill:none;stroke:var(--ink);stroke-width:1;opacity:.45` }, dyn);
      if (S.P.detail_falloff > 0) api.el("circle", { cx: px(es[0]), cy: py(es[1]), r: Math.min(M.lodStart * sc, 8000), style: `fill:none;stroke:${api.hue(5)};stroke-width:1.6;stroke-dasharray:7 5` }, dyn);
      // the load shedder's fog: the march ends at fog · near_dist (solid), the fade starts at 0.35 of it (dotted)
      if (S.P.fog > 0) {
        api.el("circle", { cx: px(es[0]), cy: py(es[1]), r: Math.min(S.P.fog * M.near * sc, 8000), style: `fill:none;stroke:${api.hue(4)};stroke-width:2` }, dyn);
        api.el("circle", { cx: px(es[0]), cy: py(es[1]), r: Math.min(0.35 * S.P.fog * M.near * sc, 8000), style: `fill:none;stroke:${api.hue(4)};stroke-width:1.2;stroke-dasharray:2 4` }, dyn);
      }
      // the steps
      for (let k = 0; k < MAXS; k++) {
        const on = k < n && k < s, st = steps[k];
        rings[k].style.display = hops[k].style.display = dots[k].style.display = on ? "" : "none";
        if (!on) continue;
        const q = toSlice(st.p), c = st.stop ? CHIT : st.phase === 1 ? C1 : C2, cur = k === s - 1;
        rings[k].setAttribute("cx", px(q[0])); rings[k].setAttribute("cy", py(q[1]));
        rings[k].setAttribute("r", Math.min(st.d * sc, 4000));
        rings[k].style.stroke = c; rings[k].style.opacity = cur ? 1 : 0.35; rings[k].style.strokeWidth = cur ? 2 : 1.1;
        const q2 = st.stop ? q : toSlice(add(st.p, M.dir, st.d));
        hops[k].setAttribute("x1", px(q[0])); hops[k].setAttribute("y1", py(q[1]));
        hops[k].setAttribute("x2", px(q2[0])); hops[k].setAttribute("y2", py(q2[1]));
        hops[k].style.stroke = c;
        dots[k].setAttribute("cx", px(q[0])); dots[k].setAttribute("cy", py(q[1]));
        dots[k].style.fill = c; dots[k].setAttribute("r", cur ? 5 : 3.2);
      }
      eyeH.setAttribute("cx", px(S.eye[0])); eyeH.setAttribute("cy", py(S.eye[1]));
      aimH.setAttribute("cx", px(S.aim[0])); aimH.setAttribute("cy", py(S.aim[1]));
      const inView = (x, y) => x >= GX && x <= GX + VW && y >= GY && y <= GY + VH;
      eyeH.style.display = inView(px(S.eye[0]), py(S.eye[1])) ? "" : "none";
      aimH.style.display = inView(px(S.aim[0]), py(S.aim[1])) ? "" : "none";
      // chart
      const bw = CW / Math.max(n, 1);
      const pts = [];
      for (let k = 0; k < MAXS; k++) {
        const on = k < n, st = steps[k], b = bars[k];
        b.style.display = on ? "" : "none";
        if (!on) continue;
        const top = ly(Math.log10(Math.max(st.d, 1e-12)));
        b.setAttribute("x", CX + k * bw + 0.5); b.setAttribute("width", Math.max(1, bw - 1));
        b.setAttribute("y", top); b.setAttribute("height", Math.max(1, CY + CH - top));
        b.style.fill = st.stop ? CHIT : st.phase === 1 ? C1 : C2;
        b.style.opacity = k < s ? 1 : 0.3;
        pts.push(`${CX + (k + 0.5) * bw},${ly(Math.log10(Math.max(st.th, 1e-12)))}`);
      }
      thLine.setAttribute("points", pts.join(" "));
      cursor.setAttribute("x1", CX + clamp(s, 0, n) * bw); cursor.setAttribute("x2", CX + clamp(s, 0, n) * bw);
      // stage + readouts
      const cur = steps[s - 1];
      stages.set(s === 0 ? 0 : s > n ? 3 : cur.phase);
      const outcome = M.miss ? "missed the cube: background (no march at all)"
        : M.fogged ? "reached the fog at fog · near_dist: background (the fog colour)"
        : M.left ? "left the cube: background"
        : M.n2 === S.P.fine ? (M.n1 === S.P.coarse ? "ran out of steps in both phases: shaded as ce = 1 (dust)" : "phase 2 ran out of steps: shaded as ce = 1")
        : "hit: phase 2 met the threshold";
      outHead.textContent = s === 0 ? "box intersect" : s > n ? "result" : `step ${s} of ${n} · phase ${cur.phase}, i = ${cur.i}`;
      const lines = [
        `eye ${vec(M.eye3, 3)}   dir ${vec(M.dir, 3)}`,
        `box_half ${S.P.boxHalf}: t_enter ${sci(M.tEnter)}, t_exit ${sci(M.tExit)}${M.miss ? "  → miss" : `, start total = ${sci(M.start)}`}${S.P.fog > 0 && !M.miss ? `, fog ends it at ${sci(M.tEnd)}` : ""}`,
        cur && s <= n ? `total ${sci(cur.total, 6)}   d ${sci(cur.d)}   threshold ${sci(cur.th)}` : "",
        cur && s <= n ? (cur.stop ? `d < threshold: phase ${cur.phase} stops (n${cur.phase} = ${cur.i})` : `hop d → total ${sci(cur.total + cur.d, 6)}`) : "",
        `n1 = ${M.miss ? "–" : M.n1}${M.n1 === S.P.coarse ? " (never stopped)" : ""}    n2 = ${M.miss || (M.left && M.n2 === S.P.fine && M.n1 === S.P.coarse) ? "–" : M.n2}${M.n2 === S.P.fine && !M.left ? " (never stopped)" : ""}    budget ${S.P.coarse} + ${S.P.fine}`,
        M.miss || M.left ? "ce: not used, the pixel is background" : M.n2 === S.P.fine ? `ce = 1 (phase 2 ran out)   inv = 0` : `ce = min((${M.n1} + ${M.n2}) / 128, 1) = ${fmt(M.ce, 4)}   inv = 1 − ce = ${fmt(1 - M.ce, 4)}`,
        `outcome: ${outcome}`,
        M.miss || M.left ? "" : `hit point v = ${vec(add(M.eye3, M.dir, M.total), 4)}, total ${sci(M.total, 6)}`,
        `${n} de() calls (the shader's cost per pixel, before the normal) · coarse_iters ${M.nc}`,
        `near_dist ${sci(M.near)} · ${S.P.detail_falloff > 0 ? `full detail to start = ${fmt(S.P.detail_range, 1)} · near = ${sci(M.lodStart)}, then ^${fmt(S.P.detail_falloff, 2)}` : "falloff 0: the plain cone"}${S.P.shed ? ` · shed level ${S.P.shed}: precision ÷ ${fmt(S.P.detail * SHED_LEVELS[S.P.shed].detail, 2)}, fog ${S.P.fog} × near` : ""}`,
      ];
      lines.forEach((t, i) => { outL[i].textContent = t; });
      outL[6].style.fill = M.miss || M.left ? api.hue(5) : M.n2 === S.P.fine ? api.hue(4) : CHIT;
      viewText.textContent = `u along the eye's heading, w = z · view ±${sci(view.hw, 2)} around (${fmt(view.cu, 3)}, ${fmt(view.cw, 3)}) · ✕ = cube entry and exit`;
    }

    // ---- controls
    const BY = GY + VH + 38;
    let bx = GX;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: BY, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, BY + 17, "March", "ink"); bx += 52;
    btn("◀ Back", 74, () => { S.s = Math.max(0, S.s - 1); render(); });
    btn("Step ▶", 74, () => { S.s = Math.min(steps.length + 1, S.s + 1); render(); });
    const playB = btn("Play", 64, b => { S.play = !S.play; b.set(S.play); if (S.play && S.s > steps.length) S.s = 0; });
    btn("To the end ▶▶", 112, () => { S.s = steps.length + 1; render(); });
    btn("Reset", 64, () => { S.s = 0; S.play = false; playB.set(false); render(); });
    bx += 16;
    btn("Centre ray", 96, () => { S.eye = eye0.slice(); S.aim = [0, 0]; remarch(); });
    const jb = btn("Julia (all) · box ±20", 150, b => { S.P = withP(S.P, { julia_all: !S.P.julia_all }); b.set(S.P.julia_all); remarch(); render(true); });
    const fb = btn("Zoom follows the step", 166, b => { S.follow = !S.follow; b.set(S.follow); render(); }, true);
    // Every slider rebuilds P from the current one, so the others keep their values.
    const setP = o => { S.P = withP(S.P, o); remarch(); };
    api.slider({ x: GX, y: BY + 78, w: 380, label: "Precision (log10)", min: -7, max: -1, step: 0.01, value: Math.log10(S.P.precision),
      fmt: v => sci(Math.pow(10, v), 2), onChange: v => setP({ precision: +Math.pow(10, v).toPrecision(3) }) });
    api.slider({ x: GX + 440, y: BY + 78, w: 440, label: "zoom (log10)", min: 0, max: 5, step: 0.01, value: 0,
      fmt: v => `×${sci(Math.pow(10, v), 2)}`, onChange: v => { S.zoom = Math.pow(10, v); render(); } });
    api.slider({ x: GX + 940, y: BY + 78, w: 380, label: "max_steps (coarse + fine at level 0)", min: 32, max: 512, step: 16, value: S.P.max_steps,
      fmt: v => { const c = Math.floor(v * 3 / 4); return `${v} = ${c} + ${v - c}`; }, onChange: v => setP({ max_steps: v }) });
    api.text(GX, BY + 112, "Renderer tab — level of detail", "ink", { style: caps });
    api.slider({ x: GX, y: BY + 148, w: 380, label: "detail (log10)", min: -1, max: 1, step: 0.01, value: 0,
      fmt: v => `×${fmt(Math.pow(10, v), 2)}`, onChange: v => setP({ detail: +Math.pow(10, v).toPrecision(3) }) });
    api.slider({ x: GX + 440, y: BY + 148, w: 440, label: "detail_range (× near_dist, log10)", min: 0, max: 3, step: 0.01, value: 1,
      fmt: v => `${fmt(Math.pow(10, v), 1)}×`, onChange: v => setP({ detail_range: +Math.pow(10, v).toPrecision(4) }) });
    api.slider({ x: GX + 940, y: BY + 148, w: 380, label: "detail_falloff", min: 0, max: 3, step: 0.05, value: 0,
      fmt: v => (v === 0 ? "0 (off)" : fmt(v, 2)), onChange: v => setP({ detail_falloff: v }) });
    api.slider({ x: GX, y: BY + 210, w: 520, label: "Governor: LoadShedder level (the shader's fog, detail and budget)", min: 0, max: 4, step: 1, value: 0,
      fmt: v => { const L = SHED_LEVELS[v]; return v === 0 ? "0 (full quality)" : `${v}: fog ${L.fog}× · detail ×${L.detail} · steps ×${L.steps}`; }, onChange: v => setP({ shed: v }) });
    api.text(GX, BY + 244, "Try: Step through the default centre ray (n1 = 36, n2 = 3); zoom ×1000 with ‘follow’ to watch the last hops; raise precision to 1e−2 and the hit comes early; aim along a crevice and phase 1 can use all 96 steps (dust); drag the eye within 0.3 of the surface and phase 1's coarse_iters climbs past 16.", "muted", { style: small });
    api.text(GX, BY + 261, "Falloff does nothing from the default eye (start = 10 · near_dist ≈ 66 is past the cube): drag the eye near the surface, set falloff 2, and the dashed ring shows where the threshold starts to grow.", "muted", { style: small });
    let acc = 0;
    api.onFrame(dt => {
      if (!S.play) return;
      acc += dt;
      if (acc < 1 / 6) return;
      acc = 0;
      if (S.s > steps.length) { S.play = false; playB.set(false); return; }
      S.s++; render();
    });
    remarch();
  },
};

// ================================================================== 6. shading and the colour modes
// Dropdown order and names: fractal_params.gd:16-21. Formula text: the renderer spec's table (289-303), plus Palette (20).
const MODES = [
  { id: 0, name: "Grayscale", normal: "none", f: "vec3(1 − ce)", line: 343 },
  { id: 1, name: "Ice Fractal", normal: "NF outside Julia, N in Julia", f: "base · ((1−ce)+0.5, 2(1−ce)²+0.5, 5(1−ce)⁴+0.5)", line: 368 },
  { id: 2, name: "Borg", normal: "NF outside Julia, N in Julia", f: "base · (max(lgt·ce, 1−ce), max(ce, 1−ce), max(0.5·lgt·ce, 1−ce))", line: 370 },
  { id: 3, name: "Rainbow", normal: "NF outside Julia, N in Julia", f: "hue(q)·ce + 0.5·lgt,  q = dot(h, h)/4", line: 373 },
  { id: 4, name: "Rainbow 2", normal: "NF outside Julia, N in Julia", f: "hue(q)·(1 − ce),  q = dot(h, h)/4", line: 376 },
  { id: 8, name: "Rainbow 3", normal: "NF outside Julia, N in Julia", f: "hue(q)·(1 − ce),  q = n.z·0.5 + 0.5 − 0.1", line: 379 },
  { id: 15, name: "Rainbow Metal", normal: "N, in view space", f: "lv = max(0, nv.z)⁴; n2 = normalize(nv + (0.5, 0.5, 0)); (n2 + 1)·0.5·(lv − 2·ce + 0.5)", line: 397 },
  { id: 5, name: "Blue", normal: "NF outside Julia, N in Julia", f: "base · (lgt·max(lgt·ce, 1−ce), lgt + avg, 1 − ce + lgt),  avg = mean(base)", line: 382 },
  { id: 6, name: "Blue 2", normal: "NF outside Julia, N in Julia", f: "the Blue result + ce²", line: 385 },
  { id: 7, name: "Pink-Blue", normal: "NF outside Julia, N in Julia", f: "(1 − 2·ce·(lgt+0.5), avg·(1−ce), (1−ce)·(lgt+0.5))", line: 388 },
  { id: 16, name: "Ice Box", normal: "N", f: "clamp(((1−ce)², 1 − 1.9·ce², 1.17 − ce²), 0, 1)·(lgt + 0.5)", line: 392 },
  { id: 9, name: "Ice Box 2", normal: "NF outside Julia, N in Julia", f: "((1−ce)², 1 − 1.9·ce², 1.17 − ce²)", line: 390 },
  { id: 14, name: "Gold", normal: "N, in view space", f: "lv = max(0, nv.z)⁴; (0.75 − ce)·2·(lv, lv², lv·ce)", line: 401 },
  { id: 20, name: "Palette", normal: "N", f: "palette(fract(src·frequency + offset))·(lgt + 0.5)·mix(1, 1−ce, occlusion),  src = ce | dot(h, h)/4 | n.z·0.5+0.5", line: 407 },
];
const to255 = c => c.map(v => Math.round(clamp(v, 0, 1) * 255));
const shadeFig = {
  type: "figure",
  title: "Shading and the colour modes",
  note: "Every mode is built from ce (the share of the 128-step budget the ray used, tab 5) and lgt, the light term. Left: one mode's output over ce (x, 0 → 1) and l = |dot(n, ldir)| (y, 0 → 1), with the normal fixed facing the light and h taken at the default centre ray's hit. Middle: the light curve lgt = diffuse·l + specular·l^shininess + ambient; the console's Lighting rows default to the site's constants (0.5, 1, 160, 0.1: a broad term plus a needle-sharp highlight), so the site's modes are unchanged until one moves. Exposure and saturation scale the result after the mode, each skipped at 1. The sliders below are those Colour-tab rows, live on the swatch, the curve and the next Render. Palette (20) is this project's own mode: Inigo Quilez's cosine palette A + B·cos(2π(C·t + D)), indexed by the step count, the radius or the normal. Right: Render draws the default view at 96 × 60 with the full port (march, normal, colour), on demand, to eyeball against screenshots/mode_<id>.png from tests/screenshots.sh. Values past 1 are clamped for display, as the GPU does. Under a load-shed level every colour (Grayscale too) is then mixed toward the mode's fog colour by fog_amount(total), and the background becomes that fog colour; the full-quality still frame never has fog.",
  w: 1640, h: 760,
  draw(api) {
    const S = { mode: 1, look: params() };
    // the default centre ray's hit, for h, and the light direction there
    const P0 = params(), M0 = march(DEFAULT_CAM.eye, DEFAULT_CAM.fwd, P0);
    const v0 = add(DEFAULT_CAM.eye, DEFAULT_CAM.fwd, M0.total), h0 = v0.map(x => x / 2), eh0 = DEFAULT_CAM.eye.map(x => x / 2);
    const ldir0 = norm([2 * eh0[0] - h0[0], 2 * eh0[1] - h0[1], 2 * eh0[2] - h0[2]]);
    const modeRefs = MODES.map(m => SH(m.line));
    // ---- mode buttons
    const mbtns = MODES.map((m, i) => api.button({ x: 8 + i * 115, y: 6, w: 108, label: m.name, on: m.id === S.mode, onClick: () => { S.mode = m.id; sync(); } }));
    const info1 = api.text(8, 62, "", "ink", { style: caps });
    const info2 = api.text(8, 82, "", "mono", { style: "font-size:11.5px" });
    // ---- swatch
    const SN = 48, SX = 44, SY = 120, SS = 384;
    const sw = api.image({ x: SX, y: SY, w: SS, h: SS, pw: SN, ph: SN });
    api.el("rect", { x: SX, y: SY, width: SS, height: SS, style: "fill:none;stroke:var(--muted);stroke-width:1;pointer-events:none" });
    api.text(SX, SY + SS + 18, "ce  0 → 1", "muted", { style: small });
    api.text(SX - 10, SY + SS, "0", "muted", { "text-anchor": "end", style: small });
    api.text(SX - 10, SY + 10, "1", "muted", { "text-anchor": "end", style: small });
    api.text(SX - 26, SY + SS / 2, "l = |dot(n, ldir)|", "muted", { "text-anchor": "middle", transform: `rotate(-90 ${SX - 26} ${SY + SS / 2})`, style: small });
    for (let j = 0; j < 12; j++) for (let i = 0; i < 12; i++) {
      const r = api.el("rect", { x: SX + i * 32, y: SY + j * 32, width: 32, height: 32, style: "fill:transparent;cursor:crosshair" });
      api.tip(r, { title: "one swatch", ...SH(405), live() {
        const ce = (i + 0.5) / 12, l = 1 - (j + 0.5) / 12, c = shade(S.mode, ce, l, ldir0, h0, DEFAULT_CAM, S.look);
        const lg = lightTerm(l, S.look);
        return { sub: MODES.find(m => m.id === S.mode).name, blurb: `ce = ${fmt(ce, 3)} (inv ${fmt(1 - ce, 3)})\nl = ${fmt(l, 3)} → lgt = ${fmt(lg, 3)}\nrgb = ${vec(c, 3)}${c.some(v => v > 1 || v < 0) ? " (clamped on screen)" : ""}` };
      } });
    }
    // ---- light curve
    const LX = 480, LY = 120, LW = 330, LH = 250, lx = l => LX + l * LW, lyv = v => LY + LH - v / 1.7 * LH;
    const curveT = api.text(LX, LY - 12, "", "ink", { style: caps });
    api.el("rect", { x: LX, y: LY, width: LW, height: LH, style: "fill:var(--surface);stroke:var(--hairline)" });
    for (const v of [0.1, 0.5, 1, 1.5]) {
      api.el("line", { x1: LX, y1: lyv(v), x2: LX + LW, y2: lyv(v), style: "stroke:var(--hairline)" });
      api.text(LX - 6, lyv(v) + 4, String(v), "muted", { "text-anchor": "end", style: "font-size:9.5px" });
    }
    const curveEl = api.el("polyline", { style: `fill:none;stroke:${api.hue(4)};stroke-width:2.2` });
    const siteCurve = [];
    for (let k = 0; k <= 200; k++) { const l = k / 200; siteCurve.push(`${lx(l)},${lyv(lightTerm(l, LOOK_P))}`); }
    api.el("polyline", { points: siteCurve.join(" "), style: "fill:none;stroke:var(--muted);stroke-width:1;stroke-dasharray:3 3" });
    api.text(LX, LY + LH + 18, "l = |dot(n, ldir)|  0 → 1", "muted", { style: small });
    const cHit = api.el("rect", { x: LX, y: LY, width: LW, height: LH, style: "fill:transparent;cursor:pointer" });
    api.tip(cHit, { title: "the light term", ...SH(405), blurb: "`nl = abs(dot(n, ldir))` with `ldir = normalize(2·eh − h)` (a light at the eye, in the site's half-scale coordinates), turned by light_yaw about cam_up and light_pitch about cam_right when either is non-zero; then `lgt = light_diffuse·nl + light_specular·pow(nl, light_shininess) + light_ambient`. At the site's 0.5, 1, 160, 0.1 the power is a highlight that only fires within a few degrees of facing the light, and the ambient keeps faces turned away from going black. `base = lgt·(−n·0.25 + 0.75) + (0, 0, 0.2)` tints by the normal and adds blue. The dashed curve is the site's.",
      links: [RL("sh", 400, "ldir"), RL("sh", 401, "the light rotation"), RL("sh", 406, "base"), RL("spec", 283, "spec: lighting")] });
    for (let k = 0; k < 4; k++) api.text(LX, LY + LH + 40 + k * 16, [
      "inputs held fixed in the swatch:",
      `h = default centre hit / 2 = ${vec(h0, 3)}`,
      `n = ldir = ${vec(ldir0, 3)} (facing the light)`,
      `dot(h, h)/4 = ${fmt(dot(h0, h0) / 4, 4)} (Rainbow, Rainbow 2)`][k], k ? "mono" : "muted", { style: small });
    // ---- the CPU render
    const RW = 96, RH = 60, RX = 860, RY = 120, RS = 6;
    const pix = new Array(RW * RH);
    const job = { P: null, cam: DEFAULT_CAM };
    const rimg = chunkedImage(api, { x: RX, y: RY, w: RW * RS, h: RH * RS, pw: RW, ph: RH }, (i, j) => {
      const r = renderPixel(job.cam, job.P, (i + 0.5) / RW, (j + 0.5) / RH, 1280 / 800);
      pix[j * RW + i] = r;
      return to255(r.rgb);
    });
    api.el("rect", { x: RX, y: RY, width: RW * RS, height: RH * RS, style: "fill:none;stroke:var(--muted);stroke-width:1;pointer-events:none" });
    const rTitle = api.text(RX, RY - 12, "CPU render of the default view · press Render", "ink", { style: caps });
    for (let j = 0; j < 15; j++) for (let i = 0; i < 24; i++) {
      const r = api.el("rect", { x: RX + i * 24, y: RY + j * 24, width: 24, height: 24, style: "fill:transparent;cursor:crosshair" });
      api.tip(r, { title: "a rendered pixel", ...SH(314), live() {
        const px_ = pix[(j * 4 + 2) * RW + i * 4 + 2];
        if (!px_) return { blurb: "Press Render first." };
        const m = px_.m;
        return { sub: `pixel (${i * 4 + 2}, ${j * 4 + 2}) of 96 × 60`,
          blurb: m.miss ? "missed the cube: background" : m.left ? "left the cube: background"
            : `n1 = ${m.n1}, n2 = ${m.n2}, ce = ${fmt(m.ce, 4)}\ntotal = ${sci(m.total, 5)}\nnormal ${px_.n ? `${px_.useNF ? "NF" : "N"} = ${vec(px_.n, 3)}` : "none (Grayscale)"}\nrgb = ${vec(px_.rgb, 3)}` };
      } });
    }
    const rStat = api.text(RX + 180, RY + RH * RS + 34, "", "mono", { style: small });
    const rStat2 = api.text(RX, RY + RH * RS + 58, "", "mono", { style: small });
    api.button({ x: RX, y: RY + RH * RS + 16, w: 160, label: "Render 96 × 60", onClick: () => {
      job.P = withP(S.look, { color_mode: S.mode });
      const name = MODES.find(m => m.id === S.mode).name, t0 = performance.now();
      rTitle.textContent = `CPU render · ${name} (id ${S.mode}) · compare screenshots/mode_${S.mode}.png`;
      rStat.textContent = "rendering…"; rStat2.textContent = "";
      rimg.restart(() => {
        let sum = [0, 0, 0], black = 0;
        for (const p of pix) { const c = p.rgb.map(v => clamp(v, 0, 1)); sum = add(sum, c); if (c[0] + c[1] + c[2] < 0.03) black++; }
        const mean = sum.map(v => v / pix.length), big = ["red", "green", "blue"][mean.indexOf(Math.max(...mean))];
        rStat.textContent = `done in ${fmt((performance.now() - t0) / 1000, 2)} s over several frames`;
        rStat2.textContent = `mean rgb ${vec(mean, 3)} · largest channel: ${big} · ${fmt(100 * black / pix.length, 1)}% black`;
      });
    } });
    api.link(RX, RY + RH * RS + 84, { file: "tests/screenshots.gd", line: 1, label: "tests/screenshots.gd (writes the PNGs)" });

    // ---- the Colour tab's look rows, live
    const KY = 640;
    api.text(8, KY - 26, "Colour tab — lighting and look (catalogue ranges; site defaults)", "ink", { style: caps });
    const looks = [
      ["light_ambient", "Ambient", 0, 1, 0.01], ["light_diffuse", "Diffuse", 0, 2, 0.01], ["light_specular", "Specular", 0, 4, 0.01],
      ["light_shininess", "Shininess (log2)", 0, 9, 0.01, true], ["exposure", "Exposure", 0, 4, 0.01], ["saturation", "Saturation", 0, 2, 0.01],
    ];
    looks.forEach(([key, label, min, max, step, log], i) => api.slider({ x: 8 + i * 270, y: KY + 10, w: 240, label, min, max, step,
      value: log ? Math.log2(S.look[key]) : S.look[key], fmt: v => fmt(log ? Math.pow(2, v) : v, log ? 1 : 2),
      onChange: v => { S.look = withP(S.look, { [key]: log ? +Math.pow(2, v).toPrecision(4) : v }); sync(); } }));
    api.text(8, KY + 52, "Palette mode", "ink", { style: caps });
    const srcBtns = ["Steps", "Radius", "Normal"].map((label, i) => api.button({ x: 120 + i * 84, y: KY + 38, w: 78, label, on: i === 0,
      onClick: () => { S.look = withP(S.look, { palette_source: i }); srcBtns.forEach((b, k) => b.set(k === i)); sync(); } }));
    [["palette_frequency", "Frequency", 0, 8, 0.01], ["palette_offset", "Offset", 0, 1, 0.001], ["palette_occlusion", "Occlusion", 0, 1, 0.01]]
      .forEach(([key, label, min, max, step], i) => api.slider({ x: 400 + i * 270, y: KY + 62, w: 240, label, min, max, step, value: S.look[key], fmt: v => fmt(v, 2),
        onChange: v => { S.look = withP(S.look, { [key]: v }); sync(); } }));
    const strip = api.image({ x: 1220, y: KY + 44, w: 400, h: 24, pw: 200, ph: 1 });
    api.text(1220, KY + 38, "palette(t), t 0 → 1 (A, B, C, D at their defaults)", "muted", { style: small });
    api.link(1220, KY + 84, { file: "src/color/palette.gd", line: 109, label: "Palette.color_at: the same formula" });

    function sync() {
      const pts = [];
      for (let k = 0; k <= 200; k++) { const l = k / 200; pts.push(`${lx(l)},${lyv(clamp(lightTerm(l, S.look), 0, 1.7))}`); }
      curveEl.setAttribute("points", pts.join(" "));
      curveT.textContent = `lgt = ${fmt(S.look.light_diffuse, 2)}·l + ${fmt(S.look.light_specular, 2)}·l^${fmt(S.look.light_shininess, 1)} + ${fmt(S.look.light_ambient, 2)}`;
      const sd = strip.ctx.createImageData(200, 1);
      for (let k = 0; k < 200; k++) { const c = to255(palette((k + 0.5) / 200, S.look)); sd.data.set([c[0], c[1], c[2], 255], k * 4); }
      strip.ctx.putImageData(sd, 0, 0); strip.flush();
      MODES.forEach((m, i) => mbtns[i].set(m.id === S.mode));
      const m = MODES.find(x => x.id === S.mode);
      info1.textContent = `mode ${m.id} · ${m.name} · normal: ${m.normal} · background ${m.id === 5 || m.id === 6 ? "white" : "black"}`;
      info2.textContent = `col = ${m.f}`;
      const img = sw.ctx.createImageData(SN, SN);
      for (let j = 0; j < SN; j++) for (let i = 0; i < SN; i++) {
        const c = to255(shade(S.mode, (i + 0.5) / SN, 1 - (j + 0.5) / SN, ldir0, h0, DEFAULT_CAM, S.look)), o = (j * SN + i) * 4;
        img.data[o] = c[0]; img.data[o + 1] = c[1]; img.data[o + 2] = c[2]; img.data[o + 3] = 255;
      }
      sw.ctx.putImageData(img, 0, 0); sw.flush();
    }
    sync();
    void modeRefs;
  },
};
const shadeRefs = { modes: MODES.map(m => SH(m.line)), screenshots: { file: "tests/screenshots.gd", line: 1 } };
const modeTable = {
  type: "table",
  title: "The fourteen modes",
  note: "In the console's Colour row order (ids match the site, so a saved number means the same thing; Palette's 20 is past the site's range). NF is the Ice Fractal normal, N the true one (next tab). inv = 1 − ce. Hover a row for its shader line.",
  columns: [{ label: "id", w: 44, mono: true }, { label: "name", w: 120 }, { label: "normal", w: 250 }, { label: "colour", w: 700, mono: true }, { label: "background", w: 110 }],
  rows: MODES.map(m => ({
    cells: [String(m.id), m.name, m.normal, m.f, m.id === 5 || m.id === 6 ? "white" : "black"],
    tip: { title: `${m.id} · ${m.name}`, ...SH(m.line),
      blurb: m.id === 0 ? "Needs no normal, so the shader skips the normal and light work entirely for it (the cheapest mode)."
        : m.normal.startsWith("NF") ? "Uses NF outside Julia (all), N inside it (the branch at line 303)."
        : m.id === 16 ? "Always N, even outside Julia mode. Clamped before the light so it never blows out."
        : m.id === 20 ? "Always N. The palette input is the step count, the radius dot(h, h)/4 or the facing n.z (palette_source), wrapped by fract(src·frequency + offset); occlusion blends in the step-count darkening. The twelve palette numbers are edited in the console's Colour window."
        : "Always N, turned into view space: nv = (dot(N, right), dot(N, up), dot(N, −forward)), so nv.z > 0 faces the camera.",
      links: [RL("params", 16, "COLOR_MODE_IDS"), RL("sh", m.id === 5 || m.id === 6 ? 245 : 303, m.id === 5 || m.id === 6 ? "white background" : "normal choice"), RL("spec", 289, "spec: colour table")] },
  })),
};

// ================================================================== 7. the two normals
const normalsFig = {
  type: "figure",
  tab: "The two normals",
  title: "The two normals: N and the Ice Fractal NF",
  note: "Why modes 1 to 9 look the way they do outside Julia (all). N is the true normal: central differences of de(·, 32) with delta = hit_eps(total) · 40 (precision · total · 40 at the default falloff 0). NF is the gradient of a different field, F(q) = |z16| − 8 (the same mb_step, 16 iterations from z = 0 with c = (q, w), the derivative unused), and not even that: its base sample is taken at the HALF-scale point h = v/2 while the three offset samples are at the full-scale v + 0.01. To first order NF = normalize(∇F(v) + (F(v) − F(h))/0.01 · (1, 1, 1)): the gradient of a different field, tilted toward the (1, 1, 1) diagonal by the half-scale mismatch. On the default view the two normals differ by tens of degrees, and that difference is the Ice Fractal look. The renderer spec says to replicate it exactly, and the shader does, from the default view. Up close it cannot: NF's offsets are a fixed 0.01, which at near_dist 0.001 spans ten views' worth of geometry, so the shading turns to noise (and shrinking the offset does not help, since NF is not a gradient: its three differences converge to one number and the normal collapses to a fixed direction). So the shader crossfades NF into N by nf_weight = smoothstep(0.1, 2, near_dist), pushed with near_dist: 1 (NF alone, the site's maths bit for bit) from 2 out, 0 (N alone, the look the Julia and metal modes already have) inside 0.1, normalize(mix(N, NF, nf_weight)) between. The default eye is at 6.6, so this figure is all NF. Rays fan from the default eye, in the same vertical slice as the march tab, across the cube face it sees; at each hit, N (blue) and NF (orange) are drawn projected onto the plane (a shorter arrow points more out of the plane).",
  w: 1500, h: 820,
  draw(api) {
    const GX = 20, GY = 60, VS = 640, PN = 160, RNG = 2.2, CU = 1.4;
    const S = { P: params(), show: "F", rays: 24 };
    const CN = api.hue(1), CNF = api.hue(2);
    const su = u => GX + (u - CU + RNG) / (2 * RNG) * VS, sw_ = w => GY + (RNG - w) / (2 * RNG) * VS;
    const col = { ramp: null, neg: null, pos: null, bg: null };
    const heat = chunkedImage(api, { x: GX, y: GY, w: VS, h: VS, pw: PN, ph: PN }, (i, j) => {
      const u = CU - RNG + (i + 0.5) / PN * 2 * RNG, w = RNG - (j + 0.5) / PN * 2 * RNG, q = fromSlice(u, w);
      if (S.show === "de") return col.ramp(de(q[0], q[1], q[2], 32, S.P));
      const f = S.show === "F" ? field(q[0], q[1], q[2], S.P) : field(q[0] / 2, q[1] / 2, q[2] / 2, S.P);
      const t = clamp(Math.log10(1 + Math.abs(f)) / 4, 0, 1);
      return mix(col.bg, f < 0 ? col.neg : col.pos, 0.15 + 0.85 * t);
    });
    api.el("rect", { x: GX, y: GY, width: VS, height: VS, style: "fill:none;stroke:var(--muted);stroke-width:1.2;pointer-events:none" });
    const legend = api.text(GX, GY + VS + 18, "", "muted", { style: small });
    const clipId = "mb-normals-clip";
    api.el("rect", { x: GX, y: GY, width: VS, height: VS }, api.el("clipPath", { id: clipId }, api.el("defs", {})));
    const dyn = api.el("g", { "clip-path": `url(#${clipId})`, style: noPtr });
    const hitG = api.el("g", { "clip-path": `url(#${clipId})` });
    const MAXR = 80, hitDots = [];
    let samples = [];
    for (let k = 0; k < MAXR; k++) {
      const d = api.el("circle", { r: 4, style: "fill:var(--ink);stroke:var(--surface);stroke-width:1;cursor:pointer" }, hitG);
      hitDots.push(d);
      api.tip(d, { title: "a surface sample", ...SH(384), live() {
        const s = samples[k]; if (!s) return {};
        const ang = Math.acos(clamp(dot(s.N, s.NF), -1, 1)) * 180 / Math.PI;
        const lg = l => 0.5 * l + Math.pow(l, 160) + 0.1;
        const c1 = shade(1, s.m.ce, s.lN, s.N, s.h, DEFAULT_CAM), c2 = shade(1, s.m.ce, s.lNF, s.NF, s.h, DEFAULT_CAM);
        return { sub: `hit at total ${sci(s.m.total, 5)}, ce ${fmt(s.m.ce, 3)}`,
          blurb: `v = ${vec(s.v, 4)}\nN  = ${vec(s.N, 3)}  (delta = ${sci(s.delta, 2)})\nNF = ${vec(s.NF, 3)}\nangle between them ${fmt(ang, 1)}°\nF(h) = ${sci(s.Fh)}, F(v) = ${sci(s.Fv)}: the base sample alone tilts NF\nlgt with N ${fmt(lg(s.lN), 3)} · with NF ${fmt(lg(s.lNF), 3)}\nIce Fractal colour with N ${vec(c1, 2)} · with NF ${vec(c2, 2)}` };
      } });
    }
    // ---- right panel
    const RX = 700;
    api.text(RX, GY + 12, "Show", "ink", { style: caps });
    const showBtns = [["F", "F(q)"], ["Fh", "F(q / 2)"], ["de", "de(q, 32)"]].map(([k, label], i) =>
      [k, api.button({ x: RX + 56 + i * 104, y: GY, w: 96, label, on: S.show === k, onClick: () => { S.show = k; for (const [kk, b] of showBtns) b.set(kk === k); recolour(); } })]);
    api.slider({ x: RX, y: GY + 70, w: 300, label: "rays in the fan", min: 8, max: MAXR, step: 1, value: S.rays, fmt: v => String(v), onChange: v => { S.rays = v; resample(); } });
    const capN = api.text(RX, GY + 116, "", "mono", { style: small });
    const capNF = api.text(RX, GY + 134, "", "mono", { style: small });
    api.arrow(RX + 560, GY + 112, RX + 600, GY + 112, CN, 2);
    api.arrow(RX + 560, GY + 130, RX + 600, GY + 130, CNF, 2);
    const stat = [];
    for (let i = 0; i < 4; i++) stat.push(api.text(RX, GY + 170 + i * 19, "", "mono", { style: "font-size:11.5px" }));
    const TY = GY + 270;
    ["sample", "angle N·NF", "lgt N", "lgt NF", "NF"].forEach((h, i) => api.text(RX + [0, 80, 190, 280, 370][i], TY, h, "ink", { style: caps }));
    const trows = [];
    for (let r = 0; r < 14; r++) trows.push([0, 80, 190, 280, 370].map(x => api.text(RX + x, TY + 22 + r * 19, "", "mono", { style: small })));
    const L = [
      ["calc_normal: central differences of de(·, 32)", SH(247)],
      ["calc_nf: lw = F(h), offsets at v + 0.01, ÷ 0.01", SH(257)],
      ["delta = hit_eps(total) · 40", SH(378)],
      ["the spec: replicate exactly, not a true gradient", R("spec", 268)],
      ["nf_weight: NF fades into N inside near_dist 2 → 0.1", SH(385)],
    ];
    L.forEach(([t, ref], i) => api.link(RX, TY + 312 + i * 19, Object.assign({ label: t }, ref)));

    function resample() {
      while (dyn.firstChild) dyn.removeChild(dyn.firstChild);
      samples = [];
      const eye = DEFAULT_EYE, eh = eye.map(x => x / 2);
      for (let k = 0; k < S.rays; k++) {
        const aim = fromSlice(2.2, -1.95 + 3.9 * (k + 0.5) / S.rays);
        const dir = norm([aim[0] - eye[0], aim[1] - eye[1], aim[2] - eye[2]]);
        const m = march(eye, dir, S.P);
        if (m.miss || m.left) continue;
        const v = add(eye, dir, m.total), h = v.map(x => x / 2), delta = hitEps(S.P, m.total, m.near) * 40;
        const N = calcNormal(v, delta, S.P), NF = calcNF(v, h, S.P);
        const ldir = norm([2 * eh[0] - h[0], 2 * eh[1] - h[1], 2 * eh[2] - h[2]]);
        samples.push({ m, v, h, N, NF, delta, lN: Math.abs(dot(N, ldir)), lNF: Math.abs(dot(NF, ldir)),
          Fh: field(h[0], h[1], h[2], S.P), Fv: field(v[0], v[1], v[2], S.P) });
      }
      const ARW = 34;
      samples.forEach(s => {
        const q = toSlice(s.v), x = su(q[0]), y = sw_(q[1]);
        const pN = [dot(s.N, [SLICE_U[0], SLICE_U[1], 0]), s.N[2]], pNF = [dot(s.NF, [SLICE_U[0], SLICE_U[1], 0]), s.NF[2]];
        api.arrow(x, y, x + pN[0] * ARW, y - pN[1] * ARW, CN, 1.8, dyn);
        api.arrow(x, y, x + pNF[0] * ARW, y - pNF[1] * ARW, CNF, 1.8, dyn);
      });
      const e = toSlice(DEFAULT_EYE);
      api.text(su(Math.min(e[0], CU + RNG - 0.05)) - 4, sw_(Math.min(e[1], RNG - 0.1)) + 4, "eye ↗ (off the view)", "muted", { "text-anchor": "end", style: small }, dyn);
      hitDots.forEach((d, k) => {
        const s = samples[k];
        d.style.display = s ? "" : "none";
        if (s) { const q = toSlice(s.v); d.setAttribute("cx", su(q[0])); d.setAttribute("cy", sw_(q[1])); }
      });
      // stats + table
      const angs = samples.map(s => Math.acos(clamp(dot(s.N, s.NF), -1, 1)) * 180 / Math.PI);
      const diag = samples.map(s => Math.abs(dot(s.NF, norm([1, 1, 1]))));
      const mean = a => a.reduce((x, y) => x + y, 0) / Math.max(a.length, 1);
      capN.textContent = "N   true normal (de, central differences)";
      capNF.textContent = "NF  Ice Fractal normal (F, mixed half/full scale)";
      stat[0].textContent = `${samples.length} hits from ${S.rays} rays (the rest leave the cube)`;
      stat[1].textContent = `mean angle between N and NF: ${fmt(mean(angs), 1)}°`;
      stat[2].textContent = `mean |NF · (1,1,1)/√3| = ${fmt(mean(diag), 3)} (1 = exactly along the diagonal)`;
      stat[3].textContent = `mean |N · (1,1,1)/√3|  = ${fmt(mean(samples.map(s => Math.abs(dot(s.N, norm([1, 1, 1]))))), 3)}`;
      for (let r = 0; r < 14; r++) {
        const s = samples[Math.floor(r * samples.length / 14)], cells = trows[r];
        if (!s || samples.length < 14 && r >= samples.length) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const idx = Math.floor(r * samples.length / 14);
        const vals = [String(idx + 1), `${fmt(angs[idx], 1)}°`, fmt(s.lN, 3), fmt(s.lNF, 3), vec(s.NF, 2)];
        cells.forEach((c, i) => { c.textContent = vals[i]; });
      }
    }
    function recolour() {
      col.ramp = deRamp(); col.neg = cssRGB("--c6"); col.pos = cssRGB("--c4"); col.bg = cssRGB("--fig-bg");
      heat.restart();
      legend.textContent = S.show === "de" ? "de(q, 32): blue at the surface"
        : `${S.show === "F" ? "F(q)" : "F(q/2), what the base sample sees at each point"}: violet where |z16| < 8 (F < 0), amber where F > 0, shaded by log10(1 + |F|) · u along the eye's heading (${fmt(CU - RNG, 1)} … ${fmt(CU + RNG, 1)}), w = z (±${RNG})`;
    }
    recolour();
    resample();
  },
};

// ================================================================== 8. cameras
const camFig = {
  type: "figure",
  title: "Fly speed, and how the fly camera turns",
  note: "Left: flying along the default centre ray toward the surface it hits. The fly speed is the CPU estimate at the eye, clamped to [1e−6, 20], times speed_factor and the load shedder's speed_limit (0.4 only at its top rung), ×2 while Shift sprints, so speed tracks the remaining gap (grey) and you slow down as you arrive, never overshooting at factor 1. The dots are where a held W puts you after each whole second (60 Hz physics ticks, the port of _physics_process). The wheel slider is the speed factor in wheel ticks (×1.25 each). Right: mouse-look from the default view: yaw turns about world +Z, pitch is clamped 1° off ±Z, and the basis is rebuilt with +Z as the up hint, so roll is always 0.",
  w: 1400, h: 640,
  draw(api) {
    const P = params(), cam = DEFAULT_CAM;
    const hit = march(cam.eye, cam.fwd, P), T = hit.total;
    const S = { ticks: 0, factor: 1, dx: 0, dy: 0, sens: 0.1, sprint: false, limit: 1 };
    // n wheel ticks from factor 1, each through the ported scroll() (so the 0.01 … 100 clamp applies)
    const ticksToFactor = n => { let f = 1; for (let k = 0; k < Math.abs(n); k++) f = scrollFactor(f, n > 0); return f; };
    // ---- speed plot
    const X0 = 70, Y0 = 50, W = 640, H = 380, LMIN = -6, LMAX = 1.5;
    const xs = t => X0 + t / T * W, ys = v => Y0 + H - (clamp(Math.log10(Math.max(v, 1e-9)), LMIN, LMAX) - LMIN) / (LMAX - LMIN) * H;
    api.el("rect", { x: X0, y: Y0, width: W, height: H, style: "fill:var(--surface);stroke:var(--hairline)" });
    for (let v = LMIN; v <= 1; v++) {
      api.el("line", { x1: X0, y1: ys(Math.pow(10, v)), x2: X0 + W, y2: ys(Math.pow(10, v)), style: "stroke:var(--hairline)" });
      api.text(X0 - 8, ys(Math.pow(10, v)) + 4, `1e${v}`, "muted", { "text-anchor": "end", style: "font-size:9.5px" });
    }
    for (let k = 0; k <= 7; k++) api.text(xs(k), Y0 + H + 16, String(k), "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
    api.text(X0 + W, Y0 + H + 34, `distance travelled along the centre ray (the hit is at ${fmt(T, 4)})`, "muted", { "text-anchor": "end", style: small });
    api.text(X0, Y0 - 12, "speed (units / s), log scale", "ink", { style: caps });
    const gap = [], spd = [];
    for (let k = 0; k <= 400; k++) {
      const t = T * k / 400 * 0.99999;
      gap.push(`${xs(t)},${ys(T - t)}`);
    }
    api.el("polyline", { points: gap.join(" "), style: "fill:none;stroke:var(--muted);stroke-width:1.4;stroke-dasharray:5 4" });
    const curve = api.el("polyline", { style: `fill:none;stroke:${api.hue(3)};stroke-width:2.2` });
    const simG = api.el("g", {});
    const secDots = [];
    for (let s = 0; s < 10; s++) {
      const c = api.el("circle", { r: 4.5, style: `fill:${api.hue(3)};stroke:var(--surface);stroke-width:1.2;cursor:pointer` }, simG);
      const t = api.text(0, 0, `${s + 1}s`, "", { "text-anchor": "middle", style: `${small};${noPtr}` }, simG);
      secDots.push({ c, t });
      api.tip(c, { title: `after ${s + 1} s of W`, ...R("fly", 82), live() {
        const d = secDots[s];
        return { sub: `speed_factor ${fmt(S.factor, 4)}`, blurb: `travelled ${sci(d.x, 5)} of ${fmt(T, 4)} (${fmt(100 * d.x / T, 3)}% of the gap)\nspeed there ${sci(d.v)} units/s\nD there ${sci(d.D)}` };
      } });
    }
    const read1 = api.text(X0, Y0 + H + 62, "", "mono", { style: "font-size:11.5px" });
    const read2 = api.text(X0, Y0 + H + 82, "", "mono", { style: "font-size:11.5px" });
    api.slider({ x: X0, y: Y0 + H + 122, w: 400, label: "speed factor (wheel ticks, ×1.25 each)", min: -25, max: 25, step: 1, value: 0,
      fmt: v => `${v > 0 ? "+" : ""}${v} → ×${sci(ticksToFactor(v), 3)}`, onChange: v => {
        S.ticks = v; S.factor = ticksToFactor(v); drawSpeed();
      } });
    api.link(X0 + 430, Y0 + H + 132, RL("fly", 153, "scroll(): ×1.25, clamp 0.01 … 100"));
    api.button({ x: X0, y: Y0 + H + 160, w: 150, label: "Shift: sprint ×2", on: false, onClick: b => { S.sprint = !S.sprint; b.set(S.sprint); drawSpeed(); } });
    api.button({ x: X0 + 160, y: Y0 + H + 160, w: 230, label: "shed level 4: speed_limit 0.4", on: false, onClick: b => { S.limit = S.limit === 1 ? SHED_LEVELS[4].speed : 1; b.set(S.limit !== 1); drawSpeed(); } });
    api.link(X0 + 400, Y0 + H + 176, RL("fly", 18, "SPRINT_MULTIPLIER"));
    function drawSpeed() {
      const pts = [];
      for (let k = 0; k <= 400; k++) {
        const t = T * k / 400 * 0.99999;
        pts.push(`${xs(t)},${ys(flySpeed(add(cam.eye, cam.fwd, t), P, S.factor, S.limit, S.sprint))}`);
      }
      curve.setAttribute("points", pts.join(" "));
      // hold W: 60 Hz physics ticks, origin += forward · current_speed · delta
      let x = 0, over = false;
      for (let s = 0; s < 10; s++) {
        for (let n = 0; n < 60; n++) x += flySpeed(add(cam.eye, cam.fwd, x), P, S.factor, S.limit, S.sprint) / 60;
        if (x > T) over = true;
        const p = add(cam.eye, cam.fwd, x), d = secDots[s];
        d.x = x; d.D = de(p[0], p[1], p[2], 32, P); d.v = flySpeed(p, P, S.factor, S.limit, S.sprint);
        const xx = xs(Math.min(x, T)), yy = ys(d.v);
        d.c.setAttribute("cx", xx); d.c.setAttribute("cy", yy);
        d.t.setAttribute("x", xx); d.t.setAttribute("y", yy - 9);
        d.c.style.display = d.t.style.display = s < 6 || s === 9 ? "" : "none";
      }
      const d1 = secDots[0];
      read1.textContent = `speed at the eye = clamp(D(eye) = ${fmt(de(...cam.eye, 32, P), 4)}, 1e−6, 20) × ${sci(S.factor, 3)} × ${S.limit}${S.sprint ? " × 2" : ""} = ${sci(flySpeed(cam.eye, P, S.factor, S.limit, S.sprint), 4)} units/s`;
      read2.textContent = `after 1 s: ${fmt(100 * d1.x / T, 2)}% of the gap · after 10 s: ${fmt(100 * secDots[9].x / T, 4)}%${over ? " · OVERSHOT the surface" : " · never past the surface"}`;
    }
    drawSpeed();

    // ---- mouse-look diagram
    const CX = 960, CY = 200, RR = 130, TX = 1240;
    api.text(CX - RR, Y0 - 12, "pitch (side view)", "ink", { style: caps });
    api.text(TX - RR + 10, Y0 - 12, "yaw (top view)", "ink", { style: caps });
    api.el("circle", { cx: CX, cy: CY, r: RR, style: "fill:none;stroke:var(--hairline);stroke-width:1.2" });
    api.el("line", { x1: CX, y1: CY - RR - 14, x2: CX, y2: CY + RR + 14, style: "stroke:var(--muted);stroke-width:1" });
    api.el("line", { x1: CX - RR - 14, y1: CY, x2: CX + RR + 14, y2: CY, style: "stroke:var(--hairline);stroke-width:1" });
    api.text(CX + 6, CY - RR - 4, "+Z (world up)", "muted", { style: small });
    api.text(CX - RR + 6, CY - 6, "horizontal", "muted", { style: small });
    // the forbidden 1° caps, drawn exaggerated ×4 so they are visible
    for (const sgn of [-1, 1]) {
      const a = 4 * Math.PI / 180, y = CY - sgn * RR;
      api.el("path", { d: `M ${CX} ${CY} L ${CX - RR * Math.sin(a)} ${CY - sgn * RR * Math.cos(a)} A ${RR} ${RR} 0 0 ${sgn > 0 ? 1 : 0} ${CX + RR * Math.sin(a)} ${CY - sgn * RR * Math.cos(a)} Z`,
        style: `fill:${api.hue(5)};opacity:.35;stroke:none` });
      void y;
    }
    api.text(CX - RR - 6, CY - RR + 18, "1° cap (drawn ×4)", "", { "text-anchor": "end", style: `${small};fill:${api.hue(5)}` });
    const pitchArrowG = api.el("g", {}), yawArrowG = api.el("g", {});
    api.el("circle", { cx: TX, cy: CY, r: RR, style: "fill:none;stroke:var(--hairline);stroke-width:1.2" });
    api.el("line", { x1: TX - RR - 10, y1: CY, x2: TX + RR + 10, y2: CY, style: "stroke:var(--hairline)" });
    api.el("line", { x1: TX, y1: CY - RR - 10, x2: TX, y2: CY + RR + 10, style: "stroke:var(--hairline)" });
    api.text(TX + RR + 4, CY - 4, "+X", "muted", { style: small });
    api.text(TX + 4, CY - RR - 4, "+Y", "muted", { style: small });
    const lookT = [];
    for (let i = 0; i < 4; i++) lookT.push(api.text(CX - RR, CY + RR + 44 + i * 19, "", "mono", { style: "font-size:11.5px" }));
    const SY_ = CY + RR + 130;
    api.slider({ x: CX - RR, y: SY_, w: 200, label: "mouse dx (px)", min: -1800, max: 1800, step: 10, value: 0, fmt: v => String(v), onChange: v => { S.dx = v; drawLook(); } });
    api.slider({ x: CX - RR + 230, y: SY_, w: 200, label: "mouse dy (px)", min: -1800, max: 1800, step: 10, value: 0, fmt: v => String(v), onChange: v => { S.dy = v; drawLook(); } });
    api.slider({ x: CX - RR, y: SY_ + 56, w: 200, label: "Mouse sensitivity (°/px)", min: 0.02, max: 0.5, step: 0.001, value: 0.1, fmt: v => fmt(v, 3), onChange: v => { S.sens = v; drawLook(); } });
    api.link(CX - RR + 230, SY_ + 62, RL("fly", 106, "apply_look"));
    api.link(CX - RR + 230, SY_ + 80, RL("fly", 12, "MAX_FORWARD_Z = sin 89°"));
    function drawLook() {
      while (pitchArrowG.firstChild) pitchArrowG.removeChild(pitchArrowG.firstChild);
      while (yawArrowG.firstChild) yawArrowG.removeChild(yawArrowG.firstChild);
      const c2 = applyLook(cam, S.dx, S.dy, S.sens), f = c2.fwd;
      const pitch = Math.asin(clamp(f[2], -1, 1)), yaw = Math.atan2(f[1], f[0]);
      const p0 = Math.asin(cam.fwd[2]), y0 = Math.atan2(cam.fwd[1], cam.fwd[0]);
      api.arrow(CX, CY, CX + RR * 0.92 * Math.cos(p0), CY - RR * 0.92 * Math.sin(p0), "var(--muted)", 1.2, pitchArrowG);
      api.arrow(CX, CY, CX + RR * 0.92 * Math.cos(pitch), CY - RR * 0.92 * Math.sin(pitch), api.hue(3), 2.4, pitchArrowG);
      api.arrow(TX, CY, TX + RR * 0.92 * Math.cos(y0), CY - RR * 0.92 * Math.sin(y0), "var(--muted)", 1.2, yawArrowG);
      api.arrow(TX, CY, TX + RR * 0.92 * Math.cos(yaw), CY - RR * 0.92 * Math.sin(yaw), api.hue(3), 2.4, yawArrowG);
      const atCap = Math.abs(f[2]) >= MAX_FORWARD_Z - 1e-9;
      lookT[0].textContent = `forward ${vec(f, 4)}`;
      lookT[1].textContent = `pitch ${fmt(pitch * 180 / Math.PI, 2)}°${atCap ? "  (clamped at ±89°)" : ""}   yaw ${fmt(yaw * 180 / Math.PI, 2)}°`;
      lookT[2].textContent = `right.z = ${sci(c2.right[2], 2)}  (no roll: the basis is rebuilt with +Z up)`;
      lookT[3].textContent = `from the default view: pitch ${fmt(p0 * 180 / Math.PI, 2)}°, yaw ${fmt(y0 * 180 / Math.PI, 2)}°`;
      lookT[1].style.fill = atCap ? api.hue(5) : "";
    }
    drawLook();
  },
};
const camTable = {
  type: "table",
  title: "Every gesture, its constant and its line",
  note: "FlyCamera's are tested in tests/fly_camera_test.gd, OrbitCamera's in tests/orbit_camera_test.gd. dist = the eye-to-centre distance.",
  columns: [{ label: "camera", w: 80 }, { label: "gesture", w: 210 }, { label: "constant", w: 290 }, { label: "what it does", w: 540 }],
  rows: [
    { cells: ["fly", "mouse move (captured)", "−dx·sens°, −dy·sens°; |forward.z| ≤ sin 89°", "Yaw about world +Z keeps the pitch; pitch clamps the ANGLE (not forward.z), so a huge delta saturates instead of wrapping. No roll."],
      tip: { ...R("fly", 106), links: [RL("fly", 112, "the clamp"), RL("fly", 107, "a zero delta returns"), RL("tFly", 108, "saturation test")] } },
    { cells: ["fly", "W A S D · Space Backspace", "dir · clamp(D(eye), 1e−6, 20) · factor · limit · delta", "Camera-axis direction, normalised (a diagonal is not faster); nothing while Cmd or Ctrl is held or a text field in any window has focus."],
      tip: { ...R("fly", 124), links: [RL("fly", 139, "current_speed"), RL("fly", 127, "TextFocus"), RL("tFly", 29, "normalised test")] } },
    { cells: ["fly", "hold Shift (sprint)", "× SPRINT_MULTIPLIER = 2", "Doubles the travel speed while held; Q and E are free for Axis A."],
      tip: { ...R("fly", 77), links: [RL("fly", 18, "SPRINT_MULTIPLIER"), RL("proj", 53, "the sprint action"), RL("tFly", 61, "the test")] } },
    { cells: ["fly", "(load shed level 4)", "speed_limit = 0.4", "The governor's last resort: at the top shed rung Main caps the travel speed, so the march gets fewer new pixels per second."],
      tip: { ...R("main", 338), links: [RL("shed", 19, "level 4"), RL("fly", 22, "speed_limit")] } },
    { cells: ["fly", "(near the surface)", "refused below zoom_floor = ulp32(max |eye|) / (50 · eps)", "A move whose target is closer to the surface than the floor (about 1e−4 near the box) is refused unless it is no closer than now, so backing away always works. The Movement pane shows `zoom limit` while it holds you."],
      tip: { ...R("fly", 83), links: [RL("fly", 95, "move_allowed"), RL("params", 304, "zoom_floor"), RL("params", 282, "ulp32"), RL("movement", 296, "the zoom limit readout"), RL("main", 258, "Main forwards at_zoom_limit"), RL("tFly", 155, "the test")] } },
    { cells: ["fly", "wheel", "×1.25 / ÷1.25, clamp 0.01 … 100", "Scales speed_factor; the console's Movement pane shows `speed x f`."], tip: { ...R("fly", 153), links: [{ file: "src/ui/console/movement_pane.gd", line: 310, label: "the speed readout" }] } },
    { cells: ["orbit", "left-drag", "0.5°/px · sens / 0.1", "Rotates the eye about `center`: yaw about +Z, pitch about the camera's right. A step that would bring forward within 1° of ±Z keeps its yaw and drops its pitch."],
      tip: { ...R("orbit", 85), links: [RL("orbit", 9, "ROT_PER_PIXEL"), RL("orbit", 96, "the pitch guard"), RL("tOrbit", 18, "keeps distance")] } },
    { cells: ["orbit", "Shift + left-drag", "0.001 · dist per px", "Pans in the camera's right/up plane, moving the eye and `center` by the same vector."],
      tip: { ...R("orbit", 103), links: [RL("orbit", 10, "PAN_PER_PIXEL"), RL("orbit", 61, "Shift")] } },
    { cells: ["orbit", "right-drag, or Alt + left-drag", "0.005 · dist per px", "Dollies along the view axis toward or away from `center`, never closer than 1e−4."],
      tip: { ...R("orbit", 112), links: [RL("orbit", 11, "DOLLY_PER_PIXEL"), RL("orbit", 68, "right-drag")] } },
    { cells: ["orbit", "wheel", "0.1 · dist per tick", "Moves the eye along the cursor's ray (toward on wheel-up); `center` stays, so the distance changes."],
      tip: { ...R("orbit", 120), links: [RL("orbit", 12, "ZOOM_PER_TICK"), RL("orbit", 144, "_cursor_dir")] } },
    { cells: ["orbit", "click (motion < 4 px)", "hit within 2 × dist, else the origin", "CPU-marches the cursor ray (one phase, de(·, 32), ≤ 200 steps, stop at hit_epsilon(total, near): the shader's threshold) and re-centres on the hit without moving the camera."],
      tip: { ...R("orbit", 134), links: [RL("orbit", 13, "CLICK_SLOP"), RL("orbit", 155, "_march"), RL("orbit", 165, "the hit_epsilon stop"), RL("orbit", 138, "the 2× test")] } },
    { cells: ["orbit", "switch into ORBIT", "hit within 2 × |eye|, else the origin", "`enter()`: the same march along the centre ray. Only on a real mode change (and after a load), never on a slider move."],
      tip: { ...R("orbit", 76), links: [RL("main", 362, "Main: only on a change"), RL("main", 301, "after a load")] } },
    { cells: ["marker", "drag the Julia ring (Julia (all), mouse free)", "press within 2 × RING_RADIUS = 20 px", "Captures depth = (julia_point() − eye) · forward, then writes unproject(mouse, depth) into the table's c_0..c_2 defaults (and mirrors them into FractalParams): it slides in the plane facing the camera, and the next resolve keeps it."],
      tip: { ...R("marker", 41), links: [RL("marker", 45, "the 20 px test"), RL("marker", 56, "unproject"), RL("marker", 61, "into the table"), RL("tMarker", 37, "the test")] } },
    { cells: ["Main", "Reset camera (Movement pane, View tab ▸ Renderer)", "the current file's camera, else the starting view", "Puts the transform and speed factor back where the last load or save left them (remembered by `_remember_home`); in ORBIT it re-centres with `enter()`."],
      tip: { ...R("main", 312), links: [RL("main", 321, "_remember_home"), RL("main", 157, "the Movement pane's button"), RL("main", 195, "the View tab's")] } },
    { cells: ["Main", "mouse capture","FLY, not freed, noise closed", "Captured, otherwise visible. Escape, a Ctrl tap or a file panel frees it (`_free_requested`); a click on the view while free in FLY recaptures (and is the user gesture pointer lock needs on the web). The console's visibility does not gate capture: it stays open while you fly."],
      tip: { ...R("main", 368), links: [RL("main", 464, "click to capture"), RL("main", 384, "the Ctrl tap")] } },
  ],
};

for (const r of camTable.rows) r.tip.title = `${r.cells[0]} · ${r.cells[1]}`;

// ================================================================== 9. resolution governor
const govFig = {
  type: "figure",
  tab: "Resolution governor",
  title: "Resolution governor and load shedder, frame by frame",
  note: "The ported ResolutionGovernor.step(frame_time, changing) and its LoadShedder.step, fed by you. Each Step is one frame: the frame-time slider is how long that frame took and ‘changing’ is whether CameraState or FractalParams emitted `changed` during it (a binding to Time makes every frame changing). While changing it renders continuously and keeps an EMA of frame time (α 0.2) against 1/30 s: above 1.2× it multiplies the scale by 0.8, below 0.6× it divides by 0.8 (only once no level is shed), clamped to min_scale … 1, at most once per 0.5 s. Once the scale sits at its floor the shedder takes over: 0.5 s under 24 fps sheds a level (fog, detail, step budget, at the top the Fly speed), 2 s over 40 fps restores one, at most one shed per second, and a shed within 5 s of a restore doubles the next restore's wait (up to 16 s, forgiven after 10 calm seconds). When changes stop it SETTLES for 0.15 s, renders one FINAL_FRAME at full scale and full quality, then goes IDLE; moving again resumes the moving scale and level. Fast Controls off pins the scale at 1 and resets the shedder.",
  w: 1440, h: 920,
  draw(api) {
    const G = newGovernor();
    const S = { ms: 60, changing: true, run: false };
    let hist = [];
    const MC = [api.hue(2), api.hue(4), api.hue(3), api.hue(1)];
    // ---- the state graph
    const NY = 40, NW = 230, NH = 52, NX = [40, 380, 720, 1060];
    const nodeR = [], desc = [
      ["CONTINUOUS", "UPDATE_ALWAYS · scale and level adapt", R("gov", 83)],
      ["SETTLING", "last moving frame stays · < 0.15 s quiet", R("gov", 128)],
      ["FINAL_FRAME", "UPDATE_ONCE · scale 1 · level 0", R("gov", 86)],
      ["IDLE", "UPDATE_DISABLED · nothing renders", R("gov", 89)],
    ];
    desc.forEach(([name, sub, ref], i) => {
      const r = api.el("rect", { x: NX[i], y: NY, width: NW, height: NH, rx: 10, style: `fill:var(--surface);stroke:${MC[i]};stroke-width:1.5;cursor:pointer` });
      nodeR.push(r);
      api.text(NX[i] + 14, NY + 22, name, "ink", { style: `font-weight:700;${noPtr}` });
      api.text(NX[i] + 14, NY + 40, sub, "muted", { style: `${small};${noPtr}` });
      api.tip(r, { title: name, sub: "ResolutionGovernor.Mode", ...ref, blurb: [
        "Rendering every frame (`set_continuous(true)`) while anything changes, at the governor's current scale and the shedder's level.",
        "Still, but under `settle` seconds of quiet: rendering stops and the last moving frame stays on screen. A captured mouse at rest still sends stray events; without the wait each one bought a full-resolution frame.",
        "One frame at full scale and shed level 0 after 0.15 s of quiet: `set_continuous(false)` then `request_frame()`.",
        "Updates disabled: the TextureRect keeps the last image, zero GPU cost until something changes."][i], links: [RL("gov", 15, "enum Mode")] });
    });
    const edge = (d, label, lx, ly, ref, blurb) => {
      api.el("path", { d, style: "fill:none;stroke:var(--edge);stroke-width:1.6", "marker-end": "url(#viz-arrow)" });
      const hit = api.el("path", { d, style: "fill:none;stroke:transparent;stroke-width:14;cursor:pointer" });
      api.tip(hit, { title: label, ...ref, blurb });
      api.text(lx, ly, label, "", { "text-anchor": "middle", style: `${small};${noPtr}` });
    };
    const mid = NY + NH / 2;
    edge(`M ${NX[0] + NW} ${mid - 8} L ${NX[1] - 4} ${mid - 8}`, "still", (NX[0] + NW + NX[1]) / 2, mid - 16, R("gov", 121), "`_idle_pending` was set while changing: still frames accumulate `_quiet`.");
    edge(`M ${NX[1] + NW} ${mid - 8} L ${NX[2] - 4} ${mid - 8}`, "quiet ≥ 0.15 s", (NX[1] + NW + NX[2]) / 2, mid - 16, R("gov", 123), "FINAL_FRAME: scale = 1, the pending flag cleared; `applied_level()` is 0 outside CONTINUOUS and SETTLING.");
    edge(`M ${NX[2] + NW} ${mid - 8} L ${NX[3] - 4} ${mid - 8}`, "still again", (NX[2] + NW + NX[3]) / 2, mid - 16, R("gov", 131), "Nothing pending: IDLE every frame until something changes.");
    edge(`M ${NX[1] + 40} ${NY + NH} C ${NX[1] + 20} ${NY + NH + 40}, ${NX[0] + NW - 20} ${NY + NH + 40}, ${NX[0] + NW - 40} ${NY + NH + 4}`, "changing", (NX[0] + NW + NX[1]) / 2, NY + NH + 44, R("gov", 102), "Any changing frame goes (back) to CONTINUOUS.");
    edge(`M ${NX[3] + 40} ${NY + NH} C ${NX[3] + 10} ${NY + NH + 96}, ${NX[0] + 120} ${NY + NH + 96}, ${NX[0] + 100} ${NY + NH + 4}`, "changing: resume the moving scale", (NX[0] + NX[3]) / 2 + 160, NY + NH + 84, R("gov", 99), "From FINAL_FRAME or IDLE the scale restarts at `_moving_scale`, where motion left off, not at 1.0; the shed level was never reset.");
    // ---- controls
    const BY = 230;
    api.slider({ x: 60, y: BY + 10, w: 300, label: "this frame's time (ms)", min: 1, max: 150, step: 1, value: S.ms, fmt: v => `${v} ms`, onChange: v => { S.ms = v; } });
    let bx = 420;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: BY, w, label, on, onClick }); bx += w + 8; return b; };
    btn("changing", 96, b => { S.changing = !S.changing; b.set(S.changing); }, true);
    btn("Fast Controls", 116, b => { G.fast = !G.fast; b.set(G.fast); }, true);
    bx += 16;
    btn("Step ▶", 76, () => stepOnce());
    const runB = btn("Run", 64, b => { S.run = !S.run; b.set(S.run); });
    btn("Reset", 66, () => { Object.assign(G, newGovernor(), { fast: G.fast, minScale: G.minScale }); hist = []; S.run = false; runB.set(false); render(); });
    api.slider({ x: bx + 10, y: BY + 10, w: 220, label: "min_render_scale", min: 0.1, max: 1, step: 0.05, value: G.minScale,
      fmt: v => fmt(v, 2), onChange: v => { G.minScale = v; render(); } });
    bx += 250;
    const ref1 = api.text(60, BY + 64, "", "mono", { style: "font-size:11.5px" });
    const ref2 = api.text(60, BY + 84, "", "mono", { style: "font-size:11.5px" });
    api.text(bx + 10, BY + 17, "Run steps 30 frames a second", "muted", { style: small });
    api.text(bx + 10, BY + 33, "with the slider's frame time.", "muted", { style: small });
    // ---- strip chart
    const CX = 60, CW = 1320, NF = 120, COLW = CW / NF;
    const lanes = [
      { name: "scale", y: 360, h: 100 },
      { name: "mode", y: 480, h: 22 },
      { name: "shed level", y: 522, h: 90 },
      { name: "EMA (ms)", y: 632, h: 130 },
      { name: "cooldown", y: 782, h: 70 },
    ];
    for (const ln of lanes) {
      api.el("rect", { x: CX, y: ln.y, width: CW, height: ln.h, style: "fill:var(--surface);stroke:var(--hairline)" });
      api.text(CX - 8, ln.y + 14, ln.name, "ink", { "text-anchor": "end", style: `${small};font-weight:600` });
    }
    const [lS, lM, lL, lE, lC] = lanes;
    const yS = v => lS.y + lS.h - (v - 0.05) / 1.0 * lS.h;
    const yL = v => lL.y + lL.h - 6 - v / 4 * (lL.h - 12);
    const EMAX = 80, yE = v => lE.y + lE.h - clamp(v / EMAX, 0, 1) * lE.h;
    const yC = v => lC.y + lC.h - clamp(v / 1.0, 0, 1) * lC.h;
    for (const v of [0.1, 0.25, 0.5, 1]) { api.el("line", { x1: CX, y1: yS(v), x2: CX + CW, y2: yS(v), style: "stroke:var(--hairline)" }); api.text(CX + CW + 6, yS(v) + 4, String(v), "muted", { style: "font-size:9.5px" }); }
    for (let v = 0; v <= 4; v++) { api.el("line", { x1: CX, y1: yL(v), x2: CX + CW, y2: yL(v), style: "stroke:var(--hairline)" }); api.text(CX + CW + 6, yL(v) + 4, String(v), "muted", { style: "font-size:9.5px" }); }
    for (const [v, lab] of [[1000 / 30, "1/30 s"], [1.2 * 1000 / 30, "1.2×"], [0.6 * 1000 / 30, "0.6×"], [1000 / 24, "24 fps"], [1000 / 40, "40 fps"]]) {
      const shedLine = lab.endsWith("fps");
      api.el("line", { x1: CX, y1: yE(v), x2: CX + CW, y2: yE(v), style: `stroke:${lab === "1/30 s" ? "var(--muted)" : shedLine ? api.hue(6) : "var(--hairline)"};stroke-dasharray:4 3;opacity:${shedLine ? 0.6 : 1}` });
      if (shedLine) api.text(CX + 6, yE(v) - 3, lab, "", { style: `font-size:9.5px;fill:${api.hue(6)}` });
      else api.text(CX + CW + 6, yE(v) + 4, lab, "muted", { style: "font-size:9.5px" });
    }
    api.el("line", { x1: CX, y1: yC(0.5), x2: CX + CW, y2: yC(0.5), style: "stroke:var(--muted);stroke-dasharray:4 3" });
    api.text(CX + CW + 6, yC(0.5) + 4, "0.5 s", "muted", { style: "font-size:9.5px" });
    const dyn = api.el("g", { style: noPtr });
    for (let k = 0; k < NF; k++) {
      const r = api.el("rect", { x: CX + k * COLW, y: lS.y, width: COLW, height: lC.y + lC.h - lS.y, style: "fill:transparent;cursor:pointer" });
      api.tip(r, { title: "a frame", ...R("gov", 96), live() {
        const off = Math.max(0, hist.length - NF), h = hist[off + k];
        if (!h) return { title: "no frame yet", blurb: "Step or Run to feed the governor." };
        const L = SHED_LEVELS[h.applied];
        return { title: `frame ${off + k + 1}`, sub: `${fmt(h.ms, 0)} ms · changing ${h.changing} · Fast Controls ${h.fast}`,
          blurb: `mode ${MODE_NAMES[h.mode]}\nscale ${fmt(h.scale, 4)} (render ${Math.round(1280 * h.scale)} × ${Math.round(800 * h.scale)} points of 1280 × 800)\nshed level ${h.level}, applied ${h.applied}${h.applied ? `: fog ${L.fog} × near · detail ×${L.detail} · steps ×${L.steps} · speed ×${L.speed}` : " (full quality)"}\nEMA ${fmt(h.ema * 1000, 2)} ms = ${fmt(1 / h.ema, 1)} fps (lower above 40 ms, raise below 20; shed under 24 fps, restore over 40)\nunder 24 fps for ${fmt(h.slow, 2)} s · over 40 fps for ${fmt(h.fastFor, 2)} s (restore needs ${fmt(h.dwell, 1)} s)\nsince last scale change ${fmt(h.since, 3)} s${h.why.length ? `\n${h.why.join(", ")}` : ""}` };
      } });
    }
    api.text(CX, lC.y + lC.h + 18, "oldest ← the last 120 frames → newest · hover a column for that frame's numbers", "muted", { style: small });
    api.link(CX + 600, lC.y + lC.h + 18, RL("tGov", 5, "the governor test"));
    api.link(CX + 800, lC.y + lC.h + 18, RL("tShed", 24, "the shedder test"));

    function stepOnce() {
      const why = governorStep(G, S.ms / 1000, S.changing);
      hist.push({ ms: S.ms, changing: S.changing, fast: G.fast, mode: G.mode, scale: G.scale, ema: G.ema, since: G.since, why,
        level: G.shed.level, applied: appliedLevel(G), slow: G.shed.slow, fastFor: G.shed.fast, dwell: G.shed.restoreDwell });
      render();
    }
    function render() {
      nodeR.forEach((r, i) => { const on = G.mode === i && hist.length; r.style.strokeWidth = on ? 3.5 : 1.5; r.style.fill = on ? "var(--fig-bg)" : "var(--surface)"; });
      while (dyn.firstChild) dyn.removeChild(dyn.firstChild);
      const off = Math.max(0, hist.length - NF), shown = hist.slice(off);
      const line = (f, color) => api.el("polyline", { points: shown.map((h, k) => `${CX + (k + 0.5) * COLW},${f(h)}`).join(" "), style: `fill:none;stroke:${color};stroke-width:1.8` }, dyn);
      shown.forEach((h, k) => {
        api.el("rect", { x: CX + k * COLW + 0.5, y: lM.y + 2, width: COLW - 1, height: lM.h - 4, style: `fill:${MC[h.mode]};opacity:${h.mode === MODE.IDLE ? 0.35 : 0.85}` }, dyn);
        if (h.why.includes("lowered") || h.why.includes("raised")) api.el("circle", { cx: CX + (k + 0.5) * COLW, cy: yS(h.scale), r: 3.5, style: `fill:${api.hue(5)}` }, dyn);
        if (h.applied > 0) api.el("rect", { x: CX + k * COLW + 0.5, y: yL(h.applied), width: COLW - 1, height: yL(0) - yL(h.applied), style: `fill:${api.hue(4)};opacity:.35` }, dyn);
      });
      line(h => yS(h.scale), api.hue(1));
      line(h => yL(h.level), api.hue(6));
      line(h => yE(h.ema * 1000), api.hue(4));
      line(h => yE(h.ms), "var(--muted)");
      line(h => yC(Math.min(h.since, 1)), api.hue(3));
      const last = hist[hist.length - 1];
      ref1.textContent = `mode ${MODE_NAMES[G.mode]} · scale ${fmt(G.scale, 4)} (floor ${fmt(G.minScale, 2)}, moving ${fmt(G.moving, 3)}) · shed level ${G.shed.level} (applied ${appliedLevel(G)}) · EMA ${fmt(G.ema * 1000, 2)} ms · quiet ${fmt(G.quiet, 2)} s`;
      ref2.textContent = last ? `frame ${hist.length}: ${last.changing ? "changing" : "still"}, ${last.ms} ms${last.why.length ? ` → ${last.why.join(", ")}` : ""}` : "no frames yet: the governor starts IDLE at scale 1, EMA = target, cooldown already elapsed, shed level 0";
    }
    let acc = 0;
    api.onFrame(dt => {
      if (!S.run) return;
      acc += dt;
      if (acc >= 1 / 30) { acc = 0; stepOnce(); }
    });
    api.text(CX + 300, lS.y - 8, "blue: scale · pink dot: a rescale", "", { style: small });
    api.text(CX + 300, lL.y - 6, "violet: the shedder's level · amber fill: the level the view renders at (applied_level)", "", { style: small });
    api.text(CX + 300, lE.y - 6, "amber: the EMA · grey: this frame's time · violet dashes: 24 and 40 fps", "", { style: small });
    api.text(CX + 300, lC.y - 6, "green: time since the last scale change (capped at 1 s)", "", { style: small });
    render();
  },
};

// ================================================================== 10. dials, uniforms, saves and gotchas
const dialTable = {
  type: "table",
  title: "Console row / menu → FractalParams → uniform → what it changes",
  note: "FractalView._push_params writes every uniform on each FractalParams change; _push_camera writes the camera's four; both refresh near_dist. The shape rows are the console's Shape pane (MandelboxShape's ranges): they write the AttributeTable, and the frame's resolve writes FractalParams. The renderer rows are set directly from the View tab's Renderer options. Nothing outside FractalView touches the shader. Hover a row for the uniform's line and the knob's.",
  columns: [{ label: "row", w: 150 }, { label: "field · range · default", w: 300, mono: true }, { label: "uniform · transform", w: 340, mono: true }, { label: "what it changes", w: 450 }],
  rows: [
    { cells: ["Shape: Scale", "box_scale · −5 … 3 (hard ±6) · −2.09", "box_scale", "Each iteration's stretch (and flip, when negative): the shape's overall topology (tabs 3, 4)."],
      tip: { title: "Scale", ...R("view", 334), links: [RL("shape", 60, "the spec"), RL("params", 51, "the field"), RL("sh", 205, "z = box_scale·z + c")] } },
    { cells: ["Shape: Fold limit", "fold_limit · 0 … 3 · 1.0", "fold_limit", "The box fold's half-size."],
      tip: { title: "Fold limit", ...R("view", 335), links: [RL("shape", 67, "the spec"), RL("sh", 144, "the box fold")] } },
    { cells: ["Shape: Min radius", "min_radius · 0 … 2 · 0.7", "min_radius (shader: mr2 = max(r², 1e-12))", "The sphere fold's constant-scale zone (f = fr2/mr2 inside it). Squared in the shader now, not on the CPU."],
      tip: { title: "Min radius", ...R("view", 336), links: [RL("shape", 73, "the spec"), RL("sh", 151, "mr2")] } },
    { cells: ["Shape: Fixed radius", "fixed_radius · 0 … 4 · 1.0", "fixed_radius (shader: fr2)", "The sphere fold's inversion radius."],
      tip: { title: "Fixed radius", ...R("view", 337), links: [RL("shape", 79, "the spec"), RL("sh", 152, "fr2")] } },
    { cells: ["Shape: Fold order", "fold_order · Box → Sphere | Sphere → Box · 0", "fold_order (int)", "Which fold runs first in each iteration; Sphere → Box is a different fractal with the same knobs. Not bindable."],
      tip: { title: "Fold order", ...R("view", 338), links: [RL("shape", 85, "the spec"), RL("sh", 202, "the branch")] } },
    { cells: ["Shape: W", "w · −4 … 4 · 0", "w", "The sample point's fourth coordinate: de starts from (p, w), the Ice Fractal field adds (q, w). 0 is the 3D box; moving it slides to another 3D slice of the 4D shape."],
      tip: { title: "W", ...R("view", 339), links: [RL("shape", 94, "the spec"), RL("sh", 221, "z0 = vec4(p, w)"), RL("sh", 237, "field: c = (q, w)")] } },
    { cells: ["Shape: Julia (all)", "julia_all · false", "julia_all; box_half = 20 if on else 2", "The constant on every component; the march's cube grows to ±20; modes 1–9 switch from NF to N; the on-screen marker shows."],
      tip: { title: "Julia (all)", ...R("view", 340), links: [RL("view", 360, "box_half"), RL("shape", 102, "the spec"), RL("sh", 384, "NF only outside Julia (all)")] } },
    { cells: ["Shape: Julia x … w", "julia_0 … julia_3 · false", "julia_0 … julia_3", "Per component: the constant instead of the point's own coordinate. A mix is a hybrid of the Mandelbox and the Julia box."],
      tip: { title: "Julia x … w", ...R("view", 341), links: [RL("shape", 108, "the specs"), RL("sh", 211, "mb_constant")] } },
    { cells: ["Shape: Constant x … w", "c_0 … c_3 · (−0.23, 1.512, 1.892, 0) · ±4", "c_0 … c_3", "The Julia constant, shown while its toggle or Julia (all) is on. c_0..c_2 are also dragged by the on-screen ring."],
      tip: { title: "Constant x … w", ...R("view", 345), links: [RL("shape", 116, "the defaults"), RL("marker", 61, "the drag writes them")] } },
    { cells: ["Shape: Iter rotation", "iter_rot_xy … zw · ±180°, wraps · 0", "the six angles, in degrees", "A 4D rotation inside every iteration, in the six planes in a fixed order. Skipped entirely while all six are 0 (mb_rotating), so the default view costs nothing."],
      tip: { title: "Iteration rotation", ...R("view", 349), links: [RL("shape", 130, "the specs"), RL("sh", 195, "mb_rotating"), RL("sh", 185, "mb_iter_rotate")] } },
    { cells: ["Colour: Colour", "color_mode · 14 ids (the site's 13 + Palette 20) · 1", "color_mode; fog_color = FOG_COLORS[id]", "The colour branch, which normal is computed, the background (white for 5, 6) and the fog tint. Not bindable."],
      tip: { title: "Colour", ...R("view", 356), links: [RL("view", 367, "fog_color"), RL("shape", 157, "the spec"), RL("params", 16, "COLOR_MODE_IDS")] } },
    { cells: ["Colour: Palette input · frequency · offset · occlusion", "palette_source · Steps | Radius | Normal · 0; palette_frequency · 0 … 8 · 1; palette_offset · 0 … 1, wraps · 0; palette_occlusion · 0 … 1 · 0.5", "the same four names (LOOK_KEYS, pushed as they are)", "Only the Palette mode reads them (and the console only shows them then): which value indexes the palette, how often it repeats, where it starts, and how much the step count darkens it."],
      tip: { title: "Palette mode rows", ...R("view", 357), links: [RL("shape", 164, "the specs"), RL("sh", 444, "the Palette branch"), RL("params", 39, "LOOK_KEYS")] } },
    { cells: ["Lighting: Ambient · Diffuse · Specular · Shininess", "light_ambient · 0 … 1 · 0.1; light_diffuse · 0 … 2 · 0.5; light_specular · 0 … 4 · 1; light_shininess · 1 … 512, log · 160", "the same four names", "lgt = diffuse·nl + specular·nl^shininess + ambient for every mode but Grayscale. The defaults are the site's constants, so the site's modes are bit-for-bit until one moves."],
      tip: { title: "Lighting", ...R("view", 357), links: [RL("shape", 197, "the specs"), RL("sh", 405, "lgt")] } },
    { cells: ["Lighting: Light yaw · Light pitch", "light_yaw · ±180°, wraps · 0; light_pitch · ±90° · 0", "light_yaw, light_pitch", "Turn the light (which sits at the eye) about cam_up, then cam_right, by Rodrigues' rotation; skipped while both are 0. Raking light shows the relief."],
      tip: { title: "Light direction", ...R("view", 357), links: [RL("shape", 225, "the specs"), RL("sh", 401, "the rotation"), RL("sh", 290, "rotate_about")] } },
    { cells: ["Lighting: Exposure · Saturation", "exposure · 0 … 4 · 1; saturation · 0 … 2 · 1", "exposure, saturation", "After the mode: col ×= exposure, then a mix toward the Rec. 601 luma by saturation. Each skipped at 1, so the defaults change nothing."],
      tip: { title: "Exposure and saturation", ...R("view", 357), links: [RL("shape", 239, "the specs"), RL("sh", 454, "exposure"), RL("sh", 455, "saturation")] } },
    { cells: ["Colour window: the palette", "palette_a_r … palette_d_b · A, B 0.5; C 1; D (0, 0.33, 0.67)", "twelve floats → palette(t) = A + B·cos(2π(C·t + D))", "Inigo Quilez's cosine palette, one catalogue id per vector and channel so each can be bound. The Colour window's strip previews it with the same formula."],
      tip: { title: "The palette", ...R("view", 357), links: [RL("shape", 255, "the twelve specs"), RL("sh", 281, "palette()"), { file: "src/color/palette.gd", line: 109, label: "Palette.color_at" }] } },
    { cells: ["Shape: Precision", "precision · 1e-6 … 1e-3, log · 0.000025", "precision / (detail · shed detail)", "The pixel cone in hit_eps: both stop thresholds and the normal's delta (hit_eps(total) · 40). Not the shape."],
      tip: { title: "Precision", ...R("view", 355), links: [RL("shape", 143, "the spec"), RL("sh", 378, "delta")] } },
    { cells: ["Renderer: Detail", "detail · 0.1 … 10 · 1.0", "folded into precision (÷ detail)", "Scales the threshold everywhere: ×2 halves it. Divided on the CPU so the default is bit-for-bit the old cone."],
      tip: { title: "Detail", ...R("view", 355), links: [RL("renderer", 35, "the slider"), RL("params", 207, "the field"), RL("sh", 110, "the hit_eps comment")] } },
    { cells: ["Renderer: Full-detail range", "detail_range · 1 … 1000 · 10", "detail_range", "Where falloff starts: start = detail_range · near_dist, so it means the same at any zoom depth."],
      tip: { title: "Full-detail range", ...R("view", 361), links: [RL("renderer", 37, "the slider"), RL("params", 209, "the field"), RL("sh", 115, "start")] } },
    { cells: ["Renderer: Detail falloff", "detail_falloff · 0 … 3 · 0", "detail_falloff", "Past start the threshold grows by (t / start)^falloff: distant structure coarsens, rays stop sooner. 0 is off."],
      tip: { title: "Detail falloff", ...R("view", 362), links: [RL("renderer", 39, "the slider"), RL("params", 211, "the field"), RL("sh", 117, "the falloff")] } },
    { cells: ["Renderer: Max march steps", "max_steps · 32 … 512 · 128", "budget = max(32, round(max_steps · shed steps)); coarse = ¾, fine = the rest", "The per-ray step budget. 128 is the original 96 + 32; the loops are bounded at 384 + 128."],
      tip: { title: "Max march steps", ...R("view", 363), links: [RL("view", 364, "coarse_steps"), RL("view", 365, "fine_steps"), RL("renderer", 41, "the slider"), RL("params", 311, "coarse_steps()"), RL("sh", 341, "phase 1 loop")] } },
    { cells: ["Renderer: Min resolution", "min_render_scale · 0.1 … 1 · 0.25", "— (the governor reads it)", "The lowest render scale Fast Controls may drop to while you move (tab 9); at it, the load shedder may start."],
      tip: { title: "Min resolution", ...R("gov", 51), links: [RL("renderer", 43, "the slider"), RL("params", 213, "the field"), RL("gov", 101, "a raised floor lifts the scale")] } },
    { cells: ["Fast Controls", "fast_controls · true", "— (the governor reads it)", "Whether the governor may drop render_scale and shed load while you move. In the View tab's Renderer options."],
      tip: { title: "Fast Controls", ...R("gov", 50), links: [RL("renderer", 46, "the Renderer tab's"), RL("gov", 116, "off: scale 1, shedder reset")] } },
    { cells: ["(governor)", "LoadShedder level 0 … 4", "fog_dist = LEVELS[level].fog", "The fog distance in multiples of near_dist (0 = none); the same level also scales detail and the step budget above."],
      tip: { title: "fog_dist", ...R("view", 366), links: [RL("shed", 14, "LEVELS"), RL("view", 223, "set_load_level"), RL("sh", 123, "fog_amount")] } },
    { cells: ["(none)", "the camera and the shape", "near_dist = max(D(eye), 1e-6)", "The eye's distance to the nearest surface (CPU, de(·, 32)): the unit detail_range and the fog are measured in."],
      tip: { title: "near_dist", ...R("view", 388), links: [RL("view", 378, "pushed with the camera"), RL("view", 368, "and with the params"), RL("params", 177, "NEAR_FLOOR")] } },
    { cells: ["(none)", "near_dist", "coarse_iters = clamp(ceil(log(2 / (2 · eps · near)) / log|box_scale|), 16, 32)", "Phase 1's iteration count: 16 from the default eye, more within about 0.3 of the surface, so the coarse surface stays inside its own hit threshold of the real one (tab 5)."],
      tip: { title: "coarse_iters", ...R("view", 390), links: [RL("params", 246, "coarse_iters()"), RL("sh", 28, "uniform int coarse_iters"), RL("sh", 339, "used by phase 1")] } },
    { cells: ["(none)", "near_dist", "nf_weight = smoothstep(0.1, 2, near)", "How much of the Ice Fractal normal modes 1 to 9 light with: 1 from 2 out (the site's look), fading to the true normal inside 0.1 (tab 7)."],
      tip: { title: "nf_weight", ...R("view", 391), links: [RL("params", 258, "NF_FADE_NEAR / FAR"), RL("params", 269, "nf_weight()"), RL("sh", 385, "the crossfade")] } },
    { cells: ["View tab: Camera", "camera_mode · FLY / ORBIT · FLY", "— (Main._apply_mode)", "Which camera handles input, and mouse capture."],
      tip: { title: "Camera", ...R("main", 357), links: [RL("viewPane", 148, "the option row")] } },
    { cells: ["View tab / Settings: Mouse sensitivity", "mouse_sensitivity · 0.02 … 0.5 · 0.1", "— (the cameras read it)", "Degrees per pixel of mouse-look; the orbit uses 0.5°/px × sens / 0.1. The player's setting, copied into each view."],
      tip: { title: "Mouse sensitivity", ...R("fly", 109), links: [RL("main", 97, "from Settings"), RL("orbit", 86, "orbit")] } },
    { cells: ["(none)", "TAN_HALF_FOV constant", "tan_half_fov = tan 20° = 0.363970", "The 40° vertical field of view of every ray."],
      tip: { title: "tan_half_fov", ...R("view", 359), links: [RL("view", 11, "TAN_HALF_FOV"), RL("sh", 317, "the ray")] } },
    { cells: ["(none)", "the view's size", "aspect = width / height", "The horizontal spread of the rays; set whenever the size changes."],
      tip: { title: "aspect", ...R("view", 288), links: [RL("view", 275, "_aspect")] } },
    { cells: ["(camera)", "CameraState.transform", "eye, cam_right, cam_up, cam_forward", "The ray origin and basis (forward = −basis.z)."],
      tip: { title: "camera uniforms", ...R("view", 374), links: [RL("cam", 29, "forward()")] } },
  ],
};

for (const r of dialTable.rows) r.tip.blurb = `Uniform: \`${r.cells[2]}\`. ${r.cells[3]}`;

const fixOk = FIX.fails.length === 0;
const cards = {
  type: "cards",
  title: "Invariants, gotchas, history, open",
  columns: 2, cardWidth: 560,
  cards: [
    { title: fixOk ? `CPU estimator = shader: the ${FIX.n} fixtures` : `✗ THIS PAGE'S de() PORT FAILS ${FIX.fails.length} OF ${FIX.n} FIXTURES`,
      tag: fixOk ? "invariant" : "port broken", hue: fixOk ? 3 : 2, ...R("tDE", 17),
      links: [{ file: F.spec, line: 174, label: "the site fixture tables" }, RL("tDE", 68, "the 4D-knob fixtures"), RL("tDE", 12, "the tolerance"), RL("de", 8, "must equal de(p, 32)")],
      body: fixOk
        ? `DistanceEstimator.estimate_at must give the shader's de(p, 32) numbers, pinned by 24 site-measured fixtures (defaults, an alternative shape, Julia (all)) and six that pin the 4D knobs (box_scale 2, Sphere → Box, iter_rot_xy 30°, w 0.5, julia_0 + julia_2), at relative 1e−5 or absolute 1e−9 below 1e−6. This pane runs all ${FIX.n} through its own de() port at load and they pass (worst relative error ${FIX.worst.toExponential(1)}), so its figures show the real shape. A failure turns this card orange and shows in the red error box.`
        : `The figures on this page are NOT the real shape until the port is fixed (fix the port, never the fixtures): ${FIX.fails.join("; ")}` },
    { title: "One mb_step, three copies", tag: "invariant", hue: 3, ...SH(201), links: [RL("sh", 235, "field() uses it too"), RL("de", 62, "the GDScript loop"), RL("shape", 12, "ids = uniform names")],
      body: "de(), the Ice Fractal field and DistanceEstimator run the same iteration: folds in fold_order, the optional six-plane rotation, z = box_scale·z + c, dz = dz·|box_scale| + 1, on a 4D point. The knobs are named the same everywhere (catalogue id = FractalParams field = uniform), so a knob cannot reach the shader and miss the CPU." },
    { title: "The shader's uniforms = the catalogue + 19 renderer uniforms", tag: "invariant", hue: 3, ...R("tShader", 11), links: [RL("sh", 8, "the naming rule"), RL("shape", 293, "catalogue_ids()"), RL("sh", 33, "the two fog uniforms"), RL("tShader", 47, "the look defaults")],
      body: "A shader that fails to compile yields an empty uniform list, so shader_test catches a broken shader headless by checking the list exactly: the 19 renderer uniforms (camera, fov, aspect, box_half, the level of detail, the step split, the coarse iteration count and the normal crossfade, fog_dist, fog_color, the probe dot) plus every MandelboxShape id, 66 in all. Fractacular's technique-schema check, ported. Every look uniform (colour, lighting, palette) also declares its catalogue default in the shader, checked from the source, so a frame drawn before the first push already looks right. The noise editor's spliced shaders keep all of them." },
    { title: "project / unproject round-trip", tag: "invariant", hue: 3, ...R("tView", 25), links: [RL("view", 249, "project"), RL("view", 264, "unproject"), RL("tMarker", 37, "the marker drag")],
      body: "FractalView's project and unproject use the shader's own ray maths (forward + ndc.x·aspect·tan_half_fov·right + ndc.y·tan_half_fov·up), so unproject(project(p), depth) == p and the Julia ring sits exactly on the point the shader uses." },
    { title: "COLOR_MODE_IDS match the site", tag: "invariant", hue: 3, ...R("params", 16), links: [RL("tParams", 42, "the id-order test"), RL("shape", 157, "the Colour ENUM spec")],
      body: "The Colour row's order maps to the site's ids [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14], then this project's Palette at 20, past the site's range; saves store the id, not the index, so a saved number means the same colour here and on the site. An unknown id sanitizes back to the default." },
    { title: "hit_epsilon (CPU) = hit_eps (shader) at level 0", tag: "invariant", hue: 3, ...R("params", 221), links: [RL("sh", 113, "hit_eps"), RL("tParams", 116, "the test"), RL("orbit", 165, "the orbit's CPU march uses it")],
      body: "One threshold, written twice: precision / detail · t, times (t / start)^falloff past start = detail_range · near_dist. The orbit camera's click-to-centre march uses the GDScript copy, so it lands where the shader draws the surface. Under a shed level the shader's precision is also divided by the level's detail factor; the CPU copy is never shed. This pane's march port is a third copy." },
    { title: "Nothing re-renders a still view", tag: "invariant", hue: 3, ...R("cam", 11), links: [RL("params", 334, "apply_resolved: emit only on a difference"), RL("fly", 107, "a zero mouse delta is ignored"), RL("gov", 29, "settle 0.15 s"), RL("tCam", 31, "the test")],
      body: "CameraState emits only when the transform or speed factor really differs (exactly, so a 1e−7 deep-zoom move still counts); apply_resolved emits only when a resolved value differs; FlyCamera ignores the zero-delta motion a resting captured mouse sends; and the governor waits 0.15 s of quiet before its full-resolution frame. Without these a still view kept buying full frames." },
    { title: "A bound knob keeps the view animating", tag: "gotcha", hue: 2, ...R("main", 265), links: [RL("gov", 46, "params.changed → _dirty"), RL("resolver", 13, "resolve")],
      body: "A binding to Time changes its knob every frame, so FractalParams emits every frame, the governor never leaves CONTINUOUS and the GPU never idles. That is correct (the picture is moving), but a view saved with a Time binding costs a continuous render. An axis binding only animates while its key is held." },
    { title: "Fog only while moving", tag: "gotcha", hue: 2, ...R("gov", 60), links: [RL("shed", 14, "LEVELS"), RL("sh", 331, "the fog exit"), RL("shedSpec", 66, "spec: fog")],
      body: "applied_level() is the shedder's level only in CONTINUOUS and SETTLING: the final still frame always renders at level 0, full scale, no fog. The level itself is kept through idle, so moving again picks up where it left off. Each colour mode has its own fog tint (a light one for the two white-background modes)." },
    { title: "Default renderer options keep the threshold, not every pixel", tag: "gotcha", hue: 2, ...SH(337), links: [RL("sh", 369, "ce on the 128-step scale"), RL("view", 355, "detail folded on the CPU")],
      body: "At the defaults hit_eps is exactly the old precision · total (detail is divided on the CPU so the shader multiplies by the same float) and the budget is 96 + 32. But the loop bounds became uniforms, and the GPU compiler emits different code for them: about 1% of pixels, in the chaotic dust, flip (mean 0.5/255 on the default view). Deterministic run to run; invisible to the eye." },
    { title: "Fractal coordinates are twice the site's", tag: "gotcha", hue: 2, ...R("readme", 353), links: [RL("spec", 50, "spec: coordinates")],
      body: "Everything here (eye, Julia constant, saves) is in the space the estimator is evaluated in. The site reports camera positions at half that: a site position (x, y, z) is (2x, 2y, 2z) here. The shader's h = v/2 and eh = eye/2 are the site's own half-scale coordinates." },
    { title: "World up is +Z; forward is −basis.z", tag: "gotcha", hue: 2, ...R("spec", 55), links: [RL("cam", 29, "forward() = −basis.z"), RL("fly", 11, "WORLD_UP")],
      body: "Not Godot's +Y. Cameras yaw about +Z and rebuild their basis with +Z as the up hint. CameraState follows Godot's Transform3D convention, so forward is −basis.z, right basis.x, up basis.y." },
    { title: "Typing silences the keys, in every window", tag: "gotcha", hue: 2, ...R("textFocus", 11), links: [RL("main", 103, "the Ctrl tap's typing_guard"), RL("fly", 127, "WASD"), RL("main", 431, "N")],
      body: "TextFocus.any(viewports) checks the main window's, the console's and the noise window's viewports: while a text field has focus the Ctrl tap, N, WASD and the axis keys do nothing, so typing an \"e\" in a spin box never moves Axis A." },
    { title: "Cmd / Ctrl suppresses movement, so Cmd+S is a save", tag: "gotcha", hue: 2, ...R("fly", 125), links: [RL("proj", 73, "workspace_quick_save"), RL("tFly", 37, "the test")],
      body: "S alone is move_back; with Cmd or Ctrl held the fly camera ignores the move actions, so ⌘S saves without flying backwards." },
    { title: "A native console must not overlap the view (macOS)", tag: "gotcha", hue: 2, ...R("uiScale", 137), links: [RL("console", 62, "force_native"), RL("uiScale", 160, "beside_position"), RL("proj", 19, "embed_subwindows")],
      body: "On macOS (Godot 4.6.1, GL Compatibility) a native sub-window over the main window corrupts the main window's frame: the fractal squeezed into the uncovered strip, or black. The project embeds sub-windows; only the console forces native, and it opens beside the main window, never over it. Headless and the web have no native sub-windows, so there it is embedded." },
    { title: "Pointer lock needs a click on the web", tag: "gotcha", hue: 2, ...R("spec", 496), links: [RL("main", 464, "click to capture"), RL("main", 419, "Escape frees the mouse")],
      body: "A browser only grants mouse capture inside a user gesture, and can swallow a bare Ctrl tap. The click-to-capture rule (a click on the view while free in FLY) is that gesture. The pause menu's Console… button, the old way in when the tap was swallowed, went with the pause menu (5ebb10a): there is no second way to open the console." },
    { title: "float32 limits deep zoom, so the fly camera stops at the floor", tag: "gotcha", hue: 2, ...R("zoomSpec", 47), links: [RL("sh", 3, "highp = float32 on WebGL 2"), RL("params", 304, "zoom_floor"), RL("fly", 95, "move_allowed"), RL("movement", 296, "`zoom limit`"), RL("spec", 491, "spec: accepted")],
      body: "The shader runs 32-bit floats (WebGL 2): near a coordinate x a ray position can only land on a grid ulp32(x) = 2^(floor(log2 x) − 23) apart, about 1.2e−7 near the box. Once the hit threshold eps · total is much finer than that, rays reach the surface only by luck: speckle, shimmer, pits. So the fly camera refuses to come closer than zoom_floor = ulp32(max |eye|) / (50 · eps), about 1e−4 near the box at the default precision (a higher Detail, a finer threshold, stops it further out), and the console's Movement pane shows `zoom limit`. Moving away is always allowed. The orbit camera is not guarded. The JS ports on this page run doubles, so they stay clean deeper than the real render." },
    { title: "Deep zoom adjusts itself; the default view is untouched", tag: "invariant", hue: 3, ...R("zoomSpec", 69), links: [RL("params", 246, "coarse_iters"), RL("params", 269, "nf_weight"), RL("view", 385, "_push_near pushes both"), RL("tDeep", 1, "deep_zoom_test"), RL("tView", 99, "16 and 1 at the default view")],
      body: "Three automatic changes, no new option and no save-format change: phase 1's iteration count follows near_dist (coarse_iters, tab 5), the Ice Fractal normal fades into the true one up close (nf_weight, tab 7), and the fly camera stops at the 32-bit floor (zoom_floor). From the default eye coarse_iters is 16 and nf_weight exactly 1, and each shader path is then the site's maths, so the default view is pixel-identical. Without the first change a camera 1e−3 from the surface spent all 96 coarse steps creeping toward the 16-iteration surface: dark shading, then dark pits." },
    { title: "DistanceEstimator runs scalars to stay 64-bit", tag: "gotcha", hue: 2, ...R("de", 10), links: [RL("tDE", 5, "fixtures pin estimate_at")],
      body: "GDScript floats are 64-bit but Vector3 components are 32-bit; the precision lost on input is amplified near the surface and broke the near-boundary fixtures. estimate_at keeps the 4D orbit in scalar floats in an Array; estimate(Vector3) is for callers whose input is already a 32-bit camera position." },
    { title: "Saved view version 2, and the version-1 migration", tag: "history", hue: 6, ...R("ws", 19), links: [RL("ws", 31, "capture"), RL("ws", 181, "_migrate_v1"), RL("tWs", 94, "the v1 test"), RL("saveDef", 1, "default.json"), RL("wsf", 20, "user://saves/ in exports")],
      body: "{ version: 2, shape: { defaults, bindings }, axes, fractal: the non-shape preference and renderer keys, camera: { eye, forward, up, speed_factor }, noise? }. The clock and the keymap are not saved. Version 1 had one flat `fractal` section of every FractalParams value; it still loads, renamed without a warning (scale → box_scale, inner_radius → min_radius, outer_radius → fixed_radius, julia_enabled → julia_all, julia_point → c_0..c_2). Saving always writes version 2; the committed saves were rewritten once." },
    { title: "The derivative: −dz·s + 1 became dz·|s| + 1", tag: "history", hue: 6, ...R("consoleSpec", 148), links: [RL("sh", 206, "now"), RL("consoleSpec", 121, "spec: the shader and the estimator")],
      body: "The site's form and Fractacular's agree for every negative scale, which is every scale the site allowed and all 24 site fixtures, so they hold unchanged. The catalogue now reaches positive scales (up to 3), where dz·|s| + 1 is the standard derivative; a new fixture pins box_scale 2." },
    { title: "The Q panel became the console (and, for a while, the pause menu)", tag: "history", hue: 6, ...R("consoleSpec", 294), links: [RL("consoleSpec", 1, "the debug console design"), RL("viewPane", 3, "the View tab"), { url: "https://github.com/Adam-G-Klein/HelpImStuckInAFractal/commit/5ebb10a984c529218b76c73813640c1b57fd9d7d", label: "5ebb10a: the pause menu goes" }],
      body: "ControlsPanel (four shape sliders, Colour, Precision, Julia + X/Y/Z, Save/Load, Camera, Fast Controls) was deleted with its test. The shape knobs, and every Fractacular Mandelbox knob besides, are the console's Shape pane over the AttributeTable; Save/Load view, Camera, Fast Controls, Console… and Noise editor… moved to the pause menu, and then (5ebb10a) with the Renderer options and Back to Menu into the console's View tab: Escape now only frees the mouse and nothing pauses the tree." },
    { title: "Not built: the spec's non-goals", tag: "open", hue: 4, ...R("spec", 24),
      body: "Save Image, Copy URL / load from URL, the High DPI toggle, a reset button, touch controls, and any fractal but the Mandelbox. The structure should not make them hard to add, but nothing is designed around them." },
    { title: "Next: level sequences", tag: "open", hue: 4, file: "docs/superpowers/specs/2026-10-08-level-sequences-design.md", line: 1, links: [RL("consoleSpec", 410, "the console's follow-ups")],
      body: "Designed, not built: a saved view becomes a level, an ordered list of levels a sequence, entered with the number keys from a third console column, each level with a deliberate start pose. Still open from the console: bindings on noise-node parameters, clock controls, Fractacular's 2D slice panels." },
  ],
};

// The checker (tools/viz/check.mjs) verifies every { file, line } it finds in a pane's data. A
// figure's tooltips are built inside draw(), so each figure also carries `refs`: every R / RL / SH
// call with literal arguments in its draw source, plus any listed by hand.
function refsIn(fn, extra) {
  const src = String(fn), out = [];
  for (const m of src.matchAll(/\bSH\((\d+)\)/g)) out.push(SH(+m[1]));
  for (const m of src.matchAll(/\bRL?\("(\w+)",\s*(\d+)/g)) out.push(R(m[1], +m[2]));
  return out.concat(extra || []);
}
foldFig.refs = refsIn(foldFig.draw);
dialsFig.refs = refsIn(dialsFig.draw, PRESETS.map(p => ({ file: p.file, line: p.line })));
marchFig.refs = refsIn(marchFig.draw);
shadeFig.refs = refsIn(shadeFig.draw, [shadeRefs]);
normalsFig.refs = refsIn(normalsFig.draw);
camFig.refs = refsIn(camFig.draw);
govFig.refs = refsIn(govFig.draw);

VIZ.pane({
  id: "mandelbox",
  short: "Mandelbox viewer",
  title: "Help I'm Stuck In A Fractal — how a pixel is made",
  subtitle: "A Godot 4.6 GDScript Mandelbox viewer emulating icefractal.com/mandelbox, with every knob of Fractacular's 4D Mandelbox. Each frame Main resolves the shape table, the axes and the clock into FractalParams; with CameraState it carries every value. A canvas_item shader ray-marches the 4D estimator's w slice in two phases inside a ±2 cube, stopping on a hit threshold that can coarsen with distance, and colours each hit by how many steps it took; a governor drops the render scale and then sheds detail into fog while you move, and stops rendering when you stop. The live figures run line-for-line JavaScript ports of the shader and the GDScript, checked at load against the estimator's 30 fixtures.",
  commit: "15801d3f64bcbf437cf4adefe5a1c7c497a9f9fe",
  pinNote: "deep-zoom, unpushed: links 404 until it is pushed",
  ctx: {
    state: { hue: 1, label: "state — FractalParams, CameraState" },
    input: { hue: 2, label: "input — Main's dispatch, the menus, the file panels, saves" },
    camera: { hue: 3, label: "cameras — fly, orbit, Julia marker" },
    render: { hue: 6, label: "render — FractalView, shader, governor, load shedder, noise" },
    math: { hue: 4, label: "CPU maths — DistanceEstimator" },
    shape: { hue: 5, label: "shape layer — table, axes, clock, console (the console pane)" },
  },
  kinds: {
    call: { style: "solid", label: "calls · sets" },
    signal: { style: "dash", label: "changed signal" },
    data: { style: "dot", label: "reads a value · a uniform" },
  },
  tabs: [
    arch,
    seq,
    foldFig,
    dialsFig,
    marchFig,
    { label: "Shading and colour modes", rows: [[shadeFig], [modeTable]] },
    normalsFig,
    { label: "Cameras", rows: [[camFig], [camTable]] },
    govFig,
    { label: "Dials, uniforms, saves", rows: [[dialTable], [cards]] },
  ],
  // The ports, exposed for checking from the console or node (VIZ.panes[0].ports.de(...)).
  ports: { params, withP, hitEps, fogAmount, nearDist, coarseIters, nfWeight, ulp32, zoomFloor, de, mbStep, orbitStages, field, calcNormal, calcNF, hue, boxIntersect, march, shade, renderPixel, lookAt, flySpeed, scrollFactor, applyLook, newShedder, shedderStep, newGovernor, governorStep, appliedLevel, FIX, DEFAULT_CAM },
});
})();
