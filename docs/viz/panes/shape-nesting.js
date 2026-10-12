// Pane: shape nesting — the scene of placed shapes and the calls behind it. Every file:line below
// was read at `commit` with `git show <commit>:<path>`. When the code changes: re-read the lines,
// bump `commit`, run `node tools/viz/check.mjs --print --pane shape-nesting`.
//
// The live figure ports the two ways a sample point can be formed (world space vs. the shape's own
// frame) and rounds through Math.fround exactly where the shader's float32 would, so the error it
// plots is the error the GPU makes.
(function () {
const F = {
  shape: "src/fractal/shape_params.gd",
  params: "src/fractal/fractal_params.gd",
  list: "src/fractal/shape_list.gd",
  cat: "src/fractal/shape_catalogue.gd",
  de: "src/fractal/distance_estimator.gd",
  sh: "src/fractal/mandelbox.gdshader",
  view: "src/fractal/fractal_view.gd",
  cam: "src/camera/camera_state.gd",
  fly: "src/camera/fly_camera.gd",
  orbit: "src/camera/orbit_camera.gd",
  marker: "src/camera/julia_marker.gd",
  main: "src/main.gd",
  pane: "src/ui/console/shape_list_pane.gd",
  console: "src/ui/console/console_window.gd",
  inspector: "src/ui/console/attribute_inspector.gd",
  ws: "src/workspace/workspace.gd",
  save: "saves/nestedEscape.json",
  readme: "README.md",
  tDE: "tests/distance_estimator_test.gd",
  tCam: "tests/camera_state_test.gd",
  tView: "tests/fractal_view_test.gd",
  tWs: "tests/workspace_test.gd",
  tList: "tests/shape_list_test.gd",
  tMain: "tests/main_test.gd",
  tShader: "tests/shader_test.gd",
  tMarker: "tests/julia_marker_test.gd",
  tConsole: "tests/console_test.gd",
  tUi: "tests/ui_console_test.gd",
  tShots: "tests/screenshots.gd",
  tParams: "tests/fractal_params_test.gd",
  tRay: "tests/center_ray_test.gd",
};
const R = (f, line) => ({ file: F[f], line });
const RL = (f, line, label) => ({ file: F[f], line, label });
const SH = line => R("sh", line);

// ================================================================== 1. the architecture
const arch = {
  type: "graph",
  tab: "How a scene renders",
  title: "From a list of shapes to one picture",
  note: "The single AttributeTable became a ShapeList of per-shape tables plus one LOOK table (light, colour, material, palette) for the whole scene; the resolved FractalParams holds a list of ShapeParams (each with a placement) and the look; the shader's per-shape uniforms became arrays indexed by shape while the look uniforms stayed scalars. Everything downstream still talks through the same `changed` signals. The one new idea is the FRAME: each shape's local coordinates, computed on the CPU in 64-bit, so the shader only ever sees O(1) numbers whatever the shape's size. Hover anything for what it does and the line that does it.",
  zones: [
    { id: "author", label: "AUTHORING — THE CONSOLE", x: 0, y: 0, w: 540, h: 330 },
    { id: "resolve", label: "RESOLVE — ONCE A FRAME", x: 600, y: 0, w: 360, h: 140 },
    { id: "state", label: "STATE — THE RESOURCES", x: 600, y: 180, w: 360, h: 340 },
    { id: "render", label: "RENDER — ARRAYS AND FRAMES", x: 1020, y: 0, w: 900, h: 520 },
    { id: "consumers", label: "CONSUMERS OF THE SCENE DISTANCE", x: 0, y: 370, w: 540, h: 330 },
    { id: "math", label: "CPU MATHS — 64-BIT", x: 600, y: 560, w: 560, h: 140 },
    { id: "files", label: "FILES — VERSION 4", x: 1200, y: 560, w: 720, h: 140 },
  ],
  nodes: [
    { id: "pane", label: "ShapeListPane", sub: "Add shape · ▾/▸ · ✕ · select", ctx: "input", zone: "author", x: 30, y: 60, ...R("pane", 1),
      blurb: "The Shape tab: one header line (arrow, editable label, ✕) over one AttributeInspector per shape, in one scrolling list, under the Add shape button and the self-similarity line. A click on a header selects the shape; Add shape asks Main for a placement in front of the camera. It rebuilds its entries whenever the list's structure changes, keeping each entry's expanded state by index.",
      links: [RL("pane", 134, "add_shape"), RL("pane", 146, "remove_shape"), RL("pane", 182, "_rebuild"), RL("tUi", 250, "driven by clicks")] },
    { id: "list", label: "ShapeList", sub: "labels + an AttributeTable per shape", ctx: "input", zone: "author", x: 30, y: 180, ...R("list", 1),
      blurb: "The scene as the player authors it: an ordered list of {label, table}. Never empty. `changed` is its structure (add, remove, a load), `relabelled` a name, `entry_changed(index, id)` a table edit. One signal per kind, so a relabel does not rebuild the console.",
      links: [RL("list", 73, "add"), RL("list", 91, "remove (never the last)"), RL("list", 103, "resolve"), RL("tList", 8, "the test")] },
    { id: "tables", label: "AttributeTable × N + the look", sub: "shape_specs() per shape, scene_specs() once", ctx: "input", zone: "author", x: 330, y: 180, ...R("cat", 92),
      blurb: "Every shape's table runs over the per-shape catalogue: seven Placement ids (pos_x/y/z, rot_x/y/z, size) in front of the fractal, fold, Julia, KIFS, Kleinian, Mandelbulb and Render ids. The Light, Material and Palette ids are one table for the scene (the console's Light and Material tabs). Being catalogue knobs, the placement rows bind, save and show like any other.",
      links: [RL("cat", 56, "PLACEMENT_IDS"), RL("cat", 101, "shape_specs()"), RL("cat", 168, "scene_specs()"), RL("cat", 426, "shader_ids(): minus the placement")] },
    { id: "inspector", label: "AttributeInspector × N", sub: "one panel per shape, no scroll of its own", ctx: "input", zone: "author", x: 330, y: 270, ...R("inspector", 33),
      blurb: "Unchanged rows; the inspector can be built without its own ScrollContainer so the pane can stack several in one list. console.inspector() returns the selected shape's panel, which is what every existing test (and the Julia marker) means by 'the inspector'.",
      links: [RL("inspector", 57, "the two layouts"), RL("console", 171, "console.inspector()")] },
    { id: "resolveN", label: "Main._resolve_once", sub: "every table → its ShapeParams; the look → params", ctx: "input", zone: "resolve", x: 630, y: 60, ...R("main", 452),
      blurb: "Each frame: ShapeList.resolve gives one id→value dict per shape (bindings applied), each written into params.shapes[i] with apply_resolved, which emits once per shape and only on a difference; the look table resolves into the params' own fields. The console's readouts get both.",
      links: [RL("main", 456, "resolve()"), RL("main", 458, "apply_resolved per shape"), RL("main", 206, "_sync_shapes keeps the counts equal")] },
    { id: "params", label: "FractalParams", sub: "look + prefs + shapes: Array[ShapeParams] + active", ctx: "state", zone: "state", x: 630, y: 240, ...R("params", 1),
      blurb: "Still 'every value the renderer reads', now holding the list and the scene's look. A new one has one default shape at the identity placement, which is exactly the old single-shape viewer, so FractalParams.new() in a test means what it always did. Any shape's `changed` is relayed as the params' own.",
      links: [RL("params", 45, "MAX_SHAPES = 8"), RL("params", 112, "add_shape relays changed"), RL("params", 297, "hit_epsilon(t, near, precision)"), RL("params", 33, "the look keys")] },
    { id: "shape", label: "ShapeParams × N", sub: "resolved knobs + the frame maths", ctx: "state", zone: "state", x: 630, y: 350, ...R("shape", 1),
      blurb: "One shape's resolved values (every fractal knob plus pos, rot, size) and the frame: R = Rz·Ry·Rx from the three angles, to_local(p) = Rᵀ(p − pos)/size and to_world, all in 64-bit scalars because Vector3 is float32 and p − pos cancels catastrophically for a small shape far from the origin. Its bound, coarse pass and zoom floor are in its own units.",
      links: [RL("shape", 358, "frame()"), RL("shape", 385, "to_local"), RL("shape", 409, "to_world"), RL("shape", 233, "apply_resolved"), RL("shape", 320, "coarse_iters"), RL("shape", 347, "zoom_floor")] },
    { id: "camState", label: "CameraState", sub: "Transform3D + a 64-bit eye", ctx: "state", zone: "state", x: 630, y: 450, ...R("cam", 1),
      blurb: "The eye is kept as three 64-bit floats; transform.origin is its float32 mirror for everything that projects. set_eye / move_by accumulate in 64-bit (and still emit when the mirror does not move); assigning `transform` makes its origin the truth again, which is what the orbit camera and the tests do.",
      links: [RL("cam", 64, "set_eye"), RL("cam", 79, "move_by"), RL("cam", 84, "set_basis"), RL("tCam", 43, "1000 moves of 1e-9")] },
    { id: "pushP", label: "FractalView._push_params", sub: "an array of MAX_SHAPES per shape id", ctx: "render", zone: "render", x: 1050, y: 60, ...R("view", 399),
      blurb: "Every per-shape uniform is a Packed*Array of MAX_SHAPES entries, filled from params.shapes in order and padded with zeros: floats as PackedFloat32Array, the toggles and enums as PackedInt32Array. The look uniforms are pushed as the scalars they always were. Detail (and the load shedder's factor) is folded into each precision entry.",
      links: [RL("view", 25, "INT_IDS"), RL("view", 417, "precision / detail"), RL("view", 445, "shape_count"), RL("view", 446, "view_limit")] },
    { id: "pushF", label: "FractalView._push_near", sub: "local_eye · frame axes · near · coarse_iters", ctx: "render", zone: "render", x: 1050, y: 190, ...R("view", 492),
      blurb: "The one place the camera and the placements meet: for every shape, the eye mapped into its frame (to_local in 64-bit, rounded once to a Vector3), the frame's three axes in world space, and that shape's coarse-pass iteration count at its own distance. It also pushes near_dist (the scene distance at the eye). Both the params push and the camera push end here.",
      links: [RL("view", 519, "local_eye"), RL("view", 520, "frame_x/y/z"), RL("view", 523, "coarse_iters per shape"), RL("view", 529, "nearest_shape()"), RL("tView", 203, "local eye = Rᵀ(eye − pos)/size")] },
    { id: "arrays", label: "uniform arrays", sub: "shape[8] … precision[8], local_eye[8]", ctx: "render", zone: "render", x: 1420, y: 60, ...SH(66),
      blurb: "The shader declares `const int MAX_SHAPES = 8` and one array per catalogue shader id, plus the frame: local_eye, frame_x/y/z, shape_size, box_half, coarse_iters and shape_count. The names still equal the catalogue (the shader ids plus the scene ids), which shader_test checks, now with the array types.",
      links: [SH(25), RL("sh", 80, "the shape arrays"), RL("sh", 92, "toggles as int arrays"), RL("tShader", 71, "MAX_SHAPES matches")] },
    { id: "deScene", label: "de_scene(off, coarse, which)", sub: "min over shapes, in world units", ctx: "render", zone: "render", x: 1420, y: 170, ...SH(414),
      blurb: "The scene distance at a world offset from the eye: for each shape, the point in its frame, the cheap cube-distance bound (skip the shape when the bound is already past the best so far), else de(i, q) × size with that shape's own coarse iteration count. Returns the smallest and WHICH shape gave it, so the hit uses that shape's precision and frame.",
      links: [SH(419), RL("sh", 421, "the bound skip"), RL("sh", 422, "coarse_iters[i]"), RL("de", 48, "the same on the CPU")] },
    { id: "localPt", label: "local_offset_point(i, off)", sub: "local_eye[i] + Rᵀoff / size", ctx: "render", zone: "render", x: 1420, y: 280, ...SH(212),
      blurb: "The only way the shader forms a sample point. local_eye came from the CPU in 64-bit, Rᵀoff is the ray's offset turned into the shape's frame, and off/size is O(1) near the shape, so nothing here is a difference of two large float32 numbers. This line is why a shape a thousandth the size renders as cleanly as the full one.",
      links: [SH(217), RL("tDE", 195, "a 1e-9 world offset resolves")] },
    { id: "shade", label: "shading in the hit shape's frame", sub: "normal, light, eye: all local", ctx: "render", zone: "render", x: 1420, y: 390, ...SH(659),
      blurb: "After the hit, v, h, the eye and the normal are all in shape `which`'s frame, so one shape at the identity shades bit-for-bit as the single-shape viewer did. The normal's finite-difference delta is divided by size; the normal is rotated back to world for the shadow march and the two view-relative modes (14, 15). The look (light, colour, material) is the scene's.",
      links: [SH(702), SH(708), SH(755)] },
    { id: "fly", label: "FlyCamera", sub: "speed = scene distance · move_by", ctx: "camera", zone: "consumers", x: 30, y: 430, ...R("fly", 1),
      blurb: "Travel speed is the distance to the nearest surface of ANY shape (at the 64-bit eye), so inside a small shape you crawl at its scale and speed up as you escape. Movement goes through CameraState.move_by, accumulated in 64-bit; a look change goes through set_basis and leaves the eye alone. The zoom floor is the nearest shape's, at its scale.",
      links: [RL("fly", 153, "base_speed: scene_estimate_at"), RL("fly", 101, "move_allowed_at"), RL("fly", 88, "move_by"), RL("fly", 167, "set_basis")] },
    { id: "orbit", label: "OrbitCamera", sub: "click → DistanceEstimator.march", ctx: "camera", zone: "consumers", x: 30, y: 530, ...R("orbit", 155),
      blurb: "Re-centring on what is under the cursor marches the scene (every shape's oriented cube, the union distance) in 64-bit. Its own moves still assign whole transforms, so orbit mode truncates the eye to float32: author at ordinary scales, escape in Fly.",
      links: [RL("orbit", 157, "the march"), RL("orbit", 109, "a transform is assigned")] },
    { id: "marker", label: "JuliaMarker", sub: "the ACTIVE shape's constant, in its frame", ctx: "camera", zone: "consumers", x: 30, y: 630, ...R("marker", 1),
      blurb: "Draws the selected shape's Julia point at to_world(c) and maps a drag back with to_local, writing c_0..2 into that shape's table. Which shape is 'active' is params.active, set by the console's selection.",
      links: [RL("marker", 42, "world_point"), RL("marker", 70, "to_local on drag"), RL("main", 230, "selection → params.active"), RL("tMarker", 44, "a placed shape's ring")] },
    { id: "nearest", label: "DistanceEstimator.nearest_at", sub: "{distance, index} at a 64-bit point", ctx: "math", zone: "math", x: 630, y: 620, ...R("de", 48),
      blurb: "The CPU twin of de_scene: to_local per shape, the cube bound, the single-shape estimate_at (unchanged: the 24 Mandelbox fixtures and the KIFS, Kleinian and Mandelbulb fixtures still pin it, each estimator now taking a ShapeParams) times size, keep the smallest. scene_estimate_at is its distance; FractalView pushes it as near_dist.",
      links: [RL("de", 143, "estimate_at (one shape)"), RL("de", 67, "cube_distance"), RL("tDE", 185, "scene = size × local"), RL("tDE", 220, "a nested KIFS")] },
    { id: "march", label: "DistanceEstimator.march", sub: "scene_bounds + the union, 200 steps", ctx: "math", zone: "math", x: 900, y: 620, ...R("de", 118),
      blurb: "The CPU march (the orbit click, the centre ray) learned the scene: scene_bounds intersects every shape's cube in that shape's frame (so a rotated cube is oriented) and maps the entry and exit back to world ray distance by size, cut at the scene's view distance; the step is nearest_at.",
      links: [RL("de", 78, "scene_bounds"), RL("de", 101, "box_intersect"), RL("params", 425, "scene_view_distance")] },
    { id: "ws", label: "Workspace v4", sub: "shapes[] · active · look · a 15-digit eye", ctx: "files", zone: "files", x: 1230, y: 620, ...R("ws", 38),
      blurb: "capture writes the ShapeList as a list of {label, defaults, bindings}, the active index and the look table; restore replaces the list and sizes params.shapes to match. A version-3 file's one 'shape' table is split into one shape and the look; versions 2 and 1 reach it the same way. The eye is written with 15 significant digits and read back through set_eye.",
      links: [RL("ws", 60, "shapes.to_dict()"), RL("ws", 238, "_split_shape"), RL("ws", 354, "set_eye on load"), RL("tWs", 175, "a v3 file loads silently")] },
    { id: "save", label: "saves/nestedEscape.json", sub: "Outer 1 ⊃ Middle 0.04 ⊃ Inner 0.0016", ctx: "files", zone: "files", x: 1560, y: 620, ...R("save", 243),
      blurb: "Three default Mandelboxes threaded through the same roomy pocket (local (1.51, 0.01, −1.33), DE 0.089, open toward local +x and −z), each turned so no straight line from the innermost pocket leaves the scene, with the camera in that pocket looking out. The screenshot pass renders it and requires it to differ from the outer shape alone.",
      links: [RL("save", 317, "the 15-digit eye"), RL("tShots", 154, "the nested_escape check"), RL("readme", 366, "Shapes and nesting")] },
  ],
  edges: [
    { from: "pane", to: "list", kind: "call", label: "add · remove · set_label", ...R("pane", 138),
      blurb: "The pane edits the list; the list answers with its signals and the pane rebuilds (or relabels) from them. Main hears the same signals." },
    { from: "list", to: "tables", kind: "data", label: "owns", ...R("list", 5), blurb: "A new entry is a fresh AttributeTable over ShapeCatalogue.shape_specs(), its defaults overridden by whatever add() was given (Main's placement)." },
    { from: "tables", to: "inspector", kind: "data", label: "rows", ...R("pane", 202), bow: 0, blurb: "Each entry's panel is built over its own table, exactly as the single inspector was." },
    { from: "list", to: "resolveN", kind: "call", label: "resolve() each frame", ...R("main", 456), bow: 0.6 },
    { from: "list", to: "params", kind: "signal", label: "changed → set_shape_count", ...R("main", 92), bow: 1.2,
      blurb: "Main keeps params.shapes the same length as the list on every structural change, then resolves at once so the new shape's values land before the next frame." },
    { from: "resolveN", to: "shape", kind: "call", label: "apply_resolved", ...R("main", 458), bow: -0.5 },
    { from: "shape", to: "params", kind: "signal", label: "changed, relayed", ...R("params", 112), bow: 0.4 },
    { from: "params", to: "pushP", kind: "signal", label: "changed", ...R("view", 117) },
    { from: "camState", to: "pushF", kind: "signal", label: "changed", ...R("view", 119) },
    { from: "pushP", to: "pushF", kind: "call", label: "ends in", ...R("view", 399), bow: 0 },
    { from: "pushP", to: "arrays", kind: "data", label: "Packed*Array per id", ...R("view", 417) },
    { from: "pushF", to: "arrays", kind: "data", label: "local_eye · frame_x/y/z", ...R("view", 519), bow: 0.4 },
    { from: "pushF", to: "nearest", kind: "call", label: "near_dist · nearest shape", ...R("view", 532), bow: 0.8 },
    { from: "shape", to: "pushF", kind: "data", label: "to_local(eye), axes()", ...R("shape", 373), bow: 0.3 },
    { from: "arrays", to: "deScene", kind: "data", label: "indexed by shape", ...SH(423) },
    { from: "deScene", to: "localPt", kind: "call", label: "per shape", ...SH(419) },
    { from: "deScene", to: "shade", kind: "data", label: "which → precision, frame", ...SH(623), bow: 1.4 },
    { from: "fly", to: "nearest", kind: "call", label: "scene_estimate_at(eye)", ...R("fly", 154), bow: 0.4 },
    { from: "fly", to: "camState", kind: "call", label: "move_by · set_basis", ...R("fly", 88), bow: -0.3 },
    { from: "orbit", to: "march", kind: "call", label: "a click", ...R("orbit", 157), bow: 0.6 },
    { from: "marker", to: "shape", kind: "data", label: "active_shape()", ...R("marker", 38), bow: -0.6 },
    { from: "nearest", to: "shape", kind: "data", label: "to_local · estimate_at", ...R("de", 58), bow: -0.3 },
    { from: "march", to: "nearest", kind: "call", label: "each step", ...R("de", 118), bow: 0 },
    { from: "ws", to: "list", kind: "call", label: "to_dict · apply_dict", ...R("ws", 99), bow: -1.6 },
    { from: "save", to: "ws", kind: "data", label: "JSON", ...R("ws", 176), bow: 0 },
  ],
};

// ================================================================== 2. the tough calls
const calls = {
  type: "cards",
  tab: "Tough calls",
  title: "Shape nesting — the calls that were not obvious",
  columns: 2, cardWidth: 560,
  cards: [
    { title: "Merged onto main by re-porting, not by resolving conflicts", tag: "history", hue: 6, ...R("params", 33),
      links: [RL("cat", 92, "specs() = shape + scene"), RL("ws", 238, "the v3 split"), RL("readme", 366, "the README's account")],
      body: "The feature was first built on a main that had one Mandelbox and thirty knobs. By the time it was done, main had grown three more fractals, a Light tab, a Material tab with the cosine palette, the deep-zoom coarse pass, the 'level' save and about eighty commits; a textual merge conflicted in two dozen files and would have reproduced neither side. So the design was re-applied to the new main file by file — the same ShapeParams / ShapeList / frame / 64-bit eye / uniform-array shape, over the new catalogue — and the old branch is kept only as history. The one decision the new main forced is the next card." },
    { title: "Light, colour and material are the scene's, not the shape's", tag: "history", hue: 6, ...R("cat", 168),
      links: [RL("cat", 409, "shape_ids()"), RL("cat", 417, "scene_ids()"), RL("console", 129, "the palette edits the look"), RL("ws", 62, "'look' in the save")],
      body: "The first build gave every shape its own colour mode (the three nested demo shapes read as three things). On the new main the look is 34 knobs — colour mode, the lamp, scattering, exposure, the material, the twelve palette numbers — and making them per shape would mean 34 more uniform arrays, a Light and a Material tab per shape, and a per-shape Palette window. Nesting needs the fractal knobs and the placement per shape; it does not need a different lamp inside each one. So the catalogue is split: shape_specs() (Placement, Fractal, Box, Julia, Iteration rotation, KIFS, Kleinian, Mandelbulb, Render) per shape, scene_specs() (Light, Scattering, Picture, Colour, Surface, Texture, Palette) once. The cost: nested shapes differ by fractal and knobs, not by colour. A per-shape tint is the obvious next knob if that proves too plain." },
    { title: "Placement is part of the catalogue", tag: "history", hue: 6, ...R("cat", 56),
      links: [RL("cat", 101, "shape_specs(): Placement first"), RL("cat", 426, "shader_ids()"), RL("tShader", 35, "the placement is not a uniform")],
      body: "Position, rotation and size are seven AttributeSpecs in a Placement group at the top of every shape's panel. That buys bindings (a position on Time drifts, a rotation on an axis tumbles), the rows, the readouts, sanitising and the save format for free. The cost: the shader's uniform set no longer equals the whole catalogue — shader_ids() is the shape ids minus PLACEMENT_IDS, and shader_test checks that the placement ids are NOT uniforms. The placement is consumed on the CPU into each shape's frame." },
    { title: "Uniform arrays of MAX_SHAPES = 8", tag: "history", hue: 6, ...SH(25),
      links: [RL("view", 25, "INT_IDS"), RL("sh", 92, "toggles as int arrays"), RL("tShader", 71, "the constant is checked")],
      body: "One array per shape id, indexed by shape in a loop with an early break on shape_count, pushed as Packed*Arrays padded to 8; the KIFS, Kleinian and Mandelbulb includes take the shape index too. The alternative — splicing a per-count shader the way the noise compiler does — would recompile on every add and remove. Eight is a cap on nesting depth, not on what fits in a frame; raising it is one constant in two places (the shader and FractalParams), and the test ties them together. The bool toggles travel as ints because bool uniform arrays were the one type I could not confirm the GL backend accepts. 127 uniforms in all; the compatibility renderer takes them." },
    { title: "The frame is applied to the eye on the CPU, in 64-bit", tag: "invariant", hue: 3, ...R("view", 492),
      links: [SH(212), RL("shape", 385, "to_local in scalars"), RL("tDE", 195, "1e-9 at |p| = 4 resolves"), RL("tView", 203, "the pushed local eye")],
      body: "The artefact the brief asked about: forming eye + dir·t in world float32 and subtracting a shape's position loses about 1e-6 absolute at |p| ≈ 10, which is 1e-3 of a shape a thousandth the size — visible jitter — and everything for a shape a ten-thousandth the size. So the shader never does it. The CPU maps the eye into every frame with 64-bit scalars (to_local), rounds once, and the shader samples local_eye + Rᵀoff/size: every term is O(1) in the shape's own units. The 'Float32 at scale' tab plots both ways." },
    { title: "The camera's eye lives in 64-bit", tag: "invariant", hue: 3, ...R("cam", 64),
      links: [RL("cam", 22, "the setter keeps the eye unless the origin moved"), RL("cam", 79, "move_by"), RL("tCam", 43, "the test")],
      body: "Mapping the eye in 64-bit is pointless if the eye itself is a float32 Vector3: inside a 1e-3 shape at |p| ≈ 5 a frame's travel (~1e-5) is only 20 ulps, and at 1e-4 it is lost. So CameraState holds three floats, FlyCamera moves through move_by and turns through set_basis, Workspace saves 15 digits and loads through set_eye, and Main's Reset camera remembers the 64-bit home. The orbit camera still assigns whole transforms and so truncates the eye: it is an authoring mode, used at ordinary scales. A deeper fix (64-bit everywhere, or a floating origin) was not worth it before anyone needs to orbit inside the innermost shape." },
    { title: "A union with a cube-bound skip is still a lower bound", tag: "invariant", hue: 3, ...SH(414),
      links: [RL("sh", 421, "the skip"), RL("de", 56, "the same on the CPU"), RL("tDE", 185, "scene = size × local")],
      body: "Each step takes min over shapes of de(i, q)·size. Before evaluating shape i the shader checks the distance to its cube (0 inside): when that bound already exceeds the best so far the shape cannot be nearest and is skipped. The true distance to the skipped shape is at least its bound, so the step the ray takes (the best so far) never crosses it. Inside a nest every enclosing shape's cube contains the point, so the enclosing shapes are always evaluated: the cost of a step is the nesting depth, not the shape count. Order the list outer to inner so the cheap skips happen. The Kleinian's bound is its view distance, so a Kleinian in the list is always evaluated." },
    { title: "The hit shape sets the precision; each shape has its own coarse pass and zoom floor", tag: "history", hue: 6, ...SH(623),
      links: [RL("sh", 422, "coarse_iters[i]"), RL("shape", 320, "coarse_iters(near / size)"), RL("shape", 347, "zoom_floor × size"), RL("tParams", 242, "a hundredth the size, a hundredth the distance")],
      body: "With one precision per shape the stop test is d < hit_eps(t, precision[which]) for the shape that gave the smallest distance, so a nested shape keeps its own Precision knob meaningful. The deep-zoom machinery that main grew meanwhile — the coarse pass that takes more iterations the closer the camera is, the LOD range, the zoom floor — is all 'how far from the surface, in the shape's own units': so coarse_iters is computed per shape from near / size and pushed as an array, and the zoom floor is the nearest shape's, at ulp32 of its local eye × its size. A camera inside a 0.0016 shape gets the full 32-iteration pass at 1e-6 of travel, as it would at 1e-3 in the unit shape." },
    { title: "Shading stays in the hit shape's frame", tag: "invariant", hue: 3, ...SH(659),
      links: [SH(702), SH(708), RL("tShots", 154, "nested_escape must differ from the outer alone")],
      body: "The point, the eye, the light direction and both normals are evaluated in local coordinates, with the finite-difference delta divided by size. That makes one shape at the identity placement shade exactly as before, and makes a rotated shape's intrinsic colouring (the modes that read n or h) turn with it. The normal goes back to world (world_dir) for the two view-relative modes (Rainbow Metal, Gold), the soft shadow and the scattering, which march world rays. The noise field is likewise sampled in local coordinates, so one graph displaces every shape at its own scale." },
    { title: "Add shape: a tenth-size copy, seven sizes ahead", tag: "history", hue: 6, ...R("main", 178),
      links: [RL("main", 35, "the two constants"), RL("main", 194, "add_shape"), RL("tMain", 224, "the test")],
      body: "The brief: default the new shape centred in front of the camera. The rest was a call. Size: a tenth of the selected shape's, because the stated workflow is nesting and 'an order of magnitude smaller' was the brief's own number. Distance: 7 × the new size, so its whole cube (4 sizes across) fits the 40° view with a margin. Knobs: copied from the selected shape, bindings not, because 'nest a smaller copy' is the move; catalogue defaults would have made every added shape the stock Mandelbox. Rotation: none. One button, no Duplicate; the placement rows are right there to change any of it." },
    { title: "Typed steps of 1e-6 and 1e-9", tag: "gotcha", hue: 2, ...R("cat", 101),
      links: [RL("shape", 44, "size never 0")],
      body: "A SpinBox snaps a typed value to its step, and the AttributeRow uses the spec's step for both the slider and the box. A nested shape's position wants digits a 0.01 step would round off, so the position specs step at 1e-6 (the box shows six decimals) and size at 1e-9 on a log slider from 1e-4 to 10, hard-limited to 1e-9…1e3. Values set by code (Main's placement, a load) are never snapped — only typing is. ShapeParams floors size at 1e-9: a zero size would divide the frame by zero." },
    { title: "Save version 4: a list, an index, a look, a 15-digit eye", tag: "history", hue: 6, ...R("ws", 38),
      links: [RL("ws", 50, "capture"), RL("ws", 238, "v3 → v4: _split_shape"), RL("ws", 370, "_tidy(x, digits)"), RL("tWs", 175, "a v3 file loads silently")],
      body: "'shape' became 'shapes' (label, defaults, bindings per entry) plus 'active' and 'look'. A version-3 file (one table over the whole old catalogue) is split by id: the per-shape ids become one entry at the identity placement, the look ids the look table, the old light_shininess still migrating to roughness on the way; v2 and v1 reach the same split as before. The camera eye used to be tidied to 7 significant digits for a readable file; a camera inside a nested shape sits at a position 7 digits would not hold, so the eye gets 15 and the unit vectors keep 7. The committed levels stay v3 on disk and load unchanged; nestedEscape.json is the first v4." },
    { title: "The demo nest is 1/25 per level, and turned", tag: "gotcha", hue: 2, ...R("save", 243),
      links: [RL("readme", 366, "the README's account"), RL("tShots", 154, "rendered by the screenshot pass")],
      body: "The roomiest pocket in the default Mandelbox (found by a grid search over the cube, then refined) has 0.089 local units of room at (1.51, 0.01, −1.33) and opens toward local +x and −z. A tenth-size shape's cube (half-width 0.2) would not fit it; at 1/25 the inner fractal's solid (about ±0.06) does. With identity rotations the three pockets line up into a straight corridor out, so each inner shape's rotation was searched (12³ angles) for the one whose probe rays from the pocket travel least: Middle (90, −150, 120), Inner (30, 120, 90). From the camera, none of 200 random rays nor any axis ray leaves the scene (the furthest hit is 0.6 away, the axes under 0.011). Clipping between levels is accepted, per the brief. With the look now scene-wide the three levels no longer differ in colour; they differ in scale." },
    { title: "Flight inside a small shape is slow by design", tag: "gotcha", hue: 2, ...R("fly", 153),
      links: [RL("fly", 156, "the 1e-6 floor")],
      body: "Speed is one second per distance to the nearest surface, of any shape, so the camera in the innermost pocket of the demo moves at about 1.4e-4 units per second and the inner cube (0.0064 across) takes a while to cross. It is the same rule that makes approach comfortable; it just applies at every scale now. The 1e-6 floor on the distance would bite for shapes below about 1e-5 — not reachable with the size slider's default range, and the precision budget tab says why not to go there." },
    { title: "The ray parameter t stays float32", tag: "open", hue: 4, ...SH(212),
      body: "t is world units; a surface at distance t is resolved to precision·t, and float32 resolves t to about 6e-8·t, so there is a thousandfold margin at the default precision and no scale at which t itself runs out before the pixel cone does. The one real limit is the 1e-6 floor on near_dist and on flight speed. If someone wants shapes below 1e-5, make the march relative to a floating origin per shape (t measured from the cube entry) rather than widening t." },
    { title: "The older panes are pinned before the scene of shapes", tag: "open", hue: 4, ...R("readme", 561),
      body: "The mandelbox, console and shapes panes port the single-shape shader and cite lines that moved; at their pinned commits the links are right and the figures still show the real single-shape maths, which is what one shape at the identity placement is. Refresh them (re-read, fix the drift, bump the commit) with /visualize when the shader settles; this pane carries the multi-shape account meanwhile." },
    { title: "Not done: reorder, Duplicate, per-shape tint, per-shape noise, 64-bit orbit", tag: "open", hue: 4, ...R("list", 1),
      body: "List order only decides which shape is tried first in de_scene, so reordering is a performance nicety (outer first); a drag handle in the pane would do it. Add shape copies the selected shape, so a Duplicate button is nearly the same thing; add it if the copy default proves wrong. A per-shape tint would give nested levels back their distinct look without a per-shape palette. The noise graph is one per view and applies in every shape's frame; a per-shape graph is a bigger change. Orbit mode truncates the 64-bit eye (see the camera card)." },
  ],
};

// ================================================================== 3. one march step
const seq = {
  type: "seq",
  tab: "One march step",
  title: "What one step of the march does for N shapes",
  note: "A ray from fragment() starts at the first cube it meets (every cube intersected in its own frame) and steps by the scene distance until a hit, the last cube, the fog or the view distance. Each step is a loop over the shapes with the cube-bound skip; the hit shape's precision ends the march and its frame shades the pixel with the scene's look.",
  laneWidth: 215, headWidth: 190,
  participants: [
    { id: "frag", col: 0, ctx: "render", name: "fragment()", sub: "the pixel's ray", ...SH(559) },
    { id: "scene", col: 1, ctx: "render", name: "de_scene", sub: "min over shapes", ...SH(414) },
    { id: "lp", col: 2, ctx: "state", name: "local_offset_point", sub: "the shape's frame", ...SH(212) },
    { id: "de", col: 3, ctx: "math", name: "de(i, q, iters)", sub: "the shape's fractal", ...SH(391) },
    { id: "shade", col: 4, ctx: "render", name: "shading", sub: "in the hit frame", ...SH(659) },
  ],
  rows: [
    { sec: "BOUNDS — the union of the cubes" },
    { from: "frag", to: "lp", kind: "call", label: "box_intersect(local_eye[i], Rᵀdir, box_half[i]) · size", tick: "per shape; t_start = min entry, t_exit = max exit", ...SH(581),
      blurb: "Each cube is met in its shape's frame (a turned shape has a turned cube) and the local t is scaled back to world by size. A ray that meets no cube is the sky; the exit is also cut at the fog and the scene's view distance." },
    { from: "frag", to: "frag", kind: "call", label: "no cube → the background", ...SH(592) },
    { sec: "PHASE 1 (coarse_iters[i]) THEN PHASE 2 (32) — one step" },
    { from: "frag", to: "scene", kind: "call", label: "d = de_scene(dir · total, coarse, which)", ...SH(611) },
    { from: "scene", to: "lp", kind: "call", label: "q = local_eye[i] + Rᵀ(dir · total) / size", ...SH(419),
      blurb: "The point in shape i's frame, from the 64-bit local eye the CPU pushed. Never eye + dir·t." },
    { from: "scene", to: "scene", kind: "call", label: "bound = cube_dist(q) · size ≥ best → skip", ...SH(421),
      blurb: "A shape whose cube is further than the best distance so far cannot be nearest. Its true distance is at least the bound, so the step stays safe." },
    { from: "scene", to: "de", kind: "call", label: "d_i = de(i, q, coarse ? coarse_iters[i] : 32) · size", ...SH(423) },
    { from: "de", to: "de", kind: "call", label: "the shape's fractal on the shape's own knobs", ...SH(391) },
    { from: "de", to: "scene", kind: "data", label: "keep the smallest, remember which", ...SH(424) },
    { from: "scene", to: "frag", kind: "data", label: "d, which", ...SH(414) },
    { from: "frag", to: "frag", kind: "call", label: "d < hit_eps(total, precision[which]) → hit", tick: "× 2 in phase 1", ...SH(623),
      blurb: "The hit shape's own precision (with the global detail folded in by the CPU) decides the stop, so a nested shape's Precision knob still means what it says." },
    { from: "frag", to: "frag", kind: "call", label: "total += d · noise_step_scale(); past t_exit → sky", ...SH(613) },
    { sec: "THE HIT" },
    { from: "frag", to: "shade", kind: "call", label: "v = local_point(which, dir, total); delta / size", ...SH(659) },
    { from: "shade", to: "de", kind: "call", label: "the normal in the frame", tick: "calc_nf or calc_normal(which, v, …)", ...SH(445) },
    { from: "shade", to: "shade", kind: "call", label: "n_world = world_dir(which, n) for shadow, scatter, modes 14/15", ...SH(702) },
    { from: "shade", to: "frag", kind: "data", label: "COLOR, fogged, faded past the view distance", ...SH(781) },
  ],
  fragments: [
    { type: "loop", rows: [4, 12], cols: [0, 3], guard1: "each step, until a hit or t_exit" },
    { type: "loop", rows: [5, 9], cols: [1, 3], guard1: "for each shape i < shape_count" },
  ],
};

// ================================================================== 4. float32 at scale, live
// The two ways to form the sample point of a shape of size s whose centre is `dist` from the
// origin, rounded where float32 would round:
//   world: p = fround(fround(eye) + fround(dir·t)); q = fround(fround(p − pos) / s)     (what NOT to do)
//   frame: le = fround((eye − pos) / s) [64-bit, rounded once]; q = fround(le + fround(t / s))  (local_offset_point)
// The exact answer is (eye − pos + t)/s in doubles. The eye sits 7 s before the shape along +x (the
// Add shape framing), so t runs over the cube, 5 s … 9 s. Error is in LOCAL units (the shape is
// about 2 across), against the hit threshold precision · t / s = 1.75e-4 … 2.25e-4 local.
const fr = Math.fround;
function sampleErrors(s, dist, n = 400) {
  const pos = dist, eye = dist - 7 * s;
  const le = fr((eye - pos) / s);
  let worldMax = 0, frameMax = 0;
  for (let k = 0; k < n; k++) {
    const t = 5 * s + 4 * s * k / (n - 1);
    const exact = (eye - pos + t) / s;
    const p = fr(fr(eye) + fr(t));
    const qWorld = fr(fr(p - fr(pos)) / fr(s));
    const qFrame = fr(le + fr(t / fr(s)));
    worldMax = Math.max(worldMax, Math.abs(qWorld - exact));
    frameMax = Math.max(frameMax, Math.abs(qFrame - exact));
  }
  return { worldMax, frameMax, eps: 2.5e-5 * 7 };   // hit_eps at the shape, in local units
}
const precFig = {
  type: "figure",
  tab: "Float32 at scale",
  title: "Why the sample point is formed in the shape's frame",
  note: "A port of the two formulas, rounded through Math.fround exactly where the GPU's float32 would round. Drag the distance of the shape from the origin; the curves are the largest error of the sample point over the cube, in the shape's own units, for every size from 1 down to 1e-7. The dashed line is the hit threshold in the same units (precision · t / size ≈ 1.75e-4): above it the surface jitters by more than the march resolves, and the picture breaks up.",
  w: 1040, h: 560,
  draw(api) {
    const { el, text, hue } = api;
    const L = 90, T = 70, PW = 900, PH = 330;
    const sizes = []; for (let e = 0; e >= -7; e -= 0.125) sizes.push(Math.pow(10, e));
    const xOf = s => L + (0 - Math.log10(s)) / 7 * PW;
    const eMin = -9, eMax = 1;
    const yOf = err => T + PH - (Math.log10(Math.max(err, 1e-9)) - eMin) / (eMax - eMin) * PH;
    el("rect", { x: L, y: T, width: PW, height: PH, fill: "none", class: "axis" });
    for (let e = 0; e >= -7; e--) {
      const x = xOf(Math.pow(10, e));
      el("line", { x1: x, y1: T, x2: x, y2: T + PH, class: "grid" });
      text(x, T + PH + 18, e === 0 ? "size 1" : `1e${e}`, "muted mono", { "text-anchor": "middle" });
    }
    for (let e = eMin; e <= eMax; e += 2) {
      const y = yOf(Math.pow(10, e));
      el("line", { x1: L, y1: y, x2: L + PW, y2: y, class: "grid" });
      text(L - 8, y + 4, `1e${e}`, "muted mono", { "text-anchor": "end" });
    }
    text(L + PW / 2, T + PH + 40, "shape size (world units per local unit, log)", "muted", { "text-anchor": "middle" });
    text(L - 70, T - 14, "error of the sample point, local units (log)", "muted");
    const epsY = yOf(2.5e-5 * 7);
    const epsLine = el("line", { x1: L, y1: epsY, x2: L + PW, y2: epsY, style: `stroke:${hue(4)};stroke-width:1.5;stroke-dasharray:6 5` });
    text(L + PW - 4, epsY - 6, "hit threshold precision · t / size", "mono", { "text-anchor": "end", style: `fill:${hue(4)}` });
    const worldPath = el("path", { fill: "none", style: `stroke:${hue(2)};stroke-width:2.4` });
    const framePath = el("path", { fill: "none", style: `stroke:${hue(3)};stroke-width:2.4` });
    const marker = el("line", { style: `stroke:${hue(2)};stroke-width:1;stroke-dasharray:3 3` });
    const legendY = T + PH + 70;
    el("line", { x1: L, y1: legendY, x2: L + 40, y2: legendY, style: `stroke:${hue(2)};stroke-width:2.4` });
    text(L + 48, legendY + 4, "world space: fround(eye + dir·t) − pos, then / size — the formula the shader does NOT use", "ink");
    el("line", { x1: L, y1: legendY + 24, x2: L + 40, y2: legendY + 24, style: `stroke:${hue(3)};stroke-width:2.4` });
    text(L + 48, legendY + 28, "the shape's frame: local_eye (64-bit, rounded once) + Rᵀdir · t / size — what local_offset_point does", "ink");
    const readout = text(L + 48, legendY + 52, "", "mono");
    let dist = 5;
    function redraw() {
      let dw = "", df = "", breakAt = null;
      for (const s of sizes) {
        const r = sampleErrors(s, dist);
        const x = xOf(s);
        dw += `${dw ? "L" : "M"} ${x.toFixed(1)} ${yOf(r.worldMax).toFixed(1)} `;
        df += `${df ? "L" : "M"} ${x.toFixed(1)} ${yOf(r.frameMax).toFixed(1)} `;
        if (breakAt === null && r.worldMax > r.eps) breakAt = s;
      }
      worldPath.setAttribute("d", dw);
      framePath.setAttribute("d", df);
      const r3 = sampleErrors(1e-3, dist), r4 = sampleErrors(1e-4, dist);
      if (breakAt !== null) {
        marker.setAttribute("x1", xOf(breakAt)); marker.setAttribute("x2", xOf(breakAt));
        marker.setAttribute("y1", T); marker.setAttribute("y2", T + PH);
        marker.style.display = "";
      } else marker.style.display = "none";
      readout.textContent = `at |pos| = ${dist.toFixed(2)}: a 1e-3 shape errs ${r3.worldMax.toExponential(1)} (world) vs ${r3.frameMax.toExponential(1)} (frame); 1e-4: ${r4.worldMax.toExponential(1)} vs ${r4.frameMax.toExponential(1)}`
        + (breakAt !== null ? ` — world-space breaks below size ${breakAt.toExponential(1)}` : "");
    }
    api.slider({ x: L + PW - 300, y: T - 36, w: 300, label: "distance of the shape from the origin |pos|", min: 0.25, max: 10, step: 0.25, value: dist,
      fmt: v => v.toFixed(2), onChange: v => { dist = v; redraw(); } });
    redraw();
    api.tip(worldPath, { title: "world-space sampling", sub: "fround(fround(eye) + fround(t)) − pos, / size",
      blurb: "Two numbers of size |pos| are subtracted to get a number of size `size`: the absolute error stays about 1e-7·|pos| whatever the shape's size, so the RELATIVE error grows as 1/size. This is the artefact the brief expected from vastly different scales.", ...SH(212) });
    api.tip(framePath, { title: "frame sampling (local_offset_point)", sub: "fround(local_eye) + fround(t / size)",
      blurb: "The subtraction happened on the CPU in 64-bit (ShapeParams.to_local); the shader adds two O(1) numbers. The error is a few float32 ulps of a number near 1, about 1e-7, at every size.", ...R("view", 519), links: [RL("shape", 385, "to_local"), SH(212)] });
    api.tip(epsLine, { title: "the hit threshold, in local units", sub: "precision · t / size with t ≈ 7 size",
      blurb: "The march stops when the distance estimate drops below precision · t. With the eye 7 sizes from the shape, that is 1.75e-4 of the shape whatever its size — the floor the error has to stay under.", ...SH(172) });
  },
};

// ================================================================== 5. tables
const budget = {
  type: "table",
  tab: "Precision budget",
  title: "Where float32 bites, and what was done about each",
  note: "Every quantity that crosses into the shader or a Vector3, with its resolution at the scales the demo nest uses (|p| ≈ 1.5, sizes 1, 0.04, 0.0016). 'ulp' is the spacing of float32 at that magnitude: about 1.2e-7 × the value.",
  columns: [{ label: "quantity", w: 230 }, { label: "where it lives", w: 250, mono: true }, { label: "float32 would give", w: 260 }, { label: "what happens instead", w: 440 }],
  rows: [
    { cells: ["the camera eye", "CameraState._ex/_ey/_ez (64-bit); transform.origin mirrors it", "ulp 1.8e-7 at |p| = 1.5: a 1.4e-5 frame step inside the inner shape is 80 ulps, jittery; a 1e-5 shape would not move at all", "FlyCamera.move_by accumulates in 64-bit; the mirror is for projection only; a save keeps 15 digits"],
      tip: { title: "the 64-bit eye", ...R("cam", 64), links: [RL("fly", 88, "move_by"), RL("ws", 66, "15 digits"), RL("tCam", 43, "the test")] } },
    { cells: ["eye in a shape's frame", "ShapeParams.to_local → local_eye[i] (vec3)", "eye − pos cancels: 1.8e-7 absolute, which is 1e-4 of a 0.0016 shape before the march even starts", "computed in 64-bit scalars, rounded once to a vec3 of O(1) local units: a few 1e-7 of the shape"],
      tip: { title: "local_eye", ...R("view", 519), links: [RL("shape", 385, "to_local"), RL("tDE", 195, "1e-9 at |p| = 4 resolves")] } },
    { cells: ["the sample point", "local_offset_point(i, off) in the shader", "eye + dir·t − pos: the same cancellation at every step (the orange curve)", "local_eye + Rᵀoff/size: a sum of O(1) numbers (the green curve)"],
      tip: { title: "local_offset_point", ...SH(212) } },
    { cells: ["the ray parameter t", "float total, world units", "resolution 6e-8·t; the hit needs precision·t = 2.5e-5·t: a thousandfold margin", "left as float32; a floating origin per shape is the next step if anyone needs shapes below 1e-5"],
      tip: { title: "t stays float32", ...SH(613) } },
    { cells: ["the frame's axes", "frame_x/y/z[i] (vec3), from Rz·Ry·Rx in 64-bit", "a unit vector rounded to 1e-7: harmless, it multiplies O(1) numbers", "pushed as Vector3; the CPU keeps the 64-bit matrix for to_local"],
      tip: { title: "frame()", ...R("shape", 358) } },
    { cells: ["near_dist, the coarse pass, the speed", "DistanceEstimator.nearest_at at the 64-bit eye; ShapeParams.coarse_iters(near / size)", "n/a (CPU)", "64-bit throughout; floored at 1e-6 for the LOD range and the speed; each shape's coarse count is taken at its own scale"],
      tip: { title: "nearest_at", ...R("de", 48), links: [RL("fly", 156, "the speed floor"), RL("params", 245, "NEAR_FLOOR"), RL("view", 523, "coarse_iters per shape")] } },
    { cells: ["the zoom floor", "ShapeParams.zoom_floor: ulp32(|local eye|) × size / (50 · precision)", "one floor for the scene would stop the camera 1e-4 short of a 0.0016 shape: outside it", "the nearest shape's floor, in its own units: about 1e-4 × its size"],
      tip: { title: "zoom_floor", ...R("shape", 347), links: [RL("params", 360, "zoom_floor_at"), RL("tParams", 284, "a thousandth the size, a thousandth the floor")] } },
    { cells: ["the Julia marker", "FractalView.project(to_world(c)) on Vector3", "the ring's pixel is off by ~1e-7·|p| / (t · tan) — sub-pixel", "left in float32: a drag handle, not the march"],
      tip: { title: "the marker", ...R("marker", 42) } },
    { cells: ["a typed position", "SpinBox step 1e-6 (position), 1e-9 (size)", "n/a (the box snaps to its step)", "fine steps so a nested position can be typed; code-set values are never snapped"],
      tip: { title: "the placement specs", ...R("cat", 101) } },
    { cells: ["the saved eye", "Workspace._tidy(x, 15)", "7 digits (the old tidy) is 1e-6 at |p| ≈ 5: the inner pocket's camera would land on the wall", "15 significant digits for the eye; the unit vectors keep 7"],
      tip: { title: "_tidy", ...R("ws", 370) } },
  ],
};
const saveTable = {
  type: "table",
  tab: "The save, version 4",
  title: "saves/*.json, version 4, and how older files get there",
  columns: [{ label: "key", w: 160, mono: true }, { label: "holds", w: 520 }, { label: "from a version-3 file", w: 300 }, { label: "from a version-1 or -2 file", w: 260 }],
  rows: [
    { cells: ["version", "4", "3 → split silently", "1 → 3 → 4, 2 → 4, silently"], tip: { title: "load_file", ...R("ws", 176) } },
    { cells: ["shapes", "a list, outer to inner by convention: {label, defaults (every per-shape id), bindings (active only)}", "the one 'shape' table's per-shape ids become a one-entry list labelled Shape 1 at the identity placement (the placement ids keep their defaults)", "v1's flat 'fractal' keys are mapped to ids first (scale→box_scale, …); v2 is a v3 with a dict of axes"],
      tip: { title: "shapes", ...R("ws", 60), links: [RL("ws", 238, "_split_shape"), RL("ws", 292, "_migrate_v1"), RL("list", 119, "ShapeList.to_dict")] } },
    { cells: ["active", "the console's selected shape (the marker's, Add shape's)", "0", "0"], tip: { title: "active", ...R("ws", 61) } },
    { cells: ["look", "the scene's light, colour, material and palette: {defaults, bindings}", "the 'shape' table's look ids (light_shininess → roughness on the way)", "the same, from what was there"],
      tip: { title: "look", ...R("ws", 62), links: [RL("ws", 114, "look.apply_dict"), RL("ws", 273, "_migrate_shininess")] } },
    { cells: ["axes", "the keymap: axes, labels, speeds, keys, values", "as is", "v2: a dict of values onto the axes in hand; v1: none"], tip: { title: "axes", ...R("ws", 63) } },
    { cells: ["fractal", "fast_controls, camera_mode, mouse_sensitivity, detail, detail_range, detail_falloff, max_steps, min_render_scale", "as is", "the preference keys that were there"], tip: { title: "fractal", ...R("ws", 64) } },
    { cells: ["camera", "eye (15 digits), forward, up, speed_factor; the eye is restored through set_eye (64-bit)", "as is", "as is"], tip: { title: "camera", ...R("ws", 354) } },
    { cells: ["noise", "the noise graph, when wired (additive)", "as is", "as is"], tip: { title: "noise", ...R("ws", 73) } },
    { cells: ["(malformed)", "a non-list 'shapes', a non-dict entry, an empty list, an unknown id or a non-dict 'look': one warning each; the list keeps one default shape at worst", "—", "—"], tip: { title: "apply_dict", ...R("list", 131), links: [RL("tWs", 229, "the tests")] } },
  ],
};

VIZ.pane({
  id: "shape-nesting",
  short: "Shape nesting",
  title: "Shape nesting — a scene of placed shapes, and the calls behind it",
  subtitle: "The viewer renders a list of shapes, each a full fractal with a position, rotation and size, as one union under one light. Every shape is evaluated in its own frame so a shape a thousandth the size of its parent renders as cleanly as the parent. The 'Tough calls' tab records every decision that was not obvious, the re-port onto the grown main included.",
  commit: "e03c9bfd9a4c5f56ea78a67e3a7cfd7a6d75f808",
  ctx: {
    input: { hue: 2, label: "authoring — the console's Shape pane, the list of tables, the look, Main's resolve" },
    state: { hue: 1, label: "state — FractalParams, ShapeParams, CameraState" },
    render: { hue: 6, label: "render — FractalView's pushes, the shader" },
    camera: { hue: 3, label: "consumers — fly, orbit, the Julia marker" },
    math: { hue: 4, label: "CPU maths — DistanceEstimator, 64-bit" },
    files: { hue: 5, label: "files — Workspace v4, saves/" },
  },
  kinds: {
    call: { style: "solid", label: "calls · sets" },
    signal: { style: "dash", label: "changed signal" },
    data: { style: "dot", label: "reads a value · a uniform" },
  },
  tabs: [arch, calls, seq, precFig, budget, saveTable],
  ports: { sampleErrors },
});
})();
