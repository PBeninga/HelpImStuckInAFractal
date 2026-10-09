// Pane: the Fractacular import (Help I'm Stuck In A Fractal): the attribute / binding model, the
// virtual axes + keymap + clock, and the console window that edits them. Every file:line below was
// read at `commit` with `git show <commit>:<path>`. When the code changes: re-read the lines, bump
// `commit`, run `node tools/viz/check.mjs --print --pane console`.
//
// The stepper runs a JavaScript port of BindingResolver.resolve / waveform_value, AttributeSpec.sanitize
// and Axes.step, each a small named function below with the lines it was ported from, checked at load
// against the expected values in tests/binding_test.gd and tests/attribute_test.gd.
(function () {
const F = {
  spec: "src/attributes/attribute_spec.gd",
  table: "src/attributes/attribute_table.gd",
  binding: "src/attributes/binding.gd",
  resolver: "src/attributes/binding_resolver.gd",
  axes: "src/axes/axes.gd",
  keymap: "src/axes/keymap.gd",
  axisCtl: "src/axes/axis_controller.gd",
  clock: "src/axes/clock.gd",
  shape: "src/fractal/mandelbox_shape.gd",
  params: "src/fractal/fractal_params.gd",
  view: "src/fractal/fractal_view.gd",
  sh: "src/fractal/mandelbox.gdshader",
  gov: "src/perf/resolution_governor.gd",
  console: "src/ui/console/console_window.gd",
  inspector: "src/ui/console/attribute_inspector.gd",
  row: "src/ui/console/attribute_row.gd",
  movement: "src/ui/console/movement_pane.gd",
  keycap: "src/ui/console/key_capture_button.gd",
  ctrlTap: "src/ui/ctrl_tap.gd",
  textFocus: "src/ui/text_focus.gd",
  uiScale: "src/ui/ui_scale.gd",
  main: "src/main.gd",
  mainScn: "src/main.tscn",
  marker: "src/camera/julia_marker.gd",
  fly: "src/camera/fly_camera.gd",
  orbit: "src/camera/orbit_camera.gd",
  ws: "src/workspace/workspace.gd",
  palette: "src/color/palette.gd",
  pwin: "src/ui/console/palette_window.gd",
  pstrip: "src/ui/console/palette_strip.gd",
  pcurves: "src/ui/console/palette_curves.gd",
  settings: "src/settings/settings.gd",
  renderer: "src/ui/renderer_options.gd",
  viewPane: "src/ui/console/view_pane.gd",
  noiseWin: "src/ui/noise_window.gd",
  kfile: "saves/keymap.json",
  saveDef: "saves/default.json",
  proj: "project.godot",
  readme: "README.md",
  design: "docs/superpowers/specs/2026-10-07-debug-console-design.md",
  plan: "docs/superpowers/plans/2026-10-07-debug-console.md",
  addendum: "docs/superpowers/specs/2026-10-07-usability-harness-design.md",
  levels: "docs/superpowers/specs/2026-10-08-level-sequences-design.md",
  tAttr: "tests/attribute_test.gd",
  tBind: "tests/binding_test.gd",
  tAxes: "tests/axes_test.gd",
  tConsole: "tests/console_test.gd",
  tShape: "tests/mandelbox_shape_test.gd",
  tUiConsole: "tests/ui_console_test.gd",
  tMain: "tests/main_test.gd",
  tParams: "tests/fractal_params_test.gd",
  tWs: "tests/workspace_test.gd",
  tMarker: "tests/julia_marker_test.gd",
  tBoot: "tests/boot_test.gd",
  tPalette: "tests/palette_test.gd",
  tPalWin: "tests/palette_window_test.gd",
  tShader: "tests/shader_test.gd",
};
// Link helpers: R("main", 245) is { file, line }; RL adds a label for a tooltip's link list.
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const REPO = "https://github.com/Adam-G-Klein/HelpImStuckInAFractal";
const COMMIT = sha => ({ url: `${REPO}/commit/${sha}`, label: `commit ${sha.slice(0, 7)}` });

// ================================================================== the ports
// Godot's float helpers, as core/math/math_funcs.h defines them (CMP_EPSILON = 1e-5).
const TAU = 2 * Math.PI;
const CMP_EPSILON = 0.00001;
const isZeroApprox = x => Math.abs(x) < CMP_EPSILON;
function isEqualApprox(a, b) {
  if (a === b) return true;
  let tol = CMP_EPSILON * Math.abs(a);
  if (tol < CMP_EPSILON) tol = CMP_EPSILON;
  return Math.abs(a - b) < tol;
}
function wrapf(v, lo, hi) {
  const range = hi - lo;
  if (isZeroApprox(range)) return lo;
  const r = v - range * Math.floor((v - lo) / range);
  return isEqualApprox(r, hi) ? lo : r;
}
function fposmod(x, y) { let v = x % y; if ((v < 0 && y > 0) || (v > 0 && y < 0)) v += y; return v + 0; }
const clampf = (x, a, b) => (x < a ? a : x > b ? b : x);
const roundf = x => (x < 0 ? -Math.round(-x) : Math.round(x));   // half away from zero, like C round()

// makeSpec: AttributeSpec.make, attribute_spec.gd:53-101 (the keys this pane needs). Extra fields
// (line, field, push, shown) are this pane's: the catalogue line, the FractalParams field line, the
// FractalView push line, and the show_when rule.
function makeSpec(d) {
  const s = { id: d.id, label: d.label || d.id, type: d.type, group: d.group || "", log: !!d.log, wrap: !!d.wrap,
    bindable: true, min: 0, max: 1, step: 0.01, enumValues: [], enumLabels: [],
    line: d.line, field: d.field, push: d.push, shown: d.shown || "" };
  switch (d.type) {
    case "FLOAT": s.min = d.min ?? 0; s.max = d.max ?? 1; s.step = d.step ?? 0.01; s.def = +d.default; break;
    case "INT": s.min = d.min ?? 0; s.max = d.max ?? 1; s.step = 1; s.def = Math.trunc(d.default); break;
    case "BOOL": s.def = !!d.default; s.bindable = false; break;
    case "ENUM":
      s.enumLabels = d.enumLabels || [];
      s.enumValues = d.enumValues || s.enumLabels.map((_, i) => i);
      s.min = 0; s.max = Math.max(s.enumLabels.length - 1, 0); s.step = 1;
      s.def = Math.trunc(d.default); s.bindable = false; break;
  }
  s.hardMin = d.hardMin ?? s.min;
  s.hardMax = d.hardMax ?? s.max;
  if ("bindable" in d) s.bindable = !!d.bindable && s.type !== "BOOL" && s.type !== "ENUM";
  return s;
}

// sanitize: AttributeSpec.sanitize, attribute_spec.gd:113-127.
function sanitize(s, value) {
  switch (s.type) {
    case "FLOAT": { const v = +value; return s.wrap ? wrapf(v, s.min, s.max) : clampf(v, s.hardMin, s.hardMax); }
    case "INT": return roundf(clampf(+value, s.hardMin, s.hardMax));
    case "BOOL": return !!value;
    case "ENUM": { const iv = Math.trunc(+value); return s.enumValues.includes(iv) ? iv : s.def; }
  }
  return value;
}

// waveformValue: BindingResolver.waveform_value, binding_resolver.gd:39-47.
const WAVES = ["LINEAR", "SINE", "TRIANGLE"];
function waveformValue(raw, wave, period) {
  const p = Math.max(period, 1e-6);
  if (wave === "SINE") return Math.sin(TAU * raw / p);
  if (wave === "TRIANGLE") return 1 - 4 * Math.abs(fposmod(raw / p + 0.25, 1) - 0.5);
  return raw;
}

// resolveValue: BindingResolver.resolve_value, binding_resolver.gd:25-36. A binding is
// { source, gain, wave, period } with source "" (none), "time", or an axis id (binding.gd:11-15).
function resolveValue(s, def, b, axisValues, t) {
  if (!b || b.source === "" || !s.bindable) return def;
  let raw = 0;
  if (b.source === "time") raw = t;
  else if (Object.prototype.hasOwnProperty.call(axisValues, b.source)) raw = +axisValues[b.source];
  return sanitize(s, +def + b.gain * waveformValue(raw, b.wave, b.period));
}

// The same steps kept apart, for the stepper's readouts (raw, wave, the unsanitized drive, the result).
function resolveParts(s, def, b, axisValues, t) {
  if (!b || b.source === "" || !s.bindable) return { active: false, raw: 0, wave: 0, pre: def, out: def };
  let raw = 0, known = true;
  if (b.source === "time") raw = t;
  else if (Object.prototype.hasOwnProperty.call(axisValues, b.source)) raw = +axisValues[b.source];
  else known = false;
  const wave = waveformValue(raw, b.wave, b.period), pre = +def + b.gain * wave;
  return { active: true, known, raw, wave, pre, out: resolveValue(s, def, b, axisValues, t) };
}

// axesStep: Axes.step, axes.gd:98-103 (the AxisController passes direction = pos − neg strength,
// axis_controller.gd:25-28; a key is strength 1).
function axesStep(value, direction, speed, delta) { return direction === 0 ? value : value + direction * speed * delta; }

// ================================================================== the catalogue
// MandelboxShape.specs(), mandelbox_shape.gd:56-270, in inspector order. `line` is the spec's id line,
// `field` its FractalParams field (fractal_params.gd:51-155), `push` the FractalView._push_params line
// that sends it (the look keys go in one loop over FractalParams.LOOK_KEYS, fractal_view.gd:316-317).
// The console's Shape tab shows SHAPE_GROUPS, its Colour tab COLOUR_GROUPS (mandelbox_shape.gd:274-275).
const COLOR_MODE_IDS = [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14, 20];  // fractal_params.gd:16
const COLOR_MODE_NAMES = ["Grayscale", "Ice Fractal", "Borg", "Rainbow", "Rainbow 2", "Rainbow 3",
  "Rainbow Metal", "Blue", "Blue 2", "Pink-Blue", "Ice Box", "Ice Box 2", "Gold", "Palette"];
const PALETTE_MODE = 20;                                                   // Palette.MODE_ID, palette.gd:27
const SHAPE_GROUPS = ["Box", "Julia", "Iteration rotation", "Render"];
const COLOUR_GROUPS = ["Colour", "Lighting", "Palette"];
const AX4 = ["x", "y", "z", "w"];
const PLANES = ["xy", "xz", "xw", "yz", "yw", "zw"];                       // PLANE_PAIRS, line 38
const PAL_V = ["A", "B", "C", "D"], PAL_CH = ["red", "green", "blue"], PAL_KEY = ["a", "b", "c", "d"], PAL_RGB = ["r", "g", "b"];
const PAL_RANGE = [[0, 1], [0, 1], [0, 4], [0, 1]];                         // Palette.RANGES, palette.gd:32-33
const PAL_DEF = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 0.0, 0.33, 0.67]; // DEFAULT_COMPONENTS, palette.gd:45-46
const PSHOWN = "color_mode is Palette";
const LOOK = 316;
const SPECS = [
  makeSpec({ id: "box_scale", label: "Scale", group: "Box", type: "FLOAT", default: -2.09, min: -5, max: 3, step: 0.01, hardMin: -6, hardMax: 6, line: 61, field: 51, push: 293 }),
  makeSpec({ id: "fold_limit", label: "Fold limit", group: "Box", type: "FLOAT", default: 1.0, min: 0, max: 3, step: 0.01, line: 68, field: 53, push: 294 }),
  makeSpec({ id: "min_radius", label: "Min radius", group: "Box", type: "FLOAT", default: 0.7, min: 0, max: 2, step: 0.01, line: 74, field: 55, push: 295 }),
  makeSpec({ id: "fixed_radius", label: "Fixed radius", group: "Box", type: "FLOAT", default: 1.0, min: 0, max: 4, step: 0.01, line: 80, field: 57, push: 296 }),
  makeSpec({ id: "fold_order", label: "Fold order", group: "Box", type: "ENUM", default: 0, enumLabels: ["Box → Sphere", "Sphere → Box"], enumValues: [0, 1], line: 86, field: 59, push: 297 }),
  makeSpec({ id: "w", label: "W", group: "Box", type: "FLOAT", default: 0.0, min: -4, max: 4, step: 0.01, line: 95, field: 61, push: 298 }),
  makeSpec({ id: "julia_all", label: "Julia (all)", group: "Julia", type: "BOOL", default: false, line: 103, field: 65, push: 299 }),
  ...[0, 1, 2, 3].map(i => makeSpec({ id: `julia_${i}`, label: `Julia ${AX4[i]}`, group: "Julia", type: "BOOL", default: false, line: 111, field: 67 + 2 * i, push: 300 + i })),
  ...[-0.23, 1.512, 1.892, 0.0].map((d, i) => makeSpec({ id: `c_${i}`, label: `Constant ${AX4[i]}`, group: "Julia", type: "FLOAT", default: d, min: -4, max: 4, step: 0.001, hardMin: -16, hardMax: 16, line: 121, field: 75 + 2 * i, push: 304 + i, shown: `julia_all or julia_${i}` })),
  ...PLANES.map((p, i) => makeSpec({ id: `iter_rot_${p}`, label: `Iter rotation ${p}`, group: "Iteration rotation", type: "FLOAT", default: 0, min: -180, max: 180, step: 0.1, wrap: true, line: 134, field: 85 + 2 * i, push: 308 + i })),
  makeSpec({ id: "precision", label: "Precision", group: "Render", type: "FLOAT", default: 0.000025, min: 1e-6, max: 1e-3, step: 1e-6, log: true, line: 144, field: 99, push: 314 }),
  makeSpec({ id: "color_mode", label: "Colour", group: "Colour", type: "ENUM", default: 1, enumLabels: COLOR_MODE_NAMES, enumValues: COLOR_MODE_IDS, line: 158, field: 103, push: 315 }),
  makeSpec({ id: "palette_source", label: "Palette input", group: "Colour", type: "ENUM", default: 0, enumLabels: ["Steps", "Radius", "Normal"], enumValues: [0, 1, 2], line: 165, field: 105, push: LOOK, shown: PSHOWN }),
  makeSpec({ id: "palette_frequency", label: "Palette frequency", group: "Colour", type: "FLOAT", default: 1.0, min: 0, max: 8, step: 0.01, hardMin: -64, hardMax: 64, line: 174, field: 107, push: LOOK, shown: PSHOWN }),
  makeSpec({ id: "palette_offset", label: "Palette offset", group: "Colour", type: "FLOAT", default: 0.0, min: 0, max: 1, step: 0.001, wrap: true, line: 182, field: 109, push: LOOK, shown: PSHOWN }),
  makeSpec({ id: "palette_occlusion", label: "Palette occlusion", group: "Colour", type: "FLOAT", default: 0.5, min: 0, max: 1, step: 0.01, line: 189, field: 111, push: LOOK, shown: PSHOWN }),
  makeSpec({ id: "light_ambient", label: "Ambient", group: "Lighting", type: "FLOAT", default: 0.1, min: 0, max: 1, step: 0.01, hardMax: 4, line: 198, field: 115, push: LOOK }),
  makeSpec({ id: "light_diffuse", label: "Diffuse", group: "Lighting", type: "FLOAT", default: 0.5, min: 0, max: 2, step: 0.01, hardMax: 8, line: 205, field: 117, push: LOOK }),
  makeSpec({ id: "light_specular", label: "Specular", group: "Lighting", type: "FLOAT", default: 1.0, min: 0, max: 4, step: 0.01, hardMax: 16, line: 212, field: 119, push: LOOK }),
  makeSpec({ id: "light_shininess", label: "Shininess", group: "Lighting", type: "FLOAT", default: 160, min: 1, max: 512, step: 0.1, log: true, line: 219, field: 121, push: LOOK }),
  makeSpec({ id: "light_yaw", label: "Light yaw", group: "Lighting", type: "FLOAT", default: 0, min: -180, max: 180, step: 0.1, wrap: true, line: 226, field: 123, push: LOOK }),
  makeSpec({ id: "light_pitch", label: "Light pitch", group: "Lighting", type: "FLOAT", default: 0, min: -90, max: 90, step: 0.1, line: 233, field: 125, push: LOOK }),
  makeSpec({ id: "exposure", label: "Exposure", group: "Lighting", type: "FLOAT", default: 1.0, min: 0, max: 4, step: 0.01, hardMax: 16, line: 240, field: 127, push: LOOK }),
  makeSpec({ id: "saturation", label: "Saturation", group: "Lighting", type: "FLOAT", default: 1.0, min: 0, max: 2, step: 0.01, hardMax: 4, line: 247, field: 129, push: LOOK }),
  ...PAL_DEF.map((d, i) => { const v = Math.floor(i / 3), ch = i % 3;
    return makeSpec({ id: `palette_${PAL_KEY[v]}_${PAL_RGB[ch]}`, label: `${PAL_V[v]} ${PAL_CH[ch]}`, group: "Palette", type: "FLOAT", default: d,
      min: PAL_RANGE[v][0], max: PAL_RANGE[v][1], step: 0.01, hardMax: v === 2 ? 16 : PAL_RANGE[v][1], wrap: v === 3, line: 259, field: 133 + 2 * i, push: LOOK, shown: PSHOWN }); }),
];
const SPEC = Object.fromEntries(SPECS.map(s => [s.id, s]));

// ================================================================== the port self-check
// The expected values of tests/binding_test.gd and tests/attribute_test.gd (and the −1.59 readout of
// ui_console_test.gd), run through the port at load with the tests' tolerance (check_approx, 1e-4).
const PORT = (function () {
  const a = makeSpec({ id: "a", type: "FLOAT", default: 1.0, min: -100, max: 100 });
  const ang = makeSpec({ id: "ang", type: "FLOAT", default: 350, min: 0, max: 360, wrap: true });
  const n = makeSpec({ id: "n", type: "INT", default: 10, min: 1, max: 100 });
  const en = makeSpec({ id: "e", type: "ENUM", default: 1, enumLabels: ["A", "B"] });
  const f = makeSpec({ id: "f", type: "FLOAT", default: 0.5, min: 0, max: 1 });
  const wide = makeSpec({ id: "w", type: "FLOAT", default: 0, min: -1, max: 1, hardMin: -10, hardMax: 10 });
  const a180 = makeSpec({ id: "a", type: "FLOAT", default: 0, min: -180, max: 180, wrap: true });
  const i8 = makeSpec({ id: "n", type: "INT", default: 4, min: 1, max: 8 });
  const e3 = makeSpec({ id: "e", type: "ENUM", default: 2, enumLabels: ["A", "B", "C"], enumValues: [0, 2, 5] });
  const bind = (source, gain = 1, wave = "LINEAR", period = 4) => ({ source, gain, wave, period });
  const rv = (s, b, ax, t) => resolveValue(s, s.def, b, ax, t);
  const cases = [
    ["tBind", 33, "unbound float is its default", rv(a, bind(""), { a: 1 }, 9), 1],
    ["tBind", 34, "unbound int is its default", rv(n, null, {}, 9), 10],
    ["tBind", 35, "a non-bindable enum is its default", rv(en, bind("q"), { q: 1 }, 0), 1],
    ["tBind", 40, "time: default + gain * t", rv(a, bind("time", 1), {}, 7.25), 8.25],
    ["tBind", 44, "axis: default + gain * value", rv(a, bind("q", 2), { q: 1.5 }, 0), 4],
    ["tBind", 46, "axis with negative gain", rv(a, bind("q", -1), { q: 0.5 }, 0), 0.5],
    ["tBind", 50, "a missing axis resolves to the default", rv(a, bind("gone", 1000), { q: 1 }, 0), 1],
    ["tBind", 53, "LINEAR passes raw", waveformValue(3, "LINEAR", 4), 3],
    ["tBind", 54, "SINE peaks at period/4", waveformValue(1, "SINE", 4), 1],
    ["tBind", 55, "SINE zero at period/2", waveformValue(2, "SINE", 4), 0],
    ["tBind", 56, "TRIANGLE starts at 0", waveformValue(0, "TRIANGLE", 4), 0],
    ["tBind", 57, "TRIANGLE peaks at period/4", waveformValue(1, "TRIANGLE", 4), 1],
    ["tBind", 58, "TRIANGLE zero at period/2", waveformValue(2, "TRIANGLE", 4), 0],
    ["tBind", 59, "TRIANGLE trough at 3/4 period", waveformValue(3, "TRIANGLE", 4), -1],
    ["tBind", 60, "TRIANGLE handles negative raw", waveformValue(-1, "TRIANGLE", 4), -1],
    ["tBind", 62, "SINE with gain and period through resolve", rv(a, bind("time", 3, "SINE", 2), {}, 0.5), 4],
    ["tBind", 66, "clamped to hard_max", rv(a, bind("q", 1000), { q: 1 }, 0), 100],
    ["tBind", 68, "wrapped into [min, max): 350+20 -> 10", rv(ang, bind("q", 20), { q: 1 }, 0), 10],
    ["tBind", 72, "INT rounds the driven value (10+2.6 -> 13)", rv(n, bind("q", 1), { q: 2.6 }, 0), 13],
    ["tAttr", 23, "float clamps to hard_max", sanitize(f, 7), 1],
    ["tAttr", 25, "past the slider but inside the hard range survives", sanitize(wide, 5), 5],
    ["tAttr", 27, "wrap folds into [min, max)", sanitize(a180, 190), -170],
    ["tAttr", 32, "INT rounds", sanitize(i8, 2.6), 3],
    ["tAttr", 33, "INT clamps", sanitize(i8, 99), 8],
    ["tAttr", 44, "ENUM keeps a listed value", sanitize(e3, 5), 5],
    ["tAttr", 45, "ENUM falls back to default for an unlisted value", sanitize(e3, 3), 2],
    ["tUiConsole", 169, "default -2.09 plus gain 1 x 0.5", rv(SPEC.box_scale, bind("a", 1), { a: 0.5 }, 0), -1.59],
  ];
  const fails = cases.filter(c => !(Math.abs(c[3] - c[4]) <= 1e-4)).map(c => `${F[c[0]]}:${c[1]} ${c[2]}: want ${c[4]}, port gives ${c[3]}`);
  if (fails.length) {
    const msg = `[console port] the binding port fails ${fails.length} of ${cases.length} test values: ${fails.join("; ")}`;
    console.error(msg);
    if (typeof VIZ !== "undefined" && Array.isArray(VIZ.errors)) VIZ.errors.push(msg);
  }
  return { n: cases.length, fails, cases };
})();

// ================================================================== shared drawing helpers
const fmt = (x, n = 3) => { if (!isFinite(x)) return String(x); const s = (+x).toFixed(n); return /^-0\.?0*$/.test(s) ? s.slice(1) : s; };
const num = (x, n = 3) => (typeof x === "boolean" ? (x ? "true" : "false") : x === 0 ? "0" : Math.abs(x) < 1e-3 ? (+x).toExponential(2) : fmt(x, n));
const caps = "font-weight:600;letter-spacing:.06em";
const small = "font-size:10.5px";
const noPtr = "pointer-events:none";

// ================================================================== 1. architecture graph
const arch = {
  type: "graph",
  tab: "Architecture",
  title: "Who talks to whom",
  note: "The shape lives in one AttributeTable: a default and a Binding per knob. Key pairs push virtual axes; a clock runs. Once per frame Main resolves table + axis values + t into FractalParams, which every consumer already reads, so the shader, the cameras and the governor never learn that bindings exist. The console only edits the table and the keymap. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "move", label: "MOVEMENT LAYER — KEYS, AXES, CLOCK", x: 0, y: 0, w: 480, h: 560 },
    { id: "core", label: "CATALOGUE AND THE PER-FRAME RESOLVE", x: 540, y: 0, w: 520, h: 560 },
    { id: "cons", label: "CONSUMERS — PARAMS AND THE PICTURE", x: 1120, y: 0, w: 560, h: 560 },
    { id: "mainz", label: "MAIN — WIRING, THE CTRL TAP, THE VIEW TAB", x: 0, y: 620, w: 480, h: 340 },
    { id: "ui", label: "CONSOLE — ITS OWN OS WINDOW", x: 540, y: 620, w: 520, h: 340 },
    { id: "files", label: "SAVED VIEWS", x: 1120, y: 620, w: 560, h: 340 },
  ],
  nodes: [
    // movement layer
    { id: "kfile", label: "saves/keymap.json", sub: "Axis A on E / Q, speed 1", ctx: "files", zone: "move", x: 30, y: 450, w: 180, ...R("kfile", 1),
      blurb: "The shipped keymap: one axis `a` labelled Axis A, pushed at 1 unit per second, E positive, Q negative. Keys are stored by NAME (layout-independent), `\"\"` meaning unbound. Deliberately not part of a saved view: a level loads a view and a keymap separately.",
      links: [RL("kfile", 5, "the axis entry"), RL("readme", 205, "README: Keymap"), RL("design", 190, "spec: the keymap")] },
    { id: "keymap", label: "Keymap", sub: "pairs · rebind API · actions", ctx: "axes", zone: "move", x: 270, y: 450, w: 180, ...R("keymap", 1),
      blurb: "Owns the Axes and one key pair per axis, and keeps two InputMap actions per axis equal to the pair. The rebind API (`add_axis`, `remove_axis`, `bind`, `set_speed`, `set_label`, `load_file`, `save_file`) each emit `changed` so the Movement pane and the Source dropdowns follow. A missing or malformed file yields the default axis.",
      links: [RL("keymap", 40, "add_axis"), RL("keymap", 60, "bind"), RL("keymap", 113, "load_file"), RL("keymap", 187, "_apply_default")] },
    { id: "inputmap", label: "InputMap actions", sub: "axis_<id>_pos / _neg", ctx: "axes", zone: "move", x: 30, y: 60, w: 180, ...R("keymap", 78),
      blurb: "Two runtime actions per axis, registered by `_register_actions`: `axis_a_pos` holds E, `axis_a_neg` holds Q. A rebind erases and re-adds the events. This is why key reading needs no special code and why tests drive an axis with `hold(&\"axis_a_pos\", s)`.",
      links: [RL("keymap", 93, "_set_action"), RL("tAxes", 21, "the actions test"), RL("design", 210, "spec: InputMap")] },
    { id: "axisctl", label: "AxisController", sub: "_process: push the axes", ctx: "axes", zone: "move", x: 270, y: 60, w: 180, ...R("axisCtl", 1),
      blurb: "The only node in the movement layer that touches input. Each frame: direction = strength(pos) − strength(neg) for every axis, then `step`. Skips everything while a text field is focused in any of the main / console / noise viewports, so typing \"e\" never moves an axis.",
      links: [RL("axisCtl", 19, "_process"), RL("axisCtl", 22, "the text-focus gate"), RL("main", 155, "Main gives it the viewports")] },
    { id: "textfocus", label: "TextFocus.any", sub: "a LineEdit focused anywhere?", ctx: "axes", zone: "move", x: 30, y: 190, w: 180, ...R("textFocus", 11),
      blurb: "True when a LineEdit or TextEdit holds focus in any of the given viewports. Each Window is its own viewport (embedded or not), so the axis controller, FlyCamera's WASD, the N key and both Ctrl-tap detectors ask about all of them.",
      links: [RL("fly", 90, "FlyCamera.move_direction uses it"), RL("main", 98, "Main's Ctrl-tap guard"), RL("main", 412, "the N key")] },
    { id: "axes", label: "Axes", sub: "id · label · speed · value", ctx: "axes", zone: "move", x: 270, y: 190, w: 180, ...R("axes", 1),
      blurb: "The virtual axes: an ordered list, each an id, label, push speed and an UNBOUNDED value. `step` adds direction × speed × delta; `set_value` is for loads and the 0 button; `values()` hands the resolver a {id: value} dictionary.",
      links: [RL("axes", 98, "step"), RL("axes", 107, "values"), RL("tAxes", 8, "the test")] },
    { id: "clock", label: "Clock", sub: "t += delta; never saved", ctx: "axes", zone: "move", x: 30, y: 320, w: 150, ...R("clock", 1),
      blurb: "`t`, seconds since the Main scene opened: the `time` source. It has the default pausable process mode, but nothing pauses the tree any more (Escape only frees the mouse), so it runs from the moment the scene opens. Never saved; `reset()` is for tests.",
      links: [RL("clock", 10, "_process"), RL("design", 235, "spec: Clock")] },

    // catalogue + resolve
    { id: "shape", label: "MandelboxShape", sub: "specs(): 47 knobs, two tabs", ctx: "attr", zone: "core", x: 570, y: 60, w: 200, ...R("shape", 1),
      blurb: "The catalogue, in inspector order: Box (scale, fold limit, the two radii, fold order, w), Julia (a master toggle, four per-component toggles, four constants), six iteration-rotation angles and Render (precision) on the console's Shape tab; Colour (the colour mode and the Palette mode's input, frequency, offset, occlusion), Lighting (eight knobs) and the Palette's twelve numbers on its Colour tab. Defaults are the site's, so the opening view is unchanged. Ids are the shader uniform names and the FractalParams field names.",
      links: [RL("shape", 56, "specs()"), RL("shape", 274, "SHAPE_GROUPS / COLOUR_GROUPS"), RL("shape", 280, "group_tooltips"), RL("tShape", 26, "the 47 ids")] },
    { id: "table", label: "AttributeTable", sub: "defaults + Bindings · changed(id)", ctx: "attr", zone: "core", x: 830, y: 190, w: 210, ...R("table", 1),
      blurb: "THE shape state: the specs in order, a default per id and a Binding per bindable id. `set_default` sanitizes and emits `changed(id)` only when the value differs. Every editor writes here (rows, the Julia marker, a load); nothing writes the shape fields of FractalParams directly.",
      links: [RL("table", 51, "set_default"), RL("table", 103, "to_dict"), RL("table", 115, "apply_dict")] },
    { id: "spec", label: "AttributeSpec", sub: "range · wrap · sanitize()", ctx: "attr", zone: "core", x: 570, y: 190, w: 200, ...R("spec", 1),
      blurb: "One knob: id, type (FLOAT / INT / BOOL / ENUM), slider range, hard range, log, wrap, bindable, tooltip and effects text, group, show_when. `sanitize` is the one rule for typed, dragged and driven values: wrap into [min, max), else clamp to the hard range; INT rounds; an unlisted ENUM falls back to the default.",
      links: [RL("spec", 53, "make"), RL("spec", 113, "sanitize"), RL("tAttr", 17, "make / sanitize test")] },
    { id: "binding", label: "Binding", sub: "source · gain · waveform · period", ctx: "attr", zone: "core", x: 830, y: 60, w: 210, ...R("binding", 1),
      blurb: "How one knob is driven: value = default + gain × wave(raw). `source` is a StringName: `&\"\"` none, `&\"time\"` the clock, anything else an axis id (Fractacular used an enum). Defaults: gain 1, Linear, period 4. Only an active binding (source ≠ \"\") is saved.",
      links: [RL("binding", 11, "the four fields"), RL("binding", 40, "from_dict"), RL("tAttr", 82, "round-trip test")] },
    { id: "resolver", label: "BindingResolver", sub: "resolve(table, axes, t)", ctx: "attr", zone: "core", x: 680, y: 320, w: 220, ...R("resolver", 1),
      blurb: "Pure functions, no nodes. For each spec: the default if unbound or not bindable; else raw = t, the axis value, or 0 for an axis id the keymap lacks; then default + gain × wave(raw), sanitized. The stepper tab runs a port of it.",
      links: [RL("resolver", 13, "resolve"), RL("resolver", 25, "resolve_value"), RL("resolver", 39, "waveform_value"), RL("tBind", 22, "the test")] },
    { id: "mresolve", label: "Main._resolve_once", sub: "each _process, first", ctx: "main", zone: "core", x: 680, y: 450, w: 200, ...R("main", 244),
      blurb: "Each frame: `resolve(_table, _keymap.axes().values(), _clock.t)`, then `params.apply_resolved(values)`, then the console's readouts if it is visible. About thirty scalars, so it runs every frame instead of watching the table, every axis and the clock. Main is the parent of Clock and AxisController, so it runs first and reads LAST frame's axis values (stepper tab).",
      links: [RL("main", 237, "_process"), RL("main", 102, "once in _ready"), RL("main", 275, "and after a load"), RL("design", 348, "spec: Main's wiring")] },

    // consumers
    { id: "params", label: "FractalParams", sub: "resolved fields · apply_resolved", ctx: "cons", zone: "cons", x: 1150, y: 60, w: 230, ...R("params", 1),
      blurb: "The object every consumer reads. Its 47 shape and look fields are the RESOLVED values, named by catalogue id. `apply_resolved` writes them with the setters muted and emits `changed` once, and only if something differed: an idle view costs no signal per frame, a Time binding changes every frame.",
      links: [RL("params", 24, "RESOLVED_KEYS"), RL("params", 39, "LOOK_KEYS"), RL("params", 254, "apply_resolved"), RL("tParams", 62, "emits-once test")] },
    { id: "view", label: "FractalView", sub: "_push_params → uniforms", ctx: "cons", zone: "cons", x: 1450, y: 170, w: 220, ...R("view", 290),
      blurb: "On `changed`: pushes every field as the uniform of the same name (Fractacular's convention; the 24 colour, lighting and palette fields in one loop over LOOK_KEYS) and requests a frame. `box_half` follows `julia_enabled()`, which is `julia_all` only.",
      links: [RL("view", 280, "_on_params_changed"), RL("view", 293, "box_scale uniform"), RL("view", 316, "the LOOK_KEYS loop"), RL("view", 319, "box_half")] },
    { id: "gov", label: "ResolutionGovernor", sub: "_dirty → a changing frame", ctx: "cons", zone: "cons", x: 1400, y: 320, w: 230, ...R("gov", 46),
      blurb: "Any `changed` marks the frame as changing, so an animating binding is treated like camera motion: continuous rendering, the adaptive render scale and the load shedder.",
      links: [RL("gov", 69, "reads _dirty in _process")] },
    { id: "marker", label: "JuliaMarker", sub: "drag writes c_0..2 to the table", ctx: "cons", zone: "cons", x: 1150, y: 450, w: 230, ...R("marker", 53),
      blurb: "The white ring at the projected Julia point (shown while `julia_all` is on). A drag writes `c_0..2` into the TABLE with `set_default`, so the next resolve keeps it, and mirrors the defaults into params at once.",
      links: [RL("marker", 61, "set_default c_0"), RL("marker", 64, "mirror into params"), RL("tMarker", 37, "the test")] },

    { id: "palette", label: "Palette", sub: "a cosine palette over the table", ctx: "attr", zone: "cons", x: 1420, y: 450, w: 240, ...R("palette", 1),
      blurb: "Inigo Quilez's cosine palette, ported from Fractacular, but it holds no numbers: the twelve components are catalogue attributes (palette_a_r … palette_d_b) in the shape table, so each saves with the view and can be bound on its own. Palette is the twelve-number view of them for the Colour window. `color_at` is the shader's `palette()` and reads the DRIVEN value of a bound component (`set_live`), the table default otherwise.",
      links: [RL("palette", 109, "color_at"), RL("sh", 254, "the shader's palette()"), RL("palette", 144, "set_live"), RL("tPalette", 114, "the numbers live in the table")] },
    { id: "pwin", label: "PaletteWindow", sub: "Colour tab: sliders · curves · strip", ctx: "ui", zone: "ui", x: 830, y: 900, w: 210, ...R("pwin", 1),
      blurb: "Fractacular's Colour window, now the header of the Colour tab's inspector: twelve sliders, the three cosine curves and the gradient strip, plus Reset. It owns no colour: sliders write `Palette.set_component` (so the table) and everything redraws from the model. A hint shows until the Colour mode is Palette.",
      links: [RL("pwin", 206, "a slider writes the table"), RL("pwin", 114, "set_resolved → set_live"), RL("pwin", 217, "the hint"), RL("tPalWin", 2, "the test")] },
    { id: "mreset", label: "Main.reset_camera", sub: "back to the current file's camera", ctx: "main", zone: "mainz", x: 250, y: 900, w: 210, ...R("main", 292),
      blurb: "The Movement pane's Reset camera button (and the one in the View tab's Renderer options) put the camera and its speed factor back where the current file has them: `_remember_home` runs at start, after a load and after a save. In Orbit it re-centres.",
      links: [RL("main", 301, "_remember_home"), RL("main", 274, "after a load"), RL("main", 187, "the View tab's Renderer button"), RL("tMain", 166, "the test")] },

    { id: "viewpane", label: "ViewPane", sub: "files · camera · renderer · menu", ctx: "ui", zone: "mainz", x: 30, y: 900, w: 200, ...R("viewPane", 1),
      blurb: "The console's third tab, everything the old pause menu held that is not a shape knob: Save view… / Load view… with the file name and a status line, the Camera mode, the mouse sensitivity, Noise editor…, the Renderer options (detail, march steps, Fast Controls, Reset renderer defaults, Reset camera) and Back to Menu. It only emits signals; Main wires them in `_build_view_pane`.",
      links: [RL("viewPane", 14, "its signals"), RL("main", 183, "_build_view_pane"), RL("viewPane", 101, "RendererOptions"), RL("tMain", 140, "the test")] },

    // Main wiring
    { id: "mready", label: "Main._ready", sub: "builds table, keymap, console", ctx: "main", zone: "mainz", x: 30, y: 680, w: 200, ...R("main", 54),
      blurb: "Builds, in order: the AttributeTable from MandelboxShape, the Keymap (loads saves/keymap.json), view, governor, cameras, the marker (given the table), then the Clock, the ConsoleWindow and the AxisController as children of Main, then file panels, pause menu and noise window. Ends with one resolve.",
      links: [RL("main", 64, "the table"), RL("main", 66, "the keymap"), RL("main", 80, "clock, console, axis controller"), RL("main", 155, "AxisController.setup(keymap, viewports)")] },
    { id: "mdispatch", label: "Main._unhandled_input", sub: "Ctrl tap first, then the rest", ctx: "main", zone: "mainz", x: 250, y: 680, w: 210, ...R("main", 390),
      blurb: "The one dispatcher: the Ctrl tap, Escape (frees the mouse, nothing else), ⌘P, N, the Julia marker drag, click-to-capture, then the active camera. Keys the focused console does not use arrive here too, through `unhandled_key`.",
      links: [RL("main", 392, "1. the Ctrl tap"), RL("main", 436, "3. click to capture"), RL("main", 379, "_on_window_key")] },
    { id: "ctrltap", label: "CtrlTap", sub: "arm on Ctrl down, fire on up", ctx: "main", zone: "mainz", x: 30, y: 790, w: 200, ...R("ctrlTap", 1),
      blurb: "The arm/disarm detector, shared: a bare non-echo Ctrl down arms (unless a text field is focused), any other key down disarms, a Ctrl up while armed fires. So Ctrl+S and Ctrl+P never toggle the console. Main runs one; the console runs its own.",
      links: [RL("ctrlTap", 21, "feed"), RL("tMain", 59, "Ctrl+S / Ctrl+P test")] },
    { id: "mtoggle", label: "Main._on_console_toggle", sub: "the capture rule", ctx: "main", zone: "mainz", x: 250, y: 790, w: 210, ...R("main", 364),
      blurb: "Mouse captured: free it and make sure the console is open. Mouse free: toggle the console, and recapture when that closed it. Capture is FLY ∧ not `_free_requested` ∧ noise editor closed: neither the console's visibility nor a pause gates it (nothing pauses).",
      links: [RL("main", 348, "_update_mouse"), RL("tMain", 50, "the test")] },

    // console UI
    { id: "console", label: "ConsoleWindow", sub: "force_native · three tabs · zoom", ctx: "ui", zone: "ui", x: 570, y: 680, w: 200, ...R("console", 1),
      blurb: "A Window with `force_native`: on the desktop its own OS window, opened BESIDE the main window (a native window overlapping it corrupts the main picture on macOS); headless and the web embed it. A VSplit: a TabContainer on top (Shape; Colour with the palette window; View, the old pause menu), the Movement pane below. Runs its own Ctrl-tap detector and hands other keys to Main. Cmd+= / Cmd+- / Cmd+0 zoom the whole window through its content scale, caught in `_input` before any control; Main keeps the level in `Settings.console_zoom`.",
      links: [RL("console", 62, "force_native"), RL("console", 167, "open: place_beside"), RL("console", 75, "the tabs"), RL("console", 209, "zoom_key"), RL("main", 147, "zoom ↔ Settings"), RL("tConsole", 123, "zoom test")] },
    { id: "inspector", label: "AttributeInspector", sub: "one per tab: headings + rows", ctx: "ui", zone: "ui", x: 830, y: 800, w: 210, ...R("inspector", 1),
      blurb: "A ScrollContainer of group headings and one AttributeRow per spec, built once from the table. There are two over the one table: the Shape tab limited to SHAPE_GROUPS, and the Colour tab limited to COLOUR_GROUPS with the palette window as a header that scrolls with the rows. Owns no state: forwards the Source list and each frame's resolved values to the rows; both stay in step through the table's `changed`.",
      links: [RL("inspector", 59, "_populate"), RL("console", 86, "Shape tab"), RL("console", 97, "Colour tab"), RL("inspector", 91, "set_resolved"), RL("tConsole", 48, "one row per spec across the tabs")] },
    { id: "movement", label: "MovementPane", sub: "axis lines · clock · keymap files", ctx: "ui", zone: "ui", x: 570, y: 800, w: 200, ...R("movement", 1),
      blurb: "One line per axis (label, id, live value, 0, speed, two key-capture buttons, ✕), Add axis, the clock and speed-factor readouts beside a Reset camera button, the load-shed level, and Save keymap / Save keymap as… / Load keymap… for the keymap (named in full: the strip is always in view, and a bare Save as… passed for the view's). A view over Keymap: writes through the rebind API, rebuilds on a structural `changed`.",
      links: [RL("movement", 149, "_build_line"), RL("movement", 262, "_on_keymap_changed"), RL("movement", 285, "readouts")] },
    { id: "row", label: "AttributeRow", sub: "value + source · gain · wave", ctx: "ui", zone: "ui", x: 830, y: 680, w: 210, ...R("row", 1),
      blurb: "Fractacular's wide row: label, slider + spin (or a CheckBox / OptionButton), and for bindable specs Source ▾ (None, Time, each axis), Gain, Waveform ▾, Period. Every edit goes to the table; the row re-reads itself on `changed`. While a binding is active it shows `→ value`, the resolved value this frame.",
      links: [RL("row", 52, "setup"), RL("row", 251, "_build_binding"), RL("row", 101, "set_resolved")] },
    { id: "keycap", label: "KeyCaptureButton", sub: "click, then press a key", ctx: "ui", zone: "ui", x: 570, y: 900, w: 200, ...R("keycap", 1),
      blurb: "Click it, press a key: the physical keycode is captured and shown by name; Escape cancels. The pane then calls `Keymap.bind` with both buttons' keys.",
      links: [RL("keycap", 38, "_input"), RL("keycap", 47, "_capture")] },

    // saved views
    { id: "msave", label: "Main save / load", sub: "save_view_to · load_view_from", ctx: "main", zone: "files", x: 1440, y: 680, w: 230, ...R("main", 253),
      blurb: "The console View tab's Save view… / Load view… and ⌘S land here. After a load Main resolves at once so the picture follows this frame.",
      links: [RL("main", 264, "load_view_from"), RL("main", 275, "resolve after a load")] },
    { id: "ws", label: "Workspace", sub: "view JSON v2 · v1 migration", ctx: "files", zone: "files", x: 1440, y: 790, w: 230, ...R("ws", 1),
      blurb: "A view, version 2: `shape` (the table's defaults and ACTIVE bindings), `axes` (every axis value), `fractal` (preferences), `camera`, `noise`. The clock and the keymap are not saved. A version-1 file is migrated to the new ids without a warning.",
      links: [RL("ws", 31, "capture"), RL("ws", 56, "restore"), RL("ws", 75, "axis values: Axes.set_value"), RL("ws", 181, "_migrate_v1")] },
    { id: "saves", label: "saves/*.json", sub: "default.json and friends, all v2", ctx: "files", zone: "files", x: 1440, y: 900, w: 230, ...R("saveDef", 2),
      blurb: "The committed views, rewritten to version 2 once: every catalogue id under shape.defaults, no bindings, no axis values.",
      links: [RL("saveDef", 3, "the shape section")] },
  ],
  edges: [
    { from: "keymap", to: "kfile", kind: "data", label: "load / save", ...R("keymap", 113), bow: 0,
      blurb: "`load_file` parses the JSON (keys by name via OS.find_keycode_from_string); `save_file` writes names with OS.get_keycode_string.", links: [RL("keymap", 159, "save_file")] },
    { from: "keymap", to: "inputmap", kind: "call", label: "_register_actions", ...R("keymap", 88),
      blurb: "Erase the action's events and add one InputEventKey with the physical keycode (none for KEY_NONE).", links: [RL("keymap", 100, "action_add_event")] },
    { from: "keymap", to: "axes", kind: "call", label: "owns", ...R("keymap", 44), bow: 0.4,
      blurb: "`add_axis` adds the axis to its Axes; `remove_axis` and `_clear_all` take it out (and its value with it)." },
    { from: "axisctl", to: "inputmap", kind: "data", label: "strength", ...R("axisCtl", 25), bow: 0,
      blurb: "`Input.get_action_strength(pos) − get_action_strength(neg)`: +1 for E, −1 for Q, 0 for both or neither." },
    { from: "axisctl", to: "axes", kind: "call", label: "step", ...R("axisCtl", 28), bow: 0,
      blurb: "`step(id, direction, delta)`: value += direction × speed × delta, then `changed`." },
    { from: "axisctl", to: "textfocus", kind: "data", label: "typing?", ...R("axisCtl", 22), bow: 0.3,
      blurb: "A focused text field in any viewport silences every axis for the frame." },
    { from: "shape", to: "spec", kind: "call", label: "make", ...R("shape", 60),
      blurb: "Each knob is one `AttributeSpec.make({...})` dictionary." },
    { from: "shape", to: "table", kind: "call", label: "specs()", ...R("main", 64), bow: 0,
      blurb: "Main builds `AttributeTable.new(MandelboxShape.specs())`." },
    { from: "table", to: "spec", kind: "call", label: "sanitize", ...R("table", 56), bow: 0.3,
      blurb: "`set_default` sanitizes through the spec, so a typed or dragged default obeys the same clamp / wrap as a driven value." },
    { from: "table", to: "binding", kind: "call", label: "one per bindable id", ...R("table", 30), bow: 0,
      blurb: "`_add` gives every bindable spec a fresh, inactive Binding." },
    { from: "resolver", to: "table", kind: "data", label: "defaults · bindings", ...R("resolver", 16), bow: -0.4,
      blurb: "For each spec: `table.get_default(id)` and `table.binding(id)`." },
    { from: "resolver", to: "spec", kind: "call", label: "sanitize", ...R("resolver", 36), bow: 0.3,
      blurb: "The driven value goes through the spec's `sanitize`." },
    { from: "mresolve", to: "resolver", kind: "call", label: "resolve()", ...R("main", 245), bow: 0,
      blurb: "`BindingResolver.resolve(_table, _keymap.axes().values(), _clock.t)`." },
    { from: "mresolve", to: "axes", kind: "data", label: "values()", ...R("main", 245), bow: -0.2,
      blurb: "The axis values as AxisController left them at the END of the previous frame (Main processes before its children)." },
    { from: "mresolve", to: "clock", kind: "data", label: "t", ...R("main", 245), bow: 0.2,
      blurb: "The clock as it stood after the previous frame." },
    { from: "mresolve", to: "params", kind: "call", label: "apply_resolved", ...R("main", 246), bow: 0.4,
      blurb: "Writes every resolved field, emits `changed` at most once." },
    { from: "mresolve", to: "console", kind: "call", label: "set_resolved", ...R("main", 248), bow: -0.2,
      blurb: "Only while the console is visible: the bound rows' `→ value` readouts follow.", links: [RL("console", 158, "set_resolved")] },
    { from: "params", to: "view", kind: "signal", label: "changed → uniforms", ...R("view", 74), bow: 0,
      blurb: "`_on_params_changed` → `_push_params` + `request_frame`." },
    { from: "params", to: "gov", kind: "signal", label: "_dirty", ...R("gov", 46), bow: -0.6,
      blurb: "Every `changed` marks the frame as changing." },
    { from: "params", to: "marker", kind: "signal", ...R("marker", 23), bow: 0,
      blurb: "The ring shows with `julia_all` and redraws at the new point." },
    { from: "marker", to: "table", kind: "call", label: "set_default c_0..2", ...R("marker", 61), bow: 0.2,
      blurb: "The drag lands in the table, so the next resolve keeps it." },
    { from: "mready", to: "keymap", kind: "call", label: "load_file()", ...R("main", 66), bow: 0.3,
      blurb: "`Keymap.new()` then `load_file()`: saves/keymap.json, or the shipped default with a warning." },
    { from: "mready", to: "console", kind: "call", label: "setup", ...R("main", 141), bow: -0.2,
      blurb: "`setup(table, keymap, clock, group_tooltips, speed source)`." },
    { from: "mdispatch", to: "ctrltap", kind: "call", label: "feed", ...R("main", 392), bow: 0.3,
      blurb: "Step 1 of the dispatcher." },
    { from: "mdispatch", to: "mtoggle", kind: "call", label: "a tap", ...R("main", 393), bow: 0,
      blurb: "A fired tap runs the capture rule." },
    { from: "mtoggle", to: "console", kind: "call", label: "open / toggle", ...R("main", 368), bow: 0.4,
      blurb: "Captured: `open()` if hidden. Free: `toggle()`.", links: [RL("main", 370, "toggle")] },
    { from: "console", to: "mtoggle", kind: "signal", label: "toggle_requested", ...R("main", 144), bow: 0.4,
      blurb: "The console's own detector fired: the native window received the Ctrl keys, so Main never saw them.", links: [RL("console", 230, "emit")] },
    { from: "console", to: "mdispatch", kind: "signal", label: "unhandled_key", ...R("main", 145), bow: -0.6,
      blurb: "Escape, N, ⌘S, ⌘P… pressed while the console has focus run through Main's dispatch.", links: [RL("console", 252, "the forward")] },
    { from: "console", to: "inspector", kind: "call", label: "setup", ...R("console", 86), bow: 0,
      blurb: "`_inspector.setup(table, group_tooltips)`; on every Keymap `changed`, `set_sources(axes)`.", links: [RL("console", 256, "_refresh_sources")] },
    { from: "console", to: "movement", kind: "call", label: "setup", ...R("console", 105), bow: 0 },
    { from: "inspector", to: "row", kind: "call", label: "one per spec", ...R("inspector", 79), bow: 0 },
    { from: "row", to: "table", kind: "call", label: "edits", ...R("row", 334), bow: 1.2,
      blurb: "Slider / spin / check / option → `set_default`; source / gain / wave / period edit the Binding and `notify_binding_changed`.", links: [RL("row", 368, "binding edits")] },
    { from: "table", to: "row", kind: "signal", label: "changed(id)", ...R("row", 60), bow: 0.8,
      blurb: "Each row connects `changed` to `refresh`, guarded by `_updating` so its own edit does not echo." },
    { from: "movement", to: "keymap", kind: "call", label: "rebind API", ...R("movement", 258), bow: -1.6,
      blurb: "Add axis, bind, set_speed, set_label, remove_axis, save_file, load_file.", links: [RL("movement", 225, "add_axis"), RL("movement", 205, "remove_axis")] },
    { from: "keymap", to: "console", kind: "signal", label: "changed", ...R("console", 111), bow: -0.3,
      blurb: "The Source dropdowns relist the axes; the Movement pane rebuilds on add / remove (movement_pane.gd:110)." },
    { from: "movement", to: "keycap", kind: "call", label: "two per axis", ...R("movement", 189), bow: 0,
      blurb: "Positive and negative; `key_captured` → `Keymap.bind(id, pos.key(), neg.key())`." },
    { from: "pwin", to: "palette", kind: "call", label: "set_component · set_live", ...R("pwin", 209), bow: 0,
      blurb: "A slider writes one component through the palette into the table; each frame the console's `set_resolved` hands the resolved values to `set_live`, so the strip follows a bound channel.", links: [RL("pwin", 116, "set_live")] },
    { from: "palette", to: "table", kind: "call", label: "the twelve ids", ...R("palette", 127), bow: 0.2,
      blurb: "`set_component` is `set_default` on `palette_<v>_<ch>`; `get_component` reads the default; `_on_table_changed` re-emits `changed` for color_mode and the twelve.", links: [RL("palette", 202, "_on_table_changed")] },
    { from: "inspector", to: "pwin", kind: "call", label: "Colour tab header", ...R("console", 97), bow: 0,
      blurb: "The Colour tab is a second AttributeInspector limited to COLOUR_GROUPS, with the palette window as its header row." },
    { from: "console", to: "viewpane", kind: "call", label: "View tab", ...R("console", 99), bow: -2,
      blurb: "`ViewPane.new()` is the TabContainer's third child; Main fetches it with `view_pane()` and wires save / load / noise / menu / sensitivity.", links: [RL("main", 184, "Main takes it")] },
    { from: "viewpane", to: "mreset", kind: "signal", ...R("main", 187), bow: 0,
      blurb: "The Renderer options' Reset camera button." },
    { from: "movement", to: "mreset", kind: "signal", label: "reset_camera_requested", ...R("main", 149), bow: 0,
      blurb: "The button's signal, relayed by the console (console_window.gd:106).", links: [RL("movement", 74, "the button")] },
    { from: "msave", to: "ws", kind: "call", label: "save / load", ...R("main", 255), bow: 0,
      blurb: "`Workspace.save_file(path, _table, _keymap.axes(), params, camera, noise)`.", links: [RL("main", 266, "load_file")] },
    { from: "ws", to: "saves", kind: "data", label: "JSON", ...R("ws", 108), bow: 0 },
    { from: "ws", to: "table", kind: "call", label: "to_dict / apply_dict", ...R("ws", 61), bow: 1.0,
      blurb: "Capture writes `table.to_dict()` (active bindings only); restore runs `apply_dict`, which sets the listed defaults and bindings and leaves the rest.", links: [RL("ws", 40, "capture")] },
  ],
};

