// Pane: the Mandelbox viewer (Help I'm Stuck In A Fractal). Every file:line below was read at
// `commit` with `git show <commit>:<path>`. When the code changes: re-read the lines, bump `commit`,
// run `node tools/viz/check.mjs --print --pane mandelbox`.
//
// The live figures run JavaScript ports of the real maths, each a small named function below with
// the source file and lines it was ported from. They run in doubles, like DistanceEstimator's
// scalar orbit; the shader itself runs float32 (see the gotcha cards in the last tab).
(function () {
const F = {
  main: "src/main.gd",
  mainScn: "src/main.tscn",
  params: "src/fractal/fractal_params.gd",
  de: "src/fractal/distance_estimator.gd",
  sh: "src/fractal/mandelbox.gdshader",
  view: "src/fractal/fractal_view.gd",
  viewScn: "src/fractal/fractal_view.tscn",
  cam: "src/camera/camera_state.gd",
  fly: "src/camera/fly_camera.gd",
  orbit: "src/camera/orbit_camera.gd",
  marker: "src/camera/julia_marker.gd",
  gov: "src/perf/resolution_governor.gd",
  panel: "src/ui/controls_panel.gd",
  renderer: "src/ui/renderer_options.gd",
  settings: "src/ui/settings_menu.gd",
  pause: "src/ui/pause_menu.gd",
  ws: "src/workspace/workspace.gd",
  wsf: "src/workspace/workspace_files.gd",
  proj: "project.godot",
  readme: "README.md",
  spec: "docs/superpowers/specs/2026-10-06-mandelbox-explorer-design.md",
  saveDef: "saves/default.json",
  saveField: "saves/juliaIceField.json",
  saveTer: "saves/juliaIceTerraces.json",
  tDE: "tests/distance_estimator_test.gd",
  tGov: "tests/resolution_governor_test.gd",
  tView: "tests/fractal_view_test.gd",
  tFly: "tests/fly_camera_test.gd",
  tParams: "tests/fractal_params_test.gd",
  tOrbit: "tests/orbit_camera_test.gd",
  tMarker: "tests/julia_marker_test.gd",
  tMain: "tests/main_test.gd",
  tWs: "tests/workspace_test.gd",
  tShader: "tests/shader_test.gd",
  tCam: "tests/camera_state_test.gd",
};
// Link helpers: R("sh", 48) is { file, line }; RL adds a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const SH = line => R("sh", line);

// ================================================================== the ports
// The maths, ported line for line. P is a flat parameter record built by params(): the four shape
// values, min_r2 / fixed_r2 as FractalView._push_params squares them, precision, Julia and mode.
const clamp = (x, a, b) => (x < a ? a : x > b ? b : x);
const TAN_HALF_FOV = 0.36397023426620234;          // fractal_view.gd:7
const DEFAULT_EYE = [8.175847, 3.812460, 3.283393]; // camera_state.gd:6
const JULIA_POINT = [-0.23, 1.512, 1.892];          // fractal_params.gd:30

// FractalParams defaults (fractal_params.gd:16-70) → the uniforms _push_params writes
// (fractal_view.gd:257-270): min_r2 = inner², fixed_r2 = outer², box_half = 20 in Julia mode else 2.
// The level-of-detail values (detail, range, falloff, maxSteps) are fractal_params.gd:61-70.
function params(o) {
  const p = Object.assign({ scale: -2.09, inner: 0.7, fold: 1.0, outer: 1.0, precision: 0.000025,
    julia: false, jp: JULIA_POINT.slice(), mode: 1, detail: 1, range: 10, falloff: 0, maxSteps: 128 }, o || {});
  p.minR2 = p.inner * p.inner;
  p.fixedR2 = p.outer * p.outer;
  p.boxHalf = p.julia ? 20 : 2;
  p.coarse = Math.floor(p.maxSteps * 3 / 4);       // coarse_steps(): fractal_params.gd:84-85
  p.fine = p.maxSteps - p.coarse;                   // fine_steps(): fractal_params.gd:88-89
  return p;
}

// hitEps: the hit threshold at ray distance t for a camera `near` from the nearest surface,
// fractal_params.gd:75-81 (hit_epsilon) = mandelbox.gdshader:38-45 (hit_eps, with precision / detail
// folded into the `precision` uniform by fractal_view.gd:261). Falloff 0 is the plain cone precision · t.
const NEAR_FLOOR = 1e-6;                            // fractal_params.gd:50
function hitEps(P, t, near) {
  let e = P.precision / P.detail * t;
  if (P.falloff > 0) {
    const start = P.range * Math.max(near, NEAR_FLOOR);
    if (t > start) e *= Math.pow(t / start, P.falloff);
  }
  return e;
}
// nearDist: what FractalView._push_near pushes as `near_dist` (fractal_view.gd:290).
function nearDist(eye, P) { return Math.max(de(eye[0], eye[1], eye[2], 32, P), NEAR_FLOOR); }

// de(p, iters): mandelbox.gdshader:48-68, equal to distance_estimator.gd:21-55 (estimate_at).
function de(px, py, pz, iters, P) {
  const cx = P.julia ? P.jp[0] : px, cy = P.julia ? P.jp[1] : py, cz = P.julia ? P.jp[2] : pz;
  let zx = px, zy = py, zz = pz, dz = 1;
  const f = P.fold, s = P.scale, minR2 = P.minR2, fixedR2 = P.fixedR2;
  for (let i = 0; i < 32; i++) {
    if (i >= iters) break;
    zx = clamp(zx, -f, f) * 2 - zx; zy = clamp(zy, -f, f) * 2 - zy; zz = clamp(zz, -f, f) * 2 - zz;  // box fold
    const r2 = zx * zx + zy * zy + zz * zz;                                                         // sphere fold
    let k = 1;
    if (r2 < minR2) k = fixedR2 / minR2;
    else if (r2 < fixedR2) k = fixedR2 / r2;
    zx *= k; zy *= k; zz *= k; dz *= k;
    zx = s * zx + cx; zy = s * zy + cy; zz = s * zz + cz;                                          // scale and add
    dz = -dz * s + 1;
  }
  return Math.sqrt(zx * zx + zy * zy + zz * zz) / Math.abs(dz);
}

// The same orbit, keeping every stage (for the fold-by-fold stepper). Stage 0 is the start; then
// three states per iteration: after the box fold, after the sphere fold, after scale-and-add.
function orbitStages(px, py, pz, P, iters) {
  const c = P.julia ? P.jp : [px, py, pz];
  let z = [px, py, pz], dz = 1;
  const out = [{ stage: 0, it: 0, z: z.slice(), dz }];
  for (let i = 0; i < iters; i++) {
    const before = z.slice();
    z = z.map(v => clamp(v, -P.fold, P.fold) * 2 - v);
    out.push({ stage: 1, it: i, z: z.slice(), dz, folded: z.map((v, a) => v !== before[a]) });
    const r2 = z[0] * z[0] + z[1] * z[1] + z[2] * z[2];
    let k = 1, branch = 2;
    if (r2 < P.minR2) { k = P.fixedR2 / P.minR2; branch = 0; }
    else if (r2 < P.fixedR2) { k = P.fixedR2 / r2; branch = 1; }
    z = z.map(v => v * k); dz *= k;
    out.push({ stage: 2, it: i, z: z.slice(), dz, r2, k, branch });
    z = z.map((v, a) => P.scale * v + c[a]);
    dz = -dz * P.scale + 1;
    out.push({ stage: 3, it: i, z: z.slice(), dz });
  }
  return out;
}

// field(q): mandelbox.gdshader:72-88, the Ice Fractal field F(q) = |z16| − 8 (z from 0, c = q, no dz).
function field(qx, qy, qz, P) {
  let zx = 0, zy = 0, zz = 0;
  const f = P.fold, s = P.scale, minR2 = P.minR2, fixedR2 = P.fixedR2;
  for (let i = 0; i < 16; i++) {
    zx = clamp(zx, -f, f) * 2 - zx; zy = clamp(zy, -f, f) * 2 - zy; zz = clamp(zz, -f, f) * 2 - zz;
    const r2 = zx * zx + zy * zy + zz * zz;
    let k = 1;
    if (r2 < minR2) k = fixedR2 / minR2;
    else if (r2 < fixedR2) k = fixedR2 / r2;
    zx *= k; zy *= k; zz *= k;
    zx = s * zx + qx; zy = s * zy + qy; zz = s * zz + qz;
  }
  return Math.sqrt(zx * zx + zy * zy + zz * zz) - 8;
}

const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const norm = v => { const l = Math.hypot(v[0], v[1], v[2]); return l > 0 ? [v[0] / l, v[1] / l, v[2] / l] : [0, 0, 0]; };
const add = (a, b, k = 1) => [a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];

// calcNormal: mandelbox.gdshader:91-97, central differences of de(·, 32).
function calcNormal(v, delta, P) {
  const [x, y, z] = v;
  return norm([de(x + delta, y, z, 32, P) - de(x - delta, y, z, 32, P),
    de(x, y + delta, z, 32, P) - de(x, y - delta, z, 32, P),
    de(x, y, z + delta, 32, P) - de(x, y, z - delta, 32, P)]);
}

// calcNF: mandelbox.gdshader:101-108. Base sample at the HALF-scale h = v/2, offsets at v + 0.01.
function calcNF(v, h, P) {
  const lw = field(h[0], h[1], h[2], P);
  return norm([(field(v[0] + 0.01, v[1], v[2], P) - lw) / 0.01,
    (field(v[0], v[1] + 0.01, v[2], P) - lw) / 0.01,
    (field(v[0], v[1], v[2] + 0.01, P) - lw) / 0.01]);
}

// hue: mandelbox.gdshader:111-121 (GLSL mod(x, 2) = x − 2·floor(x/2)).
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

// boxIntersect: mandelbox.gdshader:125-138. Returns [t_enter, t_exit]; a miss has t_exit < max(t_enter, 0).
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

// march: the two phases of fragment(), mandelbox.gdshader:149-187. With `rec`, every de() call is
// recorded ({ phase, i, total, d, th, p, stop }) for the ray stepper. `near` is near_dist for this eye.
function march(eye, dir, P, rec) {
  const tb = boxIntersect(eye, dir, P.boxHalf), near = nearDist(eye, P);
  const out = { tEnter: tb[0], tExit: tb[1], miss: false, left: false, n1: P.coarse, n2: P.fine, total: 0, start: 0, ce: 1,
    near, lodStart: P.range * near, steps: rec || null };
  if (tb[1] < Math.max(tb[0], 0)) { out.miss = true; return out; }
  let total = Math.max(tb[0], 0);
  out.start = total;
  for (let i = 0; i < P.coarse; i++) {                                     // phase 1: de(p, 16), coarse_steps
    const p = add(eye, dir, total), d = de(p[0], p[1], p[2], 16, P), th = hitEps(P, total, near) * 2;
    if (rec) rec.push({ phase: 1, i, total, d, th, p, stop: d < th });
    if (d < th) { out.n1 = i; break; }
    total += d;
    if (total > tb[1]) { out.left = true; break; }
  }
  if (!out.left) {
    for (let i = 0; i < P.fine; i++) {                                     // phase 2: de(p, 32), fine_steps
      const p = add(eye, dir, total), d = de(p[0], p[1], p[2], 32, P), th = hitEps(P, total, near);
      if (rec) rec.push({ phase: 2, i, total, d, th, p, stop: d < th });
      if (d < th) { out.n2 = i; break; }
      total += d;
      if (total > tb[1]) { out.left = true; break; }
    }
  }
  out.total = total;
  // ce stays on the original 128-step scale; a ray that ran out of phase 2 is 1 (mandelbox.gdshader:187).
  out.ce = out.n2 === P.fine ? 1 : Math.min((out.n1 + out.n2) / 128, 1);
  return out;
}

// shade: the colour branches of fragment(), mandelbox.gdshader:187-248, from ce, the raw
// |dot(n, ldir)|, the normal n, h = v/2 and the camera basis (modes 14 and 15 use view space).
function shade(mode, ce, lgtRaw, n, h, cam) {
  const inv = 1 - ce;
  if (mode === 0) return [inv, inv, inv];
  const lgt = 0.5 * lgtRaw + Math.pow(lgtRaw, 160) + 0.1;
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
    default: return [inv, inv, inv];
  }
}

// One pixel of fragment(), mandelbox.gdshader:140-249: the ray from UV (141-145), the background
// (122), the march, then normal choice (197-203), light (205-208) and colour.
function renderPixel(cam, P, ux, uy, aspect) {
  const nx = (ux - 0.5) * 2, ny = -(uy - 0.5) * 2;
  const dir = norm([0, 1, 2].map(a => cam.fwd[a] + nx * aspect * TAN_HALF_FOV * cam.right[a] + ny * TAN_HALF_FOV * cam.up[a]));
  const bg = P.mode === 5 || P.mode === 6 ? [1, 1, 1] : [0, 0, 0];
  const m = march(cam.eye, dir, P);
  if (m.miss || m.left) return { rgb: bg, m, bg: true };
  if (P.mode === 0) return { rgb: [1 - m.ce, 1 - m.ce, 1 - m.ce], m };
  const v = add(cam.eye, dir, m.total), h = v.map(x => x * 0.5), eh = cam.eye.map(x => x * 0.5);
  const delta = hitEps(P, m.total, m.near) * 40;
  const useNF = P.mode >= 1 && P.mode <= 9 && !P.julia;
  const n = useNF ? calcNF(v, h, P) : calcNormal(v, delta, P);
  const ldir = norm([2 * eh[0] - h[0], 2 * eh[1] - h[1], 2 * eh[2] - h[2]]);
  return { rgb: shade(P.mode, m.ce, Math.abs(dot(n, ldir)), n, h, cam), m, n, useNF };
}

// Transform3D.looking_at(target, +Z) as CameraState.make_default builds it (camera_state.gd:31-35):
// forward = −basis.z, right = basis.x, up = basis.y.
function lookAt(eye, target, upHint) {
  const fwd = norm([target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]]);
  const z = fwd.map(v => -v), right = norm(cross(upHint || [0, 0, 1], z)), up = cross(z, right);
  return { eye: eye.slice(), fwd, right, up };
}
const DEFAULT_CAM = lookAt(DEFAULT_EYE, [0, 0, 0]);

// flySpeed: fly_camera.gd:83-85, speed = clamp(D(eye), 1e-6, 20) · speed_factor.
function flySpeed(eye, P, speedFactor) {
  return clamp(de(eye[0], eye[1], eye[2], 32, P), 1e-6, 20) * speedFactor;
}
// The wheel: fly_camera.gd:88-90, ×1.25 per tick up, ÷1.25 down, clamped to [0.01, 100].
function scrollFactor(f, up) { return clamp(f * (up ? 1.25 : 1 / 1.25), 0.01, 100); }

// apply_look: fly_camera.gd:55-65 (yaw about world +Z keeps pitch; pitch clamped to ±89°).
const MAX_FORWARD_Z = 0.9998476951563913;
function rotZ(v, a) { const c = Math.cos(a), s = Math.sin(a); return [v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]]; }
function applyLook(cam, dx, dy, sens) {
  const fwd = rotZ(cam.fwd, -dx * sens * Math.PI / 180);
  const maxPitch = Math.asin(MAX_FORWARD_Z);
  const pitchNew = clamp(Math.asin(clamp(fwd[2], -1, 1)) + (-dy * sens * Math.PI / 180), -maxPitch, maxPitch);
  let horiz = [fwd[0], fwd[1], 0];
  const hl = Math.hypot(horiz[0], horiz[1]);
  horiz = hl > 1e-9 ? [horiz[0] / hl, horiz[1] / hl, 0] : norm([cam.right[1], -cam.right[0], 0]);
  const f = add(horiz.map(v => v * Math.cos(pitchNew)), [0, 0, 1], Math.sin(pitchNew));
  return lookAt(cam.eye, add(cam.eye, f), [0, 0, 1]);
}

// governorStep: resolution_governor.gd:62-84, on a plain record G (scale, mode, fast, minScale,
// cooldown, ema, since, idlePending). Modes as the enum at line 7. minScale is min_scale (line 16),
// which follows FractalParams.min_render_scale (lines 34-36).
const MODE = { CONTINUOUS: 0, FINAL_FRAME: 1, IDLE: 2 }, MODE_NAMES = ["CONTINUOUS", "FINAL_FRAME", "IDLE"];
const GOV = { TARGET: 1 / 30, EMA_ALPHA: 0.2, STEP: 0.8 };
function newGovernor() { return { scale: 1, mode: MODE.IDLE, fast: true, minScale: 0.25, cooldown: 0.5, ema: GOV.TARGET, since: 0.5, idlePending: false }; }
function governorStep(G, frameTime, changing) {
  const why = [];
  G.since += frameTime;
  G.scale = Math.max(G.scale, G.minScale);         // the floor may have been raised (line 64)
  if (changing) {
    G.mode = MODE.CONTINUOUS;
    G.idlePending = true;
    if (G.fast) {
      G.ema = G.ema * (1 - GOV.EMA_ALPHA) + frameTime * GOV.EMA_ALPHA;
      if (G.since >= G.cooldown) {
        if (G.ema > 1.2 * GOV.TARGET && G.scale > G.minScale) { G.scale = clamp(G.scale * GOV.STEP, G.minScale, 1); G.since = 0; why.push("lowered"); }
        else if (G.ema < 0.6 * GOV.TARGET && G.scale < 1) { G.scale = clamp(G.scale / GOV.STEP, G.minScale, 1); G.since = 0; why.push("raised"); }
      } else why.push("cooling down");
    } else G.scale = 1;
  } else if (G.idlePending) {
    G.mode = MODE.FINAL_FRAME;
    G.scale = 1;
    G.idlePending = false;
  } else G.mode = MODE.IDLE;
  return why;
}

