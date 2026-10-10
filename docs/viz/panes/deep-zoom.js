// Pane: deep zoom past the 32-bit floor (Help I'm Stuck In A Fractal). Every file:line below was
// read at `commit` with `git show <commit>:<path>`. When the code changes: re-read the lines, bump
// `commit`, run `node tools/viz/check.mjs --print --pane deep-zoom`.
//
// The live figures run JavaScript ports of the real maths, each a small named function below with
// the source file and lines it was ported from: the CPU side (ReferenceOrbit, FractalParams' floors,
// SurfaceFixture's surface points, DistanceEstimator) in JS doubles, like GDScript's floats; the GPU
// side (perturbation.gdshaderinc's pert_* functions and the direct loop) in emulated float32, every
// arithmetic result rounded with Math.fround exactly as tests/perturbation_port.gd's r() does. Only
// the box-fold Mandelbox is ported (the three saves the figures use); the KIFS, the Kleinian and the
// cylinder and hybrid folds are in the shader and the GDScript port but not here.
// At load the ports are checked against what tests/perturbation_test.gd prints (its MEASURED near
// and floor_pert for the default box, the ice field and the terraces) and against its case tables
// and its 64-bit algebra check; any mismatch goes to VIZ.errors and the red box.
(function () {
const F = {
  cam: "src/camera/camera_state.gd",
  fly: "src/camera/fly_camera.gd",
  ray: "src/camera/center_ray.gd",
  ws: "src/workspace/workspace.gd",
  orb: "src/fractal/reference_orbit.gd",
  params: "src/fractal/fractal_params.gd",
  de: "src/fractal/distance_estimator.gd",
  view: "src/fractal/fractal_view.gd",
  sh: "src/fractal/mandelbox.gdshader",
  pert: "src/fractal/perturbation.gdshaderinc",
  main: "src/main.gd",
  move: "src/ui/console/movement_pane.gd",
  port: "tests/perturbation_port.gd",
  tPert: "tests/perturbation_test.gd",
  fix: "tests/surface_fixture.gd",
  tOrbit: "tests/reference_orbit_test.gd",
  tCam: "tests/camera_state_test.gd",
  tWs: "tests/workspace_test.gd",
  tView: "tests/fractal_view_test.gd",
  tParams: "tests/fractal_params_test.gd",
  tShader: "tests/shader_test.gd",
  tFly: "tests/fly_camera_test.gd",
  tRay: "tests/center_ray_test.gd",
  spec: "docs/superpowers/specs/2026-10-09-perturbation-deep-zoom-design.md",
  note: "docs/reference/self-similar-substitution.md",
  readme: "README.md",
  saveDef: "saves/default.json",
  saveField: "saves/juliaIceField.json",
  saveTer: "saves/juliaIceTerraces.json",
};
// Link helpers: R("pert", 41) is { file, line }; RL adds a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const COMMIT = "249d26bc32e5dfdb36c8f5452ec3be9c53aa50f4";
const commitLink = (sha, label) => ({ url: `https://github.com/Adam-G-Klein/HelpImStuckInAFractal/commit/${sha}`, label });

// ================================================================== the CPU ports (64-bit doubles)
const fr = Math.fround;
const clampf = (x, a, b) => (x < a ? a : x > b ? b : x);
const TAN_HALF_FOV = 0.36397023426620234;          // fractal_view.gd:11
const PERT_MAX = 20;                                // reference_orbit.gd:29
const PERT_HANDOFF = 0.1;                           // fractal_params.gd:439 = perturbation.gdshaderinc:34
const PERT_ON = 10;                                 // fractal_params.gd:433
const ZOOM_FLOOR_DIVISOR = 50;                      // fractal_params.gd:398
// CameraState.DEFAULT_EYE (camera_state.gd:16) is a Vector3: its components are 32-bit floats.
const DEFAULT_EYE32 = [8.175847, 3.812460, 3.283393].map(fr);

// The box-fold Mandelbox's knobs: FractalParams' defaults (fractal_params.gd) overridden by o.
// jOn[a]: the Julia constant replaces component a (julia_all or julia_a).
function mbParams(o) {
  const p = Object.assign({ box_scale: -2.09, fold_limit: 1.0, min_radius: 0.7, fixed_radius: 1.0, fold_order: 0, w: 0,
    julia_all: false, julia: [false, false, false, false], c: [-0.23, 1.512, 1.892, 0], precision: 0.000025, detail: 1 }, o || {});
  p.jOn = p.julia.map(j => p.julia_all || j);
  return p;
}
// The three saves the figures use: their shape.defaults (fold_order 0, no rotation, w 0).
const SAVES = [
  { id: "box", name: "default box", ...R("saveDef", 5), P: mbParams() },
  { id: "ice", name: "ice field", ...R("saveField", 5), P: mbParams({ box_scale: -2.29, fold_limit: 0.72, min_radius: 0.0, fixed_radius: 0.29, julia_all: true, precision: 2e-5 }) },
  { id: "ter", name: "terraces", ...R("saveTer", 5), P: mbParams({ box_scale: -1.88, fold_limit: 0.81, min_radius: 0.49, fixed_radius: 0.53, julia_all: true, precision: 1e-4 }) },
];

const r2of = z => z[0] * z[0] + z[1] * z[1] + z[2] * z[2] + z[3] * z[3];
// DistanceEstimator._box_fold and _sphere_fold (distance_estimator.gd:185-205), in place.
function boxFold64(z, L) { for (let a = 0; a < 4; a++) z[a] = clampf(z[a], -L, L) * 2 - z[a]; }
function sphereFactor64(r2, mr2, fr2) {
  const mr = Math.max(mr2, 1e-12), f2 = Math.max(fr2, 1e-12);
  return r2 < mr ? f2 / mr : r2 < f2 ? f2 / Math.max(r2, 1e-12) : 1;
}
function sphereFold64(z, dz, mr2, fr2) {
  const r2 = r2of(z), mr = Math.max(mr2, 1e-12), f2 = Math.max(fr2, 1e-12);
  if (r2 < mr) { const f = f2 / mr; for (let a = 0; a < 4; a++) z[a] *= f; return dz * f; }
  if (r2 < f2) { const f = f2 / Math.max(r2, 1e-12); for (let a = 0; a < 4; a++) z[a] *= f; return dz * f; }
  return dz;
}
const constant64 = (z0, P) => [0, 1, 2, 3].map(a => (P.jOn[a] ? P.c[a] : z0[a]));
// deMB: DistanceEstimator.mandelbox_at (distance_estimator.gd:43-100), box fold, no rotation or drift.
function deMB(px, py, pz, P) {
  const mr2 = P.min_radius * P.min_radius, fr2 = P.fixed_radius * P.fixed_radius, L = P.fold_limit;
  const z0 = [px, py, pz, P.w], c = constant64(z0, P), z = z0.slice();
  let dz = 1;
  for (let i = 0; i < 32; i++) {
    if (P.fold_order === 0) { boxFold64(z, L); dz = sphereFold64(z, dz, mr2, fr2); }
    else { dz = sphereFold64(z, dz, mr2, fr2); boxFold64(z, L); }
    const s = P.box_scale;
    z[0] = s * z[0] + c[0]; z[1] = s * z[1] + c[1]; z[2] = s * z[2] + c[2]; z[3] = s * z[3] + c[3];
    dz = dz * Math.abs(s) + 1;
  }
  return Math.sqrt(r2of(z)) / Math.abs(dz);
}

// buildOrbit: ReferenceOrbit.build → _mandelbox (reference_orbit.gd:46-137, records 142-175). The
// camera's own orbit in 64-bit: pts[i] = X_i (X_0 the eye), mag[i] = λ_i (the sphere factors times
// |scale|, the running dz without its + 1s), and for the first PERT_MAX iterations the record:
//   a = −L − X, b = L − X (the box fold's gaps, of the fold's input), c = the sphere fold's input,
//   d = (|c|² − min_r², |c|² − fixed_r², the reference's sphere factor m, 0: the cylinder's slot).
// a32 … d32, pts32: the 32-bit copies the shader reads (_pack, 344-356).
function buildOrbit(P, ex, ey, ez) {
  const mr2 = P.min_radius * P.min_radius, fr2 = P.fixed_radius * P.fixed_radius, L = P.fold_limit;
  const z0 = [ex, ey, ez, P.w], c = constant64(z0, P), z = z0.slice();
  const o = { eye: [ex, ey, ez], mag: [1], pts: [z.slice()], a: [], b: [], c: [], d: [], n: 32, perturbable: true };
  let dz = 1, lam = 1;
  const sphRec = (i, keep) => {
    const r2 = r2of(z), mr = Math.max(mr2, 1e-12), f2 = Math.max(fr2, 1e-12), f = sphereFactor64(r2, mr2, fr2);
    if (keep) { o.c[i] = z.slice(); o.d[i] = [r2 - mr, r2 - f2, f, 0]; }
    return f;
  };
  const foldRec = i => { o.a[i] = z.map(v => -L - v); o.b[i] = z.map(v => L - v); };
  for (let i = 0; i < 32; i++) {
    const keep = i < PERT_MAX;
    if (P.fold_order === 0) { if (keep) foldRec(i); boxFold64(z, L); lam *= sphRec(i, keep); dz = sphereFold64(z, dz, mr2, fr2); }
    else { lam *= sphRec(i, keep); dz = sphereFold64(z, dz, mr2, fr2); if (keep) foldRec(i); boxFold64(z, L); }
    const s = P.box_scale;
    z[0] = s * z[0] + c[0]; z[1] = s * z[1] + c[1]; z[2] = s * z[2] + c[2]; z[3] = s * z[3] + c[3];
    dz = dz * Math.abs(s) + 1;
    lam *= Math.abs(s);
    o.mag[i + 1] = lam;
    o.pts[i + 1] = z.slice();
  }
  o.distance = Math.sqrt(r2of(z)) / Math.abs(dz);
  o.pts32 = o.pts.map(v => v.map(fr));
  for (const k of ["a", "b", "c", "d"]) o[k + "32"] = o[k].map(v => v.map(fr));
  return o;
}
// ulp32: FractalParams.ulp32 (fractal_params.gd:404-414): the gap between neighbouring 32-bit floats near x.
function ulp32(x) {
  x = Math.abs(x);
  if (x < Math.pow(2, -126)) return Math.pow(2, -149);
  let e = Math.floor(Math.log(x) / Math.log(2));
  if (Math.pow(2, e + 1) <= x) e += 1; else if (Math.pow(2, e) > x) e -= 1;
  return Math.pow(2, e - 23);
}
const epsOf = P => Math.max(P.precision / P.detail, 1e-30);
// floor32 (fractal_params.gd:425-427), floor_pert (455-459), pert_iters (447-450).
const floor32 = (P, eye) => ulp32(Math.max(Math.abs(eye[0]), Math.max(Math.abs(eye[1]), Math.abs(eye[2])))) / (ZOOM_FLOOR_DIVISOR * epsOf(P));
function floorPert(P, o) {
  const k = Math.min(PERT_MAX, o.n), x = o.pts32[k];
  const m = Math.max(Math.max(Math.abs(x[0]), Math.abs(x[1])), Math.max(Math.abs(x[2]), Math.abs(x[3])));
  return ulp32(m) / (ZOOM_FLOOR_DIVISOR * epsOf(P) * Math.max(o.mag[k], 1e-300));
}
const pertIters = (P, o, near) => (!o.perturbable || near >= PERT_ON * floor32(P, o.eye) ? 0 : Math.min(PERT_MAX, o.n));
// coarse_iters (fractal_params.gd:361-374, the Mandelbox branch) and nf_weight (391-392).
function coarseIters(P, near) {
  const s = Math.abs(P.box_scale);
  if (s <= 1) return 32;
  const gap = Math.max(2 * P.precision / P.detail * Math.max(near, 0), 1e-300);
  return clampf(Math.ceil(Math.log(2 / gap) / Math.log(s)), 16, 32);
}
function nfWeight(near) { const t = clampf((near - 0.1) / (2 - 0.1), 0, 1); return t * t * (3 - 2 * t); }

// The surface points tests/surface_fixture.gd marches to. norm32: Vector3.normalized() in 32-bit
// (the forward a Vector3 holds). surfaceFrom (34-51): from the eye toward the origin in 64-bit until
// the estimate is under 1e-10. defaultSurface (12-27): the default camera's centre ray (CenterRay.march,
// center_ray.gd:79-94, from the 32-bit eye; its cube entry comes back in a 32-bit Vector2), then on to
// 1e-10. backed (77-78): the camera `back` short of the point along its ray.
function norm32(v) {
  const x = fr(v[0]), y = fr(v[1]), z = fr(v[2]);
  const l = fr(Math.sqrt(fr(fr(fr(x * x) + fr(y * y)) + fr(z * z))));
  return [fr(x / l), fr(y / l), fr(z / l)];
}
function surfaceFrom(P, eye) {
  const f = norm32([-eye[0], -eye[1], -eye[2]]);
  let x = eye[0], y = eye[1], z = eye[2], best = [x, y, z], bestD = Infinity;
  for (let i = 0; i < 3000; i++) {
    const d = deMB(x, y, z, P);
    if (d < bestD) { bestD = d; best = [x, y, z]; }
    if (d < 1e-10) break;
    x += f[0] * d; y += f[1] * d; z += f[2] * d;
  }
  return [best[0], best[1], best[2], f[0], f[1], f[2]];
}
function marchAt(o, dir, P) {
  const half = P.julia_all ? 20 : 2;
  let te = -Infinity, tx = Infinity;
  for (let i = 0; i < 3; i++) {
    let r = dir[i];
    if (Math.abs(r) < 1e-9) r = r >= 0 ? 1e-9 : -1e-9;
    const inv = 1 / r, t1 = (-fr(o[i]) - half) * inv, t2 = (-fr(o[i]) + half) * inv;
    te = Math.max(te, Math.min(t1, t2)); tx = Math.min(tx, Math.max(t1, t2));
  }
  te = fr(te); tx = fr(tx);
  if (tx < Math.max(te, 0)) return [Infinity, false];
  let t = Math.max(te, 0);
  for (let i = 0; i < 64; i++) {
    const d = deMB(o[0] + dir[0] * t, o[1] + dir[1] * t, o[2] + dir[2] * t, P);
    if (d < P.precision / P.detail * t) return [t, true];
    t += d;
    if (t > tx) return [Infinity, false];
  }
  return [t, false];
}
function defaultSurface(P) {
  const e = DEFAULT_EYE32, f = norm32([-e[0], -e[1], -e[2]]);
  const t = marchAt(e, f, P)[0];
  let x = e[0] + f[0] * t, y = e[1] + f[1] * t, z = e[2] + f[2] * t;
  for (let i = 0; i < 400; i++) {
    const d = deMB(x, y, z, P);
    if (d < 1e-10) break;
    x += f[0] * d; y += f[1] * d; z += f[2] * d;
  }
  return [x, y, z, f[0], f[1], f[2]];
}
const backed = (s, b) => [s[0] - s[3] * b, s[1] - s[4] * b, s[2] - s[5] * b];
// One surface point per save, from the default eye (surface_from, as the test does for every save
// but the default box, whose MEASURED rows use default_surface).
for (const sv of SAVES) sv.surf = surfaceFrom(sv.P, DEFAULT_EYE32);
SAVES[0].centre = defaultSurface(SAVES[0].P);
// A 64-bit march from eye along dir (the test's _march_ref, perturbation_test.gd:244-254, without
// its 10 d cut-off): the t where the estimate first falls under eps × t.
function march64(eye, dir, P, steps = 128) {
  const eps = P.precision / P.detail;
  let t = 0;
  for (let i = 0; i < steps; i++) {
    const d = deMB(eye[0] + dir[0] * t, eye[1] + dir[1] * t, eye[2] + dir[2] * t, P);
    if (d < eps * t) return { t, hit: true };
    t += d;
  }
  return { t, hit: false };
}

// ================================================================== the GPU port (float32)
// The shader's perturbed estimate and its direct one, as tests/perturbation_port.gd writes them.
// R is the rounding: Math.fround for float32 (the port's r(), perturbation_port.gd:52-56) or the
// identity for its 64-bit algebra check. The record and the handoff points are read as the shader
// holds them: the 32-bit copies when R is fround, the 64-bit ones otherwise (port's rec(), 94-100).
const ID = x => x;
const mk = R => {
  const add4 = (a, b) => [R(a[0] + b[0]), R(a[1] + b[1]), R(a[2] + b[2]), R(a[3] + b[3])];
  const scale4 = (s, a) => [R(s * a[0]), R(s * a[1]), R(s * a[2]), R(s * a[3])];
  // dot4: perturbation_port.gd:79-80, GLSL's order ((x x + y y) + z z) + w w
  const dot4 = (a, b) => R(R(R(R(a[0] * b[0]) + R(a[1] * b[1])) + R(a[2] * b[2])) + R(a[3] * b[3]));
  // pert_clamp: perturbation.gdshaderinc:41-43 = perturbation_port.gd:354-363, per component.
  const pertClamp1 = (d, glo, ghi) => R(2 * R(clampf(d, glo, ghi) - clampf(0, glo, ghi)) - d);
  const pertClamp = (dl, ga, gb) => [0, 1, 2, 3].map(a => pertClamp1(dl[a], ga[a], gb[a]));
  // pert_sphere: perturbation.gdshaderinc:105-122 = perturbation_port.gd:443-473. Returns
  // { dl, dz, rx, rp, mp, dm, q } (rx, rp: the reference's and the pixel's regime, 0 inside, 1 shell, 2 outside).
  function pertSphere(dl, dz, X, gmin, gfix, mr2, fr2) {
    const q = R(R(2 * dot4(X, dl)) + dot4(dl, dl)), x2 = dot4(X, X), p2 = R(x2 + q);
    const gqmin = R(gmin + q), gqfix = R(gfix + q);
    const rx = gmin < 0 ? 0 : gfix < 0 ? 1 : 2, rp = gqmin < 0 ? 0 : gqfix < 0 ? 1 : 2;
    let mp = 1;
    if (rp === 0) mp = R(fr2 / mr2); else if (rp === 1) mp = R(fr2 / Math.max(p2, R(1e-12)));
    let dm = 0;
    if (rx === 1 && rp === 1) dm = R(R(-fr2 * q) / R(p2 * x2));
    else if (rx === 0 && rp === 1) dm = R(R(-fr2 * gqmin) / R(p2 * mr2));
    else if (rx === 1 && rp === 0) dm = R(R(fr2 * gmin) / R(mr2 * x2));
    else if (rx === 1 && rp === 2) dm = R(gfix / x2);
    else if (rx === 2 && rp === 1) dm = R(-gqfix / p2);
    else if (rx === 0 && rp === 2) dm = R(1 - R(fr2 / mr2));
    else if (rx === 2 && rp === 0) dm = R(R(fr2 / mr2) - 1);
    return { dl: add4(scale4(mp, dl), scale4(dm, X)), dz: R(dz * mp), rx, rp, mp, dm, q };
  }
  // The direct loop's steps: _clamp_fold, mb_sphere_fold, mb_step (perturbation_port.gd:142-202 =
  // mandelbox.gdshader:153-172, 277-284), box fold only.
  const boxFold = (p, L) => p.map(v => R(clampf(v, -L, L) * 2 - v));
  function sphereFold(p, dz, P) {
    const r2 = dot4(p, p), u = R, mr2 = Math.max(R(u(P.min_radius) * u(P.min_radius)), u(1e-12)), fr2 = Math.max(R(u(P.fixed_radius) * u(P.fixed_radius)), u(1e-12));
    if (r2 < mr2) { const f = R(fr2 / mr2); return { p: scale4(f, p), dz: R(dz * f), f }; }
    if (r2 < fr2) { const f = R(fr2 / Math.max(r2, u(1e-12))); return { p: scale4(f, p), dz: R(dz * f), f }; }
    return { p, dz, f: 1 };
  }
  function mbOrbit(z, dz, c, first, P) {
    const s = R(P.box_scale), L = R(P.fold_limit);
    for (let i = first; i < 32; i++) {
      let sf;
      if (P.fold_order === 0) { z = boxFold(z, L); sf = sphereFold(z, dz, P); z = sf.p; dz = sf.dz; }
      else { sf = sphereFold(z, dz, P); z = boxFold(sf.p, L); dz = sf.dz; }
      z = add4(scale4(s, z), c);
      dz = R(R(dz * Math.abs(s)) + 1);
    }
    return { z, dz };
  }
  const constant = (z0, P) => [0, 1, 2, 3].map(a => (P.jOn[a] ? R(P.c[a]) : z0[a]));
  // de_direct: perturbation_port.gd:334-343 (the shader's de(p, 32), mandelbox.gdshader:325-335).
  function deDirect(pos, P) {
    const z0 = [pos[0], pos[1], pos[2], R(P.w)], r = mbOrbit(z0.slice(), 1, constant(z0, P), 0, P);
    return R(R(Math.sqrt(dot4(r.z, r.z))) / Math.abs(r.dz));
  }
  // de_pert_mandelbox: perturbation.gdshaderinc:161-200 = perturbation_port.gd:536-573. o is the
  // reference orbit, k its pert_iters, eye the `eye` uniform, off = dir × t. handoff: PERT_HANDOFF
  // (Infinity for the algebra check). trace: if given, receives the offset after each iteration.
  function dePert(o, k, eye, off, P, handoff = PERT_HANDOFF, trace = null) {
    const rec = R === ID ? o : { a: o.a32, b: o.b32, c: o.c32, d: o.d32 };
    const pts = R === ID ? o.pts : o.pts32;
    let dl = [R(off[0]), R(off[1]), R(off[2]), 0];
    const p = [R(R(eye[0]) + dl[0]), R(R(eye[1]) + dl[1]), R(R(eye[2]) + dl[2])];   // the eye uniform is the rounded eye
    const dc = [P.jOn[0] ? 0 : dl[0], P.jOn[1] ? 0 : dl[1], P.jOn[2] ? 0 : dl[2], 0];
    const u = R, mr2 = Math.max(R(u(P.min_radius) * u(P.min_radius)), u(1e-12)), fr2 = Math.max(R(u(P.fixed_radius) * u(P.fixed_radius)), u(1e-12));
    const s = R(P.box_scale), lim = Math.min(k, 32), hh = R(R(handoff) * R(handoff));
    let dz = 1, h = 0;
    for (let i = 0; i < lim; i++) {
      if (dot4(dl, dl) >= hh) break;
      const rd = rec.d[i];
      if (P.fold_order === 0) {
        dl = pertClamp(dl, rec.a[i], rec.b[i]);
        const sf = pertSphere(dl, dz, rec.c[i], rd[0], rd[1], mr2, fr2); dl = sf.dl; dz = sf.dz;
      } else {
        const sf = pertSphere(dl, dz, rec.c[i], rd[0], rd[1], mr2, fr2); dl = sf.dl; dz = sf.dz;
        dl = pertClamp(dl, rec.a[i], rec.b[i]);
      }
      dl = add4(scale4(s, dl), dc);
      dz = R(R(dz * Math.abs(s)) + 1);
      if (trace) trace.push(dl.slice());
      h = i + 1;
    }
    const z = add4(pts[h], dl), c = constant([p[0], p[1], p[2], R(P.w)], P), res = mbOrbit(z, dz, c, h, P);
    return { de: R(R(Math.sqrt(dot4(res.z, res.z))) / Math.abs(res.dz)), h };
  }
  return { R, add4, scale4, dot4, pertClamp1, pertClamp, pertSphere, boxFold, sphereFold, mbOrbit, constant, deDirect, dePert };
};
const F32 = mk(fr), F64 = mk(ID);

// ================================================================== the self-check (load time)
// 1. The CPU ports against tests/perturbation_test.gd's MEASURED rows (_check_agreement,
//    perturbation_test.gd:296-322, printed at the pinned commit): the orbit's distance (`near`), the
//    records in use and floor_pert at the three depths, for the three Mandelbox fixtures. Godot
//    prints them with 14 decimals, so they must agree to 1e-14.
// 2. pert_clamp against the test's nine clamp cases (perturbation_test.gd:58-62) and pert_sphere
//    against its nine sphere regime pairs (99-116), in 64-bit.
// 3. The test's algebra check (152-197) on the default box, in 64-bit, without the handoff: after
//    every iteration the perturbed offset is the direct orbit's P_i − X_i within its tolerance.
const MEASURED_BOX = [
  { save: 0, d: 1e-5, near: 0.00000198810772, k: 20, fp: 0.00000000030169 },
  { save: 0, d: 1e-6, near: 0.00000047959223, k: 20, fp: 0.00000000015085 },
  { save: 0, d: 1e-7, near: 0.00000001866272, k: 20, fp: 0.00000000007542 },
  { save: 1, d: 1e-5, near: 0.00000178504271, k: 20, fp: 0.00000000024252 },
  { save: 1, d: 1e-6, near: 0.00000005116016, k: 20, fp: 0.00000000001516 },
  { save: 1, d: 1e-7, near: 0.0000000222901, k: 20, fp: 0.00000000001516 },
  { save: 2, d: 1e-5, near: 0.00000468627491, k: 20, fp: 0.00000000015653 },
  { save: 2, d: 1e-6, near: 0.00000042116158, k: 20, fp: 0.00000000003905 },
  { save: 2, d: 1e-7, near: 0.00000000040141, k: 20, fp: 0.00000000003905 },
];
const CHECK = (function () {
  const fails = [];
  // 1
  for (const m of MEASURED_BOX) {
    const sv = SAVES[m.save], s = m.save === 0 ? sv.centre : sv.surf, e = backed(s, m.d), o = buildOrbit(sv.P, e[0], e[1], e[2]);
    m.got = { near: o.distance, k: pertIters(sv.P, o, o.distance), fp: floorPert(sv.P, o), f32: floor32(sv.P, e) };
    if (!(Math.abs(o.distance - m.near) <= 1e-14) || !(Math.abs(m.got.fp - m.fp) <= 1e-14) || m.got.k !== m.k)
      fails.push(`${sv.name} at ${m.d}: near ${o.distance} (test ${m.near}), floor_pert ${m.got.fp} (test ${m.fp}), records ${m.got.k} (test ${m.k})`);
  }
  // 2
  for (const x of [-1.5, 0.2, 1.5]) for (const q of [-1.25, 0.5, 1.75]) {
    const want = (2 * clampf(q, -1, 1) - q) - (2 * clampf(x, -1, 1) - x), got = F64.pertClamp1(q - x, -1 - x, 1 - x);
    if (!(Math.abs(got - want) <= 1e-12)) fails.push(`pert_clamp X ${x} → P ${q}: ${got}, want ${want}`);
  }
  const sphF = (r2, mr2, fr2) => (r2 < mr2 ? fr2 / mr2 : r2 < fr2 ? fr2 / r2 : 1);
  for (const xa of [0.5, 0.85, 1.3]) for (const qa of [0.5, 0.85, 1.3]) {
    const x = [xa, 0.03, 0, 0], q = [qa, 0.04, 0.01, 0], x2 = xa * xa + 0.0009, q2 = qa * qa + 0.0016 + 0.0001;
    const mx = sphF(x2, 0.49, 1), mq = sphF(q2, 0.49, 1), dl = [q[0] - x[0], q[1] - x[1], q[2] - x[2], 0];
    const got = F64.pertSphere(dl, 1, x, x2 - 0.49, x2 - 1, 0.49, 1);
    const err = Math.max(...[0, 1, 2, 3].map(j => Math.abs(got.dl[j] - (mq * q[j] - mx * x[j]))));
    if (!(err < 1e-12) || !(Math.abs(got.dz - mq) <= 1e-12)) fails.push(`pert_sphere |X| ${xa} → |P| ${qa}: error ${err}, dz ${got.dz} (want ${mq})`);
  }
  // 3 (a fixed pseudo-random set of offsets, 1e-7 to 1e-1, as the test draws them)
  const P = SAVES[0].P, s = SAVES[0].surf, e = backed(s, 1e-3), X = buildOrbit(P, e[0], e[1], e[2]);
  let seed = 20261009, worst = 0;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
  for (let j = 0; j < 24; j++) {
    const v = [rnd() - 0.5, rnd() - 0.5, rnd() - 0.5], l = Math.hypot(...v), size = Math.pow(10, -7 + 6 * rnd());
    const off = v.map(c => c / l * size), Pp = buildOrbit(P, e[0] + off[0], e[1] + off[1], e[2] + off[2]), trace = [];
    F64.dePert(X, PERT_MAX, e, off, P, Infinity, trace);
    trace.forEach((dl, i) => {
      let err = 0, dmax = 0, xmax = 1;
      for (let c = 0; c < 4; c++) {
        const xv = X.pts[i + 1][c], pv = Pp.pts[i + 1][c];
        err = Math.max(err, Math.abs(dl[c] - (pv - xv))); dmax = Math.max(dmax, Math.abs(pv - xv)); xmax = Math.max(xmax, Math.abs(xv), Math.abs(pv));
      }
      worst = Math.max(worst, err / (1e-12 * X.mag[i + 1] * xmax + 1e-9 * dmax));
    });
  }
  if (!(worst <= 1)) fails.push(`the 64-bit perturbed offset strays from the direct orbit's (worst ${worst} of the test's tolerance)`);
  if (fails.length) {
    const msg = `[deep-zoom ports] ${fails.length} check(s) against tests/perturbation_test.gd fail: ${fails.join("; ")}`;
    console.error(msg);
    if (typeof VIZ !== "undefined" && Array.isArray(VIZ.errors)) VIZ.errors.push(msg);
  }
  return { fails, worst };
})();
const portOk = CHECK.fails.length === 0;

// ================================================================== shared drawing helpers
const fmt = (x, n = 3) => { if (!isFinite(x)) return String(x); const s = x.toFixed(n); return /^-0\.?0*$/.test(s) ? s.slice(1) : s; };
const sci = (x, n = 3) => (x === 0 ? "0" : !isFinite(x) ? String(x) : (Math.abs(x) >= 1e-3 && Math.abs(x) < 1e4) ? fmt(x, n + 1) : x.toExponential(n));
const e10 = x => `1e${x}`;
const pow10 = v => Math.pow(10, v);
const caps = "font-weight:600;letter-spacing:.06em";
const small = "font-size:10.5px";
const noPtr = "pointer-events:none";
const vec = (v, n = 3) => `(${v.map(x => sci(x, n)).join(", ")})`;
const maxAbs = v => Math.max(...v.map(Math.abs));

// A log-y chart frame: x linear over [x0, x1] (or log when xlog), y = log10 over [y0, y1].
// Returns { X, Y, g } mappers and its group; draws the grid and the decade labels.
function chartFrame(api, o) {
  const g = api.el("g", {});
  const X = v => o.x + (((o.xlog ? Math.log10(v) : v) - o.x0) / (o.x1 - o.x0)) * o.w;
  const Y = v => o.y + o.h - ((Math.log10(Math.max(v, 1e-300)) - o.y0) / (o.y1 - o.y0)) * o.h;
  const Yl = l => o.y + o.h - ((l - o.y0) / (o.y1 - o.y0)) * o.h;
  api.el("rect", { x: o.x, y: o.y, width: o.w, height: o.h, style: "fill:none;stroke:var(--hairline);stroke-width:1" }, g);
  for (let l = Math.ceil(o.y0); l <= o.y1; l += o.ystep || 1) {
    api.el("line", { x1: o.x, y1: Yl(l), x2: o.x + o.w, y2: Yl(l), style: "stroke:var(--hairline);stroke-width:.6" }, g);
    api.text(o.x - 6, Yl(l) + 4, e10(l), "muted", { "text-anchor": "end", style: small }, g);
  }
  for (const t of o.xticks || []) {
    const xx = o.xlog ? X(pow10(t)) : X(t);
    api.el("line", { x1: xx, y1: o.y + o.h, x2: xx, y2: o.y + o.h + 4, style: "stroke:var(--muted);stroke-width:1" }, g);
    api.text(xx, o.y + o.h + 16, o.xlog ? e10(t) : String(t), "muted", { "text-anchor": "middle", style: small }, g);
  }
  if (o.xlabel) api.text(o.x + o.w, o.y + o.h + 32, o.xlabel, "muted", { "text-anchor": "end", style: small }, g);
  if (o.ylabel) api.text(o.x, o.y - 8, o.ylabel, "muted", { style: small }, g);
  return { X, Y, Yl, g };
}
const pathOf = pts => pts.map((p, i) => `${i ? "L" : "M"} ${p[0].toFixed(2)} ${p[1].toFixed(2)}`).join(" ");

// A row of stage boxes across the top of a stepper (mandelbox.js's pattern).
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
function draggable(api, elem, onDrag) {
  elem.setAttribute("data-interactive", "");
  let drag = false;
  elem.addEventListener("mousedown", e => { e.stopPropagation(); e.preventDefault(); drag = true; });
  window.addEventListener("mousemove", e => { if (drag) onDrag(api.local(e)); });
  window.addEventListener("mouseup", () => { drag = false; });
}
// A row of toggle buttons where exactly one is on.
function radio(api, x, y, items, w, cur, onPick) {
  const hs = [];
  items.forEach((label, i) => {
    hs.push(api.button({ x: x + i * (w + 8), y, w, label, on: i === cur, onClick: () => { hs.forEach((h, k) => h.set(k === i)); onPick(i); } }));
  });
  return hs;
}

// ================================================================== 1. architecture graph
const arch = {
  type: "graph",
  tab: "Architecture",
  title: "Who works in 64-bit, who in 32",
  note: "The camera's eye and everything that measures from it now run in 64-bit doubles on the CPU: CameraState keeps the eye as three doubles (the Transform3D origin is only their rounded shadow), FlyCamera adds its step in 64-bit, CenterRay and Workspace read and write the doubles. Once per camera or shape change FractalView._push_near builds a ReferenceOrbit from that eye: the camera's own 32 iterates, how much each one magnifies, and for the first 20 iterations a record of small gaps. Those cross the bridge as uniforms. On the GPU, everything is float32: while `pert_iters > 0` the march iterates only each pixel's small offset from the reference orbit (perturbation) and hands off to the ordinary loop once the offset is big enough. With `pert_iters == 0`, the default view, the shader runs exactly the old arithmetic. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "cpu", label: "64-BIT CPU — GDSCRIPT FLOATS", x: 0, y: 0, w: 900, h: 560 },
    { id: "bridge", label: "THE BRIDGE — UNIFORMS (32-BIT)", x: 950, y: 0, w: 320, h: 560 },
    { id: "gpu", label: "FLOAT32 GPU — THE FRAGMENT SHADER", x: 1320, y: 0, w: 600, h: 560 },
    { id: "test", label: "TESTS — THE PROOF IN EMULATED FLOAT32", x: 0, y: 610, w: 1920, h: 130 },
  ],
  nodes: [
    { id: "ws", label: "Workspace", sub: "the eye saved at every digit", ctx: "cpu", zone: "cpu", x: 30, y: 60, w: 200, ...R("ws", 1),
      blurb: "Saves write `\"eye\"` from `eye64()` with no `_tidy` (which rounds to 7 significant figures; forward and up keep it), and `JSON.stringify(…, full_precision = true)`. A load calls `set_eye64`, then rebuilds the basis around the shadow, which keeps the doubles. The save format stays version 2: an old file is the same shape with fewer digits.",
      links: [RL("ws", 264, "_eye_to_array"), RL("ws", 116, "full-precision JSON"), RL("ws", 250, "restore: set_eye64"), RL("spec", 114, "spec, part 1")] },
    { id: "cam", label: "CameraState", sub: "eye_x/y/z (64-bit) · eye() the shadow", ctx: "cpu", zone: "cpu", x: 340, y: 60, w: 290, ...R("cam", 1),
      blurb: "The eye's truth is three doubles, `eye_x`, `eye_y`, `eye_z`. `transform.origin` is their 32-bit rounding, which every 32-bit consumer keeps reading through `eye()` (the `eye` uniform, the cube test, the orbit camera, project/unproject). `set_eye64` emits `changed` even when the shadow does not move. Assigning a transform whose origin is the shadow keeps the doubles, so rebuilding the basis never loses the eye.",
      links: [RL("cam", 44, "set_eye64"), RL("cam", 58, "eye64()"), RL("cam", 62, "eye(): the shadow"), RL("cam", 22, "the setter keeps the doubles")] },
    { id: "fly", label: "FlyCamera", sub: "64-bit step · move_allowed · base_speed", ctx: "cpu", zone: "cpu", x: 30, y: 180, w: 300, ...R("fly", 1),
      blurb: "Each physics tick adds `dir × step` to the 64-bit eye (below about 1e-6 a 32-bit origin could not move at all). `move_allowed` builds one ReferenceOrbit at the target eye, which gives both its distance and its zoom floor. The speed clamp floor dropped from 1e-6 to `SPEED_FLOOR = 1e-14`: the speed follows the distance, and must be able to fall below any floor.",
      links: [RL("fly", 89, "the step in 64-bit"), RL("fly", 103, "move_allowed"), RL("fly", 23, "SPEED_FLOOR"), RL("fly", 155, "base_speed")] },
    { id: "ray", label: "CenterRay", sub: "march_at from eye64", ctx: "cpu", zone: "cpu", x: 30, y: 300, w: 230, ...R("ray", 1),
      blurb: "The centre ray marches from the 64-bit eye: each sample `o + dir × t` is formed in doubles, so it resolves the surface below the 32-bit grid. The fly speed and the probe dot come from it.",
      links: [RL("ray", 79, "march_at"), RL("ray", 63, "_update reads eye64()"), RL("tRay", 119, "test: a hit at 1e-8")] },
    { id: "view", label: "FractalView._push_near", sub: "one ReferenceOrbit per change", ctx: "cpu", zone: "cpu", x: 630, y: 180, w: 250, ...R("view", 380),
      blurb: "Runs after every camera or shape push. Builds the orbit from `eye64()`; its `distance` is `near`, so the estimate is not computed twice. Pushes `near_dist`, `coarse_iters`, `nf_weight` as before, plus `pert_iters`; the five record arrays only while `pert_iters > 0`, so a still frame at depth pushes nothing more.",
      links: [RL("view", 384, "ReferenceOrbit.build"), RL("view", 389, "pert_iters"), RL("view", 391, "arrays only while on"), RL("tView", 141, "test: the pushes")] },
    { id: "orbit", label: "ReferenceOrbit.build", sub: "X_0..X_32 · λ_i · the record", ctx: "cpu", zone: "cpu", x: 630, y: 320, w: 240, ...R("orb", 46),
      blurb: "The camera eye's own orbit, the reference orbit, in 64-bit: `points` X_0 .. X_32, `mag` λ_0 .. λ_32 (how much i iterations magnify), and for the first `PERT_MAX = 20` iterations four vec4s of gaps (crease minus X, in 64-bit: small exactly when precision matters). `distance` equals `DistanceEstimator.estimate_at` at the eye exactly. Tabs 4 and 5 open it up.",
      links: [RL("orb", 70, "_mandelbox"), RL("orb", 142, "_fold_record"), RL("orb", 161, "_sphere_record"), RL("orb", 344, "_pack: the 32-bit copies"), RL("tOrbit", 16, "test: distance exact")] },
    { id: "params", label: "FractalParams", sub: "pert_iters · floor32 · floor_pert", ctx: "cpu", zone: "cpu", x: 290, y: 320, w: 250, ...R("params", 447),
      blurb: "`pert_iters(orbit, near)`: 0 (off) unless the shape is perturbable and `near < PERT_ON × floor32(eye)`, else `min(20, n)`. `floor32` is the old zoom floor, `ulp32(max |eye|) / (50 × eps)`. `floor_pert` is the same rule at the last handoff point X_K, where the view is λ_K times bigger. `zoom_floor_for` picks one; `NEAR_FLOOR` dropped to 1e-14.",
      links: [RL("params", 425, "floor32"), RL("params", 455, "floor_pert"), RL("params", 467, "zoom_floor_for"), RL("params", 433, "PERT_ON"), RL("params", 281, "NEAR_FLOOR")] },
    { id: "dest", label: "DistanceEstimator", sub: "the fold helpers it reuses", ctx: "cpu", zone: "cpu", x: 330, y: 460, w: 240, ...R("de", 1),
      blurb: "ReferenceOrbit calls its static `_fold`, `_sphere_fold` and `_rot_plane`, so the fold maths exists once; only the loop body is duplicated, and the `distance` equality test keeps the two honest. The estimator file itself was not touched.",
      links: [RL("de", 108, "_fold"), RL("de", 192, "_sphere_fold")] },

    { id: "uEye", label: "eye", sub: "vec3: the 32-bit shadow", ctx: "bridge", zone: "bridge", x: 980, y: 50, w: 260, ...R("view", 366),
      blurb: "Still `eye()`, the rounded shadow. On the perturbed path it is used only where a rough position is enough: the cube test, `v = eye + dir × total` for colour and fog, and the Mandelbrot-mode constant after the handoff." },
    { id: "uNear", label: "near_dist", sub: "max(distance, 1e-14)", ctx: "bridge", zone: "bridge", x: 980, y: 130, w: 260, ...R("view", 386),
      blurb: "The camera's distance to the nearest surface, clamped at `NEAR_FLOOR` = 1e-14 (was 1e-6, which would have frozen the level of detail and the fog exactly where perturbation starts to matter)." },
    { id: "uCoarse", label: "coarse_iters · nf_weight", sub: "follow near (tab 9)", ctx: "bridge", zone: "bridge", x: 980, y: 210, w: 260, ...R("view", 387),
      blurb: "The coarse pass's iteration count and the Ice Fractal normal's weight, both from `near`. Unchanged rules; tab 9 draws them.",
      links: [RL("view", 388, "nf_weight")] },
    { id: "uIters", label: "pert_iters", sub: "0 off · else min(20, n)", ctx: "bridge", zone: "bridge", x: 980, y: 290, w: 260, ...R("pert", 25),
      blurb: "The records available. 0 means the direct march, exactly as before. Each ray decides its own handoff from the size of its offset; this only caps it.",
      links: [RL("view", 390, "pushed")] },
    { id: "uRec", label: "pert_a · pert_b · pert_c · pert_d", sub: "vec4[20] each: the record", ctx: "bridge", zone: "bridge", x: 980, y: 370, w: 270, ...R("pert", 26),
      blurb: "Four vec4s per iteration (layout in the shader's header). For the box-fold Mandelbox: a = −L − X and b = L − X (the box fold's gaps), c = the sphere fold's input point, d = (|c|² − min_r², |c|² − fixed_r², the reference's factor m, the cylinder's radial gap).",
      links: [RL("pert", 15, "the record layout"), RL("view", 392, "pushed")] },
    { id: "uX", label: "pert_x", sub: "vec4[21]: the handoff points", ctx: "bridge", zone: "bridge", x: 980, y: 450, w: 260, ...R("pert", 30),
      blurb: "X_0 .. X_20 as 32-bit vec4s: the point a ray hands off to after h perturbed iterations. pert_x[0] is the eye, so a ray that hands off at once forms `eye + off`, today's expression.",
      links: [RL("view", 396, "pushed")] },

    { id: "frag", label: "fragment()", sub: "box_intersect · coarse · fine · shade", ctx: "gpu", zone: "gpu", x: 1350, y: 60, w: 290, ...R("sh", 420),
      blurb: "Per pixel: the cube test, the coarse pass (`coarse_iters` iterations), the fine pass (32), the normal, the colour. The only edits for perturbation: the two loops call `march_de` instead of `de`, and the normal is `true_normal`. Tab 3 walks it." },
    { id: "mde", label: "march_de", sub: "de_pert if pert_iters > 0, else de", ctx: "gpu", zone: "gpu", x: 1350, y: 180, w: 290, ...R("pert", 267),
      blurb: "The switch. `pos = eye + dir × total` (32-bit) is passed for the direct path, `off = dir × total` for the perturbed one; with `pert_iters == 0` it is exactly today's `de(pos, iters)`." },
    { id: "dep", label: "de_pert", sub: "perturbed steps, then hand off", ctx: "gpu", zone: "gpu", x: 1350, y: 300, w: 290, ...R("pert", 161),
      blurb: "Iterates the offset δ (a vec4, δ.w = 0) while `i < min(pert_iters, iters)` and `|δ| < PERT_HANDOFF = 0.1`, then forms `z = pert_x[h] + δ` in 32 bits and runs the ordinary loop from iteration h with the accumulated dz. Never forms `eye + off` for the orbit.",
      links: [RL("pert", 177, "the loop test"), RL("pert", 195, "the handoff"), RL("pert", 254, "de_pert(off, iters)")] },
    { id: "steps", label: "pert_clamp · pert_sphere", sub: "the difference formulas (tab 6)", ctx: "gpu", zone: "gpu", x: 1350, y: 420, w: 290, ...R("pert", 41),
      blurb: "Each step's δ' = f(X + δ) − f(X) written so that it never subtracts two nearly equal large numbers. The box fold is piecewise-linear, so only its creases need care; the sphere fold's factor difference m' − m is a small precise number over a product.",
      links: [RL("pert", 105, "pert_sphere"), RL("pert", 146, "pert_mb_fold")] },
    { id: "de", label: "de(p, iters)", sub: "today's direct estimate", ctx: "gpu", zone: "gpu", x: 1690, y: 180, w: 200, ...R("sh", 325),
      blurb: "The direct estimate at a 32-bit point. Its Mandelbox loop moved into `mb_orbit(z, dz, c, 0, iters)`: the same arithmetic in the same order, so the default view stays bit-for-bit." },
    { id: "mbo", label: "mb_orbit", sub: "the loop from iteration first", ctx: "gpu", zone: "gpu", x: 1690, y: 300, w: 200, ...R("sh", 298),
      blurb: "Iterations `first .. iters − 1` of the Mandelbox. The direct path runs it from 0, de_pert from its handoff h." },
    { id: "tn", label: "true_normal", sub: "calc_normal_pert or calc_normal", ctx: "gpu", zone: "gpu", x: 1690, y: 420, w: 200, ...R("pert", 283),
      blurb: "Central differences of `de_pert(off ± e)` while perturbing (six samples around `dir × total`), today's `calc_normal(v, delta)` otherwise.",
      links: [RL("pert", 273, "calc_normal_pert")] },

    { id: "port", label: "PerturbationPort", sub: "the shader in GDScript · float32 via r()", ctx: "test", zone: "test", x: 30, y: 660, w: 320, ...R("port", 1),
      blurb: "A line-for-line GDScript twin of the perturbed and direct estimates, run in emulated float32: every arithmetic result is rounded through a PackedFloat32Array (`r()`), which for + − × ÷ and √ is exactly the IEEE 32-bit result. This pane's ports copy it (Math.fround is the same rounding).",
      links: [RL("port", 52, "r()"), RL("port", 520, "de_pert")] },
    { id: "ptest", label: "perturbation_test", sub: "cases · algebra · agreement · floors", ctx: "test", zone: "test", x: 560, y: 660, w: 320, ...R("tPert", 1),
      blurb: "Four layers: every crossing case against the direct difference; whole orbits in 64-bit (the perturbed offset is the direct one, iteration by iteration); the float32 march agreement grid (tab 8's MEASURED); where the 64-bit reference itself stops hitting (tab 8's REFERENCE FLOOR).",
      links: [RL("tPert", 54, "the cases"), RL("tPert", 152, "the algebra check"), RL("tPert", 296, "the agreement grid"), RL("tPert", 362, "the reference floor")] },
    { id: "otest", label: "reference_orbit_test", sub: "distance == estimate_at, exactly", ctx: "test", zone: "test", x: 1100, y: 660, w: 300, ...R("tOrbit", 1),
      blurb: "For every shape variant: the orbit's distance equals the estimator's bit for bit, `mag` never decreases, `perturbable` is false only for the octahedral fold, the poly fold and the Mandelbulb.",
      links: [RL("tOrbit", 16, "distance"), RL("tOrbit", 19, "perturbable")] },
  ],
  edges: [
    { from: "fly", to: "cam", kind: "call", label: "set_eye64", ...R("fly", 94),
      blurb: "The accepted step, written as three doubles. The shadow follows by rounding." },
    { from: "fly", to: "orbit", kind: "call", label: "move_allowed", ...R("fly", 104), bow: 0.35,
      blurb: "One orbit at the target eye: accept if its distance is at least `zoom_floor_for(orbit)`, or no closer than the current eye (backing away is always allowed).",
      links: [RL("fly", 107, "backing away")] },
    { from: "fly", to: "params", kind: "call", label: "zoom_floor_for", ...R("fly", 105), bow: -0.2,
      blurb: "floor_pert for a perturbable shape, floor32 otherwise." },
    { from: "fly", to: "ray", kind: "data", label: "distance()", ...R("fly", 158),
      blurb: "The speed is min(centre-ray distance, 10 × near), both measured from the 64-bit eye, clamped to [1e-14, 20].", links: [RL("fly", 157, "near from eye64")] },
    { from: "ray", to: "cam", kind: "data", label: "eye64()", ...R("ray", 63), bow: -0.5,
      blurb: "The cached march re-runs after any camera or shape change, from the doubles." },
    { from: "ws", to: "cam", kind: "call", label: "set_eye64 · eye64", ...R("ws", 250),
      blurb: "Restore writes the doubles; capture reads them.", links: [RL("ws", 265, "capture")] },
    { from: "cam", to: "view", kind: "signal", label: "changed", ...R("view", 99),
      blurb: "`_on_camera_changed` → `_push_camera` → `_push_near`. CameraState emits on any change of the doubles.", links: [RL("view", 322, "_on_camera_changed"), RL("view", 370, "→ _push_near")] },
    { from: "view", to: "orbit", kind: "call", label: "build(eye64)", ...R("view", 384) },
    { from: "view", to: "params", kind: "call", label: "pert_iters", ...R("view", 389), bow: 0.2,
      blurb: "With the raw distance (not the clamped near)." },
    { from: "params", to: "orbit", kind: "call", label: "zoom_floor", ...R("params", 475), bow: 0,
      blurb: "`zoom_floor(eye64)` builds its own orbit; `zoom_floor_for(orbit)` takes one already built." },
    { from: "orbit", to: "dest", kind: "call", label: "_fold · _sphere_fold", ...R("orb", 114) },
    { from: "view", to: "uEye", kind: "data", ...R("view", 366), bow: 0.2 },
    { from: "view", to: "uNear", kind: "data", ...R("view", 386), bow: 0.15 },
    { from: "view", to: "uCoarse", kind: "data", ...R("view", 387), bow: 0.1 },
    { from: "view", to: "uIters", kind: "data", ...R("view", 390), bow: 0 },
    { from: "view", to: "uRec", kind: "data", label: "while on", ...R("view", 392), bow: -0.1 },
    { from: "view", to: "uX", kind: "data", ...R("view", 396), bow: -0.2 },
    { from: "uEye", to: "frag", kind: "data", label: "box_intersect", ...R("sh", 432) },
    { from: "uNear", to: "frag", kind: "data", label: "hit_eps", ...R("sh", 125), bow: 0.2 },
    { from: "uCoarse", to: "frag", kind: "data", ...R("sh", 448), bow: 0.3, links: [RL("sh", 496, "nf_weight")] },
    { from: "uIters", to: "mde", kind: "data", ...R("pert", 268) },
    { from: "uRec", to: "dep", kind: "data", label: "pert_a[i] …", ...R("pert", 178) },
    { from: "uX", to: "dep", kind: "data", label: "pert_x[h]", ...R("pert", 195), bow: -0.3 },
    { from: "frag", to: "mde", kind: "call", label: "coarse · fine", ...R("sh", 453), links: [RL("sh", 466, "the fine loop")] },
    { from: "frag", to: "tn", kind: "call", label: "normal", ...R("sh", 508), bow: -0.5 },
    { from: "mde", to: "dep", kind: "call", label: "pert_iters > 0", ...R("pert", 268) },
    { from: "mde", to: "de", kind: "call", label: "else", ...R("pert", 269) },
    { from: "dep", to: "steps", kind: "call", ...R("pert", 183), links: [RL("pert", 184, "pert_sphere")] },
    { from: "dep", to: "mbo", kind: "call", label: "from h", ...R("pert", 198) },
    { from: "de", to: "mbo", kind: "call", label: "from 0", ...R("sh", 333) },
    { from: "tn", to: "dep", kind: "call", label: "6 samples", ...R("pert", 276), bow: 0.4 },
    { from: "port", to: "dep", kind: "data", label: "mirrors", ...R("port", 3), bow: 0.15 },
    { from: "ptest", to: "port", kind: "call", ...R("tPert", 176) },
    { from: "ptest", to: "orbit", kind: "call", ...R("tPert", 163), bow: 0.3 },
    { from: "otest", to: "orbit", kind: "call", ...R("tOrbit", 16), bow: -0.3 },
  ],
};

// ================================================================== 2. why 32-bit breaks
const whyFig = {
  type: "figure",
  tab: "Why 32-bit breaks",
  title: "Why 32 bits break, and what perturbation buys",
  note: "A port of FractalParams.ulp32 and of ReferenceOrbit on the default box, in JS doubles. The camera sits d back from the default view's surface point, along its ray (SurfaceFixture.default_surface). The top strip: the view at the hit is 2 d tan 20° tall, the GPU forms every ray position as `eye + dir × t` in 32-bit floats, and near the eye those can only land on a grid ulp32 apart. Once the whole view is a few grid steps tall, hundreds of pixel rows share one position, and the hit threshold `eps × d` is far finer than the grid, so rays reach the surface only by luck. The chart: perturbation iterates the offset instead, and after i iterations the view has been magnified λ_i times while the grid at the reference point X_i stays about the same. A ray hands off to the 32-bit loop once its offset reaches 0.1; by then its view spans thousands of grid steps and its threshold sits well above the grid. The zoom guard asks the same at the last record K: the threshold λ_K × eps × d must stay above 50 grid steps, which is floor_pert.",
  w: 1500, h: 900,
  draw(api) {
    const sv = SAVES[0], P = sv.P, eps = epsOf(P);
    const S = { le: -6 };
    api.slider({ x: 20, y: 34, w: 520, label: "camera distance d (log10)", min: -10, max: -3, step: 0.1, value: S.le, fmt: v => `d = ${sci(pow10(v), 2)}`, onChange: v => { S.le = v; render(); } });
    const read = [];
    for (let i = 0; i < 3; i++) read.push(api.text(600, 22 + i * 19, "", "mono", { style: small }));
    // ---- the strip
    const BX = 20, BY = 130, BW = 1460, BH = 54, NPIX = 800;
    api.text(BX, BY - 26, "800 pixel rows of a view d away, coloured by the 32-bit value their ray position rounds to", "ink", { style: caps });
    api.text(BX, BY - 10, "positions W / 800 apart along x, near the eye's x (the largest coordinate); a new colour band starts where the 32-bit value changes", "muted", { style: small });
    const bandG = api.el("g", { style: noPtr });
    api.el("rect", { x: BX, y: BY, width: BW, height: BH, style: "fill:none;stroke:var(--muted);stroke-width:1" });
    const gridG = api.el("g", { style: noPtr });
    const stripTxt = [];
    for (let i = 0; i < 4; i++) stripTxt.push(api.text(BX, BY + BH + 22 + i * 19, "", "mono", { style: small }));
    const stripHit = api.el("rect", { x: BX, y: BY, width: BW, height: BH, style: "fill:transparent;cursor:help" });
    api.tip(stripHit, { title: "the float32 grid near the eye", ...R("params", 404), live: () => {
      const st = S.cur; if (!st) return {};
      return { sub: `${st.bands} distinct 32-bit positions for 800 rows`, blurb: `View height at the hit W = 2 d tan 20° = ${sci(st.W)}.\nGrid near x = ${fmt(st.x0, 4)}: ulp32 = ${sci(st.ulp)}.\nW / ulp32 = ${sci(st.W / st.ulp)} grid steps; ${sci(NPIX / Math.max(st.W / st.ulp, 1e-9))} pixel rows per step.\nHit threshold eps × d = ${sci(eps * st.d)} = ${sci(eps * st.d / st.ulp)} grid steps.` };
    } });
    // ---- the chart
    const CX = 80, CY = 330, CW = 900, CH = 470;
    api.text(20, 300, "after i perturbed iterations (λ_i from the eye's own orbit, the reference)", "ink", { style: caps });
    const ch = chartFrame(api, { x: CX, y: CY, w: CW, h: CH, x0: 0, x1: 32, y0: -14, y1: 6, ystep: 2, xticks: [0, 4, 8, 12, 16, 20, 24, 28, 32], xlabel: "iteration i", ylabel: "size (log scale)" });
    api.el("line", { x1: ch.X(PERT_MAX), y1: CY, x2: ch.X(PERT_MAX), y2: CY + CH, style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:4 4" });
    api.text(ch.X(PERT_MAX) + 4, CY + 14, "PERT_MAX = 20 records", "muted", { style: small });
    api.el("line", { x1: CX, y1: ch.Y(PERT_HANDOFF), x2: CX + CW, y2: ch.Y(PERT_HANDOFF), style: `stroke:${api.hue(4)};stroke-width:1.4;stroke-dasharray:6 3` });
    api.text(CX + 6, ch.Y(PERT_HANDOFF) - 5, "PERT_HANDOFF = 0.1", "", { style: `${small};fill:${api.hue(4)}` });
    const SER = [
      { key: "off", label: "a ray's offset at t = d, λ_i × d (the view, λ_i × W, is 0.73 of it)", hue: 1, w: 2.2 },
      { key: "thr", label: "the hit threshold, λ_i × eps × d", hue: 3, w: 2.2 },
      { key: "grid", label: "the grid at X_i, ulp32(max |X_i|)", hue: 2, w: 2.2 },
      { key: "grid50", label: "50 × that grid (ZOOM_FLOOR_DIVISOR)", hue: 2, w: 1.2, dash: "5 4" },
    ];
    const paths = SER.map(s => api.el("path", { style: `fill:none;stroke:${api.hue(s.hue)};stroke-width:${s.w};${s.dash ? `stroke-dasharray:${s.dash};` : ""}${noPtr}` }));
    const hMark = api.el("line", { y1: CY, y2: CY + CH, style: `stroke:${api.hue(4)};stroke-width:2;${noPtr}` });
    const hTxt = api.text(0, CY + CH - 8, "", "", { style: `${small};fill:${api.hue(4)};font-weight:600` });
    const dots = [];
    for (let i = 0; i <= 32; i++) {
      const c = api.el("circle", { r: 4, style: `fill:${api.hue(1)};stroke:var(--surface);stroke-width:1;cursor:pointer` });
      dots.push(c);
      api.tip(c, { title: `after ${i} iterations`, ...R("orb", 133), live: () => {
        const st = S.cur; if (!st) return {};
        const o = st.o, x = o.pts32[i], g = ulp32(maxAbs(x));
        return { sub: `λ_${i} = ${sci(o.mag[i])}`, blurb: `X_${i} = ${vec(o.pts[i])}\nview λ W = ${sci(o.mag[i] * st.W)} = ${sci(o.mag[i] * st.W / g)} grid steps at X_${i} (ulp32 ${sci(g)})\nthreshold λ eps d = ${sci(o.mag[i] * eps * st.d)} against 50 × grid = ${sci(50 * g)}\na ray at t = d: |δ| ≈ ${sci(o.mag[i] * st.d)}${o.mag[i] * st.d >= PERT_HANDOFF ? " (past the handoff)" : ""}` };
      } });
    }
    // legend + readout on the right
    const LX = 1010;
    SER.forEach((s, i) => {
      const y = CY + 10 + i * 24;
      api.el("line", { x1: LX, y1: y, x2: LX + 34, y2: y, style: `stroke:${api.hue(s.hue)};stroke-width:${s.w};${s.dash ? `stroke-dasharray:${s.dash}` : ""}` });
      api.text(LX + 42, y + 4, s.label, "", { style: small });
    });
    const out = [];
    for (let i = 0; i < 12; i++) out.push(api.text(LX, CY + 160 + i * 21, "", "mono", { style: small }));
    api.link(LX, CY + CH - 20, RL("params", 455, "floor_pert: the same rule at X_K"));
    api.link(LX, CY + CH, RL("spec", 43, "spec: the handoff in plain words"));

    function render() {
      const d = pow10(S.le), e = backed(sv.centre, d), o = buildOrbit(P, e[0], e[1], e[2]);
      const W = 2 * d * TAN_HALF_FOV, x0 = e[0], ulp = ulp32(maxAbs(e));
      // the strip: which 32-bit value each pixel row's position rounds to
      while (bandG.firstChild) bandG.removeChild(bandG.firstChild);
      while (gridG.firstChild) gridG.removeChild(gridG.firstChild);
      let bands = 0, start = 0, prev = null;
      const px = j => BX + (j / NPIX) * BW;
      const flush = (a, b) => {
        api.el("rect", { x: px(a), y: BY + 1, width: Math.max(px(b) - px(a), 0.6), height: BH - 2, style: `fill:${bands % 2 ? api.hue(6) : api.hue(1)};opacity:${bands % 2 ? 0.55 : 0.75}` }, bandG);
        bands++;
      };
      for (let j = 0; j < NPIX; j++) {
        const v = fr(x0 + (j / (NPIX - 1) - 0.5) * W);
        if (prev !== null && v !== prev) { flush(start, j); start = j; }
        prev = v;
      }
      flush(start, NPIX);
      const steps = W / ulp;
      if (steps < 80) {
        // the grid's own lines: 32-bit values inside the view
        const lo = x0 - W / 2, k0 = Math.ceil(lo / ulp), k1 = Math.floor((x0 + W / 2) / ulp);
        for (let k = k0; k <= k1; k++) {
          const xx = BX + ((k * ulp - lo) / W) * BW;
          api.el("line", { x1: xx, y1: BY - 4, x2: xx, y2: BY + BH + 4, style: "stroke:var(--ink);stroke-width:1" }, gridG);
        }
      }
      S.cur = { d, W, x0, ulp, bands, o };
      stripTxt[0].textContent = `W = 2 d tan 20° = ${sci(W)} · grid ulp32(${fmt(maxAbs(e), 3)}) = ${sci(ulp)} · W spans ${sci(steps)} grid steps${steps < 80 ? " (the lines: the 32-bit values)" : ""}`;
      stripTxt[1].textContent = `${bands} distinct positions for 800 rows: ${bands >= NPIX ? "every row its own" : `about ${fmt(NPIX / bands, 0)} rows share each one`}`;
      stripTxt[2].textContent = `hit threshold eps × d = ${sci(eps * d)}, ${sci(eps * d / ulp)} of a grid step · the old zoom floor floor32 = ulp32 / (50 eps) = ${sci(floor32(P, e))}`;
      stripTxt[3].textContent = d >= floor32(P, e) ? "above floor32: the 32-bit march still works here" : "below floor32: today's 32-bit march hits by luck (the perturbed one is what runs here)";
      stripTxt[3].style.fill = d >= floor32(P, e) ? api.hue(3) : api.hue(2);
      read[0].textContent = `eye = ${vec(e, 6)}  (the camera d back from the default view's surface point)`;
      read[1].textContent = `near (orbit.distance) = ${sci(o.distance)} · pert_iters = ${pertIters(P, o, o.distance)} (on below ${sci(PERT_ON * floor32(P, e))}) · floor_pert = ${sci(floorPert(P, o))}`;
      read[2].textContent = `eps = precision / detail = ${sci(eps)}`;
      // chart
      const series = { off: [], thr: [], grid: [], grid50: [] };
      for (let i = 0; i <= 32; i++) {
        const g = ulp32(maxAbs(o.pts32[i]));
        series.off.push([ch.X(i), ch.Y(o.mag[i] * d)]);
        series.thr.push([ch.X(i), ch.Y(o.mag[i] * eps * d)]);
        series.grid.push([ch.X(i), ch.Y(g)]);
        series.grid50.push([ch.X(i), ch.Y(50 * g)]);
        dots[i].setAttribute("cx", ch.X(i)); dots[i].setAttribute("cy", ch.Y(o.mag[i] * d));
      }
      SER.forEach((s, i) => paths[i].setAttribute("d", pathOf(series[s.key].map(p => [p[0], clampf(p[1], CY, CY + CH)]))));
      let h = o.mag.findIndex(l => l * d >= PERT_HANDOFF);
      const capped = h < 0 || h > PERT_MAX;
      if (capped) h = PERT_MAX;
      hMark.setAttribute("x1", ch.X(h)); hMark.setAttribute("x2", ch.X(h));
      hTxt.setAttribute("x", ch.X(h) + 5);
      hTxt.textContent = capped ? `records run out: hand off at h = ${h}` : `this ray hands off at h = ${h}`;
      const K = Math.min(PERT_MAX, o.n), gh = ulp32(maxAbs(o.pts32[h])), gK = ulp32(maxAbs(o.pts32[K])), thrK = o.mag[K] * eps * d;
      const L = [
        `at i = 0 (today): the view spans ${sci(W / ulp)} grid steps`,
        `   threshold ${sci(eps * d)} vs grid ${sci(ulp)}: ${eps * d >= 50 * ulp ? "fine" : "far finer than the grid"}`,
        `at the handoff h = ${h}: λ_h = ${sci(o.mag[h])}`,
        `   the view spans ${sci(o.mag[h] * W / gh)} grid steps at X_h`,
        `   threshold λ_h eps d = ${sci(o.mag[h] * eps * d)} (grid ${sci(gh)})`,
        ``,
        `the guard, at K = min(20, n) = ${K}:`,
        `   threshold λ_K eps d = ${sci(thrK)} vs 50 × grid = ${sci(50 * gK)}`,
        `   ${thrK >= 50 * gK ? "above it: d is above the zoom floor" : "below it: d is past the zoom floor"}`,
        `   floor_pert = ulp32(max |X_K|) / (50 eps λ_K) = ${sci(floorPert(P, o))}`,
        `rays also stop resolving where 32 iterations`,
        `   run out (not guarded; tab 8, REFERENCE FLOOR)`,
      ];
      L.forEach((s, i) => { out[i].textContent = s; });
      out[8].style.fill = thrK >= 50 * gK ? api.hue(3) : api.hue(2);
    }
    render();
  },
};

// ================================================================== 3. one frame at depth (seq)
const seq = {
  type: "seq",
  tab: "One frame at depth",
  title: "One frame at depth: from a 64-bit step to a perturbed pixel",
  note: "What happens, in order, when the fly camera takes a step close to the surface. The CPU side runs once per change: the 64-bit eye, one reference orbit, the uniforms (the five record arrays only while `pert_iters > 0`). The GPU side runs for every pixel: both march passes call `march_de`, which on this path is `de_pert`; the normal samples `de_pert` too. Nothing on the GPU forms `eye + dir × t` for the estimate; the rough 32-bit `v` is still used for colour, fog and the probe.",
  laneWidth: 200, headWidth: 186,
  boundaryAfterCol: 5, boundaryLabel: "GPU — every pixel",
  participants: [
    { id: "fly", col: 0, ctx: "cpu", name: "FlyCamera", sub: "_physics_process", ...R("fly", 77) },
    { id: "cs", col: 1, ctx: "cpu", name: "CameraState", sub: "eye_x/y/z", ...R("cam", 1) },
    { id: "view", col: 2, ctx: "cpu", name: "FractalView", sub: "_push_camera · _push_near", ...R("view", 1) },
    { id: "orb", col: 3, ctx: "cpu", name: "ReferenceOrbit", sub: "64-bit orbit + record", ...R("orb", 1) },
    { id: "pa", col: 4, ctx: "cpu", name: "FractalParams", sub: "pert_iters", ...R("params", 447) },
    { id: "mat", col: 5, ctx: "bridge", name: "ShaderMaterial", sub: "the uniforms", ...R("pert", 25) },
    { id: "frag", col: 6, ctx: "gpu", name: "fragment()", sub: "per pixel", ...R("sh", 420) },
    { id: "dep", col: 7, ctx: "gpu", name: "march_de · de_pert", sub: "the estimate", ...R("pert", 267) },
  ],
  rows: [
    { sec: "CPU — once per camera or shape change" },
    { from: "fly", to: "cs", kind: "call", label: "set_eye64(x, y, z)", tick: "e + dir × step, added in 64-bit", ...R("fly", 94),
      blurb: "The step is computed from the speed (which follows the distance) and added to the doubles; below about 1e-6 a 32-bit origin could not move.", links: [RL("fly", 89, "the 64-bit sum"), RL("fly", 90, "move_allowed first")] },
    { from: "cs", to: "view", kind: "signal", label: "changed → _on_camera_changed", tick: "even if the shadow did not move", ...R("view", 322),
      blurb: "`set_eye64` emits when any double differs.", links: [RL("cam", 53, "emit under the same shadow")] },
    { from: "view", to: "mat", kind: "data", label: "eye = eye()", tick: "the rounded shadow · cam_right/up/forward", ...R("view", 366),
      blurb: "The 32-bit eye, for everything that only needs a rough position." },
    { from: "view", to: "orb", kind: "call", label: "build(params, eye64)", ...R("view", 384),
      blurb: "From `_push_near`, which both `_push_camera` and `_push_params` end with." },
    { from: "orb", to: "orb", kind: "call", label: "32 iterations in 64-bit", tick: "X_i · λ_i · gaps for the first 20", ...R("orb", 108),
      blurb: "The loop body of DistanceEstimator.mandelbox_at, with the record written before each fold: the gaps from the fold's own input point.", links: [RL("orb", 113, "fold gaps"), RL("orb", 115, "λ: the sphere factor"), RL("orb", 133, "mag[i + 1]")] },
    { from: "view", to: "mat", kind: "data", label: "near_dist · coarse_iters · nf_weight", tick: "near = max(distance, 1e-14)", ...R("view", 385),
      blurb: "As before, now measured from the 64-bit eye and clamped at 1e-14 instead of 1e-6.", links: [RL("view", 386, "near_dist"), RL("view", 387, "coarse_iters"), RL("view", 388, "nf_weight")] },
    { from: "view", to: "pa", kind: "call", label: "pert_iters(orbit, distance)", tick: "0 unless near < 10 × floor32", ...R("view", 389),
      blurb: "Switching on an order of magnitude before the 32-bit march breaks means both agree within the hit threshold at the switch: no pop.", links: [RL("params", 448, "the rule")] },
    { from: "view", to: "mat", kind: "data", label: "pert_iters", ...R("view", 390) },
    { from: "view", to: "mat", kind: "data", label: "pert_a … pert_d · pert_x", tick: "4 × vec4[20] + vec4[21]", ...R("view", 392),
      blurb: "Only while perturbation is on; a still frame at depth pushes them once.", links: [RL("view", 396, "pert_x = X_0 .. X_20")] },
    { sec: "GPU — fragment() for every pixel" },
    { from: "frag", to: "frag", kind: "call", label: "box_intersect(eye, dir, box_half)", ...R("sh", 432), blurb: "The cube test needs no precision: it still uses the 32-bit eye." },
    { from: "frag", to: "dep", kind: "call", label: "march_de(pos, dir × total, n_coarse)", tick: "coarse pass: stop under 2 × hit_eps", ...R("sh", 453),
      blurb: "`pert_iters > 0`, so `de_pert(dir × total, n)`: only the offset is formed.", links: [RL("pert", 268, "the switch")] },
    { from: "dep", to: "dep", kind: "call", label: "perturbed steps on δ", tick: "while i < pert_iters and |δ| < 0.1", ...R("pert", 177),
      blurb: "Fold, sphere fold, (rotate,) scale, add, all on the offset, using the record's gaps. Tab 5 steps it.", links: [RL("pert", 183, "the fold"), RL("pert", 184, "the sphere fold"), RL("pert", 191, "scale and add")] },
    { from: "dep", to: "dep", kind: "call", label: "hand off: z = pert_x[h] + δ", tick: "then mb_orbit from h with the same dz", ...R("pert", 195),
      blurb: "By now |δ| is about 0.1, so the 32-bit sum keeps it precisely enough. A far ray (|δ_0| ≥ 0.1) hands off at h = 0: `eye + off`, today's expression.", links: [RL("pert", 198, "mb_orbit(z, dz, c, h, iters)")] },
    { from: "dep", to: "frag", kind: "data", label: "estimate: length(z) / |dz|", ...R("pert", 199) },
    { from: "frag", to: "dep", kind: "call", label: "march_de(pos, dir × total, 32)", tick: "fine pass: stop under hit_eps", ...R("sh", 466) },
    { from: "frag", to: "dep", kind: "call", label: "true_normal → calc_normal_pert", tick: "6 de_pert samples", ...R("sh", 508),
      blurb: "The central-difference normal, sampled on the offset.", links: [RL("pert", 284, "true_normal"), RL("pert", 276, "the samples")] },
    { from: "frag", to: "frag", kind: "call", label: "light, colour, fog", tick: "v = eye + dir × total (32-bit: rough is fine)", ...R("sh", 515),
      links: [RL("sh", 485, "v"), RL("sh", 570, "COLOR")] },
  ],
  fragments: [
    { type: "opt", rows: [9, 9], cols: [2, 5], guard1: "pert_iters > 0" },
    { type: "loop", rows: [12, 15], cols: [6, 7], guard1: "each coarse step" },
    { type: "loop", rows: [16, 16], cols: [6, 7], guard1: "each fine step" },
  ],
};

// ================================================================== 4. the reference orbit
const RECORD_SLOTS = [
  { k: "a", name: "a: lower gaps", comps: ["−L − X.x", "−L − X.y", "−L − X.z", "−L − X.w"], what: "the box fold's lower crease minus the fold's input X, per component (negative: X is above the crease)" },
  { k: "b", name: "b: upper gaps", comps: ["L − X.x", "L − X.y", "L − X.z", "L − X.w"], what: "the upper crease minus X (negative: X is past +L and gets reflected)" },
  { k: "c", name: "c: sphere input", comps: ["Xs.x", "Xs.y", "Xs.z", "Xs.w"], what: "the sphere fold's input point Xs (after the box fold): the pixel's radial step needs X itself" },
  { k: "d", name: "d: sphere gaps", comps: ["|Xs|² − min_r²", "|Xs|² − fixed_r²", "m", "cylinder r − L"], what: "the two radial gaps, the reference's own factor m, and the cylinder fold's radial gap (0 for the box fold)" },
];
const orbitFig = {
  type: "figure",
  tab: "The reference orbit",
  title: "The reference orbit: the eye's 32 iterates and the record",
  note: "A port of ReferenceOrbit.build (the box-fold Mandelbox) in JS doubles. For each save the camera sits d back from the surface point SurfaceFixture.surface_from finds marching from the default eye toward the origin. The chart is the eye's own orbit: λ_i (how much i iterations magnify) and the size of X_i. Close to the surface the eye's orbit stays near the box for many iterations; the further back the camera, the sooner it escapes and runs off. For the first 20 iterations the CPU writes four vec4s, the record: gaps between each crease and X, worked out in 64-bit, so they are small exactly when precision matters, and a 32-bit float holds a small number to the same relative precision as a large one. Click a record cell to read it; hover a dot for X_i.",
  w: 1500, h: 820,
  draw(api) {
    const S = { save: 0, le: -6, sel: 0 };
    radio(api, 20, 16, SAVES.map(s => s.name), 120, 0, i => { S.save = i; render(); });
    api.slider({ x: 440, y: 28, w: 380, label: "camera distance d (log10)", min: -10, max: -3, step: 0.1, value: S.le, fmt: v => `d = ${sci(pow10(v), 2)}`, onChange: v => { S.le = v; render(); } });
    const head = [];
    for (let i = 0; i < 4; i++) head.push(api.text(20, 74 + i * 19, "", "mono", { style: small }));
    // chart
    const CX = 80, CY = 190, CW = 640, CH = 440;
    const ch = chartFrame(api, { x: CX, y: CY, w: CW, h: CH, x0: 0, x1: 32, y0: -2, y1: 14, ystep: 2, xticks: [0, 4, 8, 12, 16, 20, 24, 28, 32], xlabel: "iteration i", ylabel: "log scale" });
    api.el("line", { x1: ch.X(PERT_MAX), y1: CY, x2: ch.X(PERT_MAX), y2: CY + CH, style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:4 4" });
    api.text(ch.X(PERT_MAX) + 4, CY + 14, "records end (PERT_MAX)", "muted", { style: small });
    const lamP = api.el("path", { style: `fill:none;stroke:${api.hue(1)};stroke-width:2.2;${noPtr}` });
    const xP = api.el("path", { style: `fill:none;stroke:${api.hue(2)};stroke-width:2.2;${noPtr}` });
    const selLine = api.el("line", { y1: CY, y2: CY + CH, style: `stroke:${api.hue(4)};stroke-width:2;${noPtr}` });
    const lamD = [], xD = [];
    for (let i = 0; i <= 32; i++) {
      for (const [arr, hue, what] of [[lamD, 1, "λ"], [xD, 2, "|X|"]]) {
        const c = api.el("circle", { r: 4, style: `fill:${api.hue(hue)};stroke:var(--surface);stroke-width:1;cursor:pointer` });
        arr.push(c);
        api.tip(c, { title: `X_${i}, the eye after ${i} iterations`, ...R("orb", 134), live: () => {
          const o = S.o; if (!o) return {};
          return { sub: `${what} · λ_${i} = ${sci(o.mag[i])}`, blurb: `X_${i} = ${vec(o.pts[i], 6)}\nmax |X_${i}| = ${sci(maxAbs(o.pts[i]))}, as pert_x (32-bit): ${vec(o.pts32[i], 6)}\nλ_${i} = ${sci(o.mag[i], 6)}: a neighbourhood ${sci(pow10(S.le))} wide is ${sci(o.mag[i] * pow10(S.le))} wide after ${i} iterations${i <= PERT_MAX ? `\npert_x[${i}]: a ray that hands off after ${i} perturbed iterations starts the ordinary loop here` : ""}` };
        } });
        c.addEventListener("click", () => { if (i < PERT_MAX) { S.sel = i; render(); } });
      }
    }
    api.el("line", { x1: CX + 10, y1: CY + CH + 46, x2: CX + 40, y2: CY + CH + 46, style: `stroke:${api.hue(1)};stroke-width:2.2` });
    api.text(CX + 46, CY + CH + 50, "λ_i, the magnification (orbit.mag)", "", { style: small });
    api.el("line", { x1: CX + 300, y1: CY + CH + 46, x2: CX + 330, y2: CY + CH + 46, style: `stroke:${api.hue(2)};stroke-width:2.2` });
    api.text(CX + 336, CY + CH + 50, "max |X_i| (orbit.points)", "", { style: small });
    // record strip
    const RX = 780, RY = 190, CWl = 66, CHl = 44;
    api.text(RX, RY - 14, "the record, iterations 0 .. 19 (click one)", "ink", { style: caps });
    api.text(RX, RY - 30, "each cell: the reference's sphere regime (in / shell / out) and its nearest box-fold gap", "muted", { style: small });
    const cells = [];
    for (let i = 0; i < PERT_MAX; i++) {
      const x = RX + (i % 10) * (CWl + 4), y = RY + Math.floor(i / 10) * (CHl + 4);
      const r = api.el("rect", { x, y, width: CWl, height: CHl, rx: 5, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:pointer" });
      const t1 = api.text(x + 6, y + 16, String(i), "mono", { style: `font-weight:700;${noPtr}` });
      const t2 = api.text(x + 6, y + 34, "", "", { style: `${small};${noPtr}` });
      cells.push({ r, t1, t2 });
      r.addEventListener("click", () => { S.sel = i; render(); });
      api.tip(r, { title: `record ${i}`, ...R("orb", 142), live: () => {
        const o = S.o; if (!o) return {};
        return { sub: `pert_a[${i}] … pert_d[${i}]`, blurb: RECORD_SLOTS.map(sl => `${sl.k} = ${vec(o[sl.k][i], 4)}`).join("\n") + `\n${describeRecord(o, i, SAVES[S.save].P).join("\n")}`, links: [RL("orb", 161, "_sphere_record")] };
      } });
    }
    // the selected record
    const DY = RY + 2 * (CHl + 4) + 30;
    const selHead = api.text(RX, DY, "", "ink", { style: caps });
    const slotRows = RECORD_SLOTS.map((sl, si) => {
      const y = DY + 28 + si * 64;
      api.text(RX, y, sl.name, "ink", { style: "font-weight:600" });
      api.text(RX + 130, y, sl.what, "muted", { style: small });
      const vals = sl.comps.map((cn, ci) => {
        api.text(RX + ci * 175, y + 20, cn, "muted", { style: "font-size:10px" });
        return api.text(RX + ci * 175, y + 37, "", "mono", { style: small });
      });
      return vals;
    });
    const desc = [];
    for (let i = 0; i < 4; i++) desc.push(api.text(RX, DY + 300 + i * 19, "", "", { style: small }));
    api.link(RX, DY + 390, RL("pert", 15, "the record layout (shader header)"));
    api.link(RX + 300, DY + 390, RL("spec", 147, "spec: the record table"));

    function render() {
      const sv = SAVES[S.save], P = sv.P, d = pow10(S.le), e = backed(sv.surf, d), o = buildOrbit(P, e[0], e[1], e[2]);
      S.o = o;
      const k = pertIters(P, o, o.distance);
      head[0].textContent = `eye = ${vec(e, 9)}   (surface point ${vec(sv.surf.slice(0, 3), 6)} backed off d)`;
      head[1].textContent = `orbit.distance = near = ${sci(o.distance)}   ·   n = ${o.n}   ·   perturbable: ${o.perturbable}`;
      head[2].textContent = `pert_iters = ${k} ${k ? "(on: near < 10 × floor32 = " + sci(PERT_ON * floor32(P, e)) + ")" : "(off: near ≥ 10 × floor32 = " + sci(PERT_ON * floor32(P, e)) + ")"}`;
      head[3].textContent = `floor32 = ${sci(floor32(P, e))}   ·   floor_pert = ulp32(max |X_20|) / (50 eps λ_20) = ${sci(floorPert(P, o))}`;
      const lamPts = [], xPts = [];
      for (let i = 0; i <= 32; i++) {
        const yl = clampf(ch.Y(o.mag[i]), CY, CY + CH), yx = clampf(ch.Y(maxAbs(o.pts[i])), CY, CY + CH);
        lamPts.push([ch.X(i), yl]); xPts.push([ch.X(i), yx]);
        lamD[i].setAttribute("cx", ch.X(i)); lamD[i].setAttribute("cy", yl);
        xD[i].setAttribute("cx", ch.X(i)); xD[i].setAttribute("cy", yx);
      }
      lamP.setAttribute("d", pathOf(lamPts)); xP.setAttribute("d", pathOf(xPts));
      selLine.setAttribute("x1", ch.X(S.sel)); selLine.setAttribute("x2", ch.X(S.sel));
      for (let i = 0; i < PERT_MAX; i++) {
        const c = cells[i], dd = o.d[i];
        const rx = dd[0] < 0 ? "in" : dd[1] < 0 ? "shell" : "out";
        const gap = Math.min(...[0, 1, 2, 3].map(a => Math.min(Math.abs(o.a[i][a]), Math.abs(o.b[i][a]))));
        c.t2.textContent = `${rx} ${gap.toExponential(0)}`;
        c.r.setAttribute("style", `fill:var(--surface);stroke:${i === S.sel ? api.hue(4) : "var(--hairline)"};stroke-width:${i === S.sel ? 2.6 : 1.2};cursor:pointer`);
      }
      const i = S.sel;
      selHead.textContent = `record ${i}: the fold's input X_${i} → after the box fold → the sphere fold's input`;
      RECORD_SLOTS.forEach((sl, si) => slotRows[si].forEach((t, ci) => { t.textContent = sci(o[sl.k][i][ci], 5); }));
      const ds = describeRecord(o, i, P);
      desc.forEach((t, j) => { t.textContent = ds[j] || ""; });
    }
    render();
  },
};
// Plain words for record i: which side of each crease the reference is, its sphere regime.
function describeRecord(o, i, P) {
  const a = o.a[i], b = o.b[i], dd = o.d[i];
  const past = [0, 1, 2, 3].filter(c => a[c] > 0 || b[c] < 0).map(c => "xyzw"[c]);
  const near = [0, 1, 2, 3].map(c => Math.min(Math.abs(a[c]), Math.abs(b[c])));
  const nc = near.indexOf(Math.min(...near));
  const rx = dd[0] < 0 ? "inside the min sphere (m = fixed²/min²)" : dd[1] < 0 ? "in the shell: inverted (m = fixed²/|Xs|²)" : "outside both spheres (m = 1)";
  return [
    `box fold: ${past.length ? `X is past the crease on ${past.join(", ")} (reflected)` : "X is inside the box on every component"}; the nearest crease is ${sci(near[nc])} away on ${"xyzw"[nc]}`,
    `sphere fold: |Xs|² − min_r² = ${sci(dd[0])}, |Xs|² − fixed_r² = ${sci(dd[1])}: ${rx}, m = ${sci(dd[2], 5)}`,
    `as the shader holds them (32-bit): the nearest gap ${sci(fr(near[nc]))}, its relative error ${sci(Math.abs(fr(near[nc]) - near[nc]) / Math.max(near[nc], 1e-300), 1)}`,
    `X_${i + 1} = ${vec(o.pts[i + 1], 5)} · λ_${i + 1} = ${sci(o.mag[i + 1])}`,
  ];
}

// ================================================================== 5. δ step by step
// One pixel's offset through the perturbed iterations, stage by stage, three ways: the exact offset
// P − X in 64-bit (the pixel's own orbit minus the reference's), the shader's perturbed float32
// offset (the port), and what today's direct float32 path effectively has (its 32-bit pixel orbit
// minus the 64-bit reference). kind: start | fold | sphere | rotate | scale | add | handoff.
function deltaStages(sv, d, rayIdx, noHandoff) {
  const P = sv.P, surf = sv.centre || sv.surf, eye = backed(surf, d), o = buildOrbit(P, eye[0], eye[1], eye[2]);
  const k = pertIters(P, o, o.distance) || PERT_MAX;   // the figure perturbs even where the view would not
  const f = [surf[3], surf[4], surf[5]];
  let dir = f;
  if (rayIdx === 1) {
    // one of the test's fan directions (perturbation_test.gd:228-239: ia = ib = 1, a third of the field), in doubles
    const rt = [f[1], -f[0], 0], rl = Math.hypot(...rt), right = rt.map(v => v / rl);
    const up = [right[1] * f[2] - right[2] * f[1], right[2] * f[0] - right[0] * f[2], right[0] * f[1] - right[1] * f[0]];
    const du = 1.37 * 0.5 / 3 * TAN_HALF_FOV, dv = 1.21 * 0.5 / 3 * TAN_HALF_FOV;
    const v = [0, 1, 2].map(a => f[a] + right[a] * du + up[a] * dv), l = Math.hypot(...v);
    dir = v.map(c => fr(c / l));
  }
  const t = rayIdx === 2 ? 0.3 : march64(eye, dir, P).t;
  const off = dir.map(c => c * t);
  const R = fr, u = fr, s32 = fr(P.box_scale), L32 = fr(P.fold_limit), s = P.box_scale, L = P.fold_limit;
  const mr2_32 = Math.max(fr(u(P.min_radius) * u(P.min_radius)), u(1e-12)), fr2_32 = Math.max(fr(u(P.fixed_radius) * u(P.fixed_radius)), u(1e-12));
  const mr2 = P.min_radius * P.min_radius, fr2 = P.fixed_radius * P.fixed_radius;
  // exact: the pixel's and the reference's orbits in doubles
  const pz0 = [eye[0] + off[0], eye[1] + off[1], eye[2] + off[2], P.w];
  let Pz = pz0.slice(), Xz = o.pts[0].slice();
  const cP = constant64(pz0, P), cX = constant64(o.pts[0], P);
  // perturbed f32
  let dl = [R(off[0]), R(off[1]), R(off[2]), 0];
  const dc = [P.jOn[0] ? 0 : dl[0], P.jOn[1] ? 0 : dl[1], P.jOn[2] ? 0 : dl[2], 0];
  let dzP = 1;
  // direct f32
  const eye32 = eye.map(fr), p32 = [R(eye32[0] + dl[0]), R(eye32[1] + dl[1]), R(eye32[2] + dl[2]), R(P.w)];
  let Dz = p32.slice(), dzD = 1;
  const cD = F32.constant(p32, P);
  let dzX = 1;
  const diff = (a, b) => [0, 1, 2, 3].map(c => a[c] - b[c]);
  const out = [];
  const push = (kind, it, extra) => out.push(Object.assign({ kind, it, ex: diff(Pz, Xz), pf: dl.slice(), dr: diff(Dz, Xz), X: Xz.slice(), dzP, dzX }, extra || {}));
  push("start", 0);
  const hh = R(R(PERT_HANDOFF) * R(PERT_HANDOFF));
  let h = 0;
  for (let i = 0; i < Math.min(k, 32); i++) {
    if (!noHandoff && F32.dot4(dl, dl) >= hh) break;
    const ra = o.a32[i], rb = o.b32[i], rc = o.c32[i], rd = o.d32[i];
    // fold
    const sideX = [0, 1, 2, 3].map(c => (o.a[i][c] > 0 ? -1 : o.b[i][c] < 0 ? 1 : 0));
    const sideP = [0, 1, 2, 3].map(c => (dl[c] < ra[c] ? -1 : dl[c] > rb[c] ? 1 : 0));
    dl = F32.pertClamp(dl, ra, rb);
    boxFold64(Pz, L); boxFold64(Xz, L); Dz = F32.boxFold(Dz, L32);
    push("fold", i, { sideX, sideP, cross: [0, 1, 2, 3].filter(c => sideX[c] !== sideP[c]), ga: o.a[i], gb: o.b[i] });
    // sphere
    const sp = F32.pertSphere(dl, dzP, rc, rd[0], rd[1], mr2_32, fr2_32);
    dl = sp.dl; dzP = sp.dz;
    const fXs = sphereFactor64(r2of(Xz), mr2, fr2);
    sphereFold64(Pz, 1, mr2, fr2); dzX *= fXs; sphereFold64(Xz, 1, mr2, fr2);
    const sd = F32.sphereFold(Dz, dzD, P); Dz = sd.p; dzD = sd.dz;
    push("sphere", i, { rx: sp.rx, rp: sp.rp, mp: sp.mp, dm: sp.dm, q: sp.q, m: o.d[i][2], gmin: o.d[i][0], gfix: o.d[i][1] });
    // rotate: these saves have no iteration rotation (mb_rotating() is false), so δ passes through
    push("rotate", i, { skipped: true });
    // scale
    dl = F32.scale4(s32, dl);
    for (let c = 0; c < 4; c++) { Pz[c] = s * Pz[c]; Xz[c] = s * Xz[c]; }
    Dz = F32.scale4(s32, Dz);
    push("scale", i);
    // add
    dl = F32.add4(dl, dc);
    for (let c = 0; c < 4; c++) { Pz[c] += cP[c]; Xz[c] += cX[c]; }
    Dz = F32.add4(Dz, cD);
    dzP = R(R(dzP * Math.abs(s32)) + 1); dzX = dzX * Math.abs(s);
    push("add", i);
    h = i + 1;
  }
  // the handoff: z = pert_x[h] + δ, then the ordinary loop from h
  const res = F32.dePert(o, k, eye, off, P, noHandoff ? Infinity : PERT_HANDOFF);
  const truth = deMB(pz0[0], pz0[1], pz0[2], P), direct = F32.deDirect(p32, P);
  out.push({ kind: "handoff", it: h, ex: diff(Pz, Xz), pf: dl.slice(), dr: diff(Dz, Xz), X: Xz.slice(), h, dzP, dzX,
    zh: F32.add4(o.pts32[h], dl), est: { truth, pert: res.de, direct } });
  return { stages: out, o, eye, dir, t, off, k, h, P, d };
}
const STAGE_INFO = {
  fold: { n: "1", name: "Box fold", f: "δ' from the gaps g_lo, g_hi", hue: 2, shader: 183, inc: 41, gd: 553, gdf: 354 },
  sphere: { n: "2", name: "Sphere fold", f: "δ' = m' δ + X (m' − m)", hue: 5, shader: 184, inc: 105, gd: 554, gdf: 443 },
  rotate: { n: "3", name: "Rotate", f: "the same rotation on δ", hue: 6, shader: 189, inc: 189, gd: 562, gdf: 131 },
  scale: { n: "4", name: "Scale", f: "δ' = s δ", hue: 1, shader: 191, inc: 190, gd: 565, gdf: 74 },
  add: { n: "5", name: "Add", f: "δ' = δ + δc", hue: 3, shader: 191, inc: 166, gd: 565, gdf: 70 },
  handoff: { n: "H", name: "Hand off", f: "z = pert_x[h] + δ", hue: 4, shader: 195, inc: 198, gd: 570, gdf: 572 },
};
const stepFig = {
  type: "figure",
  tab: "δ step by step",
  title: "δ step by step: one pixel's offset, three ways",
  note: "A JS port of perturbation.gdshaderinc's `pert_clamp`, `pert_sphere` and the Mandelbox `de_pert` loop (= tests/perturbation_port.gd), in float32 (Math.fround after every operation, as the port's r()), beside the same pixel in 64-bit and on today's direct float32 path. The camera sits d back from the save's surface point; the pixel is a ray of that view at its own 64-bit hit distance t (or a far sample at t = 0.3), so its starting offset is δ_0 = dir × t. Step walks one stage at a time: the left panel is the frame the stage reads, the right the frame it writes. Columns: 64-bit exact (the pixel's own orbit minus the reference's), float32 perturbed (what the shader computes), float32 direct (today's 32-bit pixel point minus the reference: what the old path effectively had). An orange flag marks a crossing: the pixel and the reference on different sides of a crease. The stepper perturbs even where the real view would still run direct (pert_iters 0), so every depth can be stepped.",
  w: 1560, h: 970,
  draw(api) {
    const S = { save: 0, di: 1, ray: 0, noHand: false, k: 0 };
    const DEPTHS = [1e-5, 1e-6, 1e-7, 1e-8];
    let run = null;
    const STAGES = ["fold", "sphere", "rotate", "scale", "add", "handoff"];
    const stages = stageRow(api, 20, 16, 240, 10, STAGES.map(kd => {
      const si = STAGE_INFO[kd];
      return { n: si.n, name: si.name, f: si.f, color: api.hue(si.hue),
        tip: { ...R("pert", si.shader), blurb: stageBlurb(kd), links: [RL("pert", si.inc, "the shader function"), RL("port", si.gd, "GDScript: the port's line"), RL("port", si.gdf, "GDScript: the port's function")] } };
    }));
    const head = api.text(20, 100, "", "ink", { style: caps });
    const sub = api.text(20, 120, "", "muted", { style: small });
    // ---- the two frames
    const COLS = [{ key: "ex", label: "64-bit exact", hue: 3 }, { key: "pf", label: "float32 perturbed", hue: 1 }, { key: "dr", label: "float32 direct", hue: 2 }];
    function framePanel(x0, title) {
      api.el("rect", { x: x0, y: 140, width: 740, height: 230, rx: 8, style: "fill:none;stroke:var(--hairline);stroke-width:1" });
      const t = api.text(x0 + 14, 162, title, "ink", { style: caps });
      COLS.forEach((c, ci) => api.text(x0 + 110 + ci * 210, 186, c.label, "", { style: `font-weight:600;fill:${api.hue(c.hue)}` }));
      const rowsL = ["δ.x", "δ.y", "δ.z", "δ.w", "|δ|", "rel. error"];
      const cells = rowsL.map((rl, ri) => {
        api.text(x0 + 14, 210 + ri * 25, rl, "mono", { style: small });
        return COLS.map((c, ci) => {
          const tx = api.text(x0 + 110 + ci * 210, 210 + ri * 25, "", "mono", { style: small });
          return tx;
        });
      });
      const hit = api.el("rect", { x: x0 + 100, y: 192, width: 630, height: 160, style: "fill:transparent;cursor:help" });
      return { t, cells, hit };
    }
    const RD = framePanel(20, ""), WR = framePanel(800, "");
    const tipFrame = (panel, which) => api.tip(panel.hit, { title: which === 0 ? "the frame this stage reads" : "the frame this stage writes", ...R("pert", 177), live: () => {
      if (!run) return {};
      const st = which === 0 ? prevStage() : cur();
      if (!st) return {};
      return { sub: stageName(st), blurb: COLS.map(c => `${c.label}: ${vec(st[c.key], 9)}`).join("\n") + `\nthe reference X here: ${vec(st.X, 9)}\nfloat32 perturbed vs exact: ${sci(relErr(st.pf, st.ex), 2)} · float32 direct vs exact: ${sci(relErr(st.dr, st.ex), 2)}` };
    } });
    tipFrame(RD, 0); tipFrame(WR, 1);
    // ---- what this stage did
    const info = [];
    for (let i = 0; i < 6; i++) info.push(api.text(20, 400 + i * 20, "", "mono", { style: small }));
    // ---- per-iteration table and chart
    const TY = 545;
    api.text(20, TY, "after each iteration (the add stage)", "ink", { style: caps });
    const TH = ["i", "|δ| exact", "f32 perturbed err", "f32 direct err", "crossings"];
    const TXc = [20, 70, 210, 360, 500];
    TH.forEach((hd, i) => api.text(TXc[i], TY + 22, hd, "muted", { style: small }));
    const trows = [];
    for (let r = 0; r < 14; r++) trows.push(TXc.map(x => api.text(x, TY + 44 + r * 19, "", "mono", { style: small })));
    const CX = 840, CY = 560, CW = 680, CH = 280;
    const ch = chartFrame(api, { x: CX, y: CY, w: CW, h: CH, x0: 0, x1: 20, y0: -10, y1: 2, ystep: 2, xticks: [0, 5, 10, 15, 20], xlabel: "iteration", ylabel: "relative error of the offset against the 64-bit one, after each iteration (log)" });
    api.el("line", { x1: CX, y1: ch.Y(1), x2: CX + CW, y2: ch.Y(1), style: "stroke:var(--muted);stroke-width:1;stroke-dasharray:6 3" });
    api.text(CX + CW - 4, ch.Y(1) - 5, "100%: no digit right", "muted", { "text-anchor": "end", style: small });
    const chP = COLS.map(c => api.el("path", { style: `fill:none;stroke:${api.hue(c.hue)};stroke-width:2.2;${c.key === "ex" ? "display:none;" : ""}${noPtr}` }));
    const hLine = api.el("line", { y1: CY, y2: CY + CH, style: `stroke:${api.hue(4)};stroke-width:1.6;stroke-dasharray:5 3;${noPtr}` });
    const hTxt = api.text(0, CY + 14, "", "", { style: `${small};fill:${api.hue(4)}` });
    const curMark = api.el("line", { y1: CY, y2: CY + CH, style: `stroke:var(--ink);stroke-width:1;opacity:.5;${noPtr}` });
    COLS.slice(1).forEach((c, i) => {
      api.el("line", { x1: CX + 10 + i * 220, y1: CY + CH + 44, x2: CX + 40 + i * 220, y2: CY + CH + 44, style: `stroke:${api.hue(c.hue)};stroke-width:2.2` });
      api.text(CX + 46 + i * 220, CY + CH + 48, c.label, "", { style: small });
    });
    // ---- controls
    const BY = 900;
    let bx = 20;
    const btn = (label, w, onClick, on) => { const b = api.button({ x: bx, y: BY, w, label, on, onClick }); bx += w + 8; return b; };
    api.text(bx, BY + 17, "Offset", "ink"); bx += 54;
    btn("◀ Back", 74, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn("Step ▶", 74, () => { S.k = Math.min(run.stages.length - 1, S.k + 1); render(); });
    btn("+1 iteration", 100, () => { const n = run.stages.findIndex((st, j) => j > S.k && (st.kind === "add" || st.kind === "handoff")); S.k = n < 0 ? run.stages.length - 1 : n; render(); });
    btn("To the handoff ▶▶", 140, () => { S.k = run.stages.length - 1; render(); });
    btn("Reset", 66, () => { S.k = 0; render(); });
    bx += 20;
    btn("No handoff (the algebra check)", 230, b => { S.noHand = !S.noHand; b.set(S.noHand); rebuild(); });
    api.text(20, BY + 60, "Save", "ink");
    radio(api, 70, BY + 43, SAVES.map(s => s.name), 110, 0, i => { S.save = i; rebuild(); });
    api.text(460, BY + 60, "d", "ink");
    radio(api, 480, BY + 43, DEPTHS.map(d => `d = ${sci(d, 0)}`), 90, S.di, i => { S.di = i; rebuild(); });
    api.text(890, BY + 60, "Pixel", "ink");
    radio(api, 940, BY + 43, ["centre ray at its hit", "fan ray at its hit", "centre ray, t = 0.3"], 170, 0, i => { S.ray = i; rebuild(); });

    const cur = () => run.stages[S.k];
    const prevStage = () => run.stages[Math.max(0, S.k - 1)];
    const relErr = (a, b) => { const n = Math.hypot(...b); return n > 0 ? Math.hypot(...a.map((v, c) => v - b[c])) / n : 0; };
    const stageName = st => (st.kind === "start" ? "δ_0 = dir × t" : st.kind === "handoff" ? `the handoff at h = ${st.h}` : `iteration ${st.it}, after the ${STAGE_INFO[st.kind].name.toLowerCase()}`);
    function fill(panel, st, title) {
      panel.t.textContent = title;
      COLS.forEach((c, ci) => {
        const v = st[c.key];
        for (let a = 0; a < 4; a++) panel.cells[a][ci].textContent = sci(v[a], 5);
        panel.cells[4][ci].textContent = sci(Math.hypot(...v), 5);
        const re = c.key === "ex" ? null : relErr(v, st.ex);
        panel.cells[5][ci].textContent = re === null ? "—" : sci(re, 2);
        panel.cells[5][ci].style.fill = re === null ? "" : re < 1e-3 ? api.hue(3) : re < 1 ? api.hue(4) : api.hue(2);
      });
    }
    function rebuild() {
      run = deltaStages(SAVES[S.save], DEPTHS[S.di], S.ray, S.noHand);
      S.k = Math.min(S.k, run.stages.length - 1);
      render();
    }
    function render() {
      const st = cur(), pv = prevStage();
      stages.set(st.kind === "start" ? -1 : STAGES.indexOf(st.kind));
      head.textContent = `${SAVES[S.save].name} · d = ${sci(run.d, 0)} · ${["centre ray", "fan ray", "centre ray"][S.ray]} · t = ${sci(run.t)} · stage ${S.k} of ${run.stages.length - 1}: ${stageName(st)}`;
      sub.textContent = `near = ${sci(run.o.distance)} · pert_iters here ${pertIters(run.P, run.o, run.o.distance)} (the stepper uses ${run.k}) · this ray perturbs ${run.h} iterations${S.noHand ? " (no handoff: all of them)" : ""} · |δ_0| = t = ${sci(run.t)}`;
      fill(RD, S.k === 0 ? st : pv, S.k === 0 ? "READS: the start" : `READS: ${stageName(pv)}`);
      fill(WR, st, `WRITES: ${stageName(st)}`);
      const L = [];
      if (st.kind === "start") {
        L.push(`δ_0 = dir × t = ${vec(run.off, 6)} (δ.w = 0: w is the slice's own, the same for both)`);
        L.push(`float32 direct: the pixel's point eye + dir × t rounded to 32 bits = ${vec([0, 1, 2].map(c => fr(fr(run.eye[c]) + fr(run.off[c]))), 9)}`);
        L.push(`   its offset from the 64-bit eye is ${vec(st.dr, 4)}: snapped to the grid ${sci(ulp32(maxAbs(run.eye)))}, ${sci(relErr(st.dr, st.ex), 2)} off already`);
        L.push(`the reference X_0 = the 64-bit eye ${vec(run.eye, 9)}`);
      } else if (st.kind === "fold") {
        const nm = ["below", "inside", "above"];
        L.push(`gaps g_lo = −L − X = ${vec(st.ga, 4)}`);
        L.push(`     g_hi =  L − X = ${vec(st.gb, 4)}`);
        L.push(`X: ${st.sideX.map((v, c) => `${"xyzw"[c]} ${nm[v + 1]}`).join(", ")}   ·   P: ${st.sideP.map((v, c) => `${"xyzw"[c]} ${nm[v + 1]}`).join(", ")}`);
        L.push(st.cross.length ? `⚑ crossing on ${st.cross.map(c => "xyzw"[c]).join(", ")}: the pixel and the reference fold differently there (tab 6's table)` : "no crossing: on each component both fold the same way, so δ' is δ or −δ");
      } else if (st.kind === "sphere") {
        const nm = ["inside", "shell", "outside"];
        L.push(`q = |P|² − |X|² = 2 X·δ + δ·δ = ${sci(st.q, 5)} (a sum of products: no cancellation)`);
        L.push(`X regime ${nm[st.rx]} (gaps ${sci(st.gmin)}, ${sci(st.gfix)}), P regime ${nm[st.rp]}${st.rx !== st.rp ? "   ⚑ crossing" : ""}`);
        L.push(`m = ${sci(st.m, 6)} (the record's d.z) · m' = ${sci(st.mp, 6)} · m' − m = ${sci(st.dm, 5)}, written per regime pair`);
        L.push(`δ' = m' δ + X (m' − m) · the pixel's dz × m' (dz now ${sci(st.dzP)})`);
      } else if (st.kind === "rotate") {
        L.push("skipped: this save has no iteration rotation (mb_rotating() is false), so δ passes through");
        L.push("with a rotation the shader runs the same mb_iter_rotate on δ: a rotation is linear, so the difference is the rotated difference");
      } else if (st.kind === "scale") {
        L.push(`δ' = s δ, s = box_scale = ${fmt(run.P.box_scale, 2)}: linear, exact up to one rounding`);
        L.push(`the magnification so far: λ = ${sci(st.dzX)} (|δ| grows by about this)`);
      } else if (st.kind === "add") {
        L.push(run.P.julia_all ? "δ' = δ + 0: in Julia mode the pixel's c is the reference's c, so the add cancels" : `δ' = δ + δc, δc = δ_0 = ${vec(run.off, 4)}: in Mandelbrot mode c is the point itself, so the pixel's c differs by its own start offset`);
        L.push(`|δ|² = ${sci(Math.hypot(...st.pf) ** 2)} ${Math.hypot(...st.pf) >= PERT_HANDOFF ? "≥ 0.01: this ray hands off before the next iteration" : "< 0.01 = PERT_HANDOFF²: perturb on"}`);
      } else {
        L.push(`hand off at h = ${st.h}: z = pert_x[${st.h}] + δ = ${vec(st.zh, 6)} (a 32-bit sum, now precise enough)`);
        L.push(`then mb_orbit from iteration ${st.h} to 32 with the carried dz; the estimate:`);
        const thr = epsOf(run.P) * run.t;
        L.push(`   64-bit exact ${sci(st.est.truth, 6)} · float32 perturbed ${sci(st.est.pert, 6)}: off by ${sci(Math.abs(st.est.pert - st.est.truth), 2)}, ${sci(Math.abs(st.est.pert - st.est.truth) / thr, 2)} × the hit threshold`);
        L.push(`   float32 direct ${sci(st.est.direct, 6)}: off by ${sci(Math.abs(st.est.direct - st.est.truth), 2)}, ${sci(Math.abs(st.est.direct - st.est.truth) / thr, 2)} × the hit threshold eps × t = ${sci(thr)}`);
      }
      info.forEach((t, i) => { t.textContent = L[i] || ""; t.style.fill = /⚑/.test(L[i] || "") ? api.hue(2) : ""; });
      // table: iterations up to the current stage
      const adds = run.stages.filter((s2, j) => s2.kind === "add" && j <= S.k);
      const first = Math.max(0, adds.length - 14);
      for (let rr = 0; rr < 14; rr++) {
        const a = adds[first + rr], cells = trows[rr];
        if (!a) { cells.forEach(c => { c.textContent = ""; }); continue; }
        const its = run.stages.filter(s2 => s2.it === a.it && s2.kind !== "start");
        const cr = [];
        its.forEach(s2 => { if (s2.kind === "fold" && s2.cross.length) cr.push(`fold ${s2.cross.map(c => "xyzw"[c]).join("")}`); if (s2.kind === "sphere" && s2.rx !== s2.rp) cr.push("sphere"); });
        const vals = [String(a.it), sci(Math.hypot(...a.ex)), sci(relErr(a.pf, a.ex), 2), sci(relErr(a.dr, a.ex), 2), cr.join(", ") || "—"];
        cells.forEach((c, i) => { c.textContent = vals[i]; c.style.fill = i === 4 && cr.length ? api.hue(2) : ""; });
      }
      // chart
      const all = run.stages.filter(s2 => s2.kind === "add");
      COLS.forEach((c, ci) => {
        if (c.key === "ex") return;
        const pts = [[ch.X(0), clampf(ch.Y(relErr(run.stages[0][c.key], run.stages[0].ex)), CY, CY + CH)]];
        all.forEach(a => pts.push([ch.X(a.it + 1), clampf(ch.Y(relErr(a[c.key], a.ex)), CY, CY + CH)]));
        chP[ci].setAttribute("d", pathOf(pts));
      });
      hLine.setAttribute("x1", ch.X(run.h)); hLine.setAttribute("x2", ch.X(run.h));
      hTxt.setAttribute("x", ch.X(run.h) + 5); hTxt.textContent = `handoff, h = ${run.h}`;
      const ci = st.kind === "start" ? 0 : st.kind === "handoff" ? st.h : st.it + (st.kind === "add" ? 1 : 0.5);
      curMark.setAttribute("x1", ch.X(ci)); curMark.setAttribute("x2", ch.X(ci));
    }
    rebuild();
  },
};
function stageBlurb(kind) {
  return {
    fold: "The box fold reflects each component past ±fold_limit. Its difference, per component, from the record's gaps g_lo = −L − X and g_hi = L − X: `2 (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ`. One formula for all nine side pairs, and both clamps are of small numbers. GDScript: PerturbationPort.pert_clamp.",
    sphere: "q = |P|² − |X|² = 2 X·δ + δ·δ (products only). The pixel's regime comes from g + q against 0 for each gap; m' − m is written per regime pair as a precise small number over a product. Then `δ' = m' δ + X (m' − m)` and the pixel's dz × m'. GDScript: pert_sphere.",
    rotate: "The iteration rotation is linear, so the offset is rotated by the same `mb_iter_rotate`. The saves here do not rotate (`mb_rotating()` is false), so the stage passes δ through.",
    scale: "`δ' = s δ` (the shader writes scale and add in one line, `dl = s * dl + dc`; the port rounds each, as here). |δ| grows by |s| every iteration: this is most of the magnification.",
    add: "Julia mode: the pixel's c is the reference's c, so the add cancels. Mandelbrot mode: c is the point itself, so the pixel's c differs by exactly its own starting offset δ_0 (`dc`).",
    handoff: "At the first iteration h where the records run out or |δ|² ≥ PERT_HANDOFF², the ray forms `z = pert_x[h] + δ` in float32 and runs the ordinary loop from h with the accumulated dz. A far ray hands off at h = 0, where z = eye + off: today's expression.",
  }[kind];
}

// ================================================================== 6. crossing a fold
const CLAMP_CASES = [
  ["−δ", "δ − 2 g_lo", "2 (g_hi − g_lo) − δ"],
  ["2 g_lo − δ", "δ", "2 g_hi − δ"],
  ["2 (g_lo − g_hi) − δ", "δ − 2 g_hi", "−δ"],
];
const SPHERE_CASES = [
  ["0", "−F (g_min + q) / (|P|² M)", "1 − F / M"],
  ["F g_min / (M |X|²)", "−F q / (|P|² |X|²)", "g_fix / |X|²"],
  ["F / M − 1", "−(g_fix + q) / |P|²", "0"],
];
const crossFig = {
  type: "figure",
  tab: "Crossing a fold",
  title: "Crossing a fold: the difference formulas, case by case",
  note: "A port of `pert_clamp` and `pert_sphere` (perturbation.gdshaderinc), in JS doubles, on one coordinate (X and P on the x axis; the sphere fold uses |X| and |P|). Drag X (blue) and P (orange). The box fold is piecewise-linear: on each side of a crease it is a straight line, so the difference of two points on the same piece is that piece's slope times δ (δ or −δ), and only a pair split by a crease needs the gap. The table shows which of the nine cases you are in and its formula, all covered by the one `clamp` expression. The sphere fold multiplies by a factor m that depends on the regime; the difference m' − m is written per regime pair so it never subtracts two nearly equal factors (catastrophic cancellation). Each panel checks the formula against the direct difference f(P) − f(X).",
  w: 1500, h: 1000,
  draw(api) {
    const S = { X: 0.85, P: 1.12, L: 1.0, sx: 0.62, sp: 0.88, mr: 0.7, fx: 1.0 };
    // ---------------- A: the box fold
    const AX = 60, AW = 820, AY = 130, A0 = -2.5, A1 = 2.5;
    const ax = v => AX + (v - A0) / (A1 - A0) * AW, axInv = px => A0 + (px - AX) / AW * (A1 - A0);
    api.text(20, 30, "the box fold, one component: f(v) = 2 clamp(v, −L, L) − v", "ink", { style: caps });
    api.text(20, 52, "δ' = f(X + δ) − f(X) = 2 (clamp(δ, g_lo, g_hi) − clamp(0, g_lo, g_hi)) − δ,   g_lo = −L − X,  g_hi = L − X   (pert_clamp)", "mono", { style: small });
    api.el("line", { x1: AX, y1: AY, x2: AX + AW, y2: AY, style: "stroke:var(--muted);stroke-width:1.4" });
    for (let v = -2; v <= 2; v++) { api.el("line", { x1: ax(v), y1: AY - 4, x2: ax(v), y2: AY + 4, style: "stroke:var(--muted)" }); api.text(ax(v), AY + 20, String(v), "muted", { "text-anchor": "middle", style: small }); }
    const crLo = api.el("line", { y1: AY - 40, y2: AY + 40, style: `stroke:${api.hue(2)};stroke-width:2;stroke-dasharray:5 3;${noPtr}` });
    const crHi = api.el("line", { y1: AY - 40, y2: AY + 40, style: `stroke:${api.hue(2)};stroke-width:2;stroke-dasharray:5 3;${noPtr}` });
    api.text(AX, AY - 48, "creases at ±L (orange dashes): the box fold's mirrors", "muted", { style: small });
    // the image axis
    const IY = AY + 110;
    api.el("line", { x1: AX, y1: IY, x2: AX + AW, y2: IY, style: "stroke:var(--muted);stroke-width:1.4" });
    api.text(AX, IY + 24, "after the fold: f(X), f(P)", "muted", { style: small });
    const dArrow = api.el("g", {}), fArrow = api.el("g", {});
    const mkHandle = (y, hue, lbl) => {
      const g = api.el("g", { style: "cursor:ew-resize" });
      const c = api.el("circle", { cy: y, r: 9, style: `fill:${api.hue(hue)};stroke:var(--surface);stroke-width:2` }, g);
      const t = api.text(0, y - 14, lbl, "", { "text-anchor": "middle", style: `font-weight:700;fill:${api.hue(hue)}` }, g);
      return { g, c, t };
    };
    const hX = mkHandle(AY, 1, "X"), hP = mkHandle(AY, 2, "P");
    const iX = api.el("circle", { cy: IY, r: 6, style: `fill:${api.hue(1)};${noPtr}` }), iP = api.el("circle", { cy: IY, r: 6, style: `fill:${api.hue(2)};${noPtr}` });
    draggable(api, hX.g, p => { S.X = +clampf(axInv(p.x), A0, A1).toFixed(3); render(); });
    draggable(api, hP.g, p => { S.P = +clampf(axInv(p.x), A0, A1).toFixed(3); render(); });
    const aOut = [];
    for (let i = 0; i < 7; i++) aOut.push(api.text(920, 90 + i * 20, "", "mono", { style: small }));
    // the 3 × 3 table
    const TX = 920, TY = 250, TW = 180, TH = 34;
    api.text(TX, TY - 12, "rows: X's side · columns: P's side", "muted", { style: small });
    const sides = ["below −L", "inside", "above L"];
    sides.forEach((s, i) => { api.text(TX + 90 + i * TW + TW / 2, TY + 10, s, "ink", { "text-anchor": "middle", style: `${small};font-weight:600` }); api.text(TX, TY + 40 + i * TH, s, "ink", { style: `${small};font-weight:600` }); });
    const cCells = CLAMP_CASES.map((row, i) => row.map((f, j) => {
      const x = TX + 90 + j * TW, y = TY + 20 + i * TH;
      const r = api.el("rect", { x, y, width: TW - 4, height: TH - 4, rx: 4, style: "fill:var(--surface);stroke:var(--hairline)" });
      api.text(x + 8, y + 20, f, "mono", { style: `${small};${noPtr}` });
      api.tip(r, { title: `X ${sides[i]}, P ${sides[j]}`, sub: `δ' = ${f}`, ...R("pert", 42), blurb: i === j ? (i === 1 ? "Both inside: the fold leaves both alone, so the offset is unchanged." : "Both past the same crease: both are mirrored, so the offset flips sign.") : "The pair is split by a crease: one is mirrored and the other is not. The gap g (crease minus X) is a small number the CPU computed in 64-bit, so the result stays precise." });
      return r;
    }));
    // ---------------- B: the sphere fold
    const BY = 520, BX = 60, BW = 820, B0 = 0, B1 = 1.6;
    const bx = v => BX + (v - B0) / (B1 - B0) * BW, bxInv = px => B0 + (px - BX) / BW * (B1 - B0);
    api.text(20, BY - 30, "the sphere fold: f(v) = m(|v|) v,  m = fixed²/min² inside, fixed²/|v|² in the shell, 1 outside", "ink", { style: caps });
    api.text(20, BY - 10, "δ' = m' δ + X (m' − m),  q = |P|² − |X|² = 2 X·δ + δ·δ,  g_min = |X|² − min²,  g_fix = |X|² − fixed²   (pert_sphere)", "mono", { style: small });
    const MY = BY + 170, mScale = 50;
    const my = m => MY - (m - 1) * mScale;
    api.el("line", { x1: BX, y1: MY, x2: BX + BW, y2: MY, style: "stroke:var(--muted);stroke-width:1.4" });
    for (let v = 0; v <= 1.6; v += 0.2) { const vv = +v.toFixed(1); api.el("line", { x1: bx(vv), y1: MY - 4, x2: bx(vv), y2: MY + 4, style: "stroke:var(--muted)" }); api.text(bx(vv), MY + 20, String(vv), "muted", { "text-anchor": "middle", style: small }); }
    api.text(BX + BW, MY + 36, "radius |v|", "muted", { "text-anchor": "end", style: small });
    const mPath = api.el("path", { style: `fill:none;stroke:${api.hue(5)};stroke-width:2;${noPtr}` });
    api.text(BX, my(2.2), "the factor m(r) (pink), 1 at the axis", "muted", { style: small });
    const sMin = api.el("line", { y1: MY - 140, y2: MY + 8, style: `stroke:${api.hue(5)};stroke-width:1.4;stroke-dasharray:3 3;${noPtr}` });
    const sFix = api.el("line", { y1: MY - 140, y2: MY + 8, style: `stroke:${api.hue(5)};stroke-width:1.8;${noPtr}` });
    const sX = mkHandle(MY, 1, "|X|"), sP = mkHandle(MY, 2, "|P|");
    draggable(api, sX.g, p => { S.sx = +clampf(bxInv(p.x), 0.05, B1).toFixed(3); render(); });
    draggable(api, sP.g, p => { S.sp = +clampf(bxInv(p.x), 0.05, B1).toFixed(3); render(); });
    const bOut = [];
    for (let i = 0; i < 8; i++) bOut.push(api.text(920, BY + 10 + i * 20, "", "mono", { style: small }));
    const T2Y = BY + 190, T2W = 190;
    const reg = ["inside", "shell", "outside"];
    reg.forEach((s, i) => { api.text(TX + 70 + i * T2W + T2W / 2, T2Y + 10, s, "ink", { "text-anchor": "middle", style: `${small};font-weight:600` }); api.text(TX, T2Y + 40 + i * TH, s, "ink", { style: `${small};font-weight:600` }); });
    const sCells = SPHERE_CASES.map((row, i) => row.map((f, j) => {
      const x = TX + 70 + j * T2W, y = T2Y + 20 + i * TH;
      const r = api.el("rect", { x, y, width: T2W - 4, height: TH - 4, rx: 4, style: "fill:var(--surface);stroke:var(--hairline)" });
      api.text(x + 6, y + 20, f, "mono", { style: `font-size:10px;${noPtr}` });
      api.tip(r, { title: `X ${reg[i]}, P ${reg[j]}: m' − m`, sub: f, ...R("pert", 113 + [[-1, 1, 5], [2, 0, 3], [6, 4, -1]][i][j]), blurb: i === j && i !== 1 ? "The same constant factor: m' − m = 0, so δ' = m δ." : (i === 0 && j === 2) || (i === 2 && j === 0) ? "Inside to outside in one step needs a huge δ; the constant difference is exact." : "A small precise number (a gap, or q) over a product: nothing subtracts two nearly equal factors." });
      return r;
    }));
    api.text(TX, T2Y + 140, "rows: X's regime · columns: P's regime · F = fixed², M = min²", "muted", { style: small });
    // sliders for L and the radii
    api.slider({ x: 60, y: 300, w: 300, label: "fold_limit L", min: 0.3, max: 2, step: 0.01, value: S.L, fmt: v => fmt(v, 2), onChange: v => { S.L = v; render(); } });
    api.slider({ x: 60, y: 900, w: 300, label: "min_radius", min: 0.1, max: 0.95, step: 0.01, value: S.mr, fmt: v => fmt(v, 2), onChange: v => { S.mr = Math.min(v, S.fx - 0.02); render(); } });
    api.slider({ x: 420, y: 900, w: 300, label: "fixed_radius", min: 0.3, max: 1.5, step: 0.01, value: S.fx, fmt: v => fmt(v, 2), onChange: v => { S.fx = Math.max(v, S.mr + 0.02); render(); } });
    api.link(920, 950, RL("spec", 198, "spec: the clamp folds"));
    api.link(1160, 950, RL("spec", 204, "spec: the radial folds"));

    function render() {
      // A
      const L = S.L, X = S.X, P = S.P, dl = P - X, glo = -L - X, ghi = L - X;
      crLo.setAttribute("x1", ax(-L)); crLo.setAttribute("x2", ax(-L));
      crHi.setAttribute("x1", ax(L)); crHi.setAttribute("x2", ax(L));
      for (const [h, v] of [[hX, X], [hP, P]]) { h.c.setAttribute("cx", ax(v)); h.t.setAttribute("x", ax(v)); }
      const f = v => 2 * clampf(v, -L, L) - v, fX = f(X), fP = f(P);
      iX.setAttribute("cx", ax(fX)); iP.setAttribute("cx", ax(fP));
      while (dArrow.firstChild) dArrow.removeChild(dArrow.firstChild);
      while (fArrow.firstChild) fArrow.removeChild(fArrow.firstChild);
      if (Math.abs(dl) > 1e-6) api.arrow(ax(X), AY + 40, ax(P), AY + 40, "var(--ink)", 1.4, dArrow);
      api.text((ax(X) + ax(P)) / 2, AY + 58, "δ", "", { "text-anchor": "middle", style: "font-weight:700" }, dArrow);
      if (Math.abs(fP - fX) > 1e-6) api.arrow(ax(fX), IY - 26, ax(fP), IY - 26, "var(--ink)", 1.4, fArrow);
      api.text((ax(fX) + ax(fP)) / 2, IY - 34, "δ'", "", { "text-anchor": "middle", style: "font-weight:700" }, fArrow);
      const got = F64.pertClamp1(dl, glo, ghi), want = fP - fX;
      const side = v => (v < -L ? 0 : v > L ? 2 : 1), si = side(X), sj = side(P);
      aOut[0].textContent = `X = ${fmt(X, 3)}   P = ${fmt(P, 3)}   δ = P − X = ${fmt(dl, 4)}`;
      aOut[1].textContent = `g_lo = −L − X = ${fmt(glo, 4)}   g_hi = L − X = ${fmt(ghi, 4)}`;
      aOut[2].textContent = `clamp(δ, g_lo, g_hi) = ${fmt(clampf(dl, glo, ghi), 4)}   clamp(0, g_lo, g_hi) = ${fmt(clampf(0, glo, ghi), 4)}`;
      aOut[3].textContent = `δ' (pert_clamp) = ${fmt(got, 6)}`;
      aOut[4].textContent = `f(P) − f(X) (direct) = ${fmt(fP, 4)} − ${fmt(fX, 4)} = ${fmt(want, 6)}`;
      aOut[5].textContent = Math.abs(got - want) < 1e-12 ? "✓ equal" : `✗ differ by ${sci(got - want)}`;
      aOut[5].style.fill = Math.abs(got - want) < 1e-12 ? api.hue(3) : api.hue(2);
      aOut[6].textContent = si === sj ? `same piece: δ' = ${si === 1 ? "δ" : "−δ"}` : `split by a crease: δ' = ${CLAMP_CASES[si][sj]}`;
      cCells.forEach((row, i) => row.forEach((r, j) => r.setAttribute("style", `fill:${i === si && j === sj ? "var(--c4)" : "var(--surface)"};fill-opacity:${i === si && j === sj ? 0.35 : 1};stroke:${i === si && j === sj ? api.hue(4) : "var(--hairline)"};stroke-width:${i === si && j === sj ? 2 : 1}`)));
      // B
      const mr2 = S.mr * S.mr, fr2 = S.fx * S.fx;
      sMin.setAttribute("x1", bx(S.mr)); sMin.setAttribute("x2", bx(S.mr));
      sFix.setAttribute("x1", bx(S.fx)); sFix.setAttribute("x2", bx(S.fx));
      const pts = [];
      for (let k = 0; k <= 160; k++) { const rr = B0 + (B1 - B0) * k / 160; pts.push([bx(rr), Math.max(my(sphereFactor64(rr * rr, mr2, fr2)), MY - 150)]); }
      mPath.setAttribute("d", pathOf(pts));
      for (const [h, v] of [[sX, S.sx], [sP, S.sp]]) { h.c.setAttribute("cx", bx(v)); h.t.setAttribute("x", bx(v)); }
      const Xv = [S.sx, 0, 0, 0], dv = [S.sp - S.sx, 0, 0, 0], x2 = S.sx * S.sx;
      const res = F64.pertSphere(dv, 1, Xv, x2 - mr2, x2 - fr2, mr2, fr2);
      const mX = sphereFactor64(x2, mr2, fr2), mP = sphereFactor64(S.sp * S.sp, mr2, fr2), wantB = mP * S.sp - mX * S.sx;
      bOut[0].textContent = `|X| = ${fmt(S.sx, 3)}  |P| = ${fmt(S.sp, 3)}  δ = ${fmt(dv[0], 4)}  min = ${fmt(S.mr, 2)}  fixed = ${fmt(S.fx, 2)}`;
      bOut[1].textContent = `g_min = ${fmt(x2 - mr2, 4)}  g_fix = ${fmt(x2 - fr2, 4)}  q = ${fmt(res.q, 5)}`;
      bOut[2].textContent = `regimes: X ${reg[res.rx]}, P ${reg[res.rp]}`;
      bOut[3].textContent = `m = ${fmt(mX, 5)}  m' = ${fmt(res.mp, 5)}`;
      bOut[4].textContent = `m' − m by the formula = ${fmt(res.dm, 6)}   by subtraction = ${fmt(mP - mX, 6)}`;
      bOut[5].textContent = `δ' = m' δ + X (m' − m) = ${fmt(res.dl[0], 6)}`;
      bOut[6].textContent = `f(P) − f(X) (direct) = ${fmt(wantB, 6)}`;
      const okB = Math.abs(res.dl[0] - wantB) < 1e-12;
      bOut[7].textContent = okB ? "✓ equal" : `✗ differ by ${sci(res.dl[0] - wantB)}`;
      bOut[7].style.fill = okB ? api.hue(3) : api.hue(2);
      sCells.forEach((row, i) => row.forEach((r, j) => r.setAttribute("style", `fill:${i === res.rx && j === res.rp ? "var(--c4)" : "var(--surface)"};fill-opacity:${i === res.rx && j === res.rp ? 0.35 : 1};stroke:${i === res.rx && j === res.rp ? api.hue(4) : "var(--hairline)"};stroke-width:${i === res.rx && j === res.rp ? 2 : 1}`)));
    }
    render();
  },
};

// ================================================================== 7. handoff and floors
const handFig = {
  type: "figure",
  title: "Each ray hands off on its own",
  note: "A port of ReferenceOrbit (λ_i) and of de_pert's loop test on the default box, in JS doubles. A ray's offset after i perturbed iterations is about λ_i × t, its own distance t times the magnification, so rays of one view need different counts. Three rays of a camera d back from the default view's surface: one grazing a near wall (t ≈ near, the camera's distance to the nearest surface), the centre hit (t ≈ d), and a far ray (t = 0.3). Each hands off where its line crosses 0.1 (or when the 20 records run out; the faint dashes are what it would have grown to); the far ray at once, which is today's expression. The dots are the centre ray's real |δ_i| from the 64-bit port.",
  w: 1500, h: 600,
  draw(api) {
    const sv = SAVES[0], P = sv.P;
    const S = { le: -6 };
    api.slider({ x: 20, y: 34, w: 460, label: "camera distance d (log10)", min: -10, max: -4, step: 0.1, value: S.le, fmt: v => `d = ${sci(pow10(v), 2)}`, onChange: v => { S.le = v; render(); } });
    const CX = 80, CY = 90, CW = 820, CH = 420;
    const ch = chartFrame(api, { x: CX, y: CY, w: CW, h: CH, x0: 0, x1: 20, y0: -12, y1: 2, ystep: 2, xticks: [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20], xlabel: "perturbed iterations i", ylabel: "|δ_i| ≈ λ_i × t (log)" });
    api.el("line", { x1: CX, y1: ch.Y(PERT_HANDOFF), x2: CX + CW, y2: ch.Y(PERT_HANDOFF), style: `stroke:${api.hue(4)};stroke-width:1.6;stroke-dasharray:6 3` });
    api.text(CX + 6, ch.Y(PERT_HANDOFF) - 6, "PERT_HANDOFF = 0.1: hand off here", "", { style: `${small};fill:${api.hue(4)}` });
    const RAYS = [{ name: "near wall", hue: 3 }, { name: "centre hit", hue: 1 }, { name: "far ray", hue: 2 }];
    const lines = RAYS.map(r => api.el("path", { style: `fill:none;stroke:${api.hue(r.hue)};stroke-width:2.4;${noPtr}` }));
    const tails = RAYS.map(r => api.el("path", { style: `fill:none;stroke:${api.hue(r.hue)};stroke-width:1.2;opacity:.45;stroke-dasharray:4 4;${noPtr}` }));
    const marks = RAYS.map(r => api.el("circle", { r: 7, style: `fill:none;stroke:${api.hue(r.hue)};stroke-width:2.4;${noPtr}` }));
    const real = [];
    for (let i = 0; i <= 20; i++) {
      const c = api.el("circle", { r: 3.4, style: `fill:${api.hue(1)};stroke:var(--surface);stroke-width:1;cursor:pointer` });
      real.push(c);
      api.tip(c, { title: `the centre ray after ${i} iterations`, ...R("port", 568), live: () => {
        const st = S.cur; if (!st || !st.trace[i - 1] && i) return {};
        const v = i ? Math.hypot(...st.trace[i - 1]) : st.t;
        return { sub: `|δ_${i}| = ${sci(v)}`, blurb: `λ_${i} × t = ${sci(st.o.mag[i] * st.t)} (the estimate)\nthe real offset is the direct orbit's difference (64-bit port, no handoff)` };
      } });
    }
    const out = [];
    for (let i = 0; i < 14; i++) out.push(api.text(950, 90 + i * 22, "", "mono", { style: small }));
    RAYS.forEach((r, i) => {
      api.el("line", { x1: 950, y1: 420 + i * 22, x2: 980, y2: 420 + i * 22, style: `stroke:${api.hue(r.hue)};stroke-width:2.4` });
      api.text(988, 424 + i * 22, r.name, "", { style: small });
    });
    api.link(950, 500, RL("pert", 177, "the loop test, per ray"));
    api.link(950, 522, RL("spec", 261, "spec: one rule per ray, not per frame"));
    function render() {
      const d = pow10(S.le), e = backed(sv.centre, d), o = buildOrbit(P, e[0], e[1], e[2]);
      const ts = [o.distance, d, 0.3];
      const trace = [];
      F64.dePert(o, PERT_MAX, e, [sv.centre[3] * d, sv.centre[4] * d, sv.centre[5] * d], P, Infinity, trace);
      S.cur = { o, t: d, trace };
      const L = [`near = ${sci(o.distance)} · records min(20, n) = ${Math.min(PERT_MAX, o.n)}`, ""];
      ts.forEach((t, ri) => {
        const pts = [];
        for (let i = 0; i <= 20; i++) pts.push([ch.X(i), clampf(ch.Y(o.mag[i] * t), CY, CY + CH)]);
        let h = o.mag.findIndex(l => l * t >= PERT_HANDOFF);
        if (h < 0 || h > PERT_MAX) h = PERT_MAX;
        lines[ri].setAttribute("d", pathOf(h ? pts.slice(0, h + 1) : [pts[0], pts[0]]));
        tails[ri].setAttribute("d", pathOf(pts.slice(h)));
        marks[ri].setAttribute("cx", ch.X(h)); marks[ri].setAttribute("cy", clampf(ch.Y(o.mag[h] * t), CY, CY + CH));
        L.push(`${RAYS[ri].name}: t = ${sci(t)}`);
        L.push(`   ${h === 0 ? "hands off at once: z = eye + dir × t, today's expression" : h === PERT_MAX && o.mag[h] * t < PERT_HANDOFF ? `records run out at h = ${h} (|δ| ≈ ${sci(o.mag[h] * t)})` : `hands off after h = ${h} iterations (λ_h t = ${sci(o.mag[h] * t)})`}`);
      });
      L.push("", "the old per-frame rule picked one k from λ_k × d;", "the per-ray test is the same quantity, exact for each t");
      out.forEach((t, i) => { t.textContent = L[i] || ""; });
      for (let i = 0; i <= 20; i++) {
        const v = i ? (trace[i - 1] ? Math.hypot(...trace[i - 1]) : null) : d;
        real[i].style.display = v === null ? "none" : "";
        if (v !== null) { real[i].setAttribute("cx", ch.X(i)); real[i].setAttribute("cy", clampf(ch.Y(v), CY, CY + CH)); }
      }
    }
    render();
  },
};
const floorTable = {
  type: "table",
  title: "The two zoom floors per save, computed by the port",
  note: `The camera d back from each save's surface point (the default box from the default view's centre ray, the others marching from the default eye: the test's own fixtures). floor32 = ulp32(max |eye|) / (50 × eps), the old guard and the scale pert_iters switches on at; floor_pert = ulp32(max |X_K|) / (50 × eps × λ_K), K = min(20, n), the guard the fly camera uses now. ${portOk ? "Every near and floor_pert here equals what tests/perturbation_test.gd prints at the pinned commit (checked when the page loads)." : "✗ THE PORT DISAGREES WITH THE TEST: see the red box."}`,
  columns: [{ label: "save", w: 110 }, { label: "d", w: 70, mono: true }, { label: "near (orbit.distance)", w: 190, mono: true }, { label: "floor32", w: 100, mono: true }, { label: "floor_pert", w: 110, mono: true }, { label: "floor32 / floor_pert", w: 180, mono: true }, { label: "records", w: 80, mono: true }, { label: "test's near · floor_pert", w: 230, mono: true }],
  rows: MEASURED_BOX.map(m => {
    const g = m.got || {};
    return { cells: [SAVES[m.save].name, sci(m.d, 0), sci(g.near, 6), sci(g.f32), sci(g.fp, 4), sci(g.f32 / g.fp, 2), String(g.k), `${sci(m.near, 6)} · ${sci(m.fp, 4)}`],
      tip: { title: `${SAVES[m.save].name} at d = ${sci(m.d, 0)}`, ...R("params", 459), blurb: `The port's numbers for the camera ${sci(m.d, 0)} back from the surface. The last column is the MEASURED row's near and floor_pert.`, links: [RL("tPert", 321, "the MEASURED row"), RL("params", 427, "floor32")] } };
  }),
};

// ================================================================== 8. measured
const MEAS = [
  ["default box", "1e-5", "1.988e-6", "20", "3.017e-10", "27/0/0", "3%", "100%"],
  ["default box", "1e-6", "4.796e-7", "20", "1.509e-10", "27/0/0", "0%", "100%"],
  ["default box", "1e-7", "1.866e-8", "20", "7.542e-11", "11/0/16", "59%", "100%"],
  ["ice field", "1e-5", "1.785e-6", "20", "2.425e-10", "25/2/0", "7%", "100%"],
  ["ice field", "1e-6", "5.116e-8", "20", "1.516e-11", "24/0/3", "11%", "100%"],
  ["ice field", "1e-7", "2.229e-8", "20", "1.516e-11", "27/0/0", "0%", "100%"],
  ["terraces", "1e-5", "4.686e-6", "20", "1.565e-10", "27/0/0", "11%", "100%"],
  ["terraces", "1e-6", "4.212e-7", "20", "3.905e-11", "0/0/27", "100%", "100%"],
  ["terraces", "1e-7", "4.014e-10", "20", "3.905e-11", "0/0/27", "100%", "100%"],
  ["Menger", "1e-5", "4.291e-6", "18", "2.521e-10", "27/0/0", "11%", "100%"],
  ["Menger", "1e-6", "5.144e-7", "20", "2.801e-11", "27/0/0", "0%", "100%"],
  ["Menger", "1e-7", "4.272e-8", "20", "3.5e-12", "27/0/0", "0%", "100%"],
  ["Kleinian", "1e-5", "4.960e-6", "8", "2.450e-8", "27/0/0", "0%", "100%"],
  ["Kleinian", "1e-6", "4.956e-7", "8", "2.441e-8", "27/0/0", "0%", "100%"],
  ["Kleinian", "1e-7", "4.960e-8", "8", "2.441e-8", "27/0/0", "0%", "100%"],
];
const measTable = {
  type: "table",
  title: "MEASURED: 27 rays per cell, float32 emulated, against a 64-bit march",
  note: "From `godot4 --headless -s tests/perturbation_test.gd` at the pinned commit (the lines starting MEASURED; numbers rounded here). Per fixture a surface point, a camera d back from it, and 27 rays (a 3 × 3 grid of screen offsets at three field fractions). The reference is a 64-bit march (estimate under eps × t, 128 steps); a march agrees when it lands in the same class (hit / beyond 10 d / out of steps) and, for a hit, within 0.1%. Direct: today's float32 shader (eye + dir × t in 32 bits). Perturbed: the per-ray handoff at 0.1 with min(20, n) records. The direct march's high scores in the terraces' deep cells and the default box at 1e-7 are agreement on 'ran out of steps': those cells are below the fixture's 32-iteration floor (the next tables), where every march fails alike. records: the Menger's eye orbit bails out after 18 iterations at 1e-5, the Kleinian's settles after 8.",
  columns: [{ label: "fixture", w: 110 }, { label: "d", w: 60, mono: true }, { label: "near", w: 100, mono: true }, { label: "records", w: 70, mono: true }, { label: "floor_pert", w: 100, mono: true }, { label: "reference hit/beyond/none", w: 240, mono: true }, { label: "direct agrees", w: 110, mono: true }, { label: "perturbed agrees", w: 130, mono: true }],
  rows: MEAS.map(r => ({ cells: r, tip: { title: `${r[0]} at d = ${r[1]}`, ...R("tPert", 321), blurb: `near = the 64-bit estimate at the camera; records = pert_iters; reference ${r[5]} of 27 rays hit / went beyond / ran out; today's float32 march agrees on ${r[6]}, the perturbed one on ${r[7]}.`, links: [RL("tPert", 274, "_march_pert"), RL("tPert", 258, "_march_direct"), RL("tPert", 244, "_march_ref")] } })),
};
const FAN = [
  ["default box (surface est. 9e-14, eps 2.5e-5)", "27/27", "27/27", "27/27", "14/27", "3/27", "0/10", "0/0", "0/0", "0/0"],
  ["ice field (5e-14, eps 2e-5)", "27/27", "25/25", "24/27", "26/27", "7/21", "0/3", "0/0", "0/0", "0/0"],
  ["terraces (1.3e-10, eps 1e-4)", "27/27", "27/27", "0/14", "0/0", "0/0", "0/0", "0/0", "0/0", "0/0"],
  ["Menger (7e-14, eps 2.5e-5)", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27"],
  ["Kleinian (9e-14, eps 2.5e-5)", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27", "27/27"],
];
const fanTable = {
  type: "table",
  title: "REFERENCE FLOOR (FAN): where 32 iterations stop resolving, per fixture",
  note: "The same 27-ray fan, all in 64-bit: no float32, no perturbation. Hit when the 32-iteration estimate falls under eps × t (detail 1, no falloff, so near plays no part); each cell is hits within 128 steps (the shader's budget) / within 2000 (to tell 'out of budget' from 'never converges'). The surface point is refined until its estimate is under 1e-13, or as low as round-off lets it go (in parentheses). Past a fixture's floor rays run out of steps and the picture darkens; the camera is not stopped there (the spec dropped that guard, tab 10).",
  columns: [{ label: "fixture", w: 300 }].concat(["1e-4", "1e-5", "1e-6", "1e-7", "1e-8", "1e-9", "1e-10", "1e-11", "1e-12"].map(l => ({ label: l, w: 62, mono: true }))),
  rows: FAN.map(r => ({ cells: r, tip: { title: r[0], ...R("tPert", 370), blurb: "Hits within 128 / 2000 steps of 27, by camera distance d.", links: [RL("tPert", 364, "the parameters"), RL("readme", 166, "README: where 32 iterations run out")] } })),
};
const VIEW9 = [
  ["spread 0.1", "1e-12", "1e-9", "1e-8", "1e-6", "1e-5", "1e-9", "1e-7", "1e-10", "none"],
  ["spread 0.3", "1e-9", "1e-11", "1e-10", "1e-7", "1e-5", "1e-6", "1e-7", "1e-6", "1e-4"],
];
const view9Table = {
  type: "table",
  title: "REFERENCE FLOOR (VIEW9): nine rays of the default view, the deepest d each resolves",
  note: "The default box at its default camera: a 3 × 3 grid of rays near the middle of the view (at 0.1 and at 0.3 of the half field), each backed off d from its own hit; the deepest d (down from 1e-4) at which that ray still hits within 10% of d, 128 steps, 64-bit. Rays in the test's order (ia = −1, 0, 1 across, ib = −1, 0, 1 within each). Points a few pixels apart resolve anywhere from 1e-5 to 1e-12: the 32-iteration floor varies by orders of magnitude, which is why it is measured, not guarded.",
  columns: [{ label: "grid", w: 100 }].concat([1, 2, 3, 4, 5, 6, 7, 8, 9].map(i => ({ label: `ray ${i}`, w: 64, mono: true }))),
  rows: VIEW9.map(r => ({ cells: r, tip: { title: `VIEW9, ${r[0]}`, ...R("tPert", 404), links: [RL("tPert", 392, "the ray grid")] } })),
};

// ================================================================== 9. coarse pass and lighting
const coarseFig = {
  type: "figure",
  tab: "Coarse pass and lighting",
  title: "The coarse pass and the lighting follow the camera's distance",
  note: "A port of FractalParams.coarse_iters and nf_weight (the Mandelbox branch) in JS doubles, against the camera's distance near on a log axis, zooming in to the right. Both rules predate perturbation; what changed is that near is now measured from the 64-bit eye and clamped at 1e-14 instead of 1e-6, so both keep following the camera down to the new floor. The coarse pass runs n iterations, n = ceil(log(2 / (2 eps near)) / log|box_scale|) kept in [16, 32]: each iteration adds detail |box_scale| times finer, and the coarse pass must not stop at a smoother surface farther away than its own threshold. The Ice Fractal normal fades into the true normal with a smoothstep between near = 2 and 0.1. Drag the sliders; hover the charts for the values.",
  w: 1400, h: 700,
  draw(api) {
    const S = { s: -2.09, detail: 1, hover: null };
    const P = () => mbParams({ box_scale: S.s, detail: S.detail });
    api.slider({ x: 20, y: 34, w: 300, label: "box_scale", min: -3.5, max: -1.05, step: 0.01, value: S.s, fmt: v => fmt(v, 2), onChange: v => { S.s = v; render(); } });
    api.slider({ x: 380, y: 34, w: 300, label: "detail (eps = precision / detail)", min: 0.1, max: 10, step: 0.1, value: S.detail, fmt: v => fmt(v, 1), onChange: v => { S.detail = v; render(); } });
    const CX = 80, CW = 900, L0 = 1, L1 = -13;
    const X = l => CX + (L0 - l) / (L0 - L1) * CW, Xinv = px => L0 - (px - CX) / CW * (L0 - L1);
    const charts = [{ y: 100, h: 230, lo: 14, hi: 34, label: "coarse_iters(near)", ticks: [16, 20, 24, 28, 32], hue: 1 }, { y: 400, h: 200, lo: -0.05, hi: 1.05, label: "nf_weight(near)", ticks: [0, 0.25, 0.5, 0.75, 1], hue: 6 }];
    const paths = charts.map(c => {
      api.el("rect", { x: CX, y: c.y, width: CW, height: c.h, style: "fill:none;stroke:var(--hairline)" });
      api.text(CX, c.y - 8, c.label, "ink", { style: caps });
      for (const t of c.ticks) {
        const y = c.y + c.h - (t - c.lo) / (c.hi - c.lo) * c.h;
        api.el("line", { x1: CX, y1: y, x2: CX + CW, y2: y, style: "stroke:var(--hairline);stroke-width:.6" });
        api.text(CX - 6, y + 4, String(t), "muted", { "text-anchor": "end", style: small });
      }
      for (let l = L0; l >= L1; l--) {
        api.el("line", { x1: X(l), y1: c.y + c.h, x2: X(l), y2: c.y + c.h + 4, style: "stroke:var(--muted)" });
        if ((L0 - l) % 2 === 0) api.text(X(l), c.y + c.h + 16, e10(l), "muted", { "text-anchor": "middle", style: small });
      }
      c.Y = v => c.y + c.h - (v - c.lo) / (c.hi - c.lo) * c.h;
      return api.el("path", { style: `fill:none;stroke:${api.hue(c.hue)};stroke-width:2.4;${noPtr}` });
    });
    api.text(CX + CW, 642, "the camera's distance to the nearest surface, near (log; zooming in →)", "muted", { "text-anchor": "end", style: small });
    // marks
    const mark = (l, label, hue, dy) => {
      api.el("line", { x1: X(l), y1: 96, x2: X(l), y2: 604, style: `stroke:${api.hue(hue)};stroke-width:1.2;stroke-dasharray:4 4;${noPtr}` });
      api.text(X(l) + 4, dy, label, "", { style: `${small};fill:${api.hue(hue)}` });
    };
    mark(Math.log10(6.5655845), "default view, near 6.57", 3, 112);
    const swOn = PERT_ON * floor32(SAVES[0].P, backed(SAVES[0].centre, 1e-3));
    mark(Math.log10(swOn), `perturbation on (10 × floor32 ≈ ${sci(swOn, 1)})`, 4, 430);
    mark(Math.log10(floorPert(SAVES[0].P, buildOrbit(SAVES[0].P, ...backed(SAVES[0].centre, 1e-8)))), "default box zoom floor (floor_pert)", 2, 450);
    const cross = api.el("line", { y1: 96, y2: 604, style: `stroke:var(--ink);stroke-width:1;opacity:.6;${noPtr}` });
    const out = [];
    for (let i = 0; i < 10; i++) out.push(api.text(1020, 110 + i * 22, "", "mono", { style: small }));
    const ov = api.el("rect", { x: CX, y: 100, width: CW, height: 500, style: "fill:transparent;cursor:crosshair", "data-interactive": "" });
    ov.addEventListener("mousemove", e => { S.hover = clampf(Xinv(api.local(e).x), L1, L0); render(); });
    ov.addEventListener("mouseleave", () => { S.hover = null; render(); });
    api.link(1020, 560, RL("params", 361, "coarse_iters"));
    api.link(1020, 582, RL("params", 391, "nf_weight"));
    api.link(1020, 604, RL("readme", 101, "README: coarse pass iterations"));
    function render() {
      const p = P();
      const ci = [], nw = [];
      for (let k = 0; k <= 700; k++) {
        const l = L0 - (L0 - L1) * k / 700, near = pow10(l);
        ci.push([X(l), charts[0].Y(coarseIters(p, near))]);
        nw.push([X(l), charts[1].Y(nfWeight(near))]);
      }
      paths[0].setAttribute("d", pathOf(ci)); paths[1].setAttribute("d", pathOf(nw));
      const l = S.hover === null ? -6 : S.hover, near = pow10(l), n = coarseIters(p, near);
      cross.setAttribute("x1", X(l)); cross.setAttribute("x2", X(l));
      const eps = p.precision / p.detail, gap = 2 * eps * near;
      const L = [
        `near = ${sci(near)}${S.hover === null ? " (hover the charts)" : ""}`,
        `eps = precision / detail = ${sci(eps)}`,
        `coarse threshold 2 eps near = ${sci(gap)}`,
        `log(2 / gap) / log|s| = ${fmt(Math.log(2 / gap) / Math.log(Math.abs(p.box_scale)), 2)}`,
        `coarse_iters = ${n}${n === 32 ? " (capped: the full count)" : n === 16 ? " (the site's 16)" : ""}`,
        `the smoother surface sits ~2 / |s|^n = ${sci(2 / Math.pow(Math.abs(p.box_scale), n))} out`,
        ``,
        `nf_weight = smoothstep(0.1, 2, near) = ${fmt(nfWeight(near), 4)}`,
        nfWeight(near) >= 1 ? "   the Ice Fractal normal alone" : nfWeight(near) <= 0 ? "   the true normal alone (true_normal)" : "   a blend of the two",
      ];
      out.forEach((t, i) => { t.textContent = L[i] || ""; });
    }
    render();
  },
};

// ================================================================== 10. cards
const cards = {
  type: "cards",
  title: "Invariants, gotchas, history, open",
  columns: 2, cardWidth: 600,
  cards: [
    { title: "The default view is bit-for-bit the site's", tag: "invariant", hue: 3, ...R("spec", 69),
      body: "At the default view `pert_iters` is 0, and with `pert_iters == 0` the shader runs exactly the old arithmetic: the Mandelbox loop moved into `mb_orbit(z, dz, c, 0, iters)`, the same operations in the same order. The user's windowed screenshot check (tests/screenshots.sh) confirms it pixel for pixel.",
      links: [RL("sh", 296, "mb_orbit: the same loop"), RL("tView", 20, "test: the default view does not perturb")] },
    { title: "pert_iters == 0 is today's path", tag: "invariant", hue: 3, ...R("pert", 267),
      body: "`march_de` calls `de(pos, iters)` and `true_normal` calls `calc_normal(v, delta)` whenever `pert_iters` is 0; nothing else on that path changed. And a ray that hands off at h = 0 computes `pert_x[0] + δ_0 = eye + dir × t`, today's expression too.",
      links: [RL("pert", 283, "true_normal"), RL("pert", 11, "the h = 0 handoff")] },
    { title: "eye() is the rounded shadow", tag: "invariant", hue: 3, ...R("cam", 62),
      body: "Every 32-bit consumer (the `eye` uniform, the cube test, the orbit camera, project/unproject) keeps reading `eye()`, the Transform3D origin. The truth is `eye64()`. Assigning a transform whose origin equals the shadow keeps the doubles, so `FlyCamera._set_forward` (which rebuilds the basis from `eye()`) never loses precision.",
      links: [RL("cam", 22, "the setter's rule"), RL("tCam", 51, "test: the shadow"), RL("tCam", 60, "test: the doubles kept")] },
    { title: portOk ? "ReferenceOrbit.distance equals the estimator exactly" : "✗ THIS PAGE'S PORT DISAGREES WITH THE TEST", tag: portOk ? "invariant" : "port broken", hue: portOk ? 3 : 2, ...R("tOrbit", 16),
      body: "The orbit's loop body duplicates DistanceEstimator's (it calls the same static fold helpers), and `distance` equals `estimate_at` at the eye bit for bit for every shape variant, so `_push_near` reuses it as `near` and nothing is computed twice. This page's port of the orbit reproduces the test's MEASURED near and floor_pert for the three Mandelbox fixtures to the printed digit (checked at load).",
      links: [RL("orb", 137, "distance"), RL("view", 385, "near = the orbit's distance")] },
    { title: "Vector3 is 32-bit", tag: "gotcha", hue: 2, ...R("cam", 9),
      body: "In Godot's standard build GDScript floats are 64-bit but `Vector3` / `Vector4` / `Transform3D` components are 32-bit. Near the default eye (coordinate 8.2) an origin sits on a grid about 1e-6 apart, so a 1e-7 step rounds to nothing: the old floor was only about 100 eye steps away. Everything that must be precise uses scalar doubles or PackedFloat64Array.",
      links: [RL("tFly", 100, "test: a 1e-10 step cannot move the shadow"), RL("de", 13, "why the estimator is scalar")] },
    { title: "_tidy, JSON's 15 digits, and Godot's parser", tag: "gotcha", hue: 2, ...R("ws", 273),
      body: "`_tidy` rounds to 7 significant figures (fine for forward and up), so the eye skips it. `JSON.stringify` keeps only 15 digits by default; saves pass full_precision. And Godot's float parser is not correctly rounded: about a third of doubles come back one 64-bit step off (at most about 4e-15 for coordinates under 20), thousands of times below any floor. In-memory capture and restore is exact; the file test allows one step.",
      links: [RL("ws", 116, "full_precision"), RL("tWs", 206, "test: the parser's one ulp")] },
    { title: "The old 1e-6 clamps: speed and NEAR_FLOOR", tag: "gotcha", hue: 2, ...R("fly", 23),
      body: "The fly speed was clamped at 1e-6 and `near` at `NEAR_FLOOR = 1e-6`. Below that the camera would outrun its own stop, and the level of detail, the fog, `coarse_iters` and the switch-on rule would all stop following the camera exactly where perturbation starts to matter. Both are 1e-14 now; they only ever guarded against a zero.",
      links: [RL("params", 281, "NEAR_FLOOR"), RL("tFly", 62, "test: SPEED_FLOOR")] },
    { title: "The WebGL uniform budget", tag: "gotcha", hue: 2, ...R("spec", 171),
      body: "The record is 4 × vec4[20] plus vec4[21]: 101 vec4s. With `pert_iters` and the existing 109 declarations that is 211 of WebGL 2's 224-vector minimum if a driver packs no scalars into shared rows (they normally pack four to a row). It compiles under GL Compatibility on 4.6.1; only the web export can confirm the link. `PERT_MAX` is the knob if it fails.",
      links: [RL("pert", 26, "the arrays"), RL("tShader", 66, "shader_test: PERT_HANDOFF matches")] },
    { title: "Folds that keep the 32-bit floor", tag: "gotcha", hue: 2, ...R("orb", 80),
      body: "The Mandelbox's octahedral fold and the KIFS poly fold are many-region piecewise maps whose crossing cases are not enumerated, and the Mandelbulb's power map is not piecewise-linear at all. For them `perturbable` is false, `pert_iters` is 0 and the fly camera keeps the 32-bit floor, about 1e-4.",
      links: [RL("orb", 188, "the poly fold"), RL("spec", 55, "spec: not perturbed")] },
    { title: "Noise is still evaluated at 32-bit", tag: "gotcha", hue: 2, ...R("pert", 262),
      body: "`de_pert` adds `noise_displace(p)` at the 32-bit point `eye + off`. A displaced surface is smooth below the displacement's own size, so there is nothing finer to resolve; the README says so.",
      links: [RL("pert", 250, "the comment"), RL("readme", 161, "README")] },
    { title: "Three fixes measured: the self-similar substitution note", tag: "history", hue: 6, ...R("note", 1),
      body: "Before the spec, a research note measured three ways past the floor in emulated float32: mapping the camera through k iterations (the substitution: seams by design), a two-float camera (exact, about 7× the cost per ray, and at the mercy of how a WebGL compiler reorders), and perturbation (94 to 100% of rays right at 1e-5 to 1e-7 for every shape at about 1.5 to 2× per ray). Perturbation was built.",
      links: [RL("note", 362, "the comparison table"), RL("spec", 18, "spec: the problem")] },
    { title: "The two-float option", tag: "history", hue: 6, ...R("note", 336),
      body: "A double-float camera keeps each number as the sum of two floats: as exact as perturbation, no seams, any k. It lost on cost (each paired-float iteration about 13 plain ones) and risk: GLSL ES 3.0 cannot stop a compiler from fusing or reordering the steps that make the trick work.",
      links: [RL("note", 370, "the risk row")] },
    { title: "Per-frame k → per-ray handoff", tag: "history", hue: 6, ...R("spec", 261),
      body: "The first spec picked one handoff count k per frame from λ_k × d. One k cannot serve rays at different distances (a near wall needs many iterations, a far ray none), so each ray now hands off on its own once |δ| reaches PERT_HANDOFF, with the orbit points as a fifth array (`pert_x`) in place of a single end point. Spec revision b05be22.",
      links: [commitLink("b05be22", "b05be22: per-ray handoff"), RL("pert", 177, "the per-ray test")] },
    { title: "PERT_HANDOFF 1e-2 → 0.1, from the measured grid", tag: "history", hue: 6, ...R("params", 437),
      body: "At 1e-2 four default-box rays in 27 at d = 1e-6 landed 0.15 to 0.5% off (a slightly early handoff); at 0.1 every cell of the grid agreed. The constant lives in FractalParams and in the shader, and shader_test checks they match.",
      links: [RL("pert", 34, "the shader's constant"), RL("spec", 252, "spec")] },
    { title: "The dropped iteration-floor guard", tag: "history", hue: 6, ...R("spec", 290),
      body: "A draft also stopped the camera at a 32-iteration floor estimated as bound_half / (eps × λ_32) from the eye's orbit. That is wrong by orders of magnitude: the eye is outside the shape and its orbit escapes, so its λ_32 is 1e10 to 1e13 against 6e12 to 6e14 at the points its rays hit. A guard a thousand times too early is worse than none; the test prints the measured floor instead (tab 8).",
      links: [RL("tPert", 362, "the printout"), RL("params", 463, "not guarded")] },
    { title: "The KIFS sort and diagonal formulas corrected", tag: "history", hue: 6, ...R("spec", 218),
      body: "The first spec's 'only the reference swaps' cases for the KIFS sort and diagonal fold had sign errors. The plan's Task 1 checked every case against the direct difference in 64-bit before any shader work, found them, and revision b05be22 fixed the spec; the shader and the port carry the corrected cases.",
      links: [commitLink("b05be22", "b05be22"), RL("tPert", 70, "test: the sort cases"), RL("pert", 56, "pert_swap")] },
    { title: "Poly and octahedral folds, the Mandelbulb", tag: "open", hue: 4, ...R("spec", 55),
      body: "Not perturbed yet: the many-region folds need their crossing cases enumerated, and the Mandelbulb's power map is not piecewise-linear (a follow-up spec). They keep today's floor.",
      links: [RL("orb", 312, "the Mandelbulb: not perturbed")] },
    { title: "The 32-iteration floor, and more iterations", tag: "open", hue: 4, ...R("spec", 63),
      body: "Past a point's own 32-iteration floor rays run out of steps and the picture darkens; on the default box at its default view that is about 1e-7 to 1e-8, while the zoom floor allows about 3e-10. More iterations past 32 would push it down; it needs measuring first. tests/perturbation_test.gd prints the data.",
      links: [RL("readme", 166, "README: where 32 iterations run out")] },
    { title: "The orbit camera", tag: "open", hue: 4, ...R("spec", 62),
      body: "Out of scope: the orbit camera cannot approach the surface, so it keeps the 32-bit eye path." },
    { title: "The perturbation-design pane", tag: "open", hue: 4, ...R("spec", 360),
      body: "The spec also asks for a smaller pane that explains the design document itself (the problem, the three approaches, the seven parts), pinned to the spec's commit and linking spec lines. It is not on this branch; a separate /visualize job." },
  ],
};

// The checker (tools/viz/check.mjs) verifies every { file, line } it finds in a pane's data. A
// figure's tooltips are built inside draw(), so each figure also carries `refs`: every R / RL call
// with literal arguments in its draw source (and in the helpers it calls), plus any listed by hand.
function refsIn(fns, extra) {
  const out = [];
  for (const fn of [].concat(fns)) {
    const src = String(fn);
    for (const m of src.matchAll(/\bRL?\("(\w+)",\s*(\d+)/g)) out.push(R(m[1], +m[2]));
  }
  return out.concat(extra || []);
}
const stageRefs = Object.values(STAGE_INFO).flatMap(si => [R("pert", si.shader), R("pert", si.inc), R("port", si.gd), R("port", si.gdf)]);
whyFig.refs = refsIn(whyFig.draw);
orbitFig.refs = refsIn([orbitFig.draw, describeRecord], SAVES.map(s => ({ file: s.file, line: s.line })));
stepFig.refs = refsIn([stepFig.draw, deltaStages], stageRefs);
crossFig.refs = refsIn(crossFig.draw, [112, 113, 114, 115, 116, 117, 118, 119].map(l => R("pert", l)));
handFig.refs = refsIn(handFig.draw);
coarseFig.refs = refsIn(coarseFig.draw);

VIZ.pane({
  id: "deep-zoom",
  short: "Deep zoom",
  title: "Deep zoom — past the 32-bit floor with perturbation",
  subtitle: "The GPU works in 32-bit floats, which near the fractal sit on a grid about 1e-7 apart, so the fly camera used to stop at about 1e-4 from the surface. Now the eye is three 64-bit numbers, the CPU runs the camera's own orbit in 64-bit once per change (the reference orbit), and the GPU follows only each pixel's small offset from it (perturbation), handing off to the ordinary loop once the offset is big enough. The fly camera can now reach about 3e-10 on the default box; the default view is unchanged, bit for bit.",
  commit: COMMIT,
  pinNote: "perturbation branch, unpushed: links 404 until it is pushed",
  ctx: {
    cpu: { hue: 1, label: "64-bit CPU — the eye, the reference orbit, the floors" },
    bridge: { hue: 4, label: "the bridge — uniforms" },
    gpu: { hue: 2, label: "float32 GPU — the march, de_pert" },
    test: { hue: 6, label: "tests — the float32 proof" },
  },
  kinds: {
    call: { style: "solid", label: "calls" },
    signal: { style: "dash", label: "changed signal" },
    data: { style: "dot", label: "reads a value · a uniform" },
  },
  tabs: [
    arch,
    whyFig,
    seq,
    orbitFig,
    stepFig,
    crossFig,
    { label: "Handoff and floors", rows: [[handFig], [floorTable]] },
    { label: "Measured", rows: [[measTable], [fanTable], [view9Table]] },
    coarseFig,
    cards,
  ],
  // The ports, exposed for checking from the console (VIZ.panes.find(p => p.id === "deep-zoom").ports).
  ports: { mbParams, deMB, buildOrbit, ulp32, floor32, floorPert, pertIters, coarseIters, nfWeight, surfaceFrom, defaultSurface, backed, march64, F32, F64, deltaStages, SAVES, CHECK },
});
})();