// ================================================================== 2. one frame
const frameSeq = {
  type: "seq",
  tab: "One frame",
  title: "One frame: a held key, through a binding, to the uniforms",
  note: "Godot runs `_process` in tree order, parents first. Main is the parent of Clock and AxisController, so in frame N Main resolves with the axis value and clock time those two left at the end of frame N−1, and only later in the frame do they move. A held key reaches the picture one frame after it moved the axis. `apply_resolved` emits only when a value differs, so an axis at rest costs nothing.",
  laneWidth: 168, headWidth: 150,
  participants: [
    { id: "input", col: 0, ctx: "axes", name: "Input", sub: "E held (axis_a_pos)", ...R("keymap", 78), blurb: "Godot's global Input state. The keymap registered `axis_a_pos` on E and `axis_a_neg` on Q." },
    { id: "ctl", col: 1, ctx: "axes", name: "AxisController", sub: "child of Main", ...R("axisCtl", 1) },
    { id: "axes", col: 2, ctx: "axes", name: "Axes", sub: "Axis A value", ...R("axes", 1) },
    { id: "clock", col: 3, ctx: "axes", name: "Clock", sub: "child of Main", ...R("clock", 1) },
    { id: "main", col: 4, ctx: "main", name: "Main", sub: "_process (the parent)", ...R("main", 237) },
    { id: "res", col: 5, ctx: "attr", name: "BindingResolver", sub: "static, pure", ...R("resolver", 1) },
    { id: "spec", col: 6, ctx: "attr", name: "AttributeSpec", sub: "sanitize", ...R("spec", 113) },
    { id: "params", col: 7, ctx: "cons", name: "FractalParams", sub: "resolved fields", ...R("params", 1) },
    { id: "view", col: 8, ctx: "cons", name: "FractalView", sub: "uniforms", ...R("view", 290) },
    { id: "gov", col: 9, ctx: "cons", name: "ResolutionGovernor", sub: "child of Main", ...R("gov", 66) },
    { id: "console", col: 10, ctx: "ui", name: "ConsoleWindow", sub: "Shape rows", ...R("console", 1) },
  ],
  rows: [
    { sec: "FRAME N · Main._process: the parent runs before its children" },
    { from: "main", to: "main", kind: "call", label: "_process → _resolve_once()", ...R("main", 237),
      blurb: "Every frame, not only on change: about thirty scalars.", links: [RL("main", 241, "why every frame")] },
    { from: "main", to: "axes", kind: "data", label: "_keymap.axes().values()", tick: "what frame N−1 pushed", ...R("main", 245),
      blurb: "A {id: value} dictionary of every axis.", links: [RL("axes", 107, "values")] },
    { from: "main", to: "clock", kind: "data", label: "_clock.t", tick: "frame N−1's t", ...R("main", 245),
      blurb: "Clock has not run its own `_process` yet this frame." },
    { from: "main", to: "res", kind: "call", label: "resolve(table, values, t)", ...R("main", 245),
      blurb: "One dictionary out: catalogue id → value.", links: [RL("resolver", 13, "resolve")] },
    { from: "res", to: "res", kind: "call", label: "resolve_value(spec, default, binding)", ...R("resolver", 16),
      blurb: "Once per spec, in catalogue order." },
    { from: "res", to: "res", kind: "call", label: "unbound or not bindable → default", ...R("resolver", 26),
      blurb: "BOOL and ENUM knobs (the Julia toggles, fold order, colour mode) are never bindable, so they always return the table default." },
    { from: "res", to: "res", kind: "call", label: "raw = t | axis value | 0", tick: "an unknown axis id stays 0", ...R("resolver", 28),
      blurb: "`&\"time\"` reads t; a known axis id reads its value; anything else leaves raw at 0, so a view bound to an axis the keymap lacks shows its default.", links: [RL("resolver", 33, "the comment")] },
    { from: "res", to: "res", kind: "call", label: "default + gain × waveform_value(raw)", tick: "Linear | sin(2π raw/p) | triangle", ...R("resolver", 35),
      links: [RL("resolver", 39, "waveform_value")] },
    { from: "res", to: "spec", kind: "call", label: "sanitize(value)", ...R("resolver", 36), toRole: "wrapf into [min, max) for angles, else clampf to the hard range; INT rounds; ENUM falls back.",
      blurb: "The same rule a typed value goes through.", links: [RL("spec", 113, "sanitize")] },
    { from: "main", to: "params", kind: "call", label: "apply_resolved(values)", ...R("main", 246),
      links: [RL("params", 254, "apply_resolved")] },
    { from: "params", to: "params", kind: "call", label: "get(k) != v → set, setters muted", ...R("params", 261),
      blurb: "`_suppress` stops each setter's `emit_changed`; `dirty` remembers whether anything moved.", links: [RL("params", 256, "_suppress = true")] },
    { from: "params", to: "view", kind: "signal", label: "changed → _push_params", tick: "+ request_frame()", ...R("view", 280),
      blurb: "All shape uniforms are pushed again (and near_dist recomputed), then a frame is requested.", links: [RL("view", 293, "box_scale")] },
    { from: "params", to: "gov", kind: "signal", label: "changed → _dirty = true", ...R("gov", 46),
      blurb: "This frame counts as 'changing': continuous rendering and the adaptive scale." },
    { from: "params", to: "params", kind: "call", label: "nothing differed: no signal at all", ...R("params", 265),
      blurb: "An axis at rest, or no active binding: the resolve costs the scalars and nothing else.", links: [RL("tParams", 74, "the no-emit test")] },
    { from: "main", to: "console", kind: "call", label: "set_resolved(values)", ...R("main", 248),
      blurb: "Only while the console is visible.", links: [RL("console", 158, "set_resolved")] },
    { from: "console", to: "console", kind: "call", label: "each bound row: \"→ value\"", ...R("row", 109),
      blurb: "Both tabs' inspectors forward to every row (a row with an active binding shows the value in use this frame), and the palette window hands the values to `Palette.set_live`, so the strip and curves follow a bound channel.", links: [RL("console", 158, "both tabs and the palette window"), RL("inspector", 91, "inspector.set_resolved"), RL("pwin", 114, "PaletteWindow.set_resolved")] },
    { sec: "LATER IN FRAME N · the children of Main, in tree order" },
    { from: "gov", to: "gov", kind: "call", label: "_process: changing = _dirty", ...R("gov", 69),
      blurb: "Sees the `changed` from this frame's resolve." },
    { from: "clock", to: "clock", kind: "call", label: "t += delta", ...R("clock", 11),
      blurb: "Nothing pauses the tree any more, so it always runs." },
    { from: "ctl", to: "ctl", kind: "call", label: "TextFocus.any(viewports)?", tick: "typing: skip the whole frame", ...R("axisCtl", 22) },
    { from: "ctl", to: "input", kind: "data", label: "strength(pos) − strength(neg)", ...R("axisCtl", 25),
      blurb: "E alone: +1. Ctrl or Cmd held does not silence it (unlike WASD)." },
    { from: "ctl", to: "axes", kind: "call", label: "step(a, +1, delta)", ...R("axisCtl", 28) },
    { from: "axes", to: "axes", kind: "call", label: "value += direction × speed × delta", tick: "1 × 1.0 × 1/60 = 0.0167", ...R("axes", 102),
      blurb: "Unbounded; emits `changed` (the Movement pane polls its readouts in `_process` instead).", links: [RL("kfile", 7, "speed 1.0")] },
    { sec: "FRAME N+1" },
    { from: "main", to: "axes", kind: "data", label: "values(): now sees the pushed value", ...R("main", 245),
      blurb: "The key press of frame N reaches params, the uniforms and the readout here." },
  ],
  fragments: [
    { type: "loop", rows: [5, 9], cols: [5, 6], guard1: "each spec in table.specs" },
    { type: "alt", rows: [12, 14], cols: [7, 9], guard1: "a value differed", divRow: 14, guard2: "all equal" },
    { type: "opt", rows: [15, 16], cols: [4, 10], guard1: "console visible" },
    { type: "opt", rows: [21, 23], cols: [0, 2], guard1: "no text field focused" },
  ],
};