// ================================================================== the fixture self-check
// The 24 fixtures from the renderer spec (2026-10-06 design, lines 174-211), pinned by
// tests/distance_estimator_test.gd with the same tolerance (line 10): relative 1e-5, absolute 1e-9.
const FIX_POINTS = [[0, 0, 0], [0.5, 0.5, 0.5], [1.2, -0.3, 0.8], [2, 2, 2], [3, 0, 0], [8.18, 3.81, 3.28], [0.1, 0.9, 1.5], [-1.5, 1.5, -1.5]];
const FIXTURES = [
  { name: "defaults", P: params(), line: 174,
    want: [0, 1.67e-15, 4.536385e-5, 1.84e-20, 1.0000000, 6.5655845, 1.2707534e-5, 7.2696999e-3] },
  { name: "alternative shape", P: params({ scale: -3, inner: 0.5, fold: 0.8, outer: 0.9 }), line: 187,
    want: [0, 3.9589733e-3, 7.3684211e-2, 0.69282032, 1.4000000, 7.1416315, 1.2998357e-2, 3.5649260e-3] },
  { name: "Julia", P: params({ julia: true }), line: 200,
    want: [4.9979908e-3, 1.0887837e-2, 4.5308936e-3, 4.9979908e-3, 8.0696204e-3, 2.3521820, 3.6647735e-3, 0.25217396] },
];
const FIX = (function () {
  const fails = [];
  let n = 0, worst = 0;
  for (const set of FIXTURES) set.want.forEach((want, i) => {
    const p = FIX_POINTS[i], got = de(p[0], p[1], p[2], 32, set.P), tol = Math.max(1e-9, 1e-5 * Math.abs(want));
    n++;
    if (Math.abs(want) > 1e-6) worst = Math.max(worst, Math.abs(got - want) / Math.abs(want));
    if (!(Math.abs(got - want) <= tol)) fails.push(`${set.name} (${p.join(", ")}): want ${want}, port gives ${got}`);
  });
  if (fails.length) {
    const msg = `[mandelbox fixtures] the de() port fails ${fails.length} of ${n} fixtures: ${fails.join("; ")}`;
    console.error(msg);
    if (typeof VIZ !== "undefined" && Array.isArray(VIZ.errors)) VIZ.errors.push(msg);
  }
  return { n, fails, worst };
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
  note: "Everything talks through two Resources, FractalParams and CameraState. The console inspector, the cameras, the Julia marker and the save loader write them; their built-in `changed` signal fans out to everything that draws or reacts. The shader never knows about the console and the console never knows about the shader. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "input", label: "INPUT — MAIN, THE PANEL, THE FILE PANELS", x: 0, y: 0, w: 460, h: 450 },
    { id: "state", label: "STATE — THE TWO SHARED RESOURCES", x: 520, y: 0, w: 420, h: 450 },
    { id: "render", label: "RENDER", x: 1000, y: 0, w: 880, h: 450 },
    { id: "cameras", label: "CAMERAS", x: 520, y: 500, w: 960, h: 170 },
    { id: "math", label: "CPU MATHS", x: 520, y: 720, w: 960, h: 130 },
    { id: "files", label: "FILES", x: 0, y: 500, w: 460, h: 360 },
  ],
  nodes: [
    { id: "panel", label: "ControlsPanel", sub: "the controls panel: edits FractalParams", ctx: "input", zone: "input", x: 30, y: 60, ...R("panel", 1),
      blurb: "The controls panel (a Ctrl tap toggles it), built in code (`_build`). Every widget writes one FractalParams field at once (lines 109-122) and `_refresh` mirrors external changes back, with `_syncing` stopping the echo. It never touches the shader or the viewport.",
      links: [RL("panel", 109, "the writes"), RL("panel", 179, "_refresh")] },
    { id: "wsf", label: "WorkspaceFiles", sub: "file panels · current file · ⌘S", ctx: "input", zone: "input", x: 30, y: 370, ...R("wsf", 1),
      blurb: "Owns the two native file panels and the current file's path, nothing else: it never reads or writes a save. The panel's Save / Load buttons open them (Main wires that); picking a file emits `save_to` / `load_from`; ⌘S (`workspace_quick_save`) saves over the current file.",
      links: [RL("wsf", 11, "signals"), RL("main", 133, "Save / Load buttons → prompt_save / prompt_load"), RL("wsf", 103, "quick_save")] },
    { id: "msave", label: "Main save / load", sub: "save_view_to · load_view_from", ctx: "input", zone: "files", x: 30, y: 570, ...R("main", 142),
      blurb: "Main does the saving and loading the file panels ask for, through Workspace, and only then marks the file current, so a failed save never becomes the current file. After a load in ORBIT it re-runs `enter()` to re-centre on the moved camera.",
      links: [RL("main", 152, "load_view_from"), RL("main", 170, "re-centre after a load")] },
    { id: "renderer", label: "RendererOptions", sub: "Settings ▸ Renderer tab", ctx: "input", zone: "input", x: 30, y: 270, ...R("renderer", 1),
      blurb: "The pause menu's Settings ▸ Renderer tab. Edits the open view's level of detail (`detail`, `detail_range`, `detail_falloff`), the step budget `max_steps`, `min_render_scale` and Fast Controls, all saved with the view. Only enabled in game (the title menu has no view); the pause dim lightens while it is open and the governor keeps running while paused, so each edit gets its full-resolution frame.",
      links: [RL("renderer", 51, "the writes"), RL("settings", 82, "set_params enables the tab"), RL("main", 93, "Main hands it params"), RL("main", 96, "governor runs while paused"), RL("pause", 61, "the dim lightens")] },
    { id: "dispatch", label: "Main._unhandled_input", sub: "the one input dispatcher", ctx: "input", zone: "input", x: 30, y: 170, ...R("main", 224),
      blurb: "The only mouse dispatcher, in a fixed order: a Ctrl tap opens the console (freeing the mouse) or closes it and recaptures; a Julia marker drag; a click while the mouse is free in FLY recaptures and leaves the console open; everything else goes to the active camera's `handle_event`. See the next tab for the order." },
    { id: "mode", label: "Main._apply_mode", sub: "camera + mouse capture", ctx: "input", zone: "input", x: 270, y: 170, ...R("main", 199),
      blurb: "Runs on every FractalParams change: enables exactly one camera from `camera_mode`, calls the orbit's `enter()` only when the mode actually changed (not on every slider move), and captures the mouse in FLY unless the pause menu or noise editor has freed it (the console no longer gates capture).",
      links: [RL("main", 205, "enter() only on a real switch"), RL("main", 212, "capture rule")] },

    { id: "params", label: "FractalParams", sub: "Resource · shape, colour, Julia, modes", ctx: "state", zone: "state", x: 660, y: 110, ...R("params", 1),
      blurb: "Every shape, colour, precision, Julia, Fast Controls, camera-mode and sensitivity value. Each setter calls `emit_changed()`, so one assignment reaches every listener. Defaults are the site's (scale −2.09, inner 0.7, fold 1, outer 1, Ice Fractal, precision 0.000025).",
      links: [RL("params", 16, "scale default"), RL("params", 10, "COLOR_MODE_IDS"), RL("tParams", 7, "defaults test")] },
    { id: "camState", label: "CameraState", sub: "Resource · Transform3D + speed_factor", ctx: "state", zone: "state", x: 680, y: 300, ...R("cam", 1),
      blurb: "The camera as a Transform3D in Godot's convention: forward = −basis.z, right = basis.x, up = basis.y. Plus the fly speed multiplier. Both setters emit `changed`. `make_default` looks from DEFAULT_EYE at the origin with +Z up.",
      links: [RL("cam", 18, "forward()"), RL("cam", 31, "make_default")] },

    { id: "view", label: "FractalView", sub: "uniforms · project / unproject", ctx: "render", zone: "render", x: 1030, y: 80, ...R("view", 1),
      blurb: "Pushes the two Resources into the shader as uniforms, sizes the SubViewport from `render_scale`, and owns the ray maths (`project` / `unproject`) so the Julia marker and the orbit camera agree with the shader exactly.",
      links: [RL("view", 254, "_push_params"), RL("view", 287, "_push_near: near_dist = D(eye)"), RL("view", 203, "project"), RL("view", 218, "unproject")] },
    { id: "sub", label: "SubViewport", sub: "window × render_scale pixels", ctx: "render", zone: "render", x: 1350, y: 80, ...R("viewScn", 22),
      blurb: "The render target. Its size is the window × `render_scale` rounded to whole pixels; its update mode (ALWAYS / ONCE / DISABLED) is how the governor freezes rendering when nothing changes.",
      links: [RL("view", 233, "_apply_size")] },
    { id: "rect", label: "ColorRect + mandelbox.gdshader", sub: "fragment(): march + shade", ctx: "render", zone: "render", x: 1350, y: 230, ...SH(140),
      blurb: "A canvas_item shader on a ColorRect filling the SubViewport: one fragment per pixel builds its ray, marches the Mandelbox in two phases and colours the hit. All of it float32 (WebGL 2).",
      links: [RL("viewScn", 28, "the ColorRect in the scene"), RL("sh", 48, "de")] },
    { id: "tex", label: "TextureRect (Display)", sub: "stretched to the window", ctx: "render", zone: "render", x: 1640, y: 80, ...R("view", 38),
      blurb: "Shows the SubViewport's texture stretched to fill the window (`EXPAND_IGNORE_SIZE`, `STRETCH_SCALE`), so a quarter-scale render still covers the screen while you move.",
      links: [RL("viewScn", 16, "the Display node")] },
    { id: "gov", label: "ResolutionGovernor", sub: "render_scale · update mode", ctx: "render", zone: "render", x: 1030, y: 330, ...R("gov", 1),
      blurb: "While anything changes it renders continuously and adapts `render_scale` to hold ~30 fps; on the first still frame it renders once at full scale; then it freezes. Its `step()` is pure and is stepped live in tab 9.",
      links: [RL("gov", 62, "step()"), RL("tGov", 5, "the test")] },

    { id: "fly", label: "FlyCamera", sub: "mouse-look · WASD · distance-scaled speed", ctx: "camera", zone: "cameras", x: 550, y: 560, ...R("fly", 1),
      blurb: "Yaw about world +Z, pitch about its own right clamped 1° off ±Z, never roll. Moves every physics tick at `clamp(D(eye), 1e-6, 20) · speed_factor`, so a second of flight covers about the gap to the nearest surface.",
      links: [RL("fly", 55, "apply_look"), RL("fly", 83, "current_speed")] },
    { id: "orbit", label: "OrbitCamera", sub: "drag to orbit · click to re-centre", ctx: "camera", zone: "cameras", x: 880, y: 560, ...R("orbit", 1),
      blurb: "The site's orbit controller: keeps a `center`; left-drag orbits it, Shift pans, right/Alt dollies, the wheel moves toward the cursor, a click re-centres on a CPU-marched hit. The mouse is never captured.",
      links: [RL("orbit", 9, "the gesture constants"), RL("orbit", 155, "_march")] },
    { id: "marker", label: "JuliaMarker", sub: "drags the Julia point", ctx: "camera", zone: "cameras", x: 1200, y: 560, ...R("marker", 1),
      blurb: "A ring drawn at `project(julia_point)` while Julia mode is on. A press on it captures the point's camera depth; dragging sets `julia_point = unproject(mouse, depth)`, so it slides in the plane facing the camera.",
      links: [RL("marker", 37, "begin_drag"), RL("marker", 49, "update_drag")] },

    { id: "de", label: "DistanceEstimator", sub: "estimate_at · 64-bit scalar orbit", ctx: "math", zone: "math", x: 780, y: 780, ...R("de", 1),
      blurb: "The CPU copy of the shader's `de(p, 32)`, used for fly speed and orbit clicks. Runs the orbit in scalar 64-bit floats, not Vector3 (32-bit), because lost input precision near the surface broke the near-boundary fixtures.",
      links: [RL("de", 7, "why scalars"), RL("tDE", 15, "the 24 fixtures")] },

    { id: "ws", label: "Workspace", sub: "capture · restore · JSON v1", ctx: "files", zone: "files", x: 240, y: 690, ...R("ws", 1),
      blurb: "Saves and loads a view as JSON: every FractalParams value plus the camera's eye, forward, up and speed factor. Loading never fails on unfamiliar content: unknown or malformed keys are skipped with a warning, missing keys leave the value alone.",
      links: [RL("ws", 34, "capture"), RL("ws", 61, "restore"), RL("tWs", 66, "the skip test")] },
    { id: "saves", label: "saves/*.json", sub: "the committed views", ctx: "files", zone: "files", x: 240, y: 790, ...R("saveDef", 1),
      blurb: "default.json, juliaIceField.json and juliaIceTerraces.json (tab 4 loads their values). A source build saves into `res://saves/`; an exported build cannot write into its PCK, so it uses `user://saves/`.",
      links: [RL("saveField", 1, "juliaIceField.json"), RL("saveTer", 1, "juliaIceTerraces.json"), RL("wsf", 19, "REPO_DIR / EXPORT_DIR")] },
  ],
  edges: [
    { from: "renderer", to: "params", kind: "call", label: "LOD · steps · min scale", ...R("renderer", 51), bow: 0.8,
      blurb: "Each slider assigns one FractalParams field through `_write`; the setters clamp to the documented ranges (fractal_params.gd:61-70)." },
    { from: "panel", to: "params", kind: "call", label: "edits", ...R("panel", 109),
      blurb: "Each widget's signal assigns one field through `_write`, which does nothing while `_refresh` is syncing the widgets (so mirroring a change never echoes it back)." },
    { from: "wsf", to: "msave", kind: "signal", label: "save_to / load_from", ...R("main", 129),
      blurb: "A picked file (or ⌘S on a current file) emits `save_to(path)` or `load_from(path)`; Main does the work." },
    { from: "msave", to: "ws", kind: "call", label: "save_file / load_file", ...R("main", 144), bow: 0,
      blurb: "`Workspace.save_file(path, params, camera)` and `load_file`; the result's warnings go to the panel's status line.",
      links: [RL("main", 155, "load_file")] },
    { from: "ws", to: "saves", kind: "data", label: "JSON", ...R("ws", 93),
      blurb: "Written as indented JSON with `store_string`; read back with `JSON.new().parse()` so a bad file is a warning, not an engine error.",
      links: [RL("ws", 112, "the parse")] },
    { from: "ws", to: "params", kind: "call", label: "restore", ...R("ws", 74), bow: -0.5,
      blurb: "Each known, well-formed key is written with `params.set(key, value)`, which runs the setter and emits `changed`." },
    { from: "ws", to: "camState", kind: "call", ...R("ws", 204), bow: 0.3,
      blurb: "The camera is rebuilt with `looking_at(eye + forward, up)`, after rejecting a zero or degenerate orientation." },
    { from: "dispatch", to: "fly", kind: "call", label: "handle_event", ...R("main", 282),
      blurb: "Step 4 of the dispatcher: whatever is left goes to the active camera. In FLY: mouse-look while captured, the wheel scales the speed factor." },
    { from: "dispatch", to: "orbit", kind: "call", ...R("main", 282),
      blurb: "Step 4 in ORBIT: drags, the wheel and clicks." },
    { from: "dispatch", to: "marker", kind: "call", label: "drag", ...R("main", 257), bow: 0.3,
      blurb: "Step 2: while Julia is on and the mouse is free, a left press that lands on the ring starts a drag, and motion during it moves the point.",
      links: [RL("main", 263, "update_drag")] },
    { from: "mode", to: "fly", kind: "call", label: "enabled", ...R("main", 201), bow: 0.5,
      blurb: "`fly.enabled = is_fly`. A disabled camera ignores events and its `_physics_process` returns at once." },
    { from: "mode", to: "orbit", kind: "call", label: "enter()", ...R("main", 206),
      blurb: "Only on a real switch into ORBIT: `enter()` centres on the surface hit by the centre ray (or the origin).",
      links: [RL("orbit", 76, "enter")] },
    { from: "fly", to: "camState", kind: "call", label: "transform", ...R("fly", 48),
      blurb: "Movement writes `transform.origin` every physics tick; mouse-look rebuilds the basis with `looking_at(eye + fwd, +Z)` (no roll).",
      links: [RL("fly", 97, "_set_forward")] },
    { from: "orbit", to: "camState", kind: "call", label: "transform", ...R("orbit", 150),
      blurb: "Every gesture ends in `_look_from(eye)` (looking at `center`, +Z up), or moves the origin directly (pan, wheel)." },
    { from: "marker", to: "params", kind: "call", label: "julia_point", ...R("marker", 52), bow: -2,
      blurb: "`julia_point = unproject(mouse, drag_depth)`: the panel's X/Y/Z fields follow through `changed`." },
    { from: "fly", to: "de", kind: "data", label: "D(eye)", ...R("fly", 84),
      blurb: "`current_speed()` asks the CPU estimator for the distance from the eye." },
    { from: "orbit", to: "de", kind: "data", label: "CPU march", ...R("orbit", 164),
      blurb: "`_march` steps a single high-precision phase (up to 200 steps) for clicks and `enter()`." },
    { from: "params", to: "view", kind: "signal", label: "uniforms", ...R("view", 64),
      blurb: "`_on_params_changed` → `_push_params` + `request_frame`." },
    { from: "params", to: "marker", kind: "signal", ...R("marker", 19), bow: 2,
      blurb: "Shows or hides the ring with Julia mode and redraws it at the new point." },
    { from: "params", to: "panel", kind: "signal", label: "refresh", ...R("panel", 129),
      blurb: "`_refresh` mirrors every field back into its widget (a dragged Julia point updates the X/Y/Z fields). CameraState.changed is connected to `_refresh` too, for the `speed ×` label.",
      links: [RL("panel", 130, "CameraState.changed → _refresh")] },
    { from: "params", to: "mode", kind: "signal", label: "_apply_mode", ...R("main", 55),
      blurb: "Main re-applies the camera mode on every FractalParams change; `_last_mode` keeps it from re-centring the orbit on a slider move (main_test, bug 5b).",
      links: [RL("tMain", 46, "bug 5b test")] },
    { from: "params", to: "gov", kind: "signal", label: "_dirty", ...R("gov", 31),
      blurb: "Any FractalParams change marks the governor dirty (this frame is 'changing') and re-reads `fast_controls`." },
    { from: "camState", to: "view", kind: "signal", label: "eye, basis", ...R("view", 66),
      blurb: "`_on_camera_changed` → `_push_camera` (eye, right, up, forward) + `request_frame`." },
    { from: "camState", to: "marker", kind: "signal", ...R("marker", 20),
      blurb: "The ring is re-projected whenever the camera moves." },
    { from: "camState", to: "gov", kind: "signal", label: "mark_changed", ...R("main", 56), bow: -0.3,
      blurb: "Main connects CameraState.changed to `governor.mark_changed()`: any camera move is a 'changing' frame." },
    { from: "gov", to: "view", kind: "call", label: "render_scale · continuous", ...R("gov", 49),
      blurb: "Every `_process`: `set_render_scale(scale)`, then by mode `set_continuous(true)`, or `set_continuous(false)` + `request_frame()`, or just `set_continuous(false)`.",
      links: [RL("gov", 50, "match mode")] },
    { from: "view", to: "sub", kind: "call", label: "size · mode", ...R("view", 238),
      blurb: "`_apply_size` sets the viewport to window × render_scale (and the `aspect` uniform); `request_frame` / `set_continuous` set its update mode.",
      links: [RL("view", 191, "UPDATE_ONCE"), RL("view", 198, "ALWAYS / DISABLED")] },
    { from: "view", to: "rect", kind: "data", label: "20 uniforms", ...R("view", 257),
      blurb: "`set_shader_parameter` for every uniform; tab 10 lists each with its transform (inner² → min_r2, …)." },
    { from: "sub", to: "rect", kind: "call", label: "renders", ...R("viewScn", 28),
      blurb: "The ColorRect is the SubViewport's only child: rendering the viewport runs the shader once per pixel." },
    { from: "sub", to: "tex", kind: "data", label: "texture", ...R("view", 38),
      blurb: "`_display.texture = _viewport.get_texture()`." },
  ],
};