// ================================================================== 6. the Ctrl tap and the mouse
const tapSeq = {
  type: "seq",
  tab: "Ctrl tap and the mouse",
  title: "The Ctrl tap, two detectors and the mouse",
  note: "Ctrl is also a chord key (⌘S, Ctrl+P), so a tap fires on RELEASE and only if no other key went down in between. A native console window gets its own key events, so it runs its own detector and forwards the keys it does not use to Main. Capture no longer depends on the console being open: a click in the view recaptures and leaves it open, so its readouts stay in sight while flying. Escape only frees the mouse: it never pauses (there is no pause any more) and never closes the console.",
  laneWidth: 210, headWidth: 180,
  participants: [
    { id: "kb", col: 0, ctx: "axes", name: "player", sub: "keyboard · mouse" },
    { id: "disp", col: 1, ctx: "main", name: "Main._unhandled_input", sub: "the dispatcher", ...R("main", 390) },
    { id: "tapM", col: 2, ctx: "main", name: "CtrlTap", sub: "Main's", ...R("main", 43) },
    { id: "tog", col: 3, ctx: "main", name: "Main._on_console_toggle", sub: "the capture rule", ...R("main", 364) },
    { id: "con", col: 4, ctx: "ui", name: "ConsoleWindow", sub: "native OS window", ...R("console", 1) },
    { id: "tapC", col: 5, ctx: "ui", name: "CtrlTap", sub: "the console's", ...R("console", 55) },
    { id: "mouse", col: 6, ctx: "axes", name: "Input.mouse_mode", sub: "CAPTURED / VISIBLE", ...R("main", 352) },
  ],
  rows: [
    { sec: "THE MAIN WINDOW HAS FOCUS · Main's own detector" },
    { from: "kb", to: "disp", kind: "call", label: "Ctrl down (not an echo)", ...R("main", 392) },
    { from: "disp", to: "tapM", kind: "call", label: "feed(event): arm", tick: "unless a text field is focused", ...R("ctrlTap", 27),
      blurb: "`_armed = not _typing()`: the typing guard asks TextFocus about every viewport.", links: [RL("main", 98, "the guard")] },
    { from: "kb", to: "disp", kind: "call", label: "S down (Ctrl+S)", tick: "any other key while armed", ...R("main", 392) },
    { from: "disp", to: "tapM", kind: "call", label: "feed: disarm", ...R("ctrlTap", 32),
      blurb: "So Ctrl+S saves and never toggles; Ctrl+P is disarmed before the screenshot consumes its P.", links: [RL("tMain", 65, "the Ctrl+P test")] },
    { from: "kb", to: "disp", kind: "call", label: "Ctrl up", ...R("main", 392) },
    { from: "disp", to: "tapM", kind: "call", label: "feed: armed → fire (true)", ...R("ctrlTap", 28) },
    { from: "disp", to: "tog", kind: "call", label: "_on_console_toggle()", ...R("main", 393) },
    { from: "tog", to: "tog", kind: "call", label: "_free_requested = true", ...R("main", 366),
      blurb: "Flying: the tap frees the mouse." },
    { from: "tog", to: "con", kind: "call", label: "open() if hidden", ...R("main", 368), blurb: "open() places the native window beside the main one (UiScale.place_beside), never over it.",
      links: [RL("console", 168, "place_beside"), RL("uiScale", 160, "beside_position")] },
    { from: "tog", to: "con", kind: "call", label: "toggle()", ...R("main", 370) },
    { from: "tog", to: "tog", kind: "call", label: "now hidden → _free_requested = false", ...R("main", 372) },
    { from: "tog", to: "mouse", kind: "call", label: "_update_mouse()", tick: "FLY ∧ ¬_free_requested ∧ ¬noise", ...R("main", 373),
      links: [RL("main", 349, "the rule")] },
    { sec: "THE CONSOLE HAS FOCUS · the native window gets the keys" },
    { from: "kb", to: "con", kind: "call", label: "Ctrl down … Ctrl up", ...R("console", 245),
      blurb: "Only while visible." },
    { from: "con", to: "tapC", kind: "call", label: "feed_ctrl(event)", ...R("console", 229),
      links: [RL("console", 109, "its typing guard: its own viewport")] },
    { from: "con", to: "tog", kind: "signal", label: "toggle_requested", ...R("main", 144),
      blurb: "Main runs the same rule as for its own tap.", links: [RL("console", 230, "emit")] },
    { from: "kb", to: "con", kind: "call", label: "Escape · N · ⌘S · ⌘P", ...R("console", 252),
      blurb: "Any key except Ctrl that the console's controls left unhandled." },
    { from: "con", to: "disp", kind: "signal", label: "unhandled_key → _on_window_key", ...R("main", 145),
      blurb: "Runs Main's whole dispatch, plus ⌘S quick-save.", links: [RL("main", 379, "_on_window_key")] },
    { sec: "A CLICK IN THE VIEW" },
    { from: "kb", to: "disp", kind: "call", label: "left click · FLY · mouse free", ...R("main", 436),
      blurb: "A click on the console is the console's own and never gets here.", links: [RL("tMain", 118, "the real-click test")] },
    { from: "disp", to: "mouse", kind: "call", label: "_free_requested = false · _update_mouse()", tick: "the console stays open", ...R("main", 440),
      links: [RL("main", 443, "_update_mouse"), RL("tMain", 104, "the test")] },
    { sec: "ESCAPE · frees the mouse, nothing else" },
    { from: "kb", to: "disp", kind: "call", label: "Escape (the cancel action)", tick: "from either window", ...R("main", 399),
      blurb: "Pressed in the main window it lands here directly; pressed in the focused console it arrives through unhandled_key like the other unused keys.", links: [RL("proj", 63, "cancel = Escape"), RL("console", 252, "the console's forward")] },
    { from: "disp", to: "mouse", kind: "call", label: "_free_requested = true · _update_mouse()", tick: "no pause; the console stays open", ...R("main", 400),
      links: [RL("tMain", 240, "the test"), RL("tMain", 249, "never closes the console")] },
  ],
  fragments: [
    { type: "alt", rows: [8, 11], cols: [3, 5], guard1: "mouse captured", divRow: 10, guard2: "mouse free" },
  ],
};

// ================================================================== 3. the stepper
// simulate: the frames of Main._process → Clock._process → AxisController._process (main.gd:237-248,
// clock.gd:10-11, axis_controller.gd:19-28), from the key held in each frame. Frame 0 is Main._ready's
// resolve (main.gd:102). Each frame READS the axis and t frame n−1 left and WRITES params, t and the axis.
// `alt` is a hypothetical: the value the same frame would write if the axes moved before the resolve.
const STEP_IDS = ["box_scale", "fold_limit", "iter_rot_xy", "c_0"];
const STEP_DIALS = {
  box_scale: { def: [-5, 3, 0.01], gain: [-10, 10, 0.05] },
  fold_limit: { def: [0, 3, 0.01], gain: [-5, 5, 0.05] },
  iter_rot_xy: { def: [-180, 180, 0.5], gain: [-400, 400, 1] },
  c_0: { def: [-4, 4, 0.01], gain: [-20, 20, 0.1] },
};
function simulate(keys, c) {
  const b = { source: c.source, gain: c.gain, wave: c.wave, period: c.period };
  const parts = (ax, t) => resolveParts(c.spec, c.def, b, { a: ax }, t);   // the keymap holds axis `a` only
  const f0 = Object.assign({ n: 0, key: 0, axisIn: 0, tIn: 0, axis: 0, t: 0, emitted: false }, parts(0, 0));
  f0.param = f0.out; f0.prevParam = c.spec.def; f0.alt = f0.out;
  const frames = [f0];
  for (let n = 1; n <= keys.length; n++) {
    const p = frames[n - 1], r = parts(p.axis, p.t), dir = keys[n - 1];
    const t = p.t + c.dt, axis = axesStep(p.axis, dir, c.speed, c.dt);
    frames.push(Object.assign({ n, key: dir, axisIn: p.axis, tIn: p.t, t, axis, prevParam: p.param }, r,
      { param: r.out, emitted: r.out !== p.param, alt: parts(axis, t).out }));
  }
  return frames;
}