// ================================================================== 2. one input, one frame
const seq = {
  type: "seq",
  tab: "One input, one frame",
  title: "One input, one frame",
  note: "From a mouse event to pixels on screen, in order. Input is dispatched once by Main; the camera writes CameraState; the `changed` signal pushes uniforms and marks the governor dirty; the governor's `_process` then decides the render scale and whether the SubViewport renders this frame. When the motion stops, one full-scale frame renders and then nothing does.",
  laneWidth: 240, headWidth: 200,
  participants: [
    { id: "ev", col: 0, ctx: "input", name: "input event", sub: "mouse / key", blurb: "An InputEvent the panel did not consume (the panel is a Control and eats clicks inside itself)." },
    { id: "main", col: 1, ctx: "input", name: "Main", sub: "_unhandled_input", ...R("main", 224), blurb: "The single dispatcher." },
    { id: "cam", col: 2, ctx: "camera", name: "active camera", sub: "FlyCamera or OrbitCamera", ...R("main", 218), blurb: "`_active_camera()`: FlyCamera in FLY, OrbitCamera in ORBIT." },
    { id: "cs", col: 3, ctx: "state", name: "CameraState", sub: "Resource", ...R("cam", 1) },
    { id: "view", col: 4, ctx: "render", name: "FractalView", sub: "uniforms, viewport size", ...R("view", 1) },
    { id: "gov", col: 5, ctx: "render", name: "ResolutionGovernor", sub: "_process every frame", ...R("gov", 43) },
    { id: "sv", col: 6, ctx: "render", name: "SubViewport", sub: "runs the shader", ...R("viewScn", 22) },
    { id: "tex", col: 7, ctx: "render", name: "TextureRect", sub: "fills the window", ...R("view", 38) },
  ],
  rows: [
    { sec: "INPUT — Main._unhandled_input, four steps in order" },
    { from: "ev", to: "main", kind: "call", label: "_unhandled_input(event)", ...R("main", 224),
      blurb: "Every unhandled event comes here first; each step returns once it has consumed the event." },
    { from: "main", to: "main", kind: "call", label: "1 · Ctrl tap opens / closes the console", tick: "on release, not while a text field has focus", ...R("main", 236),
      blurb: "A bare Ctrl key-down arms the toggle and the Ctrl key-up fires it, so the console flips only when Ctrl is tapped alone (Ctrl+S still quick-saves). Captured, it frees the mouse and opens the console; free, it closes the console and recaptures. Ignored while a text field in either window has focus.",
      links: [RL("panel", 147, "text_field_has_focus")] },
    { from: "main", to: "main", kind: "call", label: "2 · Julia marker drag", tick: "Julia on, mouse free", ...R("main", 254),
      blurb: "A left press on the ring starts a drag (`begin_drag`), motion during it calls `update_drag`, a release ends it.",
      links: [RL("marker", 37, "begin_drag")] },
    { from: "main", to: "main", kind: "call", label: "3 · click to capture", tick: "FLY, mouse free", ...R("main", 269),
      blurb: "A left click on the view while the mouse is free in FLY recaptures the mouse (and closes the noise editor), leaving the console open. On the web, pointer lock only works from inside such a user gesture.",
      links: [RL("spec", 358, "spec: mouse capture")] },
    { from: "main", to: "cam", kind: "call", label: "4 · handle_event(event)", ...R("main", 282),
      blurb: "Everything else goes to the active camera; a consumed event is marked handled." },
    { from: "cam", to: "cs", kind: "call", label: "apply_look → transform", tick: "mouse motion while captured", ...R("fly", 55),
      blurb: "Mouse motion while captured: yaw about world +Z, pitch about the camera's right clamped to ±89°, basis rebuilt with +Z as up (no roll).",
      links: [RL("fly", 97, "looking_at")] },
    { from: "cam", to: "cs", kind: "call", label: "rotate / pan / dolly / zoom", tick: "drag · wheel · click", ...R("orbit", 150),
      blurb: "The orbit's gestures all end by writing the transform." },
    { from: "cs", to: "view", kind: "signal", label: "changed → _push_camera", tick: "+ request_frame()", ...R("view", 249),
      blurb: "Eye and basis become the `eye`, `cam_right`, `cam_up`, `cam_forward` uniforms; `request_frame` asks for one render (unless already continuous).",
      links: [RL("view", 274, "_push_camera")] },
    { from: "cs", to: "gov", kind: "signal", label: "changed → mark_changed()", ...R("main", 56),
      blurb: "Sets `_dirty`; the governor reads and clears it once per frame." },
    { sec: "PHYSICS — FlyCamera._physics_process, every physics tick" },
    { from: "cam", to: "cam", kind: "call", label: "move_direction() · current_speed()", tick: "speed = clamp(D(eye), 1e-6, 20) · factor", ...R("fly", 47),
      blurb: "The six actions in camera axes, normalised; nothing while Cmd/Ctrl is held (Cmd+S is a save). Speed from the CPU estimator: tab 8.",
      links: [RL("fly", 70, "move_direction"), RL("fly", 83, "current_speed")] },
    { from: "cam", to: "cs", kind: "call", label: "origin += dir · speed · delta", ...R("fly", 48),
      blurb: "Each tick's move emits `changed` again, so a held key keeps the frame 'changing'." },
    { sec: "FRAME — ResolutionGovernor._process" },
    { from: "gov", to: "gov", kind: "call", label: "step(delta, changing = _dirty)", ...R("gov", 48),
      blurb: "Pure logic: updates `scale` and `mode` from this frame's time. Stepped live in tab 9.",
      links: [RL("gov", 62, "step")] },
    { from: "gov", to: "view", kind: "call", label: "set_render_scale(scale)", tick: "clamped min_render_scale (0.25) … 1", ...R("gov", 49),
      blurb: "Resizes the SubViewport only when the scale changed; applies before this frame renders.",
      links: [RL("view", 181, "set_render_scale")] },
    { from: "gov", to: "view", kind: "call", label: "set_continuous(true)", tick: "CONTINUOUS", ...R("gov", 52),
      blurb: "UPDATE_ALWAYS while changing; `request_frame` then refuses to downgrade it to UPDATE_ONCE mid-motion.",
      links: [RL("view", 189, "the guard")] },
    { from: "view", to: "sv", kind: "call", label: "size = window × render_scale", tick: "UPDATE_ALWAYS / UPDATE_ONCE", ...R("view", 238),
      blurb: "Whole pixels: `round(size × render_scale)`, at least 1. The `aspect` uniform follows.",
      links: [RL("view", 236, "rounding")] },
    { from: "sv", to: "sv", kind: "call", label: "fragment() for every pixel", tick: "march · normal · colour", ...SH(140),
      blurb: "Tabs 3 to 7 open this up: the estimator, the march, the colour modes and the two normals." },
    { from: "sv", to: "tex", kind: "data", label: "texture, stretched to the window", ...R("view", 38),
      blurb: "Linear-filtered stretch: a 0.25-scale render is a blurry full-window image while you move.",
      links: [RL("view", 40, "STRETCH_SCALE")] },
    { sec: "STOPPING — the first still frame, then nothing" },
    { from: "gov", to: "gov", kind: "call", label: "FINAL_FRAME: scale = 1.0", tick: "first frame with changing = false", ...R("gov", 80),
      blurb: "`_idle_pending` was set while changing; the first still frame clears it and restores full scale." },
    { from: "gov", to: "view", kind: "call", label: "set_continuous(false)", tick: "+ request_frame()", ...R("gov", 54),
      blurb: "UPDATE_DISABLED, then one UPDATE_ONCE: exactly one full-resolution render of the final view." },
    { from: "view", to: "sv", kind: "call", label: "one frame at full scale", ...R("view", 191) },
    { from: "gov", to: "gov", kind: "call", label: "IDLE: nothing renders", tick: "zero GPU cost while still", ...R("gov", 84),
      blurb: "Every later still frame stays IDLE with updates disabled; the TextureRect keeps showing the last image. The panel still redraws (a normal Control).",
      links: [RL("spec", 498, "spec: idle freeze")] },
  ],
  fragments: [
    { type: "alt", rows: [6, 7], cols: [2, 3], guard1: "FLY", divRow: 7, guard2: "ORBIT" },
    { type: "loop", rows: [11, 12], cols: [2, 3], guard1: "each physics tick while a move key is held (FLY)" },
  ],
};

// ================================================================== 3. building the shape, fold by fold
const foldFig = {
  type: "figure",
  tab: "Fold by fold",
  title: "Building the shape, fold by fold",
  note: "A port of the shader's `de` (equal to DistanceEstimator.estimate_at), stage by stage. Click the plane to pick a point p; Step walks its orbit one stage at a time: the box fold reflects any component past ±fold back inside, the sphere fold inverts z inside the outer sphere (and scales it by a constant inside the inner one), then z is scaled by `scale` and p (or the Julia point) is added back. `dz` carries the derivative; the estimate is |z| / |dz| after 32 iterations. The background is the estimate on the plane (blue at the surface). The port runs in 64-bit doubles like DistanceEstimator's scalar orbit; the shader runs float32, which is why the GDScript copy avoids Vector3 (distance_estimator.gd, header).",
  w: 1560, h: 910,
  draw(api) {
    const GX = 20, GY = 96, VS = 600, RW = 3.0, RES = 120;
    const S = { P: params(), p: [1.0, 0.5, 0], k: 0, cloud: false };
    const ITERS = 32, LAST = ITERS * 3;
    const sx = x => GX + (x + RW) / (2 * RW) * VS, sy = y => GY + (RW - y) / (2 * RW) * VS;
    const C_BOX = api.hue(2), C_SPH = api.hue(5), C_ADD = api.hue(1), C_P = api.hue(3);
    const stageColor = st => [C_P, C_BOX, C_SPH, C_ADD][st];
    let orbit = [], cloud = [];
    const isFixture = () => S.p[0] === 1.2 && S.p[1] === -0.3 && S.p[2] === 0.8 && !S.P.julia &&
      S.P.scale === -2.09 && S.P.inner === 0.7 && S.P.fold === 1 && S.P.outer === 1;

    // ---- stage list across the top
    const stages = stageRow(api, 20, 16, 360, 14, [
      { n: "1", name: "Box fold", f: "z = clamp(z, −fold, fold)·2 − z", color: C_BOX,
        tip: { ...SH(54), blurb: "Each component past ±fold is reflected back inside: x = 1.3 with fold 1 becomes 0.7. Inside the box nothing moves. The fold keeps the orbit near the origin and makes the shape's box-like walls.", links: [RL("de", 36, "GDScript: estimate_at"), RL("spec", 156, "spec, step 1")] } },
      { n: "2", name: "Sphere fold", f: "k = fixed_r2/min_r2 · fixed_r2/r2 · 1", color: C_SPH,
        tip: { ...SH(57), blurb: "r2 = |z|². Inside the inner sphere (r2 < min_r2 = inner²) z is scaled by the constant fixed_r2/min_r2; between the spheres it is inverted (k = fixed_r2/r2, so |z|·k·|z| = fixed_r2); outside the outer sphere k = 1. dz is scaled by the same k.", links: [RL("sh", 55, "r2"), RL("sh", 62, "z *= k; dz *= k"), RL("de", 40, "GDScript: sphere fold")] } },
      { n: "3", name: "Scale and add", f: "z = scale·z + c ;  dz = −dz·scale + 1", color: C_ADD,
        tip: { ...SH(64), blurb: "z is stretched by scale (negative: it also flips through the origin) and the constant c is added back: c = p, or the Julia point in Julia mode. dz follows the derivative of that map.", links: [RL("sh", 65, "dz"), RL("de", 51, "GDScript: scale and add"), RL("sh", 49, "c = julia ? julia_point : p")] } },
      { n: "D", name: "The estimate", f: "D = |z| / |dz|   after 32 iterations", color: "var(--ink)",
        tip: { ...SH(67), blurb: "A point inside the set keeps |z| bounded while |dz| grows like |scale|ⁿ, so D → 0. A point outside escapes and D settles near its distance to the surface. The march (tab 5) steps by exactly this number.", links: [RL("de", 55, "GDScript: return"), RL("tDE", 15, "the 24 fixtures")] } },
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
    // geometry the stages act on (redrawn on parameter change)
    function drawGeo() {
      while (geo.firstChild) geo.removeChild(geo.firstChild);
      api.el("line", { x1: sx(-RW), y1: sy(0), x2: sx(RW), y2: sy(0), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      api.el("line", { x1: sx(0), y1: sy(-RW), x2: sx(0), y2: sy(RW), style: "stroke:var(--hairline);stroke-width:1" }, geo);
      const bh = S.P.boxHalf;
      if (bh < RW) api.el("rect", { x: sx(-bh), y: sy(bh), width: sx(bh) - sx(-bh), height: sy(-bh) - sy(bh), style: "fill:none;stroke:var(--muted);stroke-width:1;stroke-dasharray:2 4" }, geo);
      const f = S.P.fold;
      api.el("rect", { x: sx(-f), y: sy(f), width: sx(f) - sx(-f), height: sy(-f) - sy(f), style: `fill:none;stroke:${C_BOX};stroke-width:1.6;stroke-dasharray:7 4` }, geo);
      const scaleR = VS / (2 * RW);
      api.el("circle", { cx: sx(0), cy: sy(0), r: S.P.inner * scaleR, style: `fill:none;stroke:${C_SPH};stroke-width:1.4;stroke-dasharray:3 3` }, geo);
      api.el("circle", { cx: sx(0), cy: sy(0), r: S.P.outer * scaleR, style: `fill:none;stroke:${C_SPH};stroke-width:1.6` }, geo);
      if (S.P.julia) {
        api.el("circle", { cx: sx(S.P.jp[0]), cy: sy(S.P.jp[1]), r: 6, style: `fill:none;stroke:var(--ink);stroke-width:1.6` }, geo);
      }
    }
    // trail: one segment + dot per state, tipped once with a live() reading the current orbit
    const STAGE_NAMES = ["start", "after the box fold", "after the sphere fold", "after scale and add"];
    const DOT_REFS = [SH(50), SH(54), SH(62), SH(64)];
    const segs = [], dots = [];
    for (let k = 1; k <= LAST; k++)
      segs.push(api.el("line", { style: `stroke-width:1.8;${noPtr}` }, trailG));
    for (let k = 0; k <= LAST; k++) {
      const c = api.el("circle", { r: k === 0 ? 6 : 3.4, style: "cursor:pointer" }, trailG);
      dots.push(c);
      api.tip(c, { title: k === 0 ? "p, the start of the orbit" : `iteration ${Math.floor((k - 1) / 3) + 1}, ${STAGE_NAMES[(k - 1) % 3 + 1]}`,
        ...DOT_REFS[k === 0 ? 0 : (k - 1) % 3 + 1],
        live() {
          const st = orbit[k];
          if (!st) return {};
          const lines = [`\`z\` = ${vec(st.z)}`, `|z| = ${sci(Math.hypot(...st.z))}`, `\`dz\` = ${sci(st.dz)}`];
          if (st.stage === 2) lines.push(`r2 = ${sci(st.r2)}, k = ${sci(st.k)} (${["inside the inner sphere", "between the spheres: inversion", "outside: k = 1"][st.branch]})`);
          if (st.stage === 1) lines.push(`folded: ${["x", "y", "z"].filter((_, a) => st.folded[a]).join(", ") || "nothing (inside the box)"}`);
          return { sub: `state ${k} of ${LAST}`, blurb: lines.join("\n") };
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
      api.tip(dot, { title: `sample from (${fmt(p[0], 1)}, ${fmt(p[1], 1)})`, ...SH(48), live() {
        const o = cloud[idx]; if (!o) return {};
        const st = o[S.k], prev = o[Math.max(0, S.k - 1)];
        return { sub: S.k === 0 ? "start" : `iteration ${Math.floor((S.k - 1) / 3) + 1}, ${STAGE_NAMES[(S.k - 1) % 3 + 1]}`,
          blurb: `start (${fmt(p[0], 2)}, ${fmt(p[1], 2)}, ${fmt(S.p[2], 2)})\nprevious stage ${vec(prev.z)}\nnow ${vec(st.z)}\nD at the start = ${sci(de(p[0], p[1], S.p[2], 32, S.P))}` };
      } });
    }

    // ---- readouts on the right
    const RX = 660;
    const head = api.text(RX, 112, "", "ink", { style: caps });
    const lines = [];
    for (let i = 0; i < 8; i++) lines.push(api.text(RX, 140 + i * 21, "", "mono"));
    // |z| gauge against the two spheres
    const GW = 520, GZ = 340, ZMAX = 2.5, gx = v => RX + clamp(v / ZMAX, 0, 1) * GW;
    api.text(RX, GZ - 12, "|z| against the spheres", "ink", { style: caps });
    api.el("line", { x1: RX, y1: GZ + 10, x2: RX + GW, y2: GZ + 10, style: "stroke:var(--hairline);stroke-width:8;stroke-linecap:round" });
    const gInner = api.el("line", { y1: GZ, y2: GZ + 20, style: `stroke:${C_SPH};stroke-width:2;stroke-dasharray:3 2` });
    const gOuter = api.el("line", { y1: GZ, y2: GZ + 20, style: `stroke:${C_SPH};stroke-width:2.4` });
    const gInnerT = api.text(0, GZ + 34, "", "", { "text-anchor": "middle", style: `${small};fill:${C_SPH}` });
    const gOuterT = api.text(0, GZ + 48, "", "", { "text-anchor": "middle", style: `${small};fill:${C_SPH}` });
    const gMark = api.el("circle", { cy: GZ + 10, r: 7, style: "fill:var(--ink)" });
    for (const t of [0, 0.5, 1, 1.5, 2, 2.5]) api.text(gx(t), GZ - 2, String(t), "muted", { "text-anchor": "middle", style: "font-size:9.5px" });
    const gNote = api.text(RX + GW + 16, GZ + 14, "", "mono", { style: small });
    // components against ±fold
    const CB = 446, CMAX = 3, cx_ = v => RX + GW / 2 + clamp(v / CMAX, -1, 1) * GW / 2;
    api.text(RX, CB - 12, "components against the fold box ±fold", "ink", { style: caps });
    const cBand = [], cMark = [], cVal = [];
    ["x", "y", "z"].forEach((a, i) => {
      const y = CB + i * 24;
      api.text(RX - 16, y + 4, a, "mono", { "text-anchor": "end" });
      api.el("line", { x1: RX, y1: y, x2: RX + GW, y2: y, style: "stroke:var(--hairline);stroke-width:6;stroke-linecap:round" });
      cBand.push(api.el("line", { y1: y, y2: y, style: `stroke:${C_BOX};stroke-width:6;opacity:.45` }));
      cMark.push(api.el("circle", { cy: y, r: 5.5, style: "fill:var(--ink)" }));
      cVal.push(api.text(RX + GW + 16, y + 4, "", "mono", { style: small }));
    });
    api.el("line", { x1: RX + GW / 2, y1: CB - 6, x2: RX + GW / 2, y2: CB + 54, style: "stroke:var(--muted);stroke-width:1" });
    // per-iteration table
    const TY = 540;
    api.text(RX, TY, "iteration", "ink", { style: caps });
    ["|z|", "dz", "k (sphere)", "|z| / |dz|"].forEach((h, i) => api.text(RX + 120 + i * 160, TY, h, "ink", { style: caps }));
    const trows = [];
    for (let r = 0; r < 8; r++) trows.push([0, 1, 2, 3, 4].map(c => api.text(RX + (c ? 120 + (c - 1) * 160 : 0), TY + 22 + r * 19, "", "mono", { style: small })));

    function recompute() {
      orbit = orbitStages(S.p[0], S.p[1], S.p[2], S.P, ITERS);
      cloud = CL.map(o => orbitStages(o.p[0], o.p[1], S.p[2], S.P, ITERS));
    }
    function render() {
      const k = S.k, st = orbit[k];
      stages.set(k === 0 ? -1 : k === LAST ? 3 : (k - 1) % 3);
      // trail
      for (let j = 1; j <= LAST; j++) {
        const a = orbit[j - 1].z, b = orbit[j].z, on = j <= k, seg = segs[j - 1];
        seg.style.display = on ? "" : "none";
        if (on) {
          seg.setAttribute("x1", sx(a[0])); seg.setAttribute("y1", sy(a[1]));
          seg.setAttribute("x2", sx(b[0])); seg.setAttribute("y2", sy(b[1]));
          seg.style.stroke = stageColor(orbit[j].stage);
          seg.style.opacity = j === k ? 1 : 0.55;
        }
      }
      for (let j = 0; j <= LAST; j++) {
        const on = j <= k, d = dots[j];
        d.style.display = on ? "" : "none";
        if (on) {
          d.setAttribute("cx", sx(orbit[j].z[0])); d.setAttribute("cy", sy(orbit[j].z[1]));
          d.style.fill = stageColor(orbit[j].stage);
        }
      }
      curRing.setAttribute("cx", sx(st.z[0])); curRing.setAttribute("cy", sy(st.z[1]));
      // cloud
      cloudG.style.display = S.cloud ? "" : "none";
      if (S.cloud) CL.forEach((o, i) => {
        const a = cloud[i][Math.max(0, k - 1)].z, b = cloud[i][k].z;
        o.ln.setAttribute("x1", sx(a[0])); o.ln.setAttribute("y1", sy(a[1]));
        o.ln.setAttribute("x2", sx(b[0])); o.ln.setAttribute("y2", sy(b[1]));
        o.dot.setAttribute("cx", sx(b[0])); o.dot.setAttribute("cy", sy(b[1]));
      });
      // readouts
      const it = k === 0 ? 0 : Math.floor((k - 1) / 3) + 1;
      head.textContent = k === 0 ? "the start: z = p, dz = 1" : `iteration ${it} of ${ITERS} · ${STAGE_NAMES[st.stage]}`;
      const zl = Math.hypot(...st.z), D = de(S.p[0], S.p[1], S.p[2], 32, S.P);
      const L = [
        `p = ${vec(S.p, 3)}   c = ${S.P.julia ? `Julia point ${vec(S.P.jp, 3)}` : "p"}`,
        `z = ${vec(st.z)}`,
        `|z| = ${sci(zl)}    dz = ${sci(st.dz)}`,
        st.stage === 2 ? `r2 = ${sci(st.r2)} → k = ${sci(st.k)}  (${["r2 < min_r2: constant fixed_r2/min_r2", "min_r2 ≤ r2 < fixed_r2: inversion fixed_r2/r2", "r2 ≥ fixed_r2: k = 1"][st.branch]})`
          : st.stage === 1 ? `box fold: ${["x", "y", "z"].filter((_, a) => st.folded[a]).join(", ") || "no component"} past ±${fmt(S.P.fold, 2)} reflected`
          : st.stage === 3 ? `z = ${fmt(S.P.scale, 2)}·z + c,  dz = −dz·${fmt(S.P.scale, 2)} + 1` : "Step ▶ runs the first box fold",
        `running |z| / |dz| = ${sci(zl / Math.abs(st.dz))}`,
        `de(p, 32) = ${sci(D, 6)}${isFixture() ? "   = the test's 4.536385e−5 (defaults row 3)" : ""}`,
        `de(p, 16) = ${sci(de(S.p[0], S.p[1], S.p[2], 16, S.P), 6)}   (the march's first phase)`,
        zl > RW * 1.4 ? "z has left the view: the point escapes, so D is its distance to the surface" : "",
      ];
      L.forEach((s, i) => { lines[i].textContent = s; });
      lines[5].style.fill = isFixture() ? api.hue(3) : "";
      // gauges
      const ir = S.P.inner, or = S.P.outer;
      gInner.setAttribute("x1", gx(ir)); gInner.setAttribute("x2", gx(ir));
      gOuter.setAttribute("x1", gx(or)); gOuter.setAttribute("x2", gx(or));
      gInnerT.setAttribute("x", gx(ir)); gInnerT.textContent = `inner ${fmt(ir, 2)}`;
      gOuterT.setAttribute("x", gx(or)); gOuterT.textContent = `outer ${fmt(or, 2)}`;
      gMark.setAttribute("cx", gx(zl));
      gMark.style.fill = stageColor(st.stage);
      gNote.textContent = `|z| = ${sci(zl)}${zl > ZMAX ? " (off the gauge)" : ""}`;
      const f = S.P.fold;
      for (let a = 0; a < 3; a++) {
        cBand[a].setAttribute("x1", cx_(-f)); cBand[a].setAttribute("x2", cx_(f));
        cMark[a].setAttribute("cx", cx_(st.z[a]));
        cMark[a].style.fill = stageColor(st.stage);
        cVal[a].textContent = `${sci(st.z[a])}${Math.abs(st.z[a]) > f ? "  past the fold" : ""}`;
      }
      // table: the last 8 finished iterations
      const done = k === 0 ? 0 : Math.floor(k / 3);
      const first = Math.max(1, done - 7);
      for (let r = 0; r < 8; r++) {
        const n = first + r, cells = trows[r];
        if (n > done) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const end = orbit[n * 3], sph = orbit[n * 3 - 1];
        const vals = [String(n), sci(Math.hypot(...end.z)), sci(end.dz), sci(sph.k), sci(Math.hypot(...end.z) / Math.abs(end.dz))];
        cells.forEach((c, i) => { c.textContent = vals[i]; });
      }
      axisLbl.textContent = `plane z = ${fmt(S.p[2], 2)} · x right, y up · trail projected on x-y`;
    }
    function refreshAll(geoToo) {
      recompute();
      if (geoToo) { ramp.f = deRamp(); heat.restart(); drawGeo(); }
      S.k = Math.min(S.k, LAST);
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
    let bx = GX;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: BY, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, BY + 17, "Orbit", "ink"); bx += 48;
    btn("◀ Back", 74, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn("Step ▶", 74, () => { S.k = Math.min(LAST, S.k + 1); render(); });
    btn("+1 iteration", 100, () => { S.k = Math.min(LAST, S.k === 0 ? 3 : (Math.floor((S.k - 1) / 3) + 1) * 3 + 3); render(); });
    btn("All 32 ▶▶", 90, () => { S.k = LAST; render(); });
    btn("Reset", 66, () => { S.k = 0; render(); });
    bx += 20;
    const jb = btn("Julia", 70, b => { S.P = params(Object.assign({}, S.P, { julia: !S.P.julia })); b.set(S.P.julia); refreshAll(true); });
    const cb = btn("Sample cloud", 112, b => { S.cloud = !S.cloud; b.set(S.cloud); render(); });
    btn("Fixture point (1.2, −0.3, 0.8)", 214, () => {
      S.P = params(); jb.set(false); S.p = [1.2, -0.3, 0.8]; S.k = LAST;
      for (const [k, h] of sliders) h.set(k === "h" ? 0.8 : S.P[k]);
      refreshAll(true);
    });
    const sliders = [];
    const SL = [["Slice (Scale)", "scale", -5, -0.5, 0.01], ["Inner Radius", "inner", 0, 1, 0.01], ["Fold", "fold", 0, 1, 0.01],
      ["Outer Radius", "outer", 0, 1, 0.01], ["plane height z", "h", -2.5, 2.5, 0.05]];
    SL.forEach(([label, key, min, max, step], i) => {
      const h = api.slider({ x: GX + i * 300, y: BY + 74, w: 260, label, min, max, step, value: key === "h" ? S.p[2] : S.P[key], fmt: v => fmt(v, 2),
        onChange: v => {
          if (key === "h") S.p = [S.p[0], S.p[1], v];
          else S.P = params(Object.assign({}, S.P, { [key]: v }));
          refreshAll(true);
        } });
      sliders.push([key, h]);
    });
    api.text(GX, BY + 124, "Legend: orange box = ±fold · pink dashed / solid circles = the inner and outer spheres (their equators on this plane) · grey dotted square = the march's cube (box_half) · trail colours = the stage that moved z.", "muted", { style: small });
    api.text(GX, BY + 142, "The trail and the cloud are drawn in x-y; z's third component is in the readout. Hover any dot for its numbers. Sample cloud: 121 starting points moved by the same number of stages, coloured by the side they started on.", "muted", { style: small });
    api.link(GX, BY + 164, RL("de", 7, "why the GDScript copy runs scalar 64-bit floats"));
    refreshAll(true);
  },
};

// ================================================================== 4. what each dial does
const PRESETS = [
  { name: "default.json", ...R("saveDef", 4), o: { scale: -2.09, inner: 0.7, fold: 1.0, outer: 1.0, precision: 0.000025, julia: false } },
  { name: "juliaIceField.json", ...R("saveField", 4), o: { scale: -2.29, inner: 0.0, fold: 0.72, outer: 0.29, precision: 0.00002, julia: true } },
  { name: "juliaIceTerraces.json", ...R("saveTer", 4), o: { scale: -1.88, inner: 0.49, fold: 0.81, outer: 0.53, precision: 0.0001, julia: true } },
];
const EYE_DIST = Math.hypot(...DEFAULT_EYE);
const dialsFig = {
  type: "figure",
  tab: "What each dial does",
  title: "What each dial does",
  note: "The distance estimate de(p, 32) on a plane through the shape, 160 × 160 cells, shaded by log10(d): blue at the surface, fading with distance. Cells whose d is under the hit threshold are drawn in ink: that is the surface the march would stop on. The threshold is precision × 9.62 (what the phase-2 stop test `d < hit_eps(total)` uses, at the default detail 1 and falloff 0, for a ray that has travelled the default eye's distance), so Precision moves the ink edge a hair and never the shape. The figure recomputes a few rows per frame after each change. Presets load the values in saves/.",
  w: 1500, h: 780,
  draw(api) {
    const N = 160, GX = 20, GY = 50, VS = 640;
    const S = { P: params(), axes: "xy", off: 0, range: 2.4 };
    const dvals = new Float64Array(N * N);
    const th = () => S.P.precision * EYE_DIST;
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
      api.tip(r, { title: "de(p, 32) on this patch", ...SH(48), live() {
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
    api.text(RX, y, "FractalParams → uniforms", "ink", { style: caps });
    y += 34;
    const capt = (txt, yy, ref) => {
      api.text(RX + SW + 24, yy + 2, txt[0], "", { style: small });
      if (txt[1]) api.text(RX + SW + 24, yy + 17, txt[1], "", { style: small });
      if (ref) api.link(RX + SW + 24, yy + 33, ref);
    };
    const shapeSliders = {};
    const SL = [
      ["Slice (Scale)", "scale", -5, -0.5, 0.01, ["Stretches every fold by |scale| and flips it through the origin:", "smaller |scale| packs more, finer copies into the box."], RL("view", 257, "uniform scale")],
      ["Inner Radius", "inner", 0, 1, 0.01, ["The sphere fold's dead zone: inside it z is scaled by a constant", "fixed_r2/min_r2. Pushed as min_r2 = inner²."], RL("view", 258, "uniform min_r2 = inner²")],
      ["Fold", "fold", 0, 1, 0.01, ["The box fold's half-size: components past ±fold reflect back.", "Smaller folds carve the walls into thinner plates."], RL("view", 260, "uniform fold_limit")],
      ["Outer Radius", "outer", 0, 1, 0.01, ["The inversion radius: inside it z is inverted through", "the sphere (k = fixed_r2/r2). Pushed as fixed_r2 = outer²."], RL("view", 259, "uniform fixed_r2 = outer²")],
    ];
    for (const [label, key, min, max, step, txt, ref] of SL) {
      shapeSliders[key] = api.slider({ x: RX, y, w: SW, label, min, max, step, value: S.P[key], fmt: v => fmt(v, 2),
        onChange: v => { S.P = params(Object.assign({}, S.P, { [key]: v })); recompute(); } });
      capt(txt, y - 6, ref);
      y += 64;
    }
    const precS = api.slider({ x: RX, y, w: SW, label: "Precision (log10)", min: -6, max: -3, step: 0.01, value: Math.log10(S.P.precision),
      fmt: v => sci(Math.pow(10, v), 2), onChange: v => { S.P = params(Object.assign({}, S.P, { precision: +Math.pow(10, v).toPrecision(3) })); recolour(); } });
    capt(["Not a shape parameter: only the hit threshold moves (ink edge).", "A smaller value marches closer and takes more steps."], y - 6, RL("sh", 176, "the stop test"));
    y += 70;
    api.text(RX, y + 12, "Julia", "ink", { style: caps });
    const jb = api.button({ x: RX + 60, y, w: 90, label: "Julia mode", on: false, onClick: b => { S.P = params(Object.assign({}, S.P, { julia: !S.P.julia })); b.set(S.P.julia); recompute(); } });
    api.text(RX + 166, y + 12, "c = julia_point instead of p, and the march's cube grows to ±20", "", { style: small });
    api.link(RX + 166, y + 28, RL("sh", 49, "c = julia_enabled ? julia_point : p"));
    y += 66;
    const jS = [0, 1, 2].map(a => api.slider({ x: RX + a * 200, y, w: 170, label: `Julia ${"XYZ"[a]}`, min: -3, max: 3, step: 0.01, value: S.P.jp[a], fmt: v => fmt(v, 3),
      onChange: v => { const jp = S.P.jp.slice(); jp[a] = v; S.P = params(Object.assign({}, S.P, { jp })); if (S.P.julia) recompute(); } }));
    y += 56;
    api.text(RX, y + 12, "Presets", "ink", { style: caps });
    PRESETS.forEach((pr, i) => {
      api.button({ x: RX + 80 + i * 186, y, w: 178, label: pr.name, onClick: () => {
        S.P = params(Object.assign({ jp: JULIA_POINT.slice() }, pr.o));
        for (const k of ["scale", "inner", "fold", "outer"]) shapeSliders[k].set(S.P[k]);
        precS.set(Math.log10(S.P.precision)); jb.set(S.P.julia); jS.forEach((s, a) => s.set(S.P.jp[a]));
        recompute();
      } });
    });
    y += 40;
    PRESETS.forEach((pr, i) => api.link(RX + 80 + i * 186, y, { file: pr.file, line: pr.line, label: `${pr.name.replace(".json", "")}:${pr.line}` }));

    function recolour() { col.ramp = deRamp(); col.ink = cssRGB("--ink"); heat.restart(() => { status.textContent = `done · threshold ${sci(th())}`; }); status.textContent = "computing…"; }
    function recompute() {
      const [a, b, c] = AXES[S.axes];
      axisText.textContent = `${a} right, ${b} up, ${c} = ${fmt(S.off, 2)} · ±${fmt(S.range, 1)} · ${S.P.julia ? `Julia (${S.P.jp.map(v => fmt(v, 3)).join(", ")})` : "Mandelbox"}`;
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
  note: "The ray march from fragment(), ported. The plane is the vertical slice through the default eye and the world Z axis (u along the eye's heading, w = z), so the default centre ray lies in it. Drag the eye (ink) and the aim point (green). Step walks the march: clip to the cube, phase 1 with de(p, 16) for up to coarse_steps, phase 2 with de(p, 32) for up to fine_steps, then ce = (n1 + n2)/128. Each step draws its unbounding circle of radius d (the sphere-tracing picture: no surface is closer than d, so the ray hops d) and the hop. Near the surface the hops shrink geometrically: zoom in to see them. Both phases stop on hit_eps(total): the pixel cone precision / detail · total, coarsened by (total / start)^falloff past start = detail_range · near_dist, where near_dist = de(eye, 32) is the eye's distance to the nearest surface (the solid ring round the eye; the dashed ring is start). The defaults (falloff 0, 128 steps) are the plain cone and 96 + 32 steps. A ray that runs out of steps without meeting the threshold is NOT a miss; it is shaded with ce = 1 (the dust around the fractal). The only miss is leaving the cube.",
  w: 1560, h: 910,
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
        tip: { ...SH(149), blurb: "The ray is clipped to the cube of half-size box_half (2, or 20 in Julia mode). Missing it outputs the background; otherwise the march starts at the entry (or at the eye, inside the cube). `total` is measured from the eye, not from the entry, so precision behaves as on the site.", links: [RL("sh", 125, "box_intersect"), RL("sh", 154, "total = max(tb.x, 0)"), RL("spec", 239, "spec: bounds")] } },
      { n: "1", name: "Phase 1 · de(p, 16)", f: "≤ coarse_steps · stop d < hit_eps(total)·2", color: C1,
        tip: { ...SH(159), blurb: "Cheap 16-iteration estimates, up to coarse_steps (¾ of max_steps: 96 by default), with a threshold twice as loose. n1 = the step index of the stop, or coarse_steps if it never stopped. Crossing t_exit is a miss. The loop is bounded at 384 so `coarse_steps` can be a uniform.", links: [RL("sh", 162, "de(pos, 16)"), RL("sh", 163, "the stop test"), RL("sh", 38, "hit_eps"), RL("sh", 165, "left the cube"), RL("params", 84, "coarse_steps()")] } },
      { n: "2", name: "Phase 2 · de(p, 32)", f: "≤ fine_steps · stop d < hit_eps(total)", color: C2,
        tip: { ...SH(172), blurb: "Runs even when phase 1 stopped: it refines the hit with the full 32-iteration estimate and the tight threshold, continuing from the same point. n2 = the stop index or fine_steps (max_steps − coarse_steps: 32 by default).", links: [RL("sh", 175, "de(pos, 32)"), RL("sh", 176, "the stop test"), RL("params", 88, "fine_steps()"), RL("spec", 247, "spec: march")] } },
      { n: "ce", name: "Step count → shade", f: "ce = min((n1 + n2) / 128, 1)", color: CHIT,
        tip: { ...SH(187), blurb: "ce is the share of the original 128-step budget used, whatever max_steps is, so a ray that hits looks the same under any budget; a ray that ran out of phase 2 is ce = 1. Every colour mode is built on it (inv = 1 − ce): rays that needed many steps (grazing, in crevices, or never converging) are darker. Leaving the cube is the only miss.", links: [RL("sh", 182, "left_cube → background"), RL("spec", 256, "spec: the dust")] } },
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
    const MAXS = 512, rings = [], hops = [], dots = [];     // MAX_STEPS_MAX (fractal_params.gd:59)
    for (let k = 0; k < MAXS; k++) {
      rings.push(api.el("circle", { style: `fill:none;stroke-width:1.2;${noPtr}` }, poolG));
      hops.push(api.el("line", { style: `stroke-width:2;${noPtr}` }, poolG));
    }
    const stepTip = k => ({ title: `step ${k + 1}`, ...SH(161), live() {
      const st = steps[k]; if (!st) return {};
      return { sub: `phase ${st.phase}, i = ${st.i}`, title: `step ${k + 1}: phase ${st.phase}, i = ${st.i}`,
        blurb: `total = ${sci(st.total, 6)}\nd = de(p, ${st.phase === 1 ? 16 : 32}) = ${sci(st.d)}\nthreshold = hit_eps(total)${st.phase === 1 ? " · 2" : ""} = ${sci(st.th)}${S.P.falloff > 0 && st.total > M.lodStart ? ` (past start ${sci(M.lodStart)}: × (total / start)^${fmt(S.P.falloff, 2)} = ×${sci(Math.pow(st.total / M.lodStart, S.P.falloff), 2)})` : ""}\n${st.stop ? "d < threshold: the phase stops here" : `d ≥ threshold: hop d to total = ${sci(st.total + st.d, 6)}`}\np = ${vec(st.p)}` };
    } });
    for (let k = 0; k < MAXS; k++) {
      const d = api.el("circle", { r: 3.2, style: "cursor:pointer" }, poolG);
      dots.push(d);
      api.tip(d, stepTip(k));
    }
    // eye and aim handles
    const eyeH = api.el("circle", { r: 8, style: "fill:var(--ink);stroke:var(--surface);stroke-width:2;cursor:move" });
    const aimH = api.el("circle", { r: 7, style: `fill:${CHIT};stroke:var(--surface);stroke-width:2;cursor:move` });
    api.tip(eyeH, { title: "the eye", ...R("cam", 6), blurb: "Drag to move it. Starts at DEFAULT_EYE, which lies in this plane." });
    api.tip(aimH, { title: "the aim point", ...SH(143), blurb: "The ray points from the eye through here (dir = normalize(aim − eye)). Starts at the origin: the default view's centre ray." });
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
      if (S.zoom <= 1.0001) { view.cu = 3.75; view.cw = 0.6; view.hw = 6.75 * (S.P.julia ? 3.4 : 1); }
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
      if (S.P.falloff > 0) api.el("circle", { cx: px(es[0]), cy: py(es[1]), r: Math.min(M.lodStart * sc, 8000), style: `fill:none;stroke:${api.hue(5)};stroke-width:1.6;stroke-dasharray:7 5` }, dyn);
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
        : M.left ? "left the cube: background (the only miss)"
        : M.n2 === S.P.fine ? (M.n1 === S.P.coarse ? "ran out of steps in both phases: shaded as ce = 1 (dust)" : "phase 2 ran out of steps: shaded as ce = 1")
        : "hit: phase 2 met the threshold";
      outHead.textContent = s === 0 ? "box intersect" : s > n ? "result" : `step ${s} of ${n} · phase ${cur.phase}, i = ${cur.i}`;
      const lines = [
        `eye ${vec(M.eye3, 3)}   dir ${vec(M.dir, 3)}`,
        `box_half ${S.P.boxHalf}: t_enter ${sci(M.tEnter)}, t_exit ${sci(M.tExit)}${M.miss ? "  → miss" : `, start total = ${sci(M.start)}`}`,
        cur && s <= n ? `total ${sci(cur.total, 6)}   d ${sci(cur.d)}   threshold ${sci(cur.th)}` : "",
        cur && s <= n ? (cur.stop ? `d < threshold: phase ${cur.phase} stops (n${cur.phase} = ${cur.i})` : `hop d → total ${sci(cur.total + cur.d, 6)}`) : "",
        `n1 = ${M.miss ? "–" : M.n1}${M.n1 === S.P.coarse ? " (never stopped)" : ""}    n2 = ${M.miss || (M.left && M.n2 === S.P.fine && M.n1 === S.P.coarse) ? "–" : M.n2}${M.n2 === S.P.fine && !M.left ? " (never stopped)" : ""}    budget ${S.P.coarse} + ${S.P.fine}`,
        M.miss || M.left ? "ce: not used, the pixel is background" : M.n2 === S.P.fine ? `ce = 1 (phase 2 ran out)   inv = 0` : `ce = min((${M.n1} + ${M.n2}) / 128, 1) = ${fmt(M.ce, 4)}   inv = 1 − ce = ${fmt(1 - M.ce, 4)}`,
        `outcome: ${outcome}`,
        M.miss || M.left ? "" : `hit point v = ${vec(add(M.eye3, M.dir, M.total), 4)}, total ${sci(M.total, 6)}`,
        `${n} de() calls on this ray (the shader's cost per pixel, before the normal)`,
        `near_dist ${sci(M.near)} · ${S.P.falloff > 0 ? `full detail to start = ${fmt(S.P.range, 1)} · near = ${sci(M.lodStart)}, then ^${fmt(S.P.falloff, 2)}` : "falloff 0: the plain cone everywhere"}`,
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
    const jb = btn("Julia (box ±20)", 128, b => { S.P = params(Object.assign({}, S.P, { julia: !S.P.julia })); b.set(S.P.julia); remarch(); render(true); });
    const fb = btn("Zoom follows the step", 166, b => { S.follow = !S.follow; b.set(S.follow); render(); }, true);
    // Every slider rebuilds P from the current one, so the others keep their values.
    const setP = o => { S.P = params(Object.assign({}, S.P, o)); remarch(); };
    api.slider({ x: GX, y: BY + 78, w: 380, label: "Precision (log10)", min: -7, max: -1, step: 0.01, value: Math.log10(S.P.precision),
      fmt: v => sci(Math.pow(10, v), 2), onChange: v => setP({ precision: +Math.pow(10, v).toPrecision(3) }) });
    api.slider({ x: GX + 440, y: BY + 78, w: 440, label: "zoom (log10)", min: 0, max: 5, step: 0.01, value: 0,
      fmt: v => `×${sci(Math.pow(10, v), 2)}`, onChange: v => { S.zoom = Math.pow(10, v); render(); } });
    api.slider({ x: GX + 940, y: BY + 78, w: 380, label: "max_steps (coarse + fine)", min: 32, max: 512, step: 16, value: S.P.maxSteps,
      fmt: v => { const c = Math.floor(v * 3 / 4); return `${v} = ${c} + ${v - c}`; }, onChange: v => setP({ maxSteps: v }) });
    api.text(GX, BY + 112, "Renderer tab — level of detail", "ink", { style: caps });
    api.slider({ x: GX, y: BY + 148, w: 380, label: "detail (log10)", min: -1, max: 1, step: 0.01, value: 0,
      fmt: v => `×${fmt(Math.pow(10, v), 2)}`, onChange: v => setP({ detail: +Math.pow(10, v).toPrecision(3) }) });
    api.slider({ x: GX + 440, y: BY + 148, w: 440, label: "detail_range (× near_dist, log10)", min: 0, max: 3, step: 0.01, value: 1,
      fmt: v => `${fmt(Math.pow(10, v), 1)}×`, onChange: v => setP({ range: +Math.pow(10, v).toPrecision(4) }) });
    api.slider({ x: GX + 940, y: BY + 148, w: 380, label: "detail_falloff", min: 0, max: 3, step: 0.05, value: 0,
      fmt: v => (v === 0 ? "0 (off)" : fmt(v, 2)), onChange: v => setP({ falloff: v }) });
    api.text(GX, BY + 186, "Try: Step through the default centre ray (n1 = 36, n2 = 3); zoom ×1000 with ‘follow’ to watch the last hops; raise precision to 1e−2 and the hit comes early; aim along a crevice and phase 1 can use all 96 steps (dust).", "muted", { style: small });
    api.text(GX, BY + 203, "Falloff does nothing from the default eye (start = 10 · near_dist ≈ 66 is past the cube): drag the eye near the surface, set falloff 2, and the dashed ring shows where the threshold starts to grow.", "muted", { style: small });
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
// Dropdown order and names: fractal_params.gd:10-14. Formula text: the renderer spec's table (289-303).
const MODES = [
  { id: 0, name: "Grayscale", normal: "none", f: "vec3(1 − ce)", line: 190 },
  { id: 1, name: "Ice Fractal", normal: "NF outside Julia, N in Julia", f: "base · ((1−ce)+0.5, 2(1−ce)²+0.5, 5(1−ce)⁴+0.5)", line: 211 },
  { id: 2, name: "Borg", normal: "NF outside Julia, N in Julia", f: "base · (max(lgt·ce, 1−ce), max(ce, 1−ce), max(0.5·lgt·ce, 1−ce))", line: 213 },
  { id: 3, name: "Rainbow", normal: "NF outside Julia, N in Julia", f: "hue(q)·ce + 0.5·lgt,  q = dot(h, h)/4", line: 215 },
  { id: 4, name: "Rainbow 2", normal: "NF outside Julia, N in Julia", f: "hue(q)·(1 − ce),  q = dot(h, h)/4", line: 218 },
  { id: 8, name: "Rainbow 3", normal: "NF outside Julia, N in Julia", f: "hue(q)·(1 − ce),  q = n.z·0.5 + 0.5 − 0.1", line: 221 },
  { id: 15, name: "Rainbow Metal", normal: "N, in view space", f: "lv = max(0, nv.z)⁴; n2 = normalize(nv + (0.5, 0.5, 0)); (n2 + 1)·0.5·(lv − 2·ce + 0.5)", line: 237 },
  { id: 5, name: "Blue", normal: "NF outside Julia, N in Julia", f: "base · (lgt·max(lgt·ce, 1−ce), lgt + avg, 1 − ce + lgt),  avg = mean(base)", line: 224 },
  { id: 6, name: "Blue 2", normal: "NF outside Julia, N in Julia", f: "the Blue result + ce²", line: 227 },
  { id: 7, name: "Pink-Blue", normal: "NF outside Julia, N in Julia", f: "(1 − 2·ce·(lgt+0.5), avg·(1−ce), (1−ce)·(lgt+0.5))", line: 230 },
  { id: 16, name: "Ice Box", normal: "N", f: "clamp(((1−ce)², 1 − 1.9·ce², 1.17 − ce²), 0, 1)·(lgt + 0.5)", line: 235 },
  { id: 9, name: "Ice Box 2", normal: "NF outside Julia, N in Julia", f: "((1−ce)², 1 − 1.9·ce², 1.17 − ce²)", line: 233 },
  { id: 14, name: "Gold", normal: "N, in view space", f: "lv = max(0, nv.z)⁴; (0.75 − ce)·2·(lv, lv², lv·ce)", line: 242 },
];
const to255 = c => c.map(v => Math.round(clamp(v, 0, 1) * 255));
const shadeFig = {
  type: "figure",
  title: "Shading and the colour modes",
  note: "Every mode is built from ce (the share of the 128-step budget the ray used, tab 5) and lgt, the light term. Left: one mode's output over ce (x, 0 → 1) and lgt before shaping (y, 0 → 1), with the normal fixed facing the light and h taken at the default centre ray's hit. Middle: the light curve lgt = 0.5·l + l¹⁶⁰ + 0.1 (a broad term plus a needle-sharp highlight). Right: Render draws the default view at 96 × 60 with the full port (march, normal, colour), on demand, to eyeball against screenshots/mode_<id>.png from tests/screenshots.sh. Values past 1 are clamped for display, as the GPU does.",
  w: 1520, h: 590,
  draw(api) {
    const S = { mode: 1 };
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
    api.text(SX - 26, SY + SS / 2, "lgt before shaping", "muted", { "text-anchor": "middle", transform: `rotate(-90 ${SX - 26} ${SY + SS / 2})`, style: small });
    for (let j = 0; j < 12; j++) for (let i = 0; i < 12; i++) {
      const r = api.el("rect", { x: SX + i * 32, y: SY + j * 32, width: 32, height: 32, style: "fill:transparent;cursor:crosshair" });
      api.tip(r, { title: "one swatch", ...SH(206), live() {
        const ce = (i + 0.5) / 12, l = 1 - (j + 0.5) / 12, c = shade(S.mode, ce, l, ldir0, h0, DEFAULT_CAM);
        const lg = 0.5 * l + Math.pow(l, 160) + 0.1;
        return { sub: MODES.find(m => m.id === S.mode).name, blurb: `ce = ${fmt(ce, 3)} (inv ${fmt(1 - ce, 3)})\nlgt before shaping = ${fmt(l, 3)} → after = ${fmt(lg, 3)}\nrgb = ${vec(c, 3)}${c.some(v => v > 1 || v < 0) ? " (clamped on screen)" : ""}` };
      } });
    }
    // ---- light curve
    const LX = 480, LY = 120, LW = 330, LH = 250, lx = l => LX + l * LW, lyv = v => LY + LH - v / 1.7 * LH;
    api.text(LX, LY - 12, "lgt = 0.5·l + l¹⁶⁰ + 0.1", "ink", { style: caps });
    api.el("rect", { x: LX, y: LY, width: LW, height: LH, style: "fill:var(--surface);stroke:var(--hairline)" });
    for (const v of [0.1, 0.5, 1, 1.5]) {
      api.el("line", { x1: LX, y1: lyv(v), x2: LX + LW, y2: lyv(v), style: "stroke:var(--hairline)" });
      api.text(LX - 6, lyv(v) + 4, String(v), "muted", { "text-anchor": "end", style: "font-size:9.5px" });
    }
    const curve = [];
    for (let k = 0; k <= 200; k++) { const l = k / 200; curve.push(`${lx(l)},${lyv(0.5 * l + Math.pow(l, 160) + 0.1)}`); }
    api.el("polyline", { points: curve.join(" "), style: `fill:none;stroke:${api.hue(4)};stroke-width:2.2` });
    api.text(LX, LY + LH + 18, "l = |dot(n, ldir)|  0 → 1", "muted", { style: small });
    const cHit = api.el("rect", { x: LX, y: LY, width: LW, height: LH, style: "fill:transparent;cursor:pointer" });
    api.tip(cHit, { title: "the light term", ...SH(207), blurb: "`lgt = abs(dot(n, ldir))` with `ldir = normalize(2·eh − h)` (a light at the eye, in the site's half-scale coordinates), then `0.5·lgt + pow(lgt, 160) + 0.1`. The 160th power is a highlight that only fires within a few degrees of facing the light; 0.1 keeps faces turned away from going black. `base = lgt·(−n·0.25 + 0.75) + (0, 0, 0.2)` tints by the normal and adds blue.",
      links: [RL("sh", 205, "ldir"), RL("sh", 208, "base"), RL("spec", 283, "spec: lighting")] });
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
      api.tip(r, { title: "a rendered pixel", ...SH(140), live() {
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
      job.P = params({ mode: S.mode });
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

    function sync() {
      MODES.forEach((m, i) => mbtns[i].set(m.id === S.mode));
      const m = MODES.find(x => x.id === S.mode);
      info1.textContent = `mode ${m.id} · ${m.name} · normal: ${m.normal} · background ${m.id === 5 || m.id === 6 ? "white" : "black"}`;
      info2.textContent = `col = ${m.f}`;
      const img = sw.ctx.createImageData(SN, SN);
      for (let j = 0; j < SN; j++) for (let i = 0; i < SN; i++) {
        const c = to255(shade(S.mode, (i + 0.5) / SN, 1 - (j + 0.5) / SN, ldir0, h0, DEFAULT_CAM)), o = (j * SN + i) * 4;
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
  title: "The thirteen modes",
  note: "In the panel's dropdown order (ids match the site, so a saved number means the same thing). NF is the Ice Fractal normal, N the true one (next tab). inv = 1 − ce. Hover a row for its shader line.",
  columns: [{ label: "id", w: 44, mono: true }, { label: "panel name", w: 120 }, { label: "normal", w: 250 }, { label: "colour", w: 700, mono: true }, { label: "background", w: 110 }],
  rows: MODES.map(m => ({
    cells: [String(m.id), m.name, m.normal, m.f, m.id === 5 || m.id === 6 ? "white" : "black"],
    tip: { title: `${m.id} · ${m.name}`, ...SH(m.line),
      blurb: m.id === 0 ? "Needs no normal, so the shader skips the normal and light work entirely for it (the cheapest mode)."
        : m.normal.startsWith("NF") ? "Uses NF outside Julia mode, N inside it (the branch at line 199)."
        : m.id === 16 ? "Always N, even outside Julia mode. Clamped before the light so it never blows out."
        : "Always N, turned into view space: nv = (dot(N, right), dot(N, up), dot(N, −forward)), so nv.z > 0 faces the camera.",
      links: [RL("params", 10, "COLOR_MODE_IDS"), RL("sh", m.id === 5 || m.id === 6 ? 122 : 169, m.id === 5 || m.id === 6 ? "white background" : "normal choice"), RL("spec", 289, "spec: colour table")] },
  })),
};

// ================================================================== 7. the two normals
const normalsFig = {
  type: "figure",
  tab: "The two normals",
  title: "The two normals: N and the Ice Fractal NF",
  note: "Why modes 1 to 9 look the way they do outside Julia mode. N is the true normal: central differences of de(·, 32) with delta = hit_eps(total) · 40 (precision · total · 40 at the default falloff 0). NF is the gradient of a different field, F(q) = |z16| − 8 (a 16-iteration orbit from z = 0 with c = q, no derivative), and not even that: its base sample is taken at the HALF-scale point h = v/2 while the three offset samples are at the full-scale v + 0.01. To first order NF = normalize(∇F(v) + (F(v) − F(h))/0.01 · (1, 1, 1)): the gradient of a different field, tilted toward the (1, 1, 1) diagonal by the half-scale mismatch. On the default view the two normals differ by tens of degrees, and that difference is the Ice Fractal look. The renderer spec says to replicate it exactly, and the shader does. Rays fan from the default eye, in the same vertical slice as the march tab, across the cube face it sees; at each hit, N (blue) and NF (orange) are drawn projected onto the plane (a shorter arrow points more out of the plane).",
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
      api.tip(d, { title: "a surface sample", ...SH(199), live() {
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
      ["calc_normal: central differences of de(·, 32)", SH(91)],
      ["calc_nf: lw = F(h), offsets at v + 0.01, ÷ 0.01", SH(101)],
      ["delta = hit_eps(total) · 40", SH(195)],
      ["the spec: replicate exactly, not a true gradient", R("spec", 268)],
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
  note: "Left: flying along the default centre ray toward the surface it hits. The fly speed is the CPU estimate at the eye, clamped to [1e−6, 20], times speed_factor, so speed tracks the remaining gap (grey) and you slow down as you arrive, never overshooting at factor 1. The dots are where a held W puts you after each whole second (60 Hz physics ticks, the port of _physics_process). The wheel slider is the speed factor in wheel ticks (×1.25 each). Right: mouse-look from the default view: yaw turns about world +Z, pitch is clamped 1° off ±Z, and the basis is rebuilt with +Z as the up hint, so roll is always 0.",
  w: 1400, h: 620,
  draw(api) {
    const P = params(), cam = DEFAULT_CAM;
    const hit = march(cam.eye, cam.fwd, P), T = hit.total;
    const S = { ticks: 0, factor: 1, dx: 0, dy: 0, sens: 0.1 };
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
      api.tip(c, { title: `after ${s + 1} s of W`, ...R("fly", 47), live() {
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
    api.link(X0 + 430, Y0 + H + 132, RL("fly", 88, "scroll(): ×1.25, clamp 0.01 … 100"));
    function drawSpeed() {
      const pts = [];
      for (let k = 0; k <= 400; k++) {
        const t = T * k / 400 * 0.99999;
        pts.push(`${xs(t)},${ys(flySpeed(add(cam.eye, cam.fwd, t), P, S.factor))}`);
      }
      curve.setAttribute("points", pts.join(" "));
      // hold W: 60 Hz physics ticks, origin += forward · current_speed · delta
      let x = 0, over = false;
      for (let s = 0; s < 10; s++) {
        for (let n = 0; n < 60; n++) x += flySpeed(add(cam.eye, cam.fwd, x), P, S.factor) / 60;
        if (x > T) over = true;
        const p = add(cam.eye, cam.fwd, x), d = secDots[s];
        d.x = x; d.D = de(p[0], p[1], p[2], 32, P); d.v = flySpeed(p, P, S.factor);
        const xx = xs(Math.min(x, T)), yy = ys(d.v);
        d.c.setAttribute("cx", xx); d.c.setAttribute("cy", yy);
        d.t.setAttribute("x", xx); d.t.setAttribute("y", yy - 9);
        d.c.style.display = d.t.style.display = s < 6 || s === 9 ? "" : "none";
      }
      const d1 = secDots[0];
      read1.textContent = `speed at the eye = clamp(D(eye) = ${fmt(de(...cam.eye, 32, P), 4)}, 1e−6, 20) × ${sci(S.factor, 3)} = ${sci(flySpeed(cam.eye, P, S.factor), 4)} units/s`;
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
    api.link(CX - RR + 230, SY_ + 62, RL("fly", 55, "apply_look"));
    api.link(CX - RR + 230, SY_ + 80, RL("fly", 8, "MAX_FORWARD_Z = sin 89°"));
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
      tip: { ...R("fly", 55), links: [RL("fly", 59, "the clamp"), RL("tFly", 79, "saturation test")] } },
    { cells: ["fly", "W A S D · Space Shift", "dir · clamp(D(eye), 1e−6, 20) · factor · delta", "Camera-axis direction, normalised (a diagonal is not faster); nothing while Cmd or Ctrl is held."],
      tip: { ...R("fly", 70), links: [RL("fly", 83, "current_speed"), RL("tFly", 29, "normalised test")] } },
    { cells: ["fly", "wheel", "×1.25 / ÷1.25, clamp 0.01 … 100", "Scales speed_factor; the panel shows `speed ×f`."], tip: { ...R("fly", 88), links: [RL("panel", 199, "the speed label")] } },
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
      tip: { ...R("orbit", 76), links: [RL("main", 205, "Main: only on a change"), RL("main", 171, "after a load")] } },
    { cells: ["marker", "drag the Julia ring (mouse free)", "press within 2 × RING_RADIUS = 20 px", "Captures depth = (julia_point − eye) · forward, then sets julia_point = unproject(mouse, depth): it slides in the plane facing the camera."],
      tip: { ...R("marker", 37), links: [RL("marker", 41, "the 20 px test"), RL("marker", 52, "unproject"), RL("tMarker", 29, "reprojects to the cursor")] } },
    { cells: ["Main", "mouse capture", "FLY, not paused, noise closed", "Captured, otherwise visible; a click on the view while free in FLY recaptures (and is the user gesture pointer lock needs on the web). The console window no longer gates capture."],
      tip: { ...R("main", 211), links: [RL("main", 269, "click to capture")] } },
  ],
};

for (const r of camTable.rows) r.tip.title = `${r.cells[0]} · ${r.cells[1]}`;

// ================================================================== 9. resolution governor
const govFig = {
  type: "figure",
  tab: "Resolution governor",
  title: "Resolution governor, frame by frame",
  note: "The ported ResolutionGovernor.step(frame_time, changing), fed by you. Each Step is one frame: the frame-time slider is how long that frame took and ‘changing’ is whether CameraState or FractalParams emitted `changed` during it. While changing it renders continuously and keeps an EMA of frame time (α 0.2) against a 1/30 s target: above 1.2× it multiplies the scale by 0.8, below 0.6× it divides by 0.8, clamped to min_scale … 1, at most once per 0.5 s cooldown. min_scale follows the view's min_render_scale (0.25 by default, 0.1 … 1 from Settings ▸ Renderer); raising it lifts the scale on the next frame. The first still frame renders once at full scale, then it goes IDLE and nothing renders. Fast Controls off pins the scale at 1.",
  w: 1440, h: 800,
  draw(api) {
    const G = newGovernor();     // min_scale: resolution_governor.gd:16
    const S = { ms: 60, changing: true, run: false };
    let hist = [];
    const MC = [api.hue(2), api.hue(3), api.hue(1)];
    // ---- the state graph
    const NY = 40, NW = 210, NH = 52, NX = [60, 520, 980];
    const nodeR = [], desc = [
      ["CONTINUOUS", "UPDATE_ALWAYS · scale adapts", R("gov", 51)],
      ["FINAL_FRAME", "UPDATE_ONCE at scale 1", R("gov", 53)],
      ["IDLE", "UPDATE_DISABLED · nothing renders", R("gov", 56)],
    ];
    desc.forEach(([name, sub, ref], i) => {
      const r = api.el("rect", { x: NX[i], y: NY, width: NW, height: NH, rx: 10, style: `fill:var(--surface);stroke:${MC[i]};stroke-width:1.5;cursor:pointer` });
      nodeR.push(r);
      api.text(NX[i] + 14, NY + 22, name, "ink", { style: `font-weight:700;${noPtr}` });
      api.text(NX[i] + 14, NY + 40, sub, "muted", { style: `${small};${noPtr}` });
      api.tip(r, { title: name, sub: "ResolutionGovernor.Mode", ...ref, blurb: ["Rendering every frame (`set_continuous(true)`) while anything changes, at the governor's current scale.", "One frame at full scale after the motion stops: `set_continuous(false)` then `request_frame()`.", "Updates disabled: the TextureRect keeps the last image, zero GPU cost until something changes."][i], links: [RL("gov", 7, "enum Mode")] });
    });
    const edge = (d, label, lx, ly, ref, blurb, anchor) => {
      api.el("path", { d, style: "fill:none;stroke:var(--edge);stroke-width:1.6", "marker-end": "url(#viz-arrow)" });
      const hit = api.el("path", { d, style: "fill:none;stroke:transparent;stroke-width:14;cursor:pointer" });
      api.tip(hit, { title: label, ...ref, blurb });
      api.text(lx, ly, label, "", { "text-anchor": anchor || "middle", style: `${small};${noPtr}` });
    };
    const mid = NY + NH / 2;
    edge(`M ${NX[0] + NW} ${mid - 8} L ${NX[1] - 4} ${mid - 8}`, "changing = false (first still frame)", (NX[0] + NW + NX[1]) / 2, mid - 16, R("gov", 79), "`_idle_pending` was set while changing: the first still frame goes FINAL_FRAME, sets scale = 1 and clears the flag.");
    edge(`M ${NX[1] + NW} ${mid - 8} L ${NX[2] - 4} ${mid - 8}`, "changing = false again", (NX[1] + NW + NX[2]) / 2, mid - 16, R("gov", 84), "Nothing pending: IDLE, every frame, until something changes.");
    edge(`M ${NX[1] + 40} ${NY + NH} C ${NX[1] + 20} ${NY + NH + 50}, ${NX[0] + NW - 20} ${NY + NH + 50}, ${NX[0] + NW - 40} ${NY + NH + 4}`, "changing", (NX[0] + NW + NX[1]) / 2, NY + NH + 52, R("gov", 65), "Any frame with `changing` goes (back) to CONTINUOUS and sets `_idle_pending`.");
    edge(`M ${NX[2] + 40} ${NY + NH} C ${NX[2] + 10} ${NY + NH + 96}, ${NX[0] + 120} ${NY + NH + 96}, ${NX[0] + 100} ${NY + NH + 4}`, "changing", (NX[0] + NX[2]) / 2 + 120, NY + NH + 84, R("gov", 65), "From IDLE too: the next change restarts continuous rendering.");
    // ---- controls
    const BY = 230;
    api.slider({ x: 60, y: BY + 10, w: 300, label: "this frame's time (ms)", min: 1, max: 150, step: 1, value: S.ms, fmt: v => `${v} ms`, onChange: v => { S.ms = v; } });
    let bx = 420;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: BY, w, label, on, onClick }); bx += w + 8; return b; };
    const chB = btn("changing", 96, b => { S.changing = !S.changing; b.set(S.changing); }, true);
    const fcB = btn("Fast Controls", 116, b => { G.fast = !G.fast; b.set(G.fast); }, true);
    bx += 16;
    btn("Step ▶", 76, () => stepOnce());
    const runB = btn("Run", 64, b => { S.run = !S.run; b.set(S.run); });
    btn("Reset", 66, () => { Object.assign(G, newGovernor(), { fast: G.fast, minScale: G.minScale }); hist = []; S.run = false; runB.set(false); render(); });
    void chB; void fcB;
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
      { name: "EMA (ms)", y: 522, h: 130 },
      { name: "cooldown", y: 672, h: 70 },
    ];
    for (const ln of lanes) {
      api.el("rect", { x: CX, y: ln.y, width: CW, height: ln.h, style: "fill:var(--surface);stroke:var(--hairline)" });
      api.text(CX - 8, ln.y + 14, ln.name, "ink", { "text-anchor": "end", style: `${small};font-weight:600` });
    }
    const [lS, lM, lE, lC] = lanes;
    const yS = v => lS.y + lS.h - (v - 0.05) / 1.0 * lS.h;
    const EMAX = 80, yE = v => lE.y + lE.h - clamp(v / EMAX, 0, 1) * lE.h;
    const yC = v => lC.y + lC.h - clamp(v / 1.0, 0, 1) * lC.h;
    for (const v of [0.1, 0.25, 0.5, 1]) { api.el("line", { x1: CX, y1: yS(v), x2: CX + CW, y2: yS(v), style: "stroke:var(--hairline)" }); api.text(CX + CW + 6, yS(v) + 4, String(v), "muted", { style: "font-size:9.5px" }); }
    for (const [v, lab] of [[1000 / 30, "1/30 s"], [1.2 * 1000 / 30, "1.2×"], [0.6 * 1000 / 30, "0.6×"]]) {
      api.el("line", { x1: CX, y1: yE(v), x2: CX + CW, y2: yE(v), style: `stroke:${lab === "1/30 s" ? "var(--muted)" : "var(--hairline)"};stroke-dasharray:4 3` });
      api.text(CX + CW + 6, yE(v) + 4, lab, "muted", { style: "font-size:9.5px" });
    }
    api.el("line", { x1: CX, y1: yC(0.5), x2: CX + CW, y2: yC(0.5), style: "stroke:var(--muted);stroke-dasharray:4 3" });
    api.text(CX + CW + 6, yC(0.5) + 4, "0.5 s", "muted", { style: "font-size:9.5px" });
    const dyn = api.el("g", { style: noPtr });
    const cols = [];
    for (let k = 0; k < NF; k++) {
      const r = api.el("rect", { x: CX + k * COLW, y: lS.y, width: COLW, height: lC.y + lC.h - lS.y, style: "fill:transparent;cursor:pointer" });
      cols.push(r);
      api.tip(r, { title: "a frame", ...R("gov", 62), live() {
        const off = Math.max(0, hist.length - NF), h = hist[off + k];
        if (!h) return { title: "no frame yet", blurb: "Step or Run to feed the governor." };
        return { title: `frame ${off + k + 1}`, sub: `${fmt(h.ms, 0)} ms · changing ${h.changing} · Fast Controls ${h.fast}`,
          blurb: `mode ${MODE_NAMES[h.mode]}\nscale ${fmt(h.scale, 4)} (render ${Math.round(1280 * h.scale)} × ${Math.round(800 * h.scale)} of 1280 × 800)\nEMA ${fmt(h.ema * 1000, 2)} ms (target 33.33, lower above 40, raise below 20)\nsince last change ${fmt(h.since, 3)} s (cooldown 0.5)${h.why.length ? `\n${h.why.join(", ")}` : ""}` };
      } });
    }
    api.text(CX, lC.y + lC.h + 18, "oldest ← the last 120 frames → newest · hover a column for that frame's numbers", "muted", { style: small });
    api.link(CX + 600, lC.y + lC.h + 18, RL("tGov", 5, "the test that pins these rules"));

    function stepOnce() {
      const why = governorStep(G, S.ms / 1000, S.changing);
      hist.push({ ms: S.ms, changing: S.changing, fast: G.fast, mode: G.mode, scale: G.scale, ema: G.ema, since: G.since, why });
      render();
    }
    function render() {
      nodeR.forEach((r, i) => { r.style.strokeWidth = G.mode === i && hist.length ? 3.5 : 1.5; r.style.fill = G.mode === i && hist.length ? "var(--fig-bg)" : "var(--surface)"; });
      while (dyn.firstChild) dyn.removeChild(dyn.firstChild);
      const off = Math.max(0, hist.length - NF), shown = hist.slice(off);
      const line = (f, color) => api.el("polyline", { points: shown.map((h, k) => `${CX + (k + 0.5) * COLW},${f(h)}`).join(" "), style: `fill:none;stroke:${color};stroke-width:1.8` }, dyn);
      shown.forEach((h, k) => {
        api.el("rect", { x: CX + k * COLW + 0.5, y: lM.y + 2, width: COLW - 1, height: lM.h - 4, style: `fill:${MC[h.mode]};opacity:${h.mode === 2 ? 0.35 : 0.85}` }, dyn);
        if (h.why.includes("lowered") || h.why.includes("raised")) api.el("circle", { cx: CX + (k + 0.5) * COLW, cy: yS(h.scale), r: 3.5, style: `fill:${api.hue(5)}` }, dyn);
      });
      line(h => yS(h.scale), api.hue(1));
      line(h => yE(h.ema * 1000), api.hue(4));
      line(h => yE(h.ms), "var(--muted)");
      line(h => yC(Math.min(h.since, 1)), api.hue(3));
      const last = hist[hist.length - 1];
      ref1.textContent = `mode ${MODE_NAMES[G.mode]} · scale ${fmt(G.scale, 4)} (floor ${fmt(G.minScale, 2)}) · EMA ${fmt(G.ema * 1000, 2)} ms · since change ${fmt(G.since, 3)} s · idle_pending ${G.idlePending}`;
      ref2.textContent = last ? `frame ${hist.length}: ${last.changing ? "changing" : "still"}, ${last.ms} ms${last.why.length ? ` → ${last.why.join(", ")}` : ""}` : "no frames yet: the governor starts IDLE at scale 1, EMA = target, cooldown already elapsed";
    }
    let acc = 0;
    api.onFrame(dt => {
      if (!S.run) return;
      acc += dt;
      if (acc >= 1 / 30) { acc = 0; stepOnce(); }
    });
    api.text(CX + 300, lS.y - 8, "blue: scale · pink dot: a rescale", "", { style: small });
    api.text(CX + 300, lE.y - 6, "amber: the EMA · grey: this frame's time", "", { style: small });
    api.text(CX + 300, lC.y - 6, "green: time since the last scale change (capped at 1 s)", "", { style: small });
    render();
  },
};

// ================================================================== 10. dials, uniforms, saves and gotchas
const dialTable = {
  type: "table",
  title: "Panel row → FractalParams → uniform → what it changes",
  note: "FractalView._push_params writes every uniform on each FractalParams change; _push_camera writes the camera's four; both refresh near_dist. Neither the Q panel nor the Renderer tab touches the shader. Hover a row for the uniform's line and the widget's.",
  columns: [{ label: "panel row", w: 140 }, { label: "field · range · default", w: 280, mono: true }, { label: "uniform · transform", w: 340, mono: true }, { label: "what it changes", w: 470 }],
  rows: [
    { cells: ["Slice (Scale)", "scale · −5 … −0.5 · −2.09", "scale", "Each iteration's stretch and flip: the shape's overall structure (tab 4)."],
      tip: { title: "Slice (Scale)", ...R("view", 257), links: [RL("panel", 64, "the slider"), RL("params", 16, "the field")] } },
    { cells: ["Inner Radius", "inner_radius · 0 … 1 · 0.7", "min_r2 = inner_radius²", "The sphere fold's constant-scale zone (k = fixed_r2/min_r2 inside it)."],
      tip: { title: "Inner Radius", ...R("view", 258), links: [RL("panel", 65, "the slider"), RL("params", 18, "the field")] } },
    { cells: ["Fold", "fold_limit · 0 … 1 · 1.0", "fold_limit", "The box fold's half-size."],
      tip: { title: "Fold", ...R("view", 260), links: [RL("panel", 66, "the slider"), RL("params", 20, "the field")] } },
    { cells: ["Outer Radius", "outer_radius · 0 … 1 · 1.0", "fixed_r2 = outer_radius²", "The sphere fold's inversion radius."],
      tip: { title: "Outer Radius", ...R("view", 259), links: [RL("panel", 67, "the slider"), RL("params", 22, "the field")] } },
    { cells: ["Color", "color_mode · 13 site ids · 1", "color_mode = COLOR_MODE_IDS[index]", "The colour branch, which normal is computed, and the background (white for 5, 6)."],
      tip: { title: "Color", ...R("view", 262), links: [RL("panel", 113, "index → id"), RL("params", 10, "COLOR_MODE_IDS")] } },
    { cells: ["Precision", "precision · > 0 · 0.000025", "precision = precision / detail", "The pixel cone in hit_eps: both stop thresholds and the normal's delta (hit_eps(total) · 40). Not the shape."],
      tip: { title: "Precision", ...R("view", 261), links: [RL("panel", 160, "parsed on Enter / focus-out, reverts if invalid"), RL("sh", 195, "delta")] } },
    { cells: ["Renderer: Detail", "detail · 0.1 … 10 · 1.0", "folded into precision (÷ detail)", "Scales the threshold everywhere: ×2 halves it. Divided on the CPU so the default is bit-for-bit the old cone."],
      tip: { title: "Detail", ...R("view", 261), links: [RL("renderer", 30, "the slider"), RL("params", 61, "the field"), RL("sh", 16, "the uniform's comment")] } },
    { cells: ["Renderer: Full-detail range", "detail_range · 1 … 1000 · 10", "detail_range", "Where falloff starts: start = detail_range · near_dist, so it means the same at any zoom depth."],
      tip: { title: "Full-detail range", ...R("view", 267), links: [RL("renderer", 32, "the slider"), RL("params", 63, "the field"), RL("sh", 40, "start")] } },
    { cells: ["Renderer: Detail falloff", "detail_falloff · 0 … 3 · 0", "detail_falloff", "Past start the threshold grows by (t / start)^falloff: distant structure coarsens, rays stop sooner. 0 is off."],
      tip: { title: "Detail falloff", ...R("view", 268), links: [RL("renderer", 34, "the slider"), RL("params", 65, "the field"), RL("sh", 41, "the falloff")] } },
    { cells: ["Renderer: Max march steps", "max_steps · 32 … 512 · 128", "coarse_steps = ¾ · max_steps; fine_steps = the rest", "The per-ray step budget. 128 is the original 96 + 32; the loops are bounded at 384 + 128."],
      tip: { title: "Max march steps", ...R("view", 269), links: [RL("view", 270, "fine_steps"), RL("renderer", 36, "the slider"), RL("params", 84, "coarse_steps()"), RL("sh", 159, "phase 1 loop")] } },
    { cells: ["Renderer: Min resolution", "min_render_scale · 0.1 … 1 · 0.25", "— (the governor reads it)", "The lowest render scale Fast Controls may drop to while you move (tab 9)."],
      tip: { title: "Min resolution", ...R("gov", 36), links: [RL("renderer", 38, "the slider"), RL("params", 67, "the field"), RL("gov", 64, "a raised floor lifts the scale")] } },
    { cells: ["(none)", "the camera and the shape", "near_dist = max(D(eye), 1e-6)", "The eye's distance to the nearest surface (CPU, de(·, 32)): the unit detail_range is measured in."],
      tip: { title: "near_dist", ...R("view", 287), links: [RL("view", 281, "pushed with the camera"), RL("view", 271, "and with the params"), RL("params", 50, "NEAR_FLOOR")] } },
    { cells: ["Julia", "julia_enabled · false", "julia_enabled; box_half = 20 if on else 2", "c becomes the Julia point; the march's cube grows to ±20; modes 1–9 switch from NF to N."],
      tip: { title: "Julia", ...R("view", 266), links: [RL("view", 263, "julia_enabled"), RL("panel", 116, "the check box"), RL("sh", 199, "NF only outside Julia")] } },
    { cells: ["X  Y  Z", "julia_point · (−0.23, 1.512, 1.892)", "julia_point", "The constant added each iteration in Julia mode. Also dragged by the on-screen ring."],
      tip: { title: "Julia X / Y / Z", ...R("view", 264), links: [RL("panel", 169, "_on_julia_submitted"), RL("params", 30, "the default")] } },
    { cells: ["Fast Controls", "fast_controls · true", "— (the governor reads it)", "Whether the governor may drop render_scale while you move (tab 9). Also on the Renderer tab."],
      tip: { title: "Fast Controls", ...R("gov", 35), links: [RL("panel", 120, "the check box"), RL("renderer", 56, "the Renderer tab's")] } },
    { cells: ["Camera", "camera_mode · FLY / ORBIT · FLY", "— (Main._apply_mode)", "Which camera handles input, and mouse capture."],
      tip: { title: "Camera", ...R("main", 199), links: [RL("panel", 121, "the dropdown")] } },
    { cells: ["Mouse sensitivity", "mouse_sensitivity · 0.02 … 0.5 · 0.1", "— (the cameras read it)", "Degrees per pixel of mouse-look; the orbit uses 0.5°/px × sens / 0.1."],
      tip: { title: "Mouse sensitivity", ...R("fly", 56), links: [RL("panel", 95, "the slider"), RL("orbit", 86, "orbit")] } },
    { cells: ["(none)", "TAN_HALF_FOV constant", "tan_half_fov = tan 20° = 0.363970", "The 40° vertical field of view of every ray."],
      tip: { title: "tan_half_fov", ...R("view", 265), links: [RL("view", 7, "TAN_HALF_FOV"), RL("sh", 143, "the ray")] } },
    { cells: ["(none)", "the window size", "aspect = width / height", "The horizontal spread of the rays; set whenever the size changes."],
      tip: { title: "aspect", ...R("view", 241), links: [RL("view", 229, "_aspect")] } },
    { cells: ["(camera)", "CameraState.transform", "eye, cam_right, cam_up, cam_forward", "The ray origin and basis (forward = −basis.z)."],
      tip: { title: "camera uniforms", ...R("view", 274), links: [RL("cam", 18, "forward()")] } },
  ],
};

for (const r of dialTable.rows) r.tip.blurb = `Uniform: \`${r.cells[2]}\`. ${r.cells[3]}`;

const fixOk = FIX.fails.length === 0;
const cards = {
  type: "cards",
  title: "Invariants, gotchas, history, open",
  columns: 2, cardWidth: 560,
  cards: [
    { title: fixOk ? "CPU estimator = shader: the 24 fixtures" : `✗ THIS PAGE'S de() PORT FAILS ${FIX.fails.length} OF ${FIX.n} FIXTURES`,
      tag: fixOk ? "invariant" : "port broken", hue: fixOk ? 3 : 2, ...R("tDE", 15),
      links: [{ file: F.spec, line: 174, label: "the fixture tables" }, RL("tDE", 10, "the tolerance"), RL("de", 5, "must equal de(p, 32)")],
      body: fixOk
        ? `DistanceEstimator.estimate_at must give the shader's de(p, 32) numbers, pinned by 24 site-measured fixtures (defaults, an alternative shape, Julia) at relative 1e−5 or absolute 1e−9 below 1e−6. This pane runs the same 24 through its own de() port at load: all ${FIX.n} pass (worst relative error ${FIX.worst.toExponential(1)}), so its figures show the real shape. A failure turns this card orange and shows in the red error box.`
        : `The figures on this page are NOT the real shape until the port is fixed (fix the port, never the fixtures): ${FIX.fails.join("; ")}` },
    { title: "project / unproject round-trip", tag: "invariant", hue: 3, ...R("tView", 23), links: [RL("view", 203, "project"), RL("view", 218, "unproject"), RL("tMarker", 29, "the marker drag")],
      body: "FractalView's project and unproject use the shader's own ray maths (forward + ndc.x·aspect·tan_half_fov·right + ndc.y·tan_half_fov·up), so unproject(project(p), depth) == p and the Julia ring sits exactly on the point the shader uses." },
    { title: "COLOR_MODE_IDS match the site", tag: "invariant", hue: 3, ...R("params", 10), links: [RL("tParams", 27, "the id-order test"), RL("ws", 180, "a save rejects unknown ids")],
      body: "The dropdown order maps to the site's ids [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14], and saves store the id, not the index, so a saved number means the same colour here and on the site." },
    { title: "The shader declares exactly twenty uniforms", tag: "invariant", hue: 3, ...R("tShader", 13), links: [RL("sh", 6, "the uniforms"), RL("sh", 21, "the five level-of-detail ones")],
      body: "A shader that fails to compile yields an empty uniform list, so shader_test catches a broken shader headless by checking the list names exactly: the spec's fifteen plus detail_range, detail_falloff, near_dist, coarse_steps and fine_steps. The noise editor's spliced shaders keep all twenty." },
    { title: "hit_epsilon (CPU) = hit_eps (shader)", tag: "invariant", hue: 3, ...R("params", 75), links: [RL("sh", 38, "hit_eps"), RL("tParams", 72, "the test"), RL("orbit", 165, "the orbit's CPU march uses it")],
      body: "One threshold, written twice: precision / detail · t, times (t / start)^falloff past start = detail_range · near_dist. The orbit camera's click-to-centre march uses the GDScript copy, so it lands where the shader draws the surface. fractal_params_test pins the plain cone at the defaults, detail halving it, and the falloff factor past start. This pane's march port is a third copy." },
    { title: "Default renderer options keep the threshold, not every pixel", tag: "gotcha", hue: 2, ...R("sh", 159), links: [RL("sh", 187, "ce on the 128-step scale"), RL("view", 261, "detail folded on the CPU")],
      body: "At the defaults hit_eps is exactly the old precision · total (detail is divided on the CPU so the shader multiplies by the same float) and the budget is 96 + 32. But the loop bounds became uniforms, and the GPU compiler emits different code for them: about 1% of pixels, in the chaotic dust, flip (mean 0.5/255 on the default view). Deterministic run to run; invisible to the eye." },
    { title: "Fractal coordinates are twice the site's", tag: "gotcha", hue: 2, ...R("readme", 178), links: [RL("spec", 50, "spec: coordinates")],
      body: "Everything here (eye, Julia point, saves) is in the space the estimator is evaluated in. The site reports camera positions at half that: a site position (x, y, z) is (2x, 2y, 2z) here. The shader's h = v/2 and eh = eye/2 are the site's own half-scale coordinates." },
    { title: "World up is +Z; forward is −basis.z", tag: "gotcha", hue: 2, ...R("spec", 55), links: [RL("cam", 18, "forward() = −basis.z"), RL("fly", 7, "WORLD_UP")],
      body: "Not Godot's +Y. Cameras yaw about +Z and rebuild their basis with +Z as the up hint. CameraState follows Godot's Transform3D convention, so forward is −basis.z, right basis.x, up basis.y." },
    { title: "The Ctrl toggle is ignored while a text field has focus", tag: "gotcha", hue: 2, ...R("main", 237), links: [RL("panel", 147, "text_field_has_focus")],
      body: "So editing shortcuts like Ctrl+A in Precision or the Julia fields do not also toggle the panel. Enter or Escape leaves the field." },
    { title: "Cmd / Ctrl suppresses movement, so Cmd+S is a save", tag: "gotcha", hue: 2, ...R("fly", 71), links: [RL("proj", 67, "workspace_quick_save"), RL("tFly", 37, "the test")],
      body: "S alone is move_back; with Cmd or Ctrl held the fly camera ignores the move actions, so ⌘S saves without flying backwards." },
    { title: "Pointer lock needs a click on the web", tag: "gotcha", hue: 2, ...R("spec", 496), links: [RL("main", 269, "click to capture")],
      body: "A browser only grants mouse capture inside a user gesture. The click-to-capture rule (a click on the view while free in FLY) is that gesture; the Ctrl toggle alone cannot re-capture on the web." },
    { title: "float32 limits deep zoom", tag: "gotcha", hue: 2, ...R("spec", 491), links: [RL("sh", 3, "highp = float32 on WebGL 2")],
      body: "The shader runs 32-bit floats (WebGL 2), so the march breaks down at the same zoom depth as the site's. Accepted. The JS ports on this page run doubles, so they stay clean deeper than the real render." },
    { title: "DistanceEstimator runs scalars to stay 64-bit", tag: "gotcha", hue: 2, ...R("de", 7), links: [RL("tDE", 2, "fixtures pin estimate_at")],
      body: "GDScript floats are 64-bit but Vector3 components are 32-bit; the precision lost on input is amplified near the surface and broke the near-boundary fixtures. estimate_at keeps the orbit in scalar floats; estimate(Vector3) is for callers whose input is already a 32-bit camera position." },
    { title: "The save format, version 1", tag: "history", hue: 6, ...R("ws", 18), links: [RL("ws", 43, "the layout"), RL("ws", 26, "the renderer keys"), RL("ws", 67, "unknown keys warn"), RL("wsf", 20, "user://saves/ in exports"), RL("saveDef", 1, "default.json")],
      body: "{ version, fractal: every FractalParams value (colour by site id, camera mode as \"fly\"/\"orbit\", julia_point as [x, y, z]), camera: { eye, forward, up, speed_factor } }. Unknown or malformed keys are skipped with a warning each; missing keys keep the current value; VERSION only changes if a key changes meaning. Vectors are tidied to float32's seven significant digits. Exports save to user://saves/. The renderer options (detail, detail_range, detail_falloff, max_steps, min_render_scale) were added to fractal as additive keys, still version 1; the committed saves carry the defaults so loading one resets them." },
    { title: "Not built: the spec's non-goals", tag: "open", hue: 4, ...R("spec", 24),
      body: "Save Image, Copy URL / load from URL, the High DPI toggle, a reset button, touch controls, and any fractal but the Mandelbox. The structure should not make them hard to add, but nothing is designed around them." },
  ],
};

// ================================================================== plain-words companions
// One cards block under each shape figure: the same mechanism retold without the maths, for reading
// the figure before (or instead of) the formulas. No file:line here; the figure above carries them.
const PLAIN = { tag: "in plain words", hue: 1 };
const plain = (title, cards) => ({ type: "cards", title, columns: 3, cardWidth: 500,
  // Numbered because the masonry places each card in the shortest column, not in reading order.
  cards: cards.map(([t, body], i) => Object.assign({ title: `${i + 1} · ${t}`, body: body.replace(/\n/g, "\n\n") }, PLAIN)) });

const foldPlain = plain("In plain words: how a point is tested", [
  ["Start here: the big idea",
    "The fractal is not stored anywhere as a 3D model. To find out whether a spot in space is part of the shape, the program takes that spot and puts it through the same three-move recipe 32 times over, a bit like kneading dough: fold it, flip it inside out, stretch it and shift it.\nSpots that stay near the middle after all that kneading are part of the shape. Spots that get flung off to huge numbers are empty space. This tab lets you watch one spot get kneaded, one move at a time."],
  ["What you are looking at",
    "The big square is a flat slice through 3D space, like one sheet cut from a loaf of bread. Blue means close to the fractal's surface; paler means further away.\nClick it to choose a starting spot. Each press of Step applies one move and draws a coloured line to where the spot went: orange for move 1, pink for move 2, blue for move 3. The orange square is the folding box and the pink circles are the two balls of move 2. The bars and the table on the right show the same journey as numbers."],
  ["Move 1: the box fold",
    "Imagine a box whose walls are mirrors. If the spot has wandered outside the box in any direction, it is reflected back inside, the way a ball bounces off a wall: a spot 0.3 past the wall lands 0.3 inside it. A spot already inside is left alone.\nThis is where the Mandelbox gets its square walls and flat plates. The Fold dial sets how big the box is."],
  ["Move 2: the sphere fold",
    "Now measure how far the spot is from the centre. Two invisible balls sit there, a small one (Inner Radius) and a bigger one (Outer Radius).\nOutside the big ball, nothing happens. Between the two balls, the spot is turned inside out: the closer it was to the centre, the further out it gets pushed, like turning a glove inside out. Inside the small ball, the spot is just pushed outward by a fixed amount, about 2× at the defaults.\nThis is where the round holes and bubbles come from."],
  ["Move 3: stretch and shift",
    "Blow everything up by the Scale number (−2.09 by default; the minus sign also flips it to the opposite side of the centre), then shift it by the spot you started with.\nThe shift is what gives every spot its own story: without it, every spot would behave alike. In Julia mode, every spot is shifted by the same fixed point instead, which gives a whole different family of shapes."],
  ["The verdict: one distance number",
    "While kneading, the program also keeps a running total of how much the moves have magnified things (the dz column). After 32 rounds it divides how far the spot ended up from the centre by that total. The answer, D, is a safe guess at how far the starting spot is from the fractal's surface.\nA spot inside the shape stays small while the magnification keeps growing, so D shrinks to almost nothing. A spot outside runs away, and D comes out close to its real distance. Tab 5 (Marching one ray) is built entirely on this number."],
  ["Words on this tab",
    "p: the starting spot, written as three numbers (x across, y up, z depth).\nz (in the readouts): the spot being kneaded, where it is right now. Not the same as the z axis, sorry.\n|z|: how far that spot is from the centre.\nOrbit: the list of places the spot visits along the way.\nIteration: one round of all three moves.\nComponent: one of the three numbers x, y or z.\nSample cloud: 121 spots kneaded together, to show the whole slice moving at once."],
]);

const dialsPlain = plain("In plain words: the distance map and the dials", [
  ["Start here: the big idea",
    "This is a map of distances. Every pixel in the square is one spot in a flat slice through space, coloured by how far that spot is from the fractal's surface: deep blue right at the surface, fading to pale far from it. Each step of fading means about ten times further away.\nThe black pixels are the spots close enough that the renderer would say \"this is the surface\". Move a dial and the map redraws, so you can see what that dial does to the shape. Hover anywhere for the exact numbers."],
  ["Choosing the slice",
    "X-Y, X-Z and Y-Z choose which way the slice faces: like cutting a loaf from the top versus from the front.\n\"Offset along the third axis\" slides the cut deeper or shallower into the shape.\n\"View half-width\" zooms the map out (bigger) or in (smaller)."],
  ["Slice (Scale)",
    "How much the shape is blown up in every round of kneading (move 3 on the Fold by fold tab). It changes how many copies of the pattern nest inside each other and how fine they get. Of all the dials, this one changes the shape's character the most."],
  ["Fold",
    "The size of the mirror box from move 1. Smaller boxes carve the walls into thinner and thinner plates."],
  ["Inner Radius and Outer Radius",
    "The two balls from move 2. Outer Radius sets how big the turn-inside-out zone is, which shapes the round holes and bubbles. Inner Radius is the small core where spots get a fixed push instead of being turned inside out, so it caps how wildly the inside-out move can throw a spot."],
  ["Precision is not a shape dial",
    "It only decides how close counts as touching the surface. Moving it thickens or thins the black edge by a hair; the shape itself does not move. Smaller values give a crisper picture but take the renderer more steps (and so more time) to reach."],
  ["Julia mode",
    "Normally each spot is shifted by its own starting position in move 3. Julia mode shifts every spot by the same point, the one set by the Julia X, Y and Z sliders. That gives a different family of shapes, which can reach much further out, so the renderer searches out to 20 units from the centre instead of 2."],
  ["Presets",
    "Load the three views saved in the project's saves/ folder, so you can see how a real saved view's dials shape the map."],
]);

const marchPlain = plain("In plain words: finding the surface along one line of sight", [
  ["Start here: the big idea",
    "Every pixel on screen is a line of sight (a ray) from your eye out into the scene. The renderer has to find where that line first touches the fractal, and there is no formula for that. So it creeps along the line instead.\nAt each stop it asks \"how far is the nearest bit of surface from here?\" (the distance number from the Fold by fold tab), then steps forward exactly that far. It cannot pass through anything, because nothing was closer than that. Near the surface the steps get tiny, and once a step is small enough, it calls it a hit."],
  ["What you are looking at",
    "A vertical slice through space that contains your eye. The black dot is the eye and the green dot is where it is looking; drag either.\nEach press of Step draws a circle and a hop. The circle is a safe bubble: nothing of the fractal is inside it, so the ray can jump to its edge. Orange hops are the quick rough pass, blue hops the careful pass.\nIn the chart, each bar is one step's distance to the surface, and the dashed line is the \"close enough\" mark. The march stops when a bar dips under it."],
  ["Step 0: only search the box",
    "The whole fractal fits inside a cube (2 units from the centre each way, or 20 in Julia mode). A ray that misses the cube is background straight away. A ray that hits it starts creeping where it enters."],
  ["Two passes: rough, then careful",
    "Pass 1 uses a cheaper, rougher distance (16 rounds of kneading instead of 32) and a looser \"close enough\", for up to 96 steps. Pass 2 always runs next (unless the ray has already left the cube), with the full 32 rounds and the strict \"close enough\", for up to 32 more steps to polish the hit.\nLike jogging to the right street, then walking to the front door."],
  ["Why the step count becomes the colour",
    "The renderer counts how many steps each ray took and turns that into brightness. A ray that slid straight onto an open face took few steps and comes out bright. A ray that squeezed into a crevice, or skimmed along an edge, took many and comes out dark.\nThat is the soft, shadowy look in every colour mode, and it is not real lighting. A ray that uses up every step without ever arriving is not thrown away: it is drawn as the darkest shade, which is the \"dust\" you see floating around the fractal."],
  ["How close counts as touching",
    "The \"close enough\" distance grows the further the ray has travelled from your eye, like a torch beam widening: far-off things cover fewer pixels on screen, so they only need to be hit roughly. Precision sets how narrow the beam is.\nThe Renderer tab's level-of-detail dials can widen it further for distant things, starting at a distance measured from how near you are to the surface. Around the eye, the solid ring is that nearness and the dashed ring is where the extra widening starts."],
]);

const normalsPlain = plain("In plain words: which way the surface faces", [
  ["Start here: what a normal is",
    "A normal is the direction a surface faces at one spot: picture an arrow sticking straight out of it. Lighting needs it, because a face turned toward the light is bright and a face turned away is dark.\nThe renderer works out two different arrows for every spot it hits, and the colour modes choose between them."],
  ["N, the honest arrow (blue)",
    "Found by nudging the hit spot a tiny bit left and right, up and down, forward and back, and seeing which way the distance to the surface grows fastest. That direction is straight out of the surface. It is the true answer."],
  ["NF, the deliberately wrong arrow (orange)",
    "The original website (icefractal.com) worked its arrow out a different way. It measures a different quantity altogether (how far a related spot gets flung after 16 rounds of kneading), and it compares one sample taken at half the spot's position against others taken at the full position. That mismatch tips every arrow toward the same diagonal.\nThe result is often tens of degrees off the true direction, but that tilt is the \"Ice Fractal\" look. So the project copies the site's arithmetic exactly, on purpose."],
  ["What you are looking at",
    "The same vertical slice as the Marching one ray tab. Rays fan out from the eye (just off the top right) like torch beams, and at each place one lands, the blue arrow is N and the orange is NF. A short arrow is pointing mostly into or out of the screen.\nThe Show buttons change the background: the quantity NF is built from, that quantity at half position, or the ordinary distance map. In the first two, violet marks spots that stay near the middle and amber marks spots that get flung away. The table compares the two arrows and how bright each would make that spot."],
  ["Which colour modes use which",
    "Outside Julia mode, most colour modes use the tilted NF. In Julia mode, they switch to the honest N. Rainbow Metal, Ice Box and Gold always use N, and Grayscale uses neither (it is pure step count)."],
]);

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
  subtitle: "A Godot 4.6 GDScript Mandelbox viewer emulating icefractal.com/mandelbox. Two Resources (FractalParams, CameraState) carry every value; a canvas_item shader ray-marches the distance estimator in two phases inside a ±2 cube, stopping on a hit threshold that can coarsen with distance, and colours each hit by how many steps it took; a governor drops the render scale while you move and stops rendering when you stop. The live figures run line-for-line JavaScript ports of the shader and the GDScript, checked at load against the 24 distance fixtures.",
  commit: "cbe80bfbace324eb8ea8f87aeb02f60a9f9e0f4e",
  pinNote: "main, unpushed: links 404 until it is pushed",
  ctx: {
    state: { hue: 1, label: "state — FractalParams, CameraState" },
    input: { hue: 2, label: "input — Main's dispatch, ControlsPanel, WorkspaceFiles" },
    camera: { hue: 3, label: "cameras — fly, orbit, Julia marker" },
    render: { hue: 6, label: "render — FractalView, SubViewport, shader, governor" },
    math: { hue: 4, label: "CPU maths — DistanceEstimator" },
    files: { hue: 5, label: "files — Workspace, saves/" },
  },
  kinds: {
    call: { style: "solid", label: "calls · sets" },
    signal: { style: "dash", label: "changed signal" },
    data: { style: "dot", label: "reads a value · a uniform" },
  },
  tabs: [
    arch,
    seq,
    { label: "Fold by fold", rows: [[foldFig], [foldPlain]] },
    { label: "What each dial does", rows: [[dialsFig], [dialsPlain]] },
    { label: "Marching one ray", rows: [[marchFig], [marchPlain]] },
    { label: "Shading and colour modes", rows: [[shadeFig], [modeTable]] },
    { label: "The two normals", rows: [[normalsFig], [normalsPlain]] },
    { label: "Cameras", rows: [[camFig], [camTable]] },
    govFig,
    { label: "Dials, uniforms, saves", rows: [[dialTable], [cards]] },
  ],
  // The ports, exposed for checking from the console or node (VIZ.panes[0].ports.de(...)).
  ports: { params, hitEps, nearDist, de, orbitStages, field, calcNormal, calcNF, hue, boxIntersect, march, shade, renderPixel, lookAt, flySpeed, scrollFactor, applyLook, newGovernor, governorStep, FIX, DEFAULT_CAM },
});
})();