const stepFig = {
  type: "figure",
  tab: "Frame by frame",
  title: "A held key through a binding, frame by frame",
  note: "A port of BindingResolver.resolve_value + waveform_value (binding_resolver.gd:25-47), AttributeSpec.sanitize (attribute_spec.gd:113-127) and Axes.step (axes.gd:98-103), run in the order Godot runs the nodes: Main resolves FIRST (it is the parent), then Clock and AxisController move. So frame N writes params from the axis value frame N−1 left. Pick the key held, Step through frames, change the binding on shared controls; hover or click any column for its numbers. The dials start at the shipped defaults (gain 1, Linear, period 4, speed 1 unit/s, 60 fps). The port is checked at load against binding_test.gd and attribute_test.gd.",
  w: 1560, h: 890,
  draw(api) {
    const C_RAW = api.hue(1), C_AX = api.hue(3), C_PAR = api.hue(6), C_PRE = api.hue(2), C_ALT = api.hue(4), C_EMIT = api.hue(2);
    const S = { keys: [], k: 0, cur: 1, spec: "box_scale", source: "a", wave: "LINEAR", period: 4, speed: 1, fps: 60, ghost: true,
      dial: Object.fromEntries(STEP_IDS.map(id => [id, { def: SPEC[id].def, gain: 1 }])) };
    for (let i = 0; i < 45; i++) S.keys.push(1);
    for (let i = 0; i < 15; i++) S.keys.push(0);
    S.k = S.keys.length;
    let frames = [];
    const cfg = () => ({ spec: SPEC[S.spec], def: S.dial[S.spec].def, source: S.source, gain: S.dial[S.spec].gain, wave: S.wave, period: S.period, speed: S.speed, dt: 1 / S.fps });
    const KEYNAME = d => (d > 0 ? "E held" : d < 0 ? "Q held" : "no key");
    const SRCNAME = () => (S.source === "a" ? "Axis A" : S.source === "time" ? "Time" : "axis \"b\" (not in the keymap)");
    const WNAME = { LINEAR: "Linear", SINE: "Sine", TRIANGLE: "Triangle" };

    // ---- the stage boxes: frame N's steps in run order, each showing this frame's number
    const BW = 208, BG = 10, BH = 76, BY0 = 16;
    const STAGES = [
      { n: "1", name: "raw", f: "axis(N−1) | t(N−1) | 0", c: C_RAW, tip: { ...R("resolver", 28), blurb: "Main reads `_keymap.axes().values()` and `_clock.t` as the previous frame left them. `time` reads t, a known axis id its value, an unknown id 0.", links: [RL("main", 245, "the call"), RL("resolver", 33, "unknown axis → 0")] } },
      { n: "2", name: "wave", f: "raw | sin 2πr/p | tri", c: C_RAW, tip: { ...R("resolver", 39), blurb: "Linear passes raw through (period unused). Sine is sin(2π·raw/p). Triangle is 1 − 4·|fposmod(raw/p + ¼, 1) − ½|: 0 at 0, +1 at p/4, 0 at p/2, −1 at 3p/4.", links: [RL("resolver", 43, "sine"), RL("resolver", 46, "triangle")] } },
      { n: "3", name: "drive", f: "default + gain × wave", c: C_PRE, tip: { ...R("resolver", 35), blurb: "The table default plus the binding's gain times the wave. Gain is the key's sensitivity: with Linear and speed 1, gain 0.5 moves the knob half a unit per second of E.", links: [RL("binding", 12, "gain default 1")] } },
      { n: "4", name: "sanitize", f: "wrap [min,max) | clamp hard", c: C_PAR, tip: { ...R("spec", 113), blurb: "Angles (`wrap`) fold into [min, max) with wrapf; every other FLOAT clamps to the HARD range, which may be wider than the slider (box_scale: slider −5…3, hard ±6; constants: slider ±4, hard ±16).", links: [RL("spec", 118, "wrapf"), RL("spec", 119, "clampf")] } },
      { n: "5", name: "apply_resolved", f: "emit only on a difference", c: C_PAR, tip: { ...R("params", 254), blurb: "Writes the field with the setter muted; one `changed` for the whole batch, and none if nothing differed. That signal is what pushes the uniforms and marks the governor's frame as changing.", links: [RL("params", 261, "the compare"), RL("params", 265, "the single emit")] } },
      { n: "6", name: "Clock", f: "t += delta", c: C_AX, tip: { ...R("clock", 11), blurb: "A child of Main, so it runs after the resolve." } },
      { n: "7", name: "AxisController", f: "value += dir·speed·Δ", c: C_AX, tip: { ...R("axisCtl", 25), blurb: "direction = strength(axis_a_pos) − strength(axis_a_neg); Axes.step adds direction × speed × delta. Read by the NEXT frame's resolve.", links: [RL("axes", 102, "Axes.step")] } },
    ];
    const stageVal = STAGES.map((st, i) => {
      const x = 20 + i * (BW + BG);
      const r = api.el("rect", { x, y: BY0, width: BW, height: BH, rx: 6, style: "fill:var(--surface);stroke:var(--hairline);stroke-width:1.2;cursor:pointer" });
      api.text(x + 10, BY0 + 19, st.n, "mono", { style: `fill:${st.c};font-weight:700;${noPtr}` });
      api.text(x + 28, BY0 + 19, st.name, "ink", { style: `font-weight:600;${noPtr}` });
      api.text(x + 10, BY0 + 40, st.f, "mono", { style: `font-size:11px;${noPtr}` });
      api.tip(r, Object.assign({ title: st.name, sub: st.f }, st.tip));
      return api.text(x + 10, BY0 + 62, "", "mono", { style: `font-size:11.5px;fill:${st.c};${noPtr}` });
    });
    api.el("line", { x1: 20 + 5 * (BW + BG) - BG / 2, y1: BY0 - 4, x2: 20 + 5 * (BW + BG) - BG / 2, y2: BY0 + BH + 4, style: "stroke:var(--muted);stroke-width:1.2;stroke-dasharray:3 3" });
    api.text(20, BY0 + BH + 16, "Main._process: the resolve (main.gd:244-248)", "muted", { style: small });
    api.text(20 + 5 * (BW + BG), BY0 + BH + 16, "then Main's children (main.gd:132-156)", "muted", { style: small });

    // ---- the two charts
    const GX = 70, NCOL = 240, COLW = 4, CW = NCOL * COLW;
    const A = { y: 136, h: 130 }, B = { y: 314, h: 170 }, EY = 496;
    const titleA = api.text(GX, A.y - 10, "", "ink", { style: caps });
    const titleB = api.text(GX, B.y - 10, "", "ink", { style: caps });
    for (const ch of [A, B]) api.el("rect", { x: GX, y: ch.y, width: CW, height: ch.h, style: "fill:none;stroke:var(--hairline);stroke-width:1" });
    const bandB = api.el("rect", { x: GX, width: CW, style: `fill:${C_PAR};opacity:.08;${noPtr}` });
    const hardLo = api.el("line", { x1: GX, x2: GX + CW, style: `stroke:${C_PAR};stroke-width:1;stroke-dasharray:5 4;${noPtr}` });
    const hardHi = api.el("line", { x1: GX, x2: GX + CW, style: `stroke:${C_PAR};stroke-width:1;stroke-dasharray:5 4;${noPtr}` });
    const hardLoT = api.text(GX + CW - 6, 0, "", "mono", { "text-anchor": "end", style: `${small};fill:${C_PAR}` });
    const hardHiT = api.text(GX + CW - 6, 0, "", "mono", { "text-anchor": "end", style: `${small};fill:${C_PAR}` });
    const zeroA = api.el("line", { x1: GX, x2: GX + CW, style: `stroke:var(--hairline);stroke-width:1;${noPtr}` });
    const axLbl = [0, 1, 2].map(() => api.text(GX - 6, 0, "", "mono", { "text-anchor": "end", style: small }));
    const bLbl = [0, 1, 2].map(() => api.text(GX - 6, 0, "", "mono", { "text-anchor": "end", style: small }));
    const pAxis = api.el("path", { style: `fill:none;stroke:${C_AX};stroke-width:1.4;opacity:.55;${noPtr}` });
    const pRaw = api.el("path", { style: `fill:none;stroke:${C_RAW};stroke-width:2;${noPtr}` });
    const pPre = api.el("path", { style: `fill:none;stroke:${C_PRE};stroke-width:1.3;stroke-dasharray:4 3;${noPtr}` });
    const pAlt = api.el("path", { style: `fill:none;stroke:${C_ALT};stroke-width:1.4;stroke-dasharray:1.5 3;${noPtr}` });
    const pPar = api.el("path", { style: `fill:none;stroke:${C_PAR};stroke-width:2.2;${noPtr}` });
    api.text(GX - 6, EY + 11, "changed", "muted", { "text-anchor": "end", style: small });
    const emits = [];
    for (let i = 0; i < NCOL; i++) emits.push(api.el("rect", { x: GX + i * COLW + 0.5, y: EY, width: COLW - 1, height: 14, style: noPtr }));
    const cursor = api.el("line", { y1: A.y - 4, y2: EY + 18, style: `stroke:var(--ink);stroke-width:1.2;opacity:.6;${noPtr}` });
    const xLbl = [0, 1, 2, 3, 4].map(i => api.text(GX + i * 60 * COLW, EY + 34, "", "mono", { "text-anchor": "middle", style: small }));
    // legend
    const LEG = [[C_RAW, "raw this frame read", ""], [C_AX, "Axis A after the frame", "opacity:.55"], [C_PAR, "params value written", ""], [C_PRE, "default + gain × wave (before sanitize)", "stroke-dasharray:4 3"], [C_ALT, "hypothetical: axes moved first", "stroke-dasharray:1.5 3"]];
    let lx = GX, ghostLegend = null;
    for (const [c, label, st] of LEG) {
      const lg = api.el("g", {});
      api.el("line", { x1: lx, y1: EY + 54, x2: lx + 22, y2: EY + 54, style: `stroke:${c};stroke-width:2;${st}` }, lg);
      api.text(lx + 28, EY + 58, label, "muted", { style: small }, lg);
      lx += 40 + label.length * 6.1;
      ghostLegend = lg;
    }

    // hover / click columns
    let s0 = 0;
    for (let i = 0; i < NCOL; i++) {
      const hit = api.el("rect", { x: GX + i * COLW, y: A.y, width: COLW, height: EY + 14 - A.y, style: "fill:transparent;cursor:pointer" });
      api.tip(hit, { title: "a frame", ...R("main", 244), links: [RL("resolver", 25, "resolve_value"), RL("axes", 102, "Axes.step")], live() {
        const f = frames[s0 + i];
        if (!f || s0 + i > S.k) return { title: "no frame yet", blurb: "Step ▶ adds frames." };
        return { title: `frame ${f.n}${f.n === 0 ? " (Main._ready's resolve)" : ` · ${KEYNAME(f.key)}`}`, sub: "click to open this frame",
          blurb: [`reads: Axis A = ${num(f.axisIn, 4)}, t = ${num(f.tIn, 4)} s`,
            f.active ? `raw = ${num(f.raw, 4)} → wave = ${num(f.wave, 4)} → drive = ${num(f.pre, 4)}` : "binding inactive: the default",
            `writes: params.${S.spec} = ${num(f.param, 4)} ${f.emitted ? "(changed emitted)" : "(no signal)"}`,
            `then t = ${num(f.t, 4)}, Axis A = ${num(f.axis, 4)}`,
            S.ghost ? `hypothetical, axes first: ${num(f.alt, 4)}` : ""].filter(Boolean).join("\n") };
      } });
      hit.addEventListener("click", e => { e.stopPropagation(); if (s0 + i <= S.keys.length) { S.k = s0 + i; render(); } });
    }

    // ---- the frame panel on the right
    const RX = 1070, RW = 470;
    const head = api.text(RX, 130, "", "ink", { style: `${caps};font-size:13px` });
    const box = (y, h, label, c) => {
      api.el("rect", { x: RX, y, width: RW, height: h, rx: 6, style: `fill:none;stroke:${c};stroke-width:1.2` });
      api.text(RX + 10, y + 17, label, "", { style: `${caps};${small};fill:${c}` });
      return [0, 1, 2, 3].map(i => api.text(RX + 12, y + 38 + i * 19, "", "mono", { style: "font-size:11.5px" }));
    };
    const readL = box(142, 112, "READS — what frame N−1 left", C_RAW);
    const writeL = box(266, 94, "WRITES", C_PAR);
    const calcL = [0, 1, 2, 3, 4].map(i => api.text(RX, 384 + i * 19, "", "mono", { style: "font-size:11.5px" }));
    api.tip(api.el("rect", { x: RX, y: 142, width: RW, height: 112, style: "fill:transparent" }), { title: "what the resolve reads", ...R("main", 245),
      blurb: "Axis values and t as the children left them at the end of the previous frame; the table default and binding as the console last edited them.", links: [RL("table", 46, "get_default"), RL("table", 69, "binding")] });
    api.tip(api.el("rect", { x: RX, y: 266, width: RW, height: 94, style: "fill:transparent" }), { title: "what the frame writes", ...R("params", 254),
      blurb: "params (once, through apply_resolved), then the clock and the axis for the next frame.", links: [RL("clock", 11, "t += delta"), RL("axes", 102, "the axis")] });
    // the waveform for these controls, with this frame's raw on it
    const WY = 500, WH = 110;
    api.text(RX, WY - 8, "waveform_value(raw) for these controls", "ink", { style: caps });
    api.el("rect", { x: RX, y: WY, width: RW, height: WH, style: "fill:none;stroke:var(--hairline);stroke-width:1" });
    const wZero = api.el("line", { x1: RX, x2: RX + RW, style: `stroke:var(--hairline);${noPtr}` });
    const wPath = api.el("path", { style: `fill:none;stroke:${C_RAW};stroke-width:1.8;${noPtr}` });
    const wDot = api.el("circle", { r: 5, style: `fill:${C_PRE};${noPtr}` });
    const wLbl = api.text(RX + RW, WY + WH + 15, "", "mono", { "text-anchor": "end", style: small });
    api.tip(api.el("rect", { x: RX, y: WY, width: RW, height: WH, style: "fill:transparent" }), { title: "waveform_value", ...R("resolver", 39), live: () => ({ sub: WNAME[S.wave],
      blurb: S.wave === "LINEAR" ? "Linear: wave = raw. Period is ignored (the row disables its spin box)." : `period p = ${S.period}: one full cycle per ${S.period} units of the source.` }), links: [RL("row", 94, "the period spin is disabled for Linear")] });

    // ---- the drawing
    const yA = (v, lo, hi) => A.y + A.h - (v - lo) / (hi - lo) * A.h;
    const yB = (v, lo, hi) => B.y + B.h - (clampf(v, lo, hi) - lo) / (hi - lo) * B.h;
    const pathOf = (vals, yf, breakSpan) => {
      let d = "", prev = null;
      vals.forEach((v, i) => {
        if (v === null) { prev = null; return; }
        const x = GX + i * COLW + COLW / 2, y = yf(v);
        d += (prev === null || (breakSpan && Math.abs(v - prev) > breakSpan) ? "M" : "L") + x.toFixed(1) + " " + y.toFixed(1) + " ";
        prev = v;
      });
      return d;
    };
    const range = (vals, base) => {
      let lo = Math.min(...base), hi = Math.max(...base);
      for (const v of vals) if (v !== null && isFinite(v)) { lo = Math.min(lo, v); hi = Math.max(hi, v); }
      if (hi - lo < 1e-9) { lo -= 1; hi += 1; }
      const pad = (hi - lo) * 0.08;
      return [lo - pad, hi + pad];
    };
    function render() {
      const c = cfg(), sp = c.spec;
      frames = simulate(S.keys, c);
      S.k = Math.min(S.k, frames.length - 1);
      s0 = Math.max(0, S.k - NCOL + 1);
      const win = frames.slice(s0, S.k + 1);
      const rawOf = f => (f.active ? f.raw : null);
      // chart A
      const rawV = win.map(rawOf), axV = win.map(f => f.axis);
      const [aLo, aHi] = range(rawV.concat(axV), [0]);
      titleA.textContent = `raw read by frame N — ${f0src()}   ·   Axis A after frame N`;
      pRaw.setAttribute("d", pathOf(rawV, v => yA(v, aLo, aHi)));
      pAxis.setAttribute("d", pathOf(axV, v => yA(v, aLo, aHi)));
      zeroA.setAttribute("y1", yA(0, aLo, aHi)); zeroA.setAttribute("y2", yA(0, aLo, aHi));
      [aHi, (aLo + aHi) / 2, aLo].forEach((v, i) => { axLbl[i].setAttribute("y", yA(v, aLo, aHi) + 4); axLbl[i].textContent = num(v, 2); });
      // chart B
      const lim = sp.wrap ? [sp.min, sp.max] : [sp.hardMin, sp.hardMax];
      const parV = win.map(f => f.param), preV = win.map(f => (f.active ? f.pre : null)), altV = win.map(f => f.alt);
      let [bLo, bHi] = range(parV.concat(S.ghost ? altV : []), [c.def]);
      // show a limit (and the slider band) once the drive comes within a fifth of the slider span of it
      const near = (sp.max - sp.min) * 0.2, pv = preV.filter(v => v !== null);
      const preLo = Math.min(c.def, ...pv), preHi = Math.max(c.def, ...pv);
      if (preLo < lim[0] + near) bLo = Math.min(bLo, lim[0] - near * 0.3);
      if (preHi > lim[1] - near) bHi = Math.max(bHi, lim[1] + near * 0.3);
      const span = bHi - bLo;
      const [pLo, pHi] = range(preV, [bLo, bHi]);
      bLo = Math.max(pLo, bLo - span * 0.6); bHi = Math.min(pHi, bHi + span * 0.6);
      const yb = v => yB(v, bLo, bHi);
      titleB.textContent = `params.${sp.id} written by frame N   ·   ${sp.wrap ? `wraps into [${sp.min}, ${sp.max})` : `clamps to the hard range [${sp.hardMin}, ${sp.hardMax}]`}`;
      bandB.setAttribute("y", yb(sp.max)); bandB.setAttribute("height", Math.max(0, yb(sp.min) - yb(sp.max)));
      hardLo.setAttribute("y1", yb(lim[0])); hardLo.setAttribute("y2", yb(lim[0]));
      hardHi.setAttribute("y1", yb(lim[1])); hardHi.setAttribute("y2", yb(lim[1]));
      hardLo.style.display = lim[0] >= bLo && lim[0] <= bHi ? "" : "none"; hardHi.style.display = lim[1] >= bLo && lim[1] <= bHi ? "" : "none";
      hardLoT.setAttribute("y", yb(lim[0]) - 4); hardLoT.style.display = lim[0] >= bLo && lim[0] <= bHi ? "" : "none"; hardLoT.textContent = `${sp.wrap ? "min" : "hard"} ${lim[0]}`;
      hardHiT.setAttribute("y", yb(lim[1]) - 4); hardHiT.style.display = lim[1] >= bLo && lim[1] <= bHi ? "" : "none"; hardHiT.textContent = `${sp.wrap ? "max" : "hard"} ${lim[1]}`;
      const wrapBreak = sp.wrap ? (sp.max - sp.min) / 2 : 0;
      pPar.setAttribute("d", pathOf(parV, yb, wrapBreak));
      pPre.setAttribute("d", pathOf(preV, yb));
      pAlt.setAttribute("d", S.ghost ? pathOf(altV, yb, wrapBreak) : "");
      [bHi, (bLo + bHi) / 2, bLo].forEach((v, i) => { bLbl[i].setAttribute("y", yb(v) + 4); bLbl[i].textContent = num(v, 2); });
      for (let i = 0; i < NCOL; i++) {
        const f = win[i];
        emits[i].style.display = f ? "" : "none";
        if (f) emits[i].setAttribute("style", `fill:${f.emitted ? C_EMIT : "var(--hairline)"};opacity:${f.emitted ? 0.9 : 0.5};${noPtr}`);
      }
      const cx = GX + (S.k - s0) * COLW + COLW / 2;
      cursor.setAttribute("x1", cx); cursor.setAttribute("x2", cx);
      xLbl.forEach((t, i) => { const n = s0 + i * 60; t.textContent = n <= S.k ? `frame ${n}` : ""; });
      ghostLegend.style.display = S.ghost ? "" : "none";
      // the frame panel
      const f = frames[S.k];
      head.textContent = f.n === 0 ? `FRAME 0 of ${frames.length - 1} · Main._ready's resolve` : `FRAME ${f.n} of ${frames.length - 1} · ${KEYNAME(f.key)}`;
      readL[0].textContent = `axes().values() = {a: ${num(f.axisIn, 4)}}`;
      readL[1].textContent = `_clock.t = ${num(f.tIn, 4)} s`;
      readL[2].textContent = `table default ${sp.id} = ${num(c.def, 4)}`;
      readL[3].textContent = `binding: ${S.source === "a" ? "a" : S.source === "time" ? "time" : "b"} · gain ${num(c.gain, 3)} · ${WNAME[S.wave]} · period ${num(S.period, 2)}`;
      writeL[0].textContent = `params.${sp.id} = ${num(f.param, 4)}  ${f.n === 0 ? "" : f.emitted ? `changed (was ${num(f.prevParam, 4)})` : "same: no signal"}`;
      writeL[1].textContent = `Clock.t = ${num(f.t, 4)} s`;
      writeL[2].textContent = `Axis A = ${num(f.axis, 4)}${f.key ? `  (${f.key > 0 ? "+" : "−"}1 × ${num(S.speed, 2)} × 1/${S.fps})` : "  (no key)"} → frame ${f.n + 1}`;
      writeL[3].textContent = "";
      const clampNote = !f.active ? "" : sp.wrap ? (Math.abs(f.pre - f.out) > 1e-9 ? `wrapf into [${sp.min}, ${sp.max}) → ${num(f.out, 4)}` : `inside [${sp.min}, ${sp.max}): unchanged`)
        : (f.pre > sp.hardMax ? `clamped to hard_max ${sp.hardMax}` : f.pre < sp.hardMin ? `clamped to hard_min ${sp.hardMin}` : `inside the hard range [${sp.hardMin}, ${sp.hardMax}]: unchanged`);
      const calc = !f.active ? ["binding inactive or not bindable: the default", "", "", "", ""] : [
        `raw = ${S.source === "time" ? `t = ${num(f.raw, 4)}` : S.source === "a" ? `Axis A = ${num(f.raw, 4)}` : "0   (\"b\" is not a keymap axis)"}`,
        `wave = ${WNAME[S.wave]}(${num(f.raw, 4)}${S.wave === "LINEAR" ? "" : `, p = ${num(S.period, 2)}`}) = ${num(f.wave, 4)}`,
        `drive = ${num(c.def, 4)} + ${num(c.gain, 3)} × ${num(f.wave, 4)} = ${num(f.pre, 4)}`,
        `sanitize: ${clampNote}`,
        S.ghost ? `hypothetical (axes first): ${num(f.alt, 4)}` : "",
      ];
      calc.forEach((s, i) => { calcL[i].textContent = s; });
      calcL[3].style.fill = f.active && Math.abs(f.pre - f.out) > 1e-9 ? C_PAR : "";
      // stage values
      const sv = !f.active ? ["inactive", "—", "—", "—", "", "", ""] : [`= ${num(f.raw, 4)}`, `= ${num(f.wave, 4)}`, `= ${num(f.pre, 4)}`,
        `= ${num(f.out, 4)}${Math.abs(f.pre - f.out) > 1e-9 ? (sp.wrap ? " wrapped" : " clamped") : ""}`, "", "", ""];
      sv[4] = f.n === 0 ? "(in _ready: no compare)" : f.emitted ? "changed emitted" : "no signal";
      sv[5] = `t = ${num(f.t, 4)}`;
      sv[6] = `a = ${num(f.axis, 4)} (${KEYNAME(f.key)})`;
      stageVal.forEach((t, i) => { t.textContent = sv[i]; });
      // waveform
      const p = S.wave === "LINEAR" ? 4 : S.period, r0 = f.active ? f.raw : 0;
      const xl = r0 - 2 * p, xh = r0 + 2 * p;
      const yl = S.wave === "LINEAR" ? xl : -1.2, yh = S.wave === "LINEAR" ? xh : 1.2;
      const wx = v => RX + (v - xl) / (xh - xl) * RW, wy = v => WY + WH - (clampf(v, yl, yh) - yl) / (yh - yl) * WH;
      let d = "";
      for (let i = 0; i <= 160; i++) { const v = xl + (xh - xl) * i / 160; d += (i ? "L" : "M") + wx(v).toFixed(1) + " " + wy(waveformValue(v, S.wave, S.period)).toFixed(1) + " "; }
      wPath.setAttribute("d", d);
      wZero.setAttribute("y1", wy(0)); wZero.setAttribute("y2", wy(0));
      wDot.setAttribute("cx", wx(r0)); wDot.setAttribute("cy", wy(waveformValue(r0, S.wave, S.period)));
      wLbl.textContent = `raw ${num(xl, 2)} … ${num(xh, 2)} · wave(${num(r0, 3)}) = ${num(waveformValue(r0, S.wave, S.period), 4)}`;
    }
    const f0src = () => (S.source === "a" ? "Axis A" : S.source === "time" ? "Clock t" : "0 (missing axis)");

    // ---- controls
    const BY = 660;
    let bx = 20;
    const btn = (y, label, w, onClick, on) => { const b = api.button({ x: bx, y, w, label, on, onClick }); bx += w + 8; return b; };
    const lab = (y, s, w) => { api.text(bx, y + 17, s, "ink"); bx += w; };
    const step = n => { for (let i = 0; i < n; i++) { S.keys.length = S.k; S.keys.push(S.cur); S.k++; } render(); };
    lab(BY, "Frames", 56);
    btn(BY, "◀ Back", 70, () => { S.k = Math.max(0, S.k - 1); render(); });
    btn(BY, "Step ▶", 70, () => step(1));
    btn(BY, "+10 ▶", 60, () => step(10));
    btn(BY, "+1 s ▶▶", 76, () => step(S.fps));
    btn(BY, "Reset", 62, () => { S.keys = []; S.k = 0; render(); });
    bx += 24;
    lab(BY, "Key held in the next frames", 196);
    const keyBtns = [];
    const setKey = d => { S.cur = d; keyBtns.forEach(([v, h]) => h.set(v === d)); };
    keyBtns.push([-1, btn(BY, "Q", 40, () => setKey(-1))]);
    keyBtns.push([0, btn(BY, "none", 56, () => setKey(0))]);
    keyBtns.push([1, btn(BY, "E", 40, () => setKey(1), true)]);
    bx += 24;
    btn(BY, "Same-frame variant", 156, h => { S.ghost = !S.ghost; h.set(S.ghost); render(); }, true);

    const radio = (y, label, lw, opts, get, set) => {
      lab(y, label, lw);
      const hs = opts.map(([v, text, w]) => [v, btn(y, text, w, () => { set(v); hs.forEach(([vv, h]) => h.set(vv === v)); render(); }, get() === v)]);
      bx += 20;
      return hs;
    };
    bx = 20;
    radio(BY + 40, "Source", 56, [["a", "Axis A", 72], ["time", "Time", 56], ["b", "missing \"b\"", 104]], () => S.source, v => { S.source = v; });
    radio(BY + 40, "Wave", 46, [["LINEAR", "Linear", 64], ["SINE", "Sine", 52], ["TRIANGLE", "Triangle", 76]], () => S.wave, v => { S.wave = v; });
    radio(BY + 40, "Knob", 44, STEP_IDS.map(id => [id, id, id.length * 7.4 + 22]), () => S.spec, v => { S.spec = v; showDials(); });

    // sliders: default and gain per knob (their own ranges), then period, speed, fps
    const SY = BY + 106, SW = 250, SX = i => 20 + i * 296;
    const dialGroups = {};
    for (const id of STEP_IDS) {
      const g = api.el("g", {}), D = STEP_DIALS[id];
      api.slider({ x: SX(0), y: SY, w: SW, label: `default (${id})`, min: D.def[0], max: D.def[1], step: D.def[2], value: S.dial[id].def, fmt: v => num(v, 3), onChange: v => { S.dial[id].def = v; render(); } });
      g.appendChild(api.g.lastChild);
      api.slider({ x: SX(1), y: SY, w: SW, label: "gain", min: D.gain[0], max: D.gain[1], step: D.gain[2], value: 1, fmt: v => num(v, 3), onChange: v => { S.dial[id].gain = v; render(); } });
      g.appendChild(api.g.lastChild);
      dialGroups[id] = g;
    }
    function showDials() { for (const id of STEP_IDS) dialGroups[id].style.display = id === S.spec ? "" : "none"; }
    api.slider({ x: SX(2), y: SY, w: SW, label: "period (Sine, Triangle)", min: 0.1, max: 20, step: 0.1, value: S.period, fmt: v => num(v, 1), onChange: v => { S.period = v; render(); } });
    api.slider({ x: SX(3), y: SY, w: SW, label: "Axis A speed (units / s)", min: 0, max: 10, step: 0.1, value: S.speed, fmt: v => num(v, 1), onChange: v => { S.speed = v; render(); } });
    api.slider({ x: SX(4), y: SY, w: SW, label: "frames per second", min: 10, max: 240, step: 1, value: S.fps, fmt: v => String(v), onChange: v => { S.fps = v; render(); } });
    api.text(20, SY + 46, "Try: Knob iter_rot_xy with gain 120 to see the wrap; box_scale with gain 4 and +1 s ▶▶ twice to hit the hard clamp at 6; Source missing \"b\" to see a binding to an axis the keymap lacks resolve to its default.", "muted", { style: small });
    api.text(20, SY + 64, "Frame 45 → 46 (E released): frame 46 still writes the value from frame 45's push, because Main resolves before AxisController runs. The dotted line is the same frame if the axes moved first.", "muted", { style: small });
    api.link(20, SY + 86, RL("tBind", 22, "the test this port is checked against"));
    api.link(330, SY + 86, RL("mainScn", 10, "Main is the scene root; Clock and AxisController are added as its children"));
    showDials();
    render();
  },
};

// ================================================================== 4. the console window, widget by widget
const consoleFig = {
  type: "figure",
  tab: "The console window",
  title: "The console window, widget by widget",
  note: "A sketch of the window at about its default 1000 × 700 points: three tabs (Shape, Colour, View) stacked above the Movement pane in a VSplitContainer (side by side, the panes' minimum widths overflowed the window). Left, the Shape tab, with Scale bound to Axis A and E held half a second, as ui_console_test checks it (→ −1.59). Middle, the same window on its Colour tab: the palette window above the Colour, Lighting and Palette rows. Right, its View tab, which replaced the pause menu. Hover any widget for the line that builds it and what an edit does.",
  w: 2130, h: 820,
  draw(api) {
    const X0 = 30, Y0 = 30, WW = 1000, TB = 28, CH = 740;
    const C_UI = api.hue(2), C_OK = api.hue(3), C_ATTR = api.hue(1);
    const rr = (x, y, w, h, style, tipload, label, cls, lstyle) => {
      const r = api.el("rect", { x, y, width: w, height: h, rx: 4, style: style || "fill:var(--surface);stroke:var(--hairline);stroke-width:1" });
      if (label !== undefined) api.text(x + 7, y + h / 2 + 4, label, cls || "mono", { style: `font-size:11.5px;${lstyle || ""};${noPtr}` });
      if (tipload) { r.style.cursor = "pointer"; api.tip(r, tipload); }
      return r;
    };
    // window chrome
    const winRect = rr(X0, Y0, WW, TB + CH, "fill:var(--fig-bg);stroke:var(--muted);stroke-width:1.4", { title: "ConsoleWindow", ...R("console", 58),
      blurb: "Title \"Console\", sized `UiScale.px(DEFAULT_SIZE)` (1000 × 700 points), minimum 700 × 400, resizable, hidden at start. `force_native` must be set while hidden. Opened BESIDE the main window by `place_beside`; on the web and headless it is embedded. Cmd+= / Cmd+- step the zoom through ZOOM_STEPS (0.5 … 2) and Cmd+0 resets it: the content scale grows, the window keeps its size and the panes reflow. The level is the player's, kept in Settings.console_zoom.",
      links: [RL("console", 39, "DEFAULT_SIZE"), RL("console", 61, "hidden before force_native"), RL("console", 167, "open"), RL("console", 42, "ZOOM_STEPS"), RL("console", 237, "zoom chords caught in _input"), RL("settings", 29, "Settings.console_zoom")] });
    rr(X0, Y0, WW, TB, `fill:var(--surface);stroke:var(--muted);stroke-width:1`, { title: "the window's own title bar", ...R("console", 60),
      blurb: "A native OS window: drag it anywhere, onto another monitor. Its ✕ calls `hide_console`.", links: [RL("console", 69, "close_requested")] }, "Console", "ink", "font-weight:600");
    // columns of a wide row (attribute_row.gd: label 140, spin 92, option 92, small spin 76)
    const LX = X0 + 12, VX = LX + 146, SPX = X0 + 524, BX0 = X0 + 624, SRC = 92, GN = 76, WV = 92, PD = 76;
    let y = Y0 + TB + 6;
    const tabBar = (x0, active) => {
      ["Shape", "Colour", "View"].forEach((name, i) => {
        rr(x0 + i * 74, y, 70, 22, i === active ? `fill:var(--surface);stroke:${C_UI};stroke-width:1.4` : "fill:var(--fig-bg);stroke:var(--hairline);stroke-width:1",
          { title: `the ${name} tab`, ...R("console", 75), blurb: ["An AttributeInspector limited to SHAPE_GROUPS: Box, Julia, Iteration rotation, Render.", "An AttributeInspector limited to COLOUR_GROUPS (Colour, Lighting, Palette), with the palette window as its header.", "The ViewPane: files, camera mode, mouse sensitivity, Noise editor, Renderer options and Back to Menu (the old pause menu)."][i],
            links: [RL("console", [86, 97, 99][i], "built here"), RL("shape", 274, "SHAPE_GROUPS / COLOUR_GROUPS")] }, name, "ink", "font-size:11.5px");
      });
    };
    tabBar(LX, 0);
    y += 26;
    const heading = (text, tipText) => {
      const t = api.text(LX, y + 14, text, "", { style: `${caps};font-size:12px;fill:${C_ATTR};cursor:pointer` });
      api.tip(t, { title: `${text} heading`, ...R("inspector", 77), blurb: `Hover tooltip: ${tipText}`, links: [RL("inspector", 106, "_make_heading"), RL("shape", 280, "group_tooltips")] });
      y += 24;
    };
    const label = (s, specLine) => {
      const t = api.text(LX, y + 18, s, "ink", { style: "font-size:12.5px;cursor:pointer" });
      api.tip(t, { title: `${s}: the label`, ...R("row", 146), blurb: "The label's tooltip is the spec's tooltip and effects text, plus a line for log and wrap rows.", links: [RL("shape", specLine, "the spec"), RL("row", 152, "wrap note")] });
    };
    const slider = (frac, logRow) => {
      rr(VX, y + 13, SPX - VX - 8, 4, "fill:var(--hairline);stroke:none", { title: logRow ? "a logarithmic slider (0…1)" : "the slider", ...R("row", logRow ? 177 : 184),
        blurb: logRow ? "Log rows run the slider over 0…1 and map it with exp(lerp(log min, log max, t))." : "Covers the spec's slider range [min, max] at its step; a drag calls `set_default` through `_on_slider_changed`.",
        links: [RL("row", 331, "_on_slider_changed"), RL("row", logRow ? 430 : 420, logRow ? "_from_slider" : "_to_slider")] });
      api.el("circle", { cx: VX + frac * (SPX - VX - 8), cy: y + 15, r: 6, style: `fill:var(--muted);${noPtr}` });
    };
    const spin = v => rr(SPX, y + 3, 92, 24, null, { title: "the spin box", ...R("row", 192),
      blurb: "Typing may go past the slider out to the HARD range; past that it is clamped and the box flashes red (0.3 s).", links: [RL("row", 193, "hard range"), RL("row", 343, "the flash")] }, v);
    const binding = (src, gain, wave, period, active) => {
      let x = BX0;
      rr(x, y + 3, SRC, 24, active ? `fill:var(--surface);stroke:${C_UI};stroke-width:1.6` : null, { title: "Source ▾", ...R("row", 256),
        blurb: "None, Time, then every keymap axis by label (rebuilt on Keymap.changed). A binding to an axis that no longer exists shows as \"(missing: id)\" and keeps its source.", links: [RL("row", 293, "_rebuild_source_items"), RL("row", 307, "(missing: id)"), RL("row", 361, "_on_source_selected")] }, `${src} ▾`); x += SRC + 4;
      rr(x, y + 3, GN, 24, null, { title: "Gain", ...R("row", 263), blurb: "Multiplies the wave before it is added: the key's sensitivity. Negative flips; 0 silences without forgetting.", links: [RL("row", 371, "_on_gain_changed")] }, gain); x += GN + 4;
      rr(x, y + 3, WV, 24, null, { title: "Waveform ▾", ...R("row", 272), blurb: "Linear, Sine, Triangle.", links: [RL("row", 381, "_on_wave_selected")] }, `${wave} ▾`); x += WV + 4;
      rr(x, y + 3, PD, 24, wave === "Linear" ? "fill:var(--surface);stroke:var(--hairline);stroke-width:1;opacity:.45" : null, { title: "Period", ...R("row", 280),
        blurb: "Source units per cycle for Sine and Triangle; not editable for Linear. Floored at 0.001.", links: [RL("row", 94, "editable only off Linear"), RL("row", 397, "the floor")] }, period);
    };
    const floatRow = (s, specLine, frac, v, b, h) => {
      label(s, specLine); slider(frac); spin(v);
      if (b) binding(...b); else binding("None", "1.00", "Linear", "4.00", false);
      y += h || 32;
    };
    heading("BOX", "the fold-and-scale step repeated at every pixel …");
    label("Scale", 61); slider((-2.09 + 5) / 8); spin("-2.09"); binding("Axis A", "1.00", "Linear", "4.00", true);
    const ro = api.text(VX, y + 42, "→ -1.59", "mono", { style: `font-size:11px;fill:${C_OK};cursor:pointer` });
    api.tip(ro, { title: "the readout", ...R("row", 101), blurb: "Visible while the binding is active: the value in use this frame (default + gain × wave(source)), fed by Main through `set_resolved` each frame the console is open. −2.09 + 1 × 0.5 = −1.59.", links: [RL("main", 248, "Main feeds it"), RL("tUiConsole", 169, "the test")] });
    y += 50;
    floatRow("Fold limit", 68, 1 / 3, "1");
    floatRow("Min radius", 74, 0.35, "0.7");
    floatRow("Fixed radius", 80, 0.25, "1");
    label("Fold order", 86);
    rr(VX, y + 3, 150, 24, null, { title: "an ENUM row", ...R("row", 212), blurb: "An OptionButton of the enum labels, item ids = enum values. ENUM and BOOL rows have no binding widgets: they are never bindable.", links: [RL("spec", 92, "ENUM: bindable = false")] }, "Box → Sphere ▾");
    y += 32;
    floatRow("W", 95, 0.5, "0");
    heading("JULIA", "which components add a fixed constant …");
    label("Julia (all)", 103);
    rr(VX, y + 5, 18, 18, null, { title: "a BOOL row", ...R("row", 206), blurb: "A CheckBox \"on\". `julia_all` also drives the on-screen marker and the ±20 Julia cube.", links: [RL("params", 275, "julia_enabled() = julia_all")] });
    api.text(VX + 26, y + 19, "on", "ink", { style: noPtr });
    y += 30;
    const hid = api.text(LX, y + 16, "Julia x · y · z · w (four more checkboxes) · Constant x / y / z / w: collapsed until julia_all or their own toggle is on", "muted", { style: `${small};cursor:pointer` });
    api.tip(hid, { title: "show_when", ...R("shape", 124), blurb: "`refresh()` sets `visible = spec.is_shown(table.defaults())`: a Constant row shows while its Julia toggle or Julia (all) is on.", links: [RL("row", 77, "refresh"), RL("shape", 44, "_julia_shown"), RL("tShape", 102, "the test")] });
    y += 28;
    heading("ITERATION ROTATION", "a 4D rotation applied inside every iteration …");
    floatRow("Iter rotation xy", 134, 0.5, "0");
    heading("RENDER", "how finely the ray march resolves the surface …");
    label("Precision (log)", 144); slider(Math.log(25) / Math.log(1000), true); spin("2.5e-05"); binding("None", "1.00", "Linear", "4.00", false);
    const ticks = ["1e-06", "3.16e-05", "0.001"];
    ticks.forEach((t, i) => api.text(VX + i * (SPX - VX - 8) / 2, y + 40, t, "muted", { "text-anchor": ["start", "middle", "end"][i], style: "font-size:10px" }));
    api.tip(api.el("rect", { x: VX, y: y + 30, width: SPX - VX - 8, height: 14, style: "fill:transparent" }), { title: "log ticks", ...R("row", 230), blurb: "Min, geometric mid (√(min·max)) and max under every log slider." });
    y += 52;
    // scrollbar and the VSplit dragger
    rr(X0 + WW - 12, Y0 + TB + 6, 6, y - Y0 - TB - 12, "fill:var(--hairline);stroke:none", { title: "the Shape list scrolls", ...R("inspector", 47),
      blurb: "A ScrollContainer with horizontal scrolling off; the wheel over a label, slider or unfocused spin box scrolls without changing a value.", links: [RL("tUiConsole", 94, "the wheel test")] });
    const dragY = y + 4;
    rr(X0 + 4, dragY - 3, WW - 8, 6, "fill:var(--hairline);stroke:none", { title: "the VSplitContainer dragger", ...R("console", 71),
      blurb: "Drag to share the height differently (kept for the session only). The inspector expands; the Movement pane keeps its natural height.", links: [RL("console", 104, "Movement: SIZE_FILL"), RL("addendum", 201, "why stacked")] });
    y = dragY + 10;
    // Movement pane
    const mh = api.text(LX, y + 14, "MOVEMENT", "", { style: `${caps};font-size:12px;fill:${C_ATTR}` });
    api.tip(mh, { title: "the Movement pane", ...R("movement", 42), blurb: "A view over Keymap; built in `_ready`." });
    y += 24;
    let mx = LX;
    const mw = (w, lbl, t) => { rr(mx, y + 3, w, 24, null, t, lbl); mx += w + 4; };
    mw(90, "Axis A", { title: "label (LineEdit)", ...R("movement", 153), blurb: "Rename on Enter or focus loss: `Keymap.set_label`; the Source dropdowns relist. While it has focus, every axis key, WASD, N and the Ctrl tap are silenced.", links: [RL("movement", 237, "_on_label_submitted"), RL("tMain", 197, "WASD silenced")] });
    api.text(mx + 4, y + 19, "a", "muted", { style: "font-size:12px" }); mx += 44;
    const vt = api.text(mx, y + 19, "0.500", "mono", { style: "font-size:12px;cursor:pointer" });
    api.tip(vt, { title: "the live value", ...R("movement", 167), blurb: "Unbounded; refreshed every `_process` (\"%.3f\").", links: [RL("movement", 287, "the readout")] });
    mx += 84;
    mw(26, "0", { title: "0", ...R("movement", 172), blurb: "`axes().set_value(id, 0)`: a bound knob snaps back to default + gain × wave(0) = the default." });
    mw(72, "1.0", { title: "speed", ...R("movement", 179), blurb: "Units per second while a key is held: `Keymap.set_speed`.", links: [RL("movement", 245, "_on_speed_changed")] });
    mw(40, "E", { title: "positive key", ...R("movement", 189), blurb: "A KeyCaptureButton: click, then press a key (Escape cancels); then `Keymap.bind(id, pos, neg)` repoints `axis_a_pos`.", links: [RL("keycap", 32, "_begin_capture"), RL("movement", 253, "_on_key_captured")] });
    mw(40, "Q", { title: "negative key", ...R("movement", 195), blurb: "The same for `axis_a_neg`." });
    mw(28, "✕", { title: "remove", ...R("movement", 201), blurb: "`Keymap.remove_axis`: the actions are erased; bindings to it resolve to their default and their Source shows \"(missing: a)\"." });
    y += 32;
    mx = LX;
    mw(84, "Add axis", { title: "Add axis", ...R("movement", 223), blurb: "A new axis `ax1`, `ax2`… labelled \"Axis AX1\", speed 1, no keys.", links: [RL("movement", 228, "_unique_id")] });
    y += 34;
    const ro2 = (s, line, title, blurb, dim) => { const t = api.text(LX, y + 14, s, "mono", { style: `font-size:12px;cursor:pointer;${dim ? "opacity:.45" : ""}` }); api.tip(t, { title, ...R("movement", line), blurb }); y += 20; };
    ro2("t = 12.34 s", 289, "the clock", "`Clock.t`: what a Time binding reads.");
    api.text(LX, y + 14, "speed x1.00", "mono", { style: "font-size:12px;" + noPtr });
    api.tip(api.el("rect", { x: LX, y: y, width: 84, height: 18, style: "fill:transparent;cursor:pointer" }), { title: "the fly speed factor", ...R("movement", 292), blurb: "Moved here from the Q panel; the mouse wheel changes it." });
    mx = LX + 96;
    rr(mx, y - 2, 104, 22, null, { title: "Reset camera", ...R("movement", 72), blurb: "Emits reset_camera_requested, relayed by the console to Main.reset_camera: the camera and its speed factor go back to where the current file has them (the starting view when none is current; a save or a load moves that point). The View tab's Renderer options have the same button.",
      links: [RL("console", 106, "relayed"), RL("main", 292, "Main.reset_camera"), RL("main", 301, "_remember_home"), RL("renderer", 57, "the View tab's Renderer button"), RL("tMain", 166, "the test")] }, "Reset camera");
    y += 24;
    ro2("load shed 2/4", 277, "the load-shed level", "Shown only while the governor sheds quality (level > 0).", true);
    y += 6;
    mx = LX;
    mw(88, "Save keymap", { title: "Save keymap", ...R("movement", 304), blurb: "Over the keymap's current file (saves/keymap.json at start), or the panel if there is none." });
    mw(112, "Save keymap as…", { title: "Save keymap as…", ...R("movement", 111), blurb: "A WorkspaceFiles with subdir \"\", noun keymap, filtered to *.json.", links: [RL("movement", 97, "the file panels")] });
    mw(96, "Load keymap…", { title: "Load keymap…", ...R("movement", 321), blurb: "`Keymap.load_file(path)`. A missing or malformed file still resets the keymap to the default (see the gotcha cards); a saved view is refused by name and changes nothing." });
    winRect.setAttribute("height", y + 44 - Y0);

    // ---- the Colour tab, on the right
    const CX = X0 + WW + 30, CW = 600, C_R = api.hue(5), C_G = api.hue(3), C_B = api.hue(1);
    const CH_COL = [C_R, C_G, C_B];
    const cRect = rr(CX, Y0, CW, 100, "fill:var(--fig-bg);stroke:var(--muted);stroke-width:1.4", { title: "the same window on its Colour tab", ...R("console", 88),
      blurb: "One Palette over the shape table, one PaletteWindow over that palette, as the header of a second AttributeInspector.", links: [RL("console", 97, "the Colour inspector")] });
    rr(CX, Y0, CW, TB, "fill:var(--surface);stroke:var(--muted);stroke-width:1", null, "Console", "ink", "font-weight:600");
    y = Y0 + TB + 6;
    tabBar(CX + 12, 1);
    y += 30;
    const cl = CX + 16, cw = CW - 32;
    const ftxt = api.text(CX + CW / 2, y + 12, "color(x) = A + B · cos(2π (Cx + D))", "muted", { "text-anchor": "middle", style: "font-size:12px;cursor:pointer" });
    api.tip(ftxt, { title: "the formula", ...R("pwin", 18), blurb: "Inigo Quilez's cosine palette; A, B, C and D are each an RGB triple, so twelve numbers make a whole gradient. The shader's palette() is the same formula.", links: [RL("sh", 254, "palette()")] });
    y += 20;
    const hint = api.text(CX + CW / 2, y + 12, "Set Colour to Palette (below) to paint the fractal with this.", "", { "text-anchor": "middle", style: `font-size:11px;fill:${api.hue(4)};cursor:pointer` });
    api.tip(hint, { title: "the hint", ...R("pwin", 217), blurb: "Shown while the Colour mode is anything but Palette (Palette.in_use() reads the table default): editing the palette then changes nothing on screen.", links: [RL("palette", 159, "in_use")] });
    y += 22;
    const PD3 = [[0.5, 0.5, 0.5], [0.5, 0.5, 0.5], [1, 1, 1], [0, 0.33, 0.67]];
    for (let v = 0; v < 4; v++) {
      const lt = api.text(cl, y + 16, PAL_V[v], "ink", { style: "font-size:15px;font-weight:700;cursor:pointer" });
      api.tip(lt, { title: `${PAL_V[v]} — ${["the middle level", "the contrast", "cycles per pass", "the phase, in turns"][v]}`, ...R("pwin", 143), blurb: `Slider range ${PAL_RANGE[v][0]} … ${PAL_RANGE[v][1]} (Palette.RANGES), step 0.01.${v === 2 ? " The catalogue row lets C go to 16; the slider stops at 4." : v === 3 ? " The catalogue row wraps D at 1." : ""}`, links: [RL("palette", 32, "RANGES")] });
      const cellW = (cw - 30) / 3;
      for (let ch = 0; ch < 3; ch++) {
        const x = cl + 26 + ch * cellW, val = PD3[v][ch], frac = (val - PAL_RANGE[v][0]) / (PAL_RANGE[v][1] - PAL_RANGE[v][0]);
        rr(x, y + 6, cellW - 14, 4, "fill:var(--hairline);stroke:none", { title: `${PAL_V[v]}, ${PAL_CH[ch]} channel`, ...R("pwin", 167), blurb: `Writes palette_${PAL_KEY[v]}_${PAL_RGB[ch]} through Palette.set_component, so into the shape table; it redraws from the model whatever edited it (this slider, the matching Palette row, Reset, a load).`, links: [RL("pwin", 206, "_on_slider_changed"), RL("palette", 126, "set_component")] });
        api.el("circle", { cx: x + frac * (cellW - 14), cy: y + 8, r: 5, style: `fill:var(--muted);${noPtr}` });
        api.text(x + (cellW - 14) / 2, y + 24, val.toFixed(2), "mono", { "text-anchor": "middle", style: `font-size:10.5px;fill:${CH_COL[ch]};${noPtr}` });
      }
      y += 32;
    }
    // the curves and the strip, drawn with the port of Palette.color_at (palette.gd:109-117)
    const pal = (t, ch) => Math.max(0, Math.min(1, PD3[0][ch] + PD3[1][ch] * Math.cos(TAU * (PD3[2][ch] * t + PD3[3][ch]))));
    const cvH = 60;
    rr(cl, y, cw, cvH, "fill:var(--fig-bg);stroke:var(--hairline);stroke-width:1", { title: "the curves", ...R("pcurves", 55), blurb: "The red, green and blue curves over one pass: a flat line is a channel with no contrast, one squashed against an edge is clamped, curves in step make greys." });
    for (let ch = 0; ch < 3; ch++) {
      let d = "";
      for (let k = 0; k <= 60; k++) { const t = k / 60; d += (k ? "L" : "M") + (cl + t * cw).toFixed(1) + " " + (y + cvH - 4 - pal(t, ch) * (cvH - 8)).toFixed(1) + " "; }
      api.el("path", { d, style: `fill:none;stroke:${CH_COL[ch]};stroke-width:1.6;${noPtr}` });
    }
    y += cvH + 6;
    const N = 60, sg = api.el("g", {});
    for (let k = 0; k < N; k++) {
      const t = (k + 0.5) / N, c = [0, 1, 2].map(ch => Math.round(pal(t, ch) * 255));
      api.el("rect", { x: cl + k * cw / N, y, width: cw / N + 0.5, height: 22, style: `fill:rgb(${c.join(",")});stroke:none` }, sg);
    }
    api.tip(api.el("rect", { x: cl, y, width: cw, height: 22, style: "fill:transparent;cursor:pointer" }), { title: "the strip", ...R("pstrip", 47), blurb: "The palette end to end, the honest preview of the picture: color_at() with the DRIVEN value of any bound component (set_live), drawn here from the default rainbow (A, B 0.5 · C 1 · D 0 / 0.33 / 0.67).", links: [RL("palette", 109, "color_at"), RL("palette", 144, "set_live"), RL("tPalWin", 87, "the strip follows a bound channel")] });
    y += 28;
    rr(cl, y, 60, 22, null, { title: "Reset", ...R("pwin", 73), blurb: "Back to the default rainbow, one `changed` for the whole move; bindings are kept.", links: [RL("palette", 131, "Palette.reset")] }, "Reset");
    y += 32;
    const cHead = (text, tipText) => {
      const t = api.text(cl, y + 14, text, "", { style: `${caps};font-size:12px;fill:${C_ATTR};cursor:pointer` });
      api.tip(t, { title: `${text} heading`, ...R("inspector", 77), blurb: `Hover tooltip: ${tipText}`, links: [RL("shape", 280, "group_tooltips")] });
      y += 22;
    };
    const cRow = (lbl, specLine, widget, tipObj) => {
      api.text(cl, y + 16, lbl, "ink", { style: "font-size:12.5px;" + noPtr });
      rr(cl + 150, y + 2, 170, 22, null, Object.assign({ ...R("shape", specLine) }, tipObj), widget);
      y += 28;
    };
    const cNote = (text, specLine, title, blurb) => {
      const t = api.text(cl, y + 12, text, "muted", { style: `${small};cursor:pointer` });
      api.tip(t, { title, ...R("shape", specLine), blurb });
      y += 20;
    };
    cHead("COLOUR", "which colouring mode paints the surface …");
    cRow("Colour", 158, "Ice Fractal ▾", { title: "Colour ▾", blurb: "The thirteen site modes by site id, plus Palette (20), this project's own. Not bindable.", links: [RL("params", 16, "COLOR_MODE_IDS")] });
    cNote("Palette input · frequency · offset · occlusion: shown only in the Palette mode", 165, "the Palette mode's rows", "show_when color_mode == Palette.MODE_ID: what picks the position along the palette (steps, radius, normal), how fast, where it starts, and how much the step count darkens it.");
    cHead("LIGHTING", "the light every lit colour mode shares …");
    cRow("Ambient", 198, "0.1", { title: "a Lighting row", blurb: "A normal bindable FLOAT row (only the value and Source shown here). The eight lighting defaults are the site's constants, so the default picture is unchanged.", links: [RL("tShape", 61, "the defaults test")] });
    cNote("Diffuse · Specular · Shininess (log) · Light yaw (wraps) · Light pitch · Exposure · Saturation", 205, "the other lighting rows", "Yaw and pitch rake the headlight across the surface; exposure and saturation act on the final colour of every mode but Grayscale.");
    cHead("PALETTE", "the twelve numbers of the cosine palette …");
    cNote("A red … D blue: twelve rows, Palette mode only, each with its own Source / Gain / Wave / Period", 259, "the twelve palette rows", "The same numbers as the sliders above, as catalogue rows, so each channel can pulse, ripple or cycle on its own binding.");
    cRect.setAttribute("height", y + 12 - Y0);
    const colourBottom = y;

    // ---- the View tab, on the far right
    const VX0 = CX + CW + 30, VW = 410, vl = VX0 + 16;
    const vRect = rr(VX0, Y0, VW, 100, "fill:var(--fig-bg);stroke:var(--muted);stroke-width:1.4", { title: "the same window on its View tab", ...R("viewPane", 1),
      blurb: "Everything the old pause menu held that is not a shape knob. It only emits signals; Main wires them.", links: [RL("main", 183, "_build_view_pane"), COMMIT("5ebb10a")] });
    rr(VX0, Y0, VW, TB, "fill:var(--surface);stroke:var(--muted);stroke-width:1", null, "Console", "ink", "font-weight:600");
    y = Y0 + TB + 6;
    tabBar(VX0 + 12, 2);
    y += 34;
    const vHead = text => { api.text(vl, y + 12, text, "", { style: `${caps};font-size:12px;fill:${C_ATTR}` }); y += 22; };
    const vBtn = (x, w, lbl, file, line, title, blurb, links) => rr(x, y, w, 22, null, { title, file: F[file], line, blurb, links }, lbl);
    vHead("FILE");
    vBtn(vl, 96, "Save view…", "viewPane", 52, "Save view…", "save_requested → WorkspaceFiles.prompt_save; Main saves through Workspace and the saved file becomes the Reset camera point. ⌘S overwrites the current file without a panel.", [RL("main", 189, "wired"), RL("main", 253, "save_view_to")]);
    vBtn(vl + 104, 96, "Load view…", "viewPane", 54, "Load view…", "load_requested → prompt_load; Main loads, resolves at once and reports here.", [RL("main", 190, "wired")]);
    const fl = api.text(vl + 212, y + 15, "default.json", "mono", { style: "font-size:11.5px;cursor:pointer" });
    api.tip(fl, { title: "the current file", ...R("viewPane", 127), blurb: "show_file(display_name), an em dash when no file is current; Main calls it on WorkspaceFiles.current_changed.", links: [RL("main", 217, "Main updates it")] });
    y += 28;
    const st = api.text(vl, y + 12, "Loaded default.json", "muted", { style: `${small};cursor:pointer` });
    api.tip(st, { title: "the status line", ...R("viewPane", 132), blurb: "Main._report writes every save / load / screenshot message here (it was the pause menu's).", links: [RL("main", 322, "_report")] });
    y += 24;
    vHead("CAMERA");
    api.text(vl, y + 15, "Camera", "ink", { style: "font-size:12px;" + noPtr });
    vBtn(vl + 70, 80, "Fly ▾", "viewPane", 70, "Camera mode", "Writes params.camera_mode; Main._apply_mode switches the camera.", [RL("viewPane", 148, "_on_camera_selected"), RL("tMain", 186, "the test")]);
    y += 28;
    api.text(vl, y + 15, "Mouse sensitivity", "ink", { style: "font-size:12px;" + noPtr });
    vBtn(vl + 130, 180, "──●──────  0.100", "viewPane", 81, "mouse sensitivity", "The player's, kept by the Settings autoload: sensitivity_changed → Settings.mouse_sensitivity, and Settings.changed → set_sensitivity. A loaded view never overrides it.", [RL("main", 192, "→ Settings"), RL("main", 205, "← Settings"), RL("tMain", 212, "the test")]);
    y += 28;
    vBtn(vl, 110, "Noise editor…", "viewPane", 95, "Noise editor…", "Opens the noise-field editor (also N). The mouse is already free while you use the console.", [RL("main", 196, "_open_noise"), RL("tMain", 232, "the test")]);
    y += 30;
    vHead("RENDERER");
    const rrow = (lbl, line) => {
      api.text(vl, y + 14, lbl, "ink", { style: "font-size:11.5px;" + noPtr });
      rr(vl + 150, y + 7, 200, 4, "fill:var(--hairline);stroke:none", { title: lbl, file: F.renderer, line, blurb: "A RendererOptions slider: it writes one FractalParams field, saved with the view (not a catalogue knob, so it cannot be bound).", links: [RL("renderer", 93, "_write"), RL("tMain", 297, "the test")] });
      y += 22;
    };
    rrow("Detail", 35); rrow("Full-detail range", 37); rrow("Detail falloff", 39); rrow("Max march steps", 41); rrow("Min resolution", 43);
    rr(vl, y + 2, 16, 16, null, { title: "Fast Controls", ...R("renderer", 46), blurb: "Let the resolution governor drop the render scale while you move." });
    api.text(vl + 24, y + 15, "Fast Controls", "ink", { style: "font-size:11.5px;" + noPtr });
    y += 26;
    vBtn(vl, 170, "Reset renderer defaults", "renderer", 54, "Reset renderer defaults", "RendererOptions.reset_defaults: the level-of-detail, step budget, minimum scale and Fast Controls defaults.", [RL("renderer", 81, "reset_defaults")]);
    vBtn(vl + 178, 110, "Reset camera", "renderer", 57, "Reset camera", "The same as the Movement pane's: Main.reset_camera, back to the current file's camera.", [RL("main", 187, "wired"), RL("main", 292, "Main.reset_camera")]);
    y += 34;
    api.el("line", { x1: vl, y1: y, x2: VX0 + VW - 16, y2: y, style: "stroke:var(--hairline)" });
    y += 8;
    vBtn(vl, 110, "Back to Menu", "viewPane", 105, "Back to Menu", "menu_requested → Main.back_to_menu: change_scene_to_file to the title menu. Unsaved changes are lost.", [RL("main", 201, "back_to_menu"), RL("tMain", 324, "the test")]);
    y += 34;
    vRect.setAttribute("height", y - Y0);

    // notes under the Colour tab
    const notes = [
      ["Every edit goes to the table", "A row writes `set_default` or edits its Binding; the palette sliders write the same table through Palette. The table's `changed(id)` redraws every row in both tabs."],
      ["The readouts are the only per-frame traffic", "`set_resolved` from Main is the one per-frame call, only while the console is open; it reaches both tabs and the palette strip."],
      ["Native, beside, never over", "A separate OS window opened right of the main window, else left of it, else on another screen. On the web and headless it is embedded."],
      ["Keys it does not use go to Main", "Escape, N, ⌘S, ⌘P go through `unhandled_key`; the Ctrl tap has its own detector; Cmd+= / - / 0 zoom."],
    ];
    let ny = colourBottom + 34;
    notes.forEach(([h, b], k) => {
      const nx = CX + (k % 2) * 305, yy = ny + Math.floor(k / 2) * 92;
      api.text(nx, yy, h, "ink", { style: "font-weight:600;font-size:12px" });
      api.wrap(b, 46).forEach((line, li) => api.text(nx, yy + 18 + li * 15, line.replace(/`/g, ""), "muted", { style: small }));
    });
    ny += 184;
    api.link(CX, ny, RL("readme", 128, "README: Console"));
    api.link(CX + 180, ny, RL("design", 238, "spec: the console window"));
    api.link(CX + 380, ny, RL("addendum", 173, "addendum: embedded, then stacked"));
  },
};

// ================================================================== 5. the catalogue
const g6 = x => String(+(+x).toPrecision(6));
const rangeOf = s => (s.type === "FLOAT" ? `${g6(s.min)} … ${g6(s.max)}` : s.type === "ENUM" ? `${s.enumValues.length} values` : "on / off");
const limitOf = s => (s.type !== "FLOAT" ? (s.type === "ENUM" ? "unlisted → default" : "—") : s.wrap ? `wraps [${s.min}, ${s.max})` : (s.hardMin !== s.min || s.hardMax !== s.max) ? `clamp ${g6(s.hardMin)} … ${g6(s.hardMax)}` : "clamp = slider");
const ENUM_DEF = { fold_order: "0 (Box → Sphere)", color_mode: "1 (Ice Fractal)", palette_source: "0 (Steps)" };
const noteOf = s => (s.log ? "log slider with min / mid / max ticks"
  : s.id === "julia_all" ? "drives the marker and the ±20 cube"
  : s.id === "w" ? "the 4D sample point's fourth coordinate"
  : s.id === "color_mode" ? "site ids, plus 20 = Palette (this project's)"
  : s.group === "Palette" ? ["A: the middle level", "B: the contrast", "C: cycles per pass", "D: the phase, in turns"][PAL_V.indexOf(s.label[0])] + " · Palette mode only"
  : s.shown === PSHOWN ? "shown only in the Palette mode"
  : s.shown ? `shown while ${s.shown}`
  : s.group === "Lighting" ? (s.id.startsWith("light_") ? "the site's constant by default" : "every mode but Grayscale") : "");
function catalogueTable(tab, groups, title, note) {
  return {
    type: "table", title, note,
    columns: [{ label: "group", w: 140 }, { label: "id", w: 140, mono: true }, { label: "label", w: 130 }, { label: "type", w: 60 }, { label: "default", w: 130, mono: true },
      { label: "slider", w: 130, mono: true }, { label: "typed / driven", w: 160, mono: true }, { label: "bindable", w: 70 }, { label: "notes", w: 290 }],
    rows: SPECS.filter(s => groups.includes(s.group)).map(s => ({
      cells: [s.group, s.id, s.label, s.type, s.type === "ENUM" ? ENUM_DEF[s.id] : s.type === "BOOL" ? String(s.def) : g6(s.def), rangeOf(s), limitOf(s), s.bindable ? "yes" : "no", noteOf(s)],
      tip: { title: `${s.id} · ${s.label}`, sub: `${tab} tab · ${s.group} · ${s.type}`, ...R("shape", s.line),
        blurb: (s.type === "BOOL" || s.type === "ENUM") ? "Not bindable: `make` forces bindable = false for BOOL and ENUM, so the row has no Source / Gain / Wave / Period."
          : s.wrap ? `Driven or typed values wrap into [${s.min}, ${s.max}) with wrapf, so a Linear binding to Time cycles it forever.`
          : (s.hardMin !== s.min || s.hardMax !== s.max) ? `The slider covers ${g6(s.min)} … ${g6(s.max)}; typing and bindings may go to ${g6(s.hardMin)} … ${g6(s.hardMax)}, then clamp.`
          : "Typed and driven values clamp to the slider range (hard range = slider range).",
        links: [RL("params", s.field, "FractalParams field"), RL("view", s.push, s.push === LOOK ? "pushed in the LOOK_KEYS loop" : "the uniform push"), RL("tShape", 8, "the 47 expected ids")] },
    })),
  };
}
const shapeCat = catalogueTable("Shape", SHAPE_GROUPS, "The Shape tab: Box, Julia, Iteration rotation, Render",
  "MandelboxShape.specs() in inspector order, the first 22 of 47: the uniform names and the FractalParams field names at once. BOOL and ENUM knobs are never bindable. A FLOAT clamps to its hard range (which may be wider than the slider) or wraps. Hover a row for its spec, its FractalParams field and the line that pushes it to the shader.");
const colourCat = catalogueTable("Colour", COLOUR_GROUPS, "The Colour tab: Colour, Lighting, Palette",
  "The other 25, under the palette window. The lighting defaults are the site's constants, so the default picture is unchanged until one moves. The Palette mode's four rows and the palette's twelve numbers show only while the Colour mode is Palette (id 20); the palette window above them is always there. Each of the twelve can be bound on its own.");

// ================================================================== 7. keymap tables
const kmFile = {
  type: "table",
  title: "saves/keymap.json and its actions",
  note: "Separate from any view. Keys are stored by name, so the file reads as text and does not depend on the keyboard layout.",
  columns: [{ label: "key", w: 150, mono: true }, { label: "shipped", w: 110, mono: true }, { label: "what it means", w: 470 }],
  rows: [
    { cells: ["version", "1", "Written as Keymap.VERSION. Load never reads it: it only checks that `axes` is an array."], tip: { ...R("keymap", 13), links: [RL("keymap", 139, "the only shape check")] } },
    { cells: ["axes[].id", "\"a\"", "The binding source id. A missing or duplicate id is skipped with a warning."], tip: { ...R("kfile", 5), links: [RL("keymap", 148, "skip")] } },
    { cells: ["label", "\"Axis A\"", "Shown in every Source dropdown and the Movement pane."], tip: { ...R("kfile", 6), links: [RL("console", 261, "into set_sources")] } },
    { cells: ["speed", "1.0", "Units per second while a key is held."], tip: { ...R("kfile", 7), links: [RL("axes", 102, "step")] } },
    { cells: ["positive", "\"E\"", "OS.find_keycode_from_string; \"\" is unbound. Registered as `axis_a_pos`."], tip: { ...R("kfile", 8), links: [RL("keymap", 192, "_key_from_name"), RL("keymap", 78, "pos_action")] } },
    { cells: ["negative", "\"Q\"", "Registered as `axis_a_neg`."], tip: { ...R("kfile", 9), links: [RL("keymap", 82, "neg_action")] } },
    { cells: ["(no file, bad JSON)", "default", "One Axis A on E / Q at 1.0, with a warning."], tip: { ...R("keymap", 187), links: [RL("tAxes", 66, "the test")] } },
    { cells: ["(where)", "saves/", "WorkspaceFiles.directory() + keymap.json: res://saves/ from source, user://saves/ in an export."], tip: { ...R("keymap", 199) } },
  ],
};
const kmApi = {
  type: "table",
  title: "The rebind API (all on Keymap, each emits changed)",
  note: "What a level's code will call. The Movement pane is a view over exactly these.",
  columns: [{ label: "call", w: 290, mono: true }, { label: "does", w: 360 }, { label: "called from", w: 210 }],
  rows: [
    { cells: ["add_axis(id, label, speed, pos, neg)", "Adds to Axes, stores the pair, registers both actions. A duplicate id warns and does nothing.", "Add axis; load_file"], tip: { ...R("keymap", 40), links: [RL("movement", 225, "Add axis"), RL("keymap", 155, "load")] } },
    { cells: ["remove_axis(id)", "Erases the actions, the pair and the axis. Bindings to it resolve to their default.", "the ✕ button"], tip: { ...R("keymap", 50), links: [RL("movement", 205, "✕"), RL("tAxes", 41, "inert binding test")] } },
    { cells: ["bind(id, positive, negative)", "Repoints the pair; either may be KEY_NONE. The actions' events are erased and re-added.", "key capture buttons"], tip: { ...R("keymap", 60), links: [RL("movement", 258, "_on_key_captured"), RL("tAxes", 30, "the test")] } },
    { cells: ["set_speed(id, units_per_second)", "", "the speed spin"], tip: { ...R("keymap", 68), links: [RL("movement", 249, "the spin")] } },
    { cells: ["set_label(id, text)", "", "the label field"], tip: { ...R("keymap", 73), links: [RL("movement", 241, "the field")] } },
    { cells: ["load_file(path = \"\") → {ok, warnings}", "Missing or malformed: the default axis, and current_path still becomes `path`. A saved view: refused, nothing changes.", "Main._ready; Load keymap…"], tip: { ...R("keymap", 113), links: [RL("main", 66, "_ready"), RL("movement", 317, "Load…")] } },
    { cells: ["save_file(path = \"\") → Error", "To `path`, else current_path, else the default file. Keys by name.", "Save keymap; Save keymap as…"], tip: { ...R("keymap", 171), links: [RL("movement", 308, "Save keymap"), RL("movement", 313, "Save keymap as…")] } },
    { cells: ["pos_action(id) / neg_action(id)", "\"axis_<id>_pos\" / \"axis_<id>_neg\"", "AxisController; tests"], tip: { ...R("keymap", 78), links: [RL("axisCtl", 25, "AxisController"), RL("tMain", 88, "hold(&\"axis_a_pos\")")] } },
    { cells: ["axes() → Axes", "The values, for the resolver and saves.", "Main; Workspace"], tip: { ...R("keymap", 23), links: [RL("main", 245, "the resolve"), RL("main", 255, "save")] } },
  ],
};

// ================================================================== 8. saved view tables
const viewTable = {
  type: "table",
  title: "A saved view, version 2",
  note: "Loading is additive and warning-based: what the file does not mention keeps its current value.",
  columns: [{ label: "section", w: 140, mono: true }, { label: "written from", w: 280 }, { label: "read back by", w: 380 }],
  rows: [
    { cells: ["version", "2 (Workspace.VERSION)", "1 is migrated; anything else refuses to load."], tip: { ...R("ws", 19), links: [RL("ws", 129, "the check")] } },
    { cells: ["shape.defaults", "table.to_dict(): every catalogue id", "apply_dict → set_default (sanitized); an unknown id warns."], tip: { ...R("ws", 40), links: [RL("table", 115, "apply_dict"), RL("tWs", 79, "unknown id test")] } },
    { cells: ["shape.bindings", "only ACTIVE bindings", "set_binding(Binding.from_dict) for the listed ids; a binding the file does not list is left as it is."], tip: { ...R("table", 108), links: [RL("table", 123, "apply_dict bindings"), RL("binding", 40, "from_dict")] } },
    { cells: ["axes", "every axis value by id", "set_value for ids the keymap has; an unknown axis id is dropped with a warning."], tip: { ...R("ws", 41), links: [RL("ws", 66, "restore"), RL("ws", 71, "the warning")] } },
    { cells: ["fractal", "fast_controls, camera_mode, mouse_sensitivity, detail, detail_range, detail_falloff, max_steps, min_render_scale", "_parse_fractal per key; Main then puts mouse_sensitivity back to the player's Settings value."], tip: { ...R("ws", 23), links: [RL("ws", 214, "_parse_fractal"), RL("main", 268, "sensitivity reset")] } },
    { cells: ["camera", "eye, forward, up (7 significant digits), speed_factor", "looking_at(eye + forward, up); a degenerate orientation warns."], tip: { ...R("ws", 43), links: [RL("ws", 231, "_restore_camera")] } },
    { cells: ["noise", "the noise graph, when wired", "NoiseWindow.apply_dict, after the shape."], tip: { ...R("ws", 50), links: [RL("main", 278, "apply_dict")] } },
    { cells: ["(not saved)", "the clock, the keymap", "A level loads a view and a keymap separately."], tip: { ...R("ws", 5), links: [RL("design", 345, "spec: why")] } },
  ],
};
const v1Table = {
  type: "table",
  title: "Version 1 → 2, without a warning (_migrate_v1)",
  columns: [{ label: "version 1 (flat fractal)", w: 210, mono: true }, { label: "version 2", w: 260, mono: true }],
  rows: [
    { cells: ["scale", "shape.defaults.box_scale"], tip: { ...R("ws", 185), links: [RL("tWs", 110, "the test")] } },
    { cells: ["inner_radius", "min_radius"], tip: { ...R("ws", 185), links: [RL("tWs", 111, "the test")] } },
    { cells: ["outer_radius", "fixed_radius"], tip: { ...R("ws", 185), links: [RL("tWs", 112, "the test")] } },
    { cells: ["fold_limit · color_mode · precision", "the same ids"], tip: { ...R("ws", 186) } },
    { cells: ["julia_enabled", "julia_all"], tip: { ...R("ws", 187), links: [RL("tWs", 113, "the test")] } },
    { cells: ["julia_point [x, y, z]", "c_0, c_1, c_2"], tip: { ...R("ws", 192), links: [RL("tWs", 114, "the test")] } },
    { cells: ["fast_controls, camera_mode, …", "fractal (the FRACTAL_KEYS)"], tip: { ...R("ws", 198) } },
    { cells: ["camera · noise", "copied as they are"], tip: { ...R("ws", 206) } },
    { cells: ["any other key", "dropped silently"], tip: { ...R("ws", 189), blurb: "Only the renamed keys and FRACTAL_KEYS are carried over." } },
    { cells: ["(nothing)", "bindings {} · axes {}"], tip: { ...R("ws", 203) } },
  ],
};

// ================================================================== 9. cards
const portOk = PORT.fails.length === 0;
const cards = {
  type: "cards",
  tab: "Invariants and gotchas",
  title: "Invariants, gotchas, history, open",
  columns: 2, cardWidth: 560,
  cards: [
    { title: portOk ? `This page's binding port passes the tests' ${PORT.n} values` : `✗ THE BINDING PORT FAILS ${PORT.fails.length} OF ${PORT.n} TEST VALUES`,
      tag: portOk ? "invariant" : "port broken", hue: portOk ? 3 : 2, ...R("tBind", 22),
      links: [RL("tAttr", 16, "attribute_test"), RL("tUiConsole", 169, "the −1.59 readout")],
      body: portOk ? "At load the stepper's port of resolve_value, waveform_value and sanitize is run against every expected value in binding_test.gd (time, axis, missing axis, the three waveforms, clamp, wrap, INT rounding) and attribute_test.gd's sanitize checks, at the tests' 1e−4 tolerance. A failure turns this card orange and lands in the red error box."
        : `Fix the port, never the tests: ${PORT.fails.join("; ")}` },
    { title: "The table is canonical; params is a per-frame projection", tag: "invariant", hue: 3, ...R("main", 244),
      links: [RL("params", 3, "FractalParams header"), RL("marker", 57, "the marker writes the table"), RL("design", 174, "spec")],
      body: "Rows in both tabs, the palette window's sliders (through Palette), the Julia marker and a load all write the AttributeTable. Main resolves it into FractalParams every frame; nothing else writes the shape fields (the marker's mirror writes the same table defaults). An edit that bypassed the table would be overwritten by the next resolve." },
    { title: "apply_resolved emits once, and only on a difference", tag: "invariant", hue: 3, ...R("params", 254),
      links: [RL("tParams", 62, "the test"), RL("gov", 46, "the governor counts it as motion")],
      body: "A view with no active binding, or one bound to an axis at rest, costs the resolve and no signal. A Time binding (or a held key) changes a value every frame, so the governor renders continuously and adapts the scale, as it does for camera motion." },
    { title: "An unknown axis resolves to raw 0, so to the default", tag: "invariant", hue: 3, ...R("resolver", 33),
      links: [RL("tBind", 48, "the test"), RL("tAxes", 51, "after remove_axis"), RL("row", 307, "the row keeps (missing: id)")],
      body: "All three waveforms give 0 at raw 0 (Triangle's quarter-period offset is there for exactly this), so default + gain × 0 = default. A view bound to an axis the loaded keymap lacks shows its defaults, and the row keeps the source so the keymap can be fixed without losing the binding." },
    { title: "One sanitize rule for typed, dragged and driven values", tag: "invariant", hue: 3, ...R("spec", 113),
      links: [RL("table", 56, "set_default sanitizes"), RL("resolver", 36, "the resolve sanitizes")],
      body: "set_default and the resolve both go through the spec: angles wrap into [min, max), everything else clamps to the hard range. BOOL and ENUM are never bindable (make forces it), so the Julia toggles, fold order, colour mode and palette input only ever change by a click or a load." },
    { title: "Each axis owns two InputMap actions equal to its pair", tag: "invariant", hue: 3, ...R("keymap", 88),
      links: [RL("tAxes", 21, "the test"), RL("tMain", 74, "Q and E are the default axis")],
      body: "axis_<id>_pos and axis_<id>_neg are created, repointed and erased with the axis, so key reading is plain Input.get_action_strength and tests drive an axis with hold(&\"axis_a_pos\", s)." },

    { title: "The palette's twelve numbers live in the shape table", tag: "invariant", hue: 3, ...R("palette", 8),
      links: [RL("tPalette", 114, "the test"), RL("palette", 109, "color_at"), RL("sh", 252, "the shader's palette()"), RL("tPalette", 142, "a bound component previews its driven value")],
      body: "Palette holds no colour: palette_a_r … palette_d_b are catalogue attributes, so they save with the view, resolve every frame and can each be bound with its own waveform. Palette.color_at is the shader's palette() formula, and it reads the driven value of a bound component (set_live), so the strip previews what is actually drawn." },
    { title: "Reset camera goes where the current file has it", tag: "invariant", hue: 3, ...R("main", 292),
      links: [RL("main", 301, "_remember_home"), RL("main", 260, "after a save"), RL("main", 274, "after a load"), RL("tMain", 30, "no file: the starting view"), RL("tMain", 177, "a save moves the reset point")],
      body: "_remember_home runs at start, after every load and after every save, so Reset camera (Movement pane or the View tab's Renderer options) restores the camera and speed factor of the file you are on, or the starting view while no file is current. In Orbit it re-centres." },
    { title: "Zoom chords never reach a control, and never count as a Ctrl tap", tag: "invariant", hue: 3, ...R("console", 237),
      links: [RL("console", 209, "zoom_key"), RL("tConsole", 145, "the chord test"), RL("main", 147, "Settings.console_zoom")],
      body: "The console catches Cmd/Ctrl with =, +, - or 0 in _input, before the GUI, so a focused spin box cannot swallow them, and feeds the event to its Ctrl detector first so Ctrl+= disarms the tap. The level is the player's (Settings), not the view's." },
    { title: "Escape frees the mouse and touches nothing else", tag: "invariant", hue: 3, ...R("main", 399),
      links: [RL("console", 252, "the focused console forwards it"), RL("noiseWin", 115, "the focused noise window closes instead"), RL("tMain", 240, "the test"), RL("tMain", 249, "Escape never closes the console")],
      body: "`cancel` sets _free_requested and recaptures nothing: no pause, the console stays open, a click in the view recaptures. With the console focused, Escape is one of the keys it hands to Main, so it frees the mouse there too. Only the focused noise window treats Escape as close." },
    { title: "One frame of latency: Main resolves before the axes move", tag: "gotcha", hue: 2, ...R("main", 237),
      links: [RL("main", 80, "Clock and AxisController are added as Main's children"), RL("axisCtl", 19, "AxisController._process")],
      body: "Godot processes parents before children. Main's _process resolves with the axis value and t the children left last frame; AxisController and Clock move afterwards. A key press reaches params (and the uniforms) one frame after it moved the axis. Invisible at 60 fps; the stepper tab shows it, and the 'same-frame' line is what a higher process_priority on Main would give." },
    { title: "Typing anywhere silences the axes, WASD, N and the Ctrl tap", tag: "gotcha", hue: 2, ...R("textFocus", 11),
      links: [RL("axisCtl", 22, "axes"), RL("fly", 90, "WASD"), RL("main", 412, "N"), RL("main", 98, "Ctrl tap")],
      body: "So typing \"e\" into a spin box never pushes Axis A. Leave the field (Enter, Escape or a click elsewhere) and the keys come back. Unlike WASD, holding Ctrl or Cmd does not silence the axes (fly_camera.gd:88 has no counterpart in AxisController)." },
    { title: "The native console gets its own key events", tag: "gotcha", hue: 2, ...R("console", 245),
      links: [RL("console", 252, "forward to Main"), RL("main", 379, "_on_window_key"), RL("addendum", 193, "why the forwarding exists")],
      body: "Main's _unhandled_input never sees keys typed into the console, so the console runs its own CtrlTap and hands every other unused key to Main through unhandled_key. Held keys still reach the global Input state, so E pushes Axis A while the console has focus (unless a field there has focus)." },
    { title: "Loading a view never unbinds", tag: "gotcha", hue: 2, ...R("table", 123),
      links: [RL("table", 108, "to_dict writes only active bindings"), RL("ws", 61, "restore")],
      body: "A file lists only its active bindings and apply_dict sets only what is listed, so loading saves/default.json while Scale is bound to Axis A keeps the binding (and its drive on top of the loaded default). Same for axis values the file omits, and for the 24 colour, lighting and palette ids: the committed saves predate them, so loading one keeps whatever lighting and palette you had. Consistent with 'loading is additive', but surprising." },
    { title: "A failed keymap Load keymap… still replaces the axes", tag: "gotcha", hue: 2, ...R("keymap", 120),
      links: [RL("keymap", 120, "current_path = path anyway"), RL("movement", 318, "the pane says Load failed"), RL("keymap", 180, "_clear_all")],
      body: "load_file falls back to the default axis on a missing or malformed file AND points current_path at the bad file, so a later Save overwrites it with the default (a saved view handed to it is the one exception: refused by name, nothing changes). Any keymap load also zeroes every axis value (the axes are rebuilt), snapping bound knobs back to their defaults." },
    { title: "Dragging a bound Julia constant", tag: "gotcha", hue: 2, ...R("marker", 60),
      links: [RL("resolver", 35, "the drive is added on top")],
      body: "The marker writes the mouse position as the table DEFAULT. If c_0..2 is bound, the next resolve adds gain × wave on top, so the ring sits off the cursor by the drive." },
    { title: "Only julia_all counts as Julia mode", tag: "gotcha", hue: 2, ...R("params", 275),
      links: [RL("view", 319, "box_half 20 only with julia_all"), RL("sh", 352, "NF normal unless julia_all"), RL("orbit", 156, "the orbit's CPU march")],
      body: "julia_enabled() is julia_all. With only per-component toggles on there is no ring, the march keeps the ±2 cube (a hybrid may reach past it and be clipped), and colour modes 1 to 9 keep the Ice Fractal field normal." },
    { title: "The palette window's sliders stop at the slider range", tag: "gotcha", hue: 2, ...R("pwin", 174),
      links: [RL("shape", 263, "C rows: hard_max 16"), RL("shape", 264, "D rows wrap"), RL("pwin", 217, "the hint")],
      body: "C's catalogue row accepts up to 16 cycles, but the window's slider stops at 4 (Palette.RANGES), so a typed 6 pins the slider at its end while the readout says 6.00. The window is always shown, but edits only show on screen in the Palette colour mode (the hint says so), and its twelve rows stay hidden until then." },
    { title: "The keymap does not check key conflicts", tag: "gotcha", hue: 2, ...R("keymap", 60),
      links: [RL("levels", 183, "level spec: 1–9 reserved")],
      body: "Binding an axis to W also flies forward; both fire. The level-sequences spec reserves 1–9 for levels, with the same caveat." },

    { title: "Ported from Fractacular, minus the Category", tag: "history", hue: 6, ...R("binding", 5),
      links: [COMMIT("11e1a3a"), COMMIT("1b977a3"), RL("design", 79, "spec: what changed in the port")],
      body: "AttributeSpec / Table / Binding / BindingResolver are Fractacular's with one table (no Category), the source a StringName instead of an enum (\"\" none, \"time\", an axis id), no isoclinic and no movement scale. The axes, keymap and clock are new: Fractacular's sources were fixed." },
    { title: "Saved view v1 → v2", tag: "history", hue: 6, ...R("ws", 181),
      links: [COMMIT("782a1ef"), RL("design", 313, "spec: version 2"), RL("saveDef", 2, "default.json is version 2")],
      body: "Version 1 was a flat fractal section with the old names (scale, inner_radius, outer_radius, julia_enabled, julia_point). Version 2 splits shape / axes / fractal / camera / noise. v1 still loads, mapped without a warning; saving always writes v2, and the committed saves were rewritten once." },
    { title: "The Q panel retired", tag: "history", hue: 6, ...R("design", 294),
      links: [COMMIT("c49807b"), COMMIT("55c1bcf"), RL("readme", 197, "README: View tab")],
      body: "ControlsPanel is gone. Its shape sliders, colour, precision and Julia moved to the console; Save / Load, Camera, Noise editor and Fast Controls went to a pause menu (with a Console… button for browsers that swallow the Ctrl tap); the speed readout to the Movement pane. The pause menu itself is gone since 5ebb10a: see the next card." },
    { title: "The pause menu moved into the console", tag: "history", hue: 6, ...R("viewPane", 1),
      links: [COMMIT("5ebb10a"), RL("main", 183, "_build_view_pane"), RL("main", 399, "Escape: cancel"), RL("proj", 63, "the action renamed pause → cancel"), RL("readme", 197, "README: View tab")],
      body: "PauseMenu is deleted. Escape (the action renamed pause → cancel) only frees the mouse: nothing pauses the tree, and the console and noise window stay as they are. Save / Load view with the file name and status, the Camera mode, the mouse sensitivity, the Noise editor button, the Renderer options (with Fast Controls and Reset camera) and Back to Menu are the console's View tab; the title menu's Settings lost its Renderer tab, which only the pause menu could enable. With nothing paused, the governor no longer needs PROCESS_MODE_ALWAYS and the clock never stops." },
    { title: "The Colour tab", tag: "history", hue: 6, ...R("shape", 274),
      links: [COMMIT("58575fc"), COMMIT("e246166"), COMMIT("1cbb1a2"), COMMIT("7f7ba6b"), COMMIT("b527826"), RL("readme", 128, "README: Console")],
      body: "The catalogue grew from 23 to 47 ids: lighting knobs and a cosine-palette colour mode (58575fc), then the console's TabContainer, with Fractacular's palette window heading a Colour tab (e246166). color_mode moved from Render to the new Colour group, after precision, which changed RESOLVED_KEYS order. Alongside: console zoom (7f7ba6b) and Reset camera (b527826)." },
    { title: "Native, then embedded, then native again", tag: "history", hue: 6, ...R("console", 15),
      links: [COMMIT("9401782"), COMMIT("2e23f8c"), COMMIT("ab00332"), RL("addendum", 175, "addendum: why embedded"), RL("uiScale", 134, "place_beside")],
      body: "The spec made both sub-windows native. On macOS (Godot 4.6.1, GL Compatibility) a native window overlapping the main one corrupts its picture, so 9401782 embedded both, and 2e23f8c stacked the console's panes (side by side they overflowed 1000 points). ab00332 made only the console native again with force_native, opened beside the main window; the noise editor stays embedded, and headless and the web embed everything." },

    { title: "Follow-ups the console spec left open", tag: "open", hue: 4, ...R("design", 410),
      body: "Binding rows on noise-node parameters (unify NoiseParamSpec with AttributeSpec); a level format (now the level-sequences spec); clock controls, if a Time binding ever needs pausing; Fractacular's 2D slice panels of the live shape." },
    { title: "Level sequences reshape the console", tag: "open", hue: 4, ...R("levels", 193),
      links: [RL("levels", 151, "entering a level"), RL("levels", 331, "1400 × 700")],
      body: "Planned: a third Sequence column (one HSplitContainer, 1400 × 700 points, so it will often not fit beside the main window), number keys 1–9 entering levels through Main's dispatch, and the console's unhandled_key path forwarding them. Entering a level clears the noise graph when the file has none, but nothing there clears bindings: the 'loading never unbinds' card above still applies." },
    { title: "toggle_panel is a dead action on Ctrl", tag: "open", hue: 4, ...R("proj", 58),
      links: [RL("tBoot", 11, "boot_test still lists it"), RL("ctrlTap", 25, "CtrlTap reads the physical key")],
      body: "The Q panel's action survives in project.godot (physical Ctrl) and boot_test, but nothing in src/ reads it: both detectors look at the physical keycode. Safe to drop with the boot_test line." },
  ],
};

// The checker (tools/viz/check.mjs) verifies every { file, line } it finds in a pane's data. A
// figure's tooltips are built inside draw(), so each figure carries `refs`: every R / RL call with
// literal arguments in its draw source.
function refsIn(fn, extra) {
  const out = [];
  for (const m of String(fn).matchAll(/\bRL?\("(\w+)",\s*(\d+)/g)) out.push(R(m[1], +m[2]));
  return out.concat(extra || []);
}
stepFig.refs = refsIn(stepFig.draw);
consoleFig.refs = refsIn(consoleFig.draw, [52, 54, 70, 81, 95, 105].map(l => R("viewPane", l)).concat([35, 37, 39, 41, 43, 54, 57].map(l => R("renderer", l))).concat([61, 68, 74, 80, 86, 95, 103, 134, 144, 158, 165, 198, 205, 259].map(l => R("shape", l)).concat([289, 292, 277].map(l => R("movement", l)))));

VIZ.pane({
  id: "console",
  short: "Attributes & console",
  title: "Help I'm Stuck In A Fractal — attributes, bindings, axes and the console",
  subtitle: "The Fractacular import. Every knob (47: the Mandelbox shape on the console's Shape tab; colour, lighting and the cosine palette on its Colour tab) is an AttributeSpec in one AttributeTable, with a default and a Binding: value = default + gain × wave(source), where the source is the clock or a virtual axis pushed by a key pair from saves/keymap.json. Main resolves the table into FractalParams once per frame, so the renderer is unchanged. The console, its own OS window, edits the table and the keymap. The stepper runs a line-for-line port of the resolver, checked at load against the tests.",
  commit: "3190cd5565293d27d3d8f5077c9a81f6b5b68d51",
  pinNote: "main, unpushed: links 404 until it is pushed",
  ctx: {
    attr: { hue: 1, label: "catalogue — MandelboxShape, AttributeSpec / Table, Binding, BindingResolver" },
    axes: { hue: 3, label: "movement — Keymap, InputMap, AxisController, Axes, Clock, TextFocus" },
    main: { hue: 4, label: "Main — wiring, the resolve, the Ctrl tap, save / load" },
    ui: { hue: 2, label: "console UI — ConsoleWindow and its panes" },
    cons: { hue: 6, label: "consumers — FractalParams, FractalView, governor, Julia marker" },
    files: { hue: 5, label: "files — keymap.json, Workspace, saves/" },
  },
  kinds: {
    call: { style: "solid", label: "calls · writes" },
    signal: { style: "dash", label: "signal (changed, toggle_requested, unhandled_key)" },
    data: { style: "dot", label: "reads a value" },
  },
  tabs: [
    arch,
    frameSeq,
    stepFig,
    consoleFig,
    { label: "The catalogue", rows: [[shapeCat], [colourCat]] },
    tapSeq,
    { label: "Keymap", rows: [[kmFile], [kmApi]] },
    { label: "Saved views", rows: [[viewTable, v1Table]] },
    cards,
  ],
  // The ports, exposed for checking from the console or node.
  ports: { makeSpec, sanitize, waveformValue, resolveValue, resolveParts, axesStep, simulate, wrapf, fposmod, SPECS, PORT },
});
})();
