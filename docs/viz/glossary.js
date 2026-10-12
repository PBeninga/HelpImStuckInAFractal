// The viz glossary: maths, geometry and graphics terms that pane prose leans on, explained for an
// engineer who is not a mathematician. viz.js colours each term's first mention in every
// tooltip blurb, subtitle, block note, card body and table cell, and hovering the coloured term shows
// the entry with its links. Panes need no markup for that; `[[id]]` or `[[id|shown text]]` in
// prose marks a mention by hand.
//
//   id: { term, body, links: [{ url, label }], match?: [...] }
//
// `match` lists what to mark: a string matches case-insensitively as a whole word (never
// inside an identifier like fold_limit or a path like mandelbox.gdshader), a RegExp matches as
// written. Without `match` the term itself is matched. Text in `backticks` is never matched.
// Keep a body short, concrete, and tied to this project where it can be. Run
// `node tools/viz/check.mjs` after editing: it validates every entry.
(function () {
const WIKI = page => ({ url: `https://en.wikipedia.org/wiki/${page}`, label: `Wikipedia: ${decodeURIComponent(page).replace(/_/g, " ").replace(/#.*/, "")}` });
const SYNTOPIA_MANDELBOX = { url: "http://blog.hvidtfeldts.net/index.php/2011/11/distance-estimated-3d-fractals-vi-the-mandelbox/",
  label: "Syntopia: Distance Estimated 3D Fractals VI, the Mandelbox" };
const LEARNOPENGL_COORDS = { url: "https://learnopengl.com/Getting-started/Coordinate-Systems", label: "LearnOpenGL: Coordinate Systems" };

VIZ.glossary({
  // ---------------------------------------------------------------- the fractal
  mandelbox: {
    term: "Mandelbox",
    match: ["Mandelbox"],
    body: "A 3D fractal found by Tom Lowe in 2010. Every point p goes through the same short recipe again and again: fold space onto itself (a box fold, then a sphere fold), stretch it by box_scale, and add a constant c (p itself, or a fixed Julia constant). If the result stays small after all the repeats, p is inside the shape; if it runs off to infinity, p is outside. The surface you fly around is the border between the two. It is called a box because at the usual box_scale of about −2 its overall outline is a cube.\nThis project runs it in 4D (x, y, z, w) and draws a 3D slice.",
    links: [WIKI("Mandelbox"), SYNTOPIA_MANDELBOX],
  },
  fold: {
    term: "Fold",
    match: ["folds", "fold by fold", "folding"],
    body: "In fractal formulas a fold is a mirror. Every point on one side of a plane or sphere is reflected to the other side, so space gets folded over like paper and both halves land on top of each other. Folds are cheap to compute. Repeated many times with a stretch between them, they copy the shape into smaller and smaller versions of itself, and that is where all the fractal detail comes from. The Mandelbox uses two of them: the box fold and the sphere fold, in the order set by fold_order.",
    links: [SYNTOPIA_MANDELBOX],
  },
  "box-fold": {
    term: "Box fold",
    match: ["box fold"],
    body: "Mirrors each coordinate on its own at the walls ±fold_limit. A value past +fold_limit is reflected back inside (x becomes 2·fold_limit − x), and the same goes past −fold_limit. Values already inside don't change. Picture a box with mirror walls: anything sticking out gets flipped back in. In the shader it is one line: `clamp(p, -fold_limit, fold_limit) * 2.0 - p`. The Kleinian uses the same rule with its own half-width per axis (kleinian_box_0..3), which is what tiles space into its lattice of cells.",
    links: [SYNTOPIA_MANDELBOX, WIKI("Mandelbox")],
  },
  kifs: {
    term: "KIFS (kaleidoscopic iterated function system)",
    match: ["KIFS", "kaleidoscopic", /\bIFS\b/g],
    body: "An iterated function system (IFS) builds a shape out of smaller copies of itself: apply a few shrinking maps to the shape and take the union, over and over. A kaleidoscopic IFS (Knighty's name, 2010) does that with one recipe per iteration: fold space into one wedge with a set of mirrors (so every copy lands on the same wedge, as a kaleidoscope's mirrors do), then scale it away from a fixed offset by s. Run backwards from a point, that tells you whether the point is in the shape and how far it is from it. The folds set the symmetry: coordinate mirrors give the Menger sponge, diagonal mirrors the Sierpinski tetrahedron, an angular mirror the polyfold's k-fold stars.",
    links: [WIKI("Iterated_function_system"), { url: "http://blog.hvidtfeldts.net/index.php/2011/08/distance-estimated-3d-fractals-iii-folding-space/", label: "Syntopia: Distance Estimated 3D Fractals III, folding space" }],
  },
  menger: {
    term: "Menger sponge",
    match: ["Menger"],
    body: "The 3D cousin of the Cantor set: a cube with the middle third of each face drilled straight through, then the same done to each of the 20 remaining sub-cubes, forever. It has zero volume and infinite surface. The KIFS makes it with the coordinate fold at scale 3 and offset (1, 1, 1): each iteration maps the cube onto one of its 20 corner-and-edge sub-cubes, and the Menger correction reflects the far z layer back so the tunnels line up. The viewer's default KIFS is this sponge, with its faces at ±1.",
    links: [WIKI("Menger_sponge")],
  },
  sierpinski: {
    term: "Sierpinski tetrahedron",
    match: ["Sierpinski"],
    body: "The 3D version of the Sierpinski triangle: a tetrahedron made of four half-size copies of itself at its four corners, forever. The KIFS makes it with the diagonal fold (reflections across x = −y, x = −z, y = −z) at scale 2 and offset (1, 1, 1): the fold has the tetrahedron's symmetry, and halving is exactly the copies' size. Fractacular's version of this fold never fired, which this project fixed.",
    links: [WIKI("Sierpi%C5%84ski_triangle"), WIKI("Tetrix")],
  },
  kleinian: {
    term: "Pseudo-Kleinian limit set",
    match: ["Kleinian", "pseudo-Kleinian", "limit set"],
    body: "A Kleinian group is a collection of mirror-like transformations of space (here a box fold and a sphere inversion) applied in every combination; its limit set is the set of points those transformations keep returning to, an endless lattice of curved sheets and rings. 'Pseudo' because this is Knighty's shortcut (fragmentarium, 2011), a fold-and-invert iteration that produces the look without the group theory, and in 4D here. There is no inside and outside: the set fills space, which is why its rays need a view distance to stop at.",
    links: [WIKI("Kleinian_group"), WIKI("Limit_set"), { url: "https://fractalforums.org/fractal-mathematics-and-new-theories/28/pseudo-kleinian-fractals/", label: "Fractal Forums: pseudo-Kleinian fractals" }],
  },
  attractor: {
    term: "Attractor",
    match: ["attractor"],
    body: "The set a repeated map settles onto whatever point it starts from. For a KIFS, run the shrinking maps forward from any starting shape and after enough rounds you get the fractal: the fractal is the attractor. Because each map shrinks toward the offset, the attractor sits within |offset| of the origin, which is where the KIFS's march cube (bound_half) comes from.",
    links: [WIKI("Attractor"), WIKI("Iterated_function_system")],
  },
  polyfold: {
    term: "Polyfold (k-fold mirror symmetry)",
    match: ["polyfold", "k-fold"],
    body: "A fold on the angle rather than on a coordinate. Measure the point's angle in the xy plane, mirror it into one wedge of 2π/k (actually a half-wedge, so the fold is continuous: the angle becomes a triangle wave), and put the point back at the same radius. The result has k mirror lines through the z axis, like a kaleidoscope with k mirrors: a triangular cross-section at k = 3, a five-pointed star at 5. Fractacular rotated the angle into the wedge instead, which jumps at the wedge edges and misleads a ray march; here it mirrors.",
    links: [WIKI("Dihedral_group"), WIKI("Kaleidoscope")],
  },
  orthant: {
    term: "Orthant (the positive corner)",
    match: ["orthant", "positive corner"],
    body: "The 4D version of a quadrant: the region where every coordinate has a fixed sign. The positive orthant is where x, y, z, w are all ≥ 0. Taking |p| folds all sixteen orthants onto that one, which is the first half of the coordinate (Menger) fold; sorting x ≥ y ≥ z then folds that corner once more into a single wedge.",
    links: [WIKI("Orthant")],
  },
  bailout: {
    term: "Bailout (escape)",
    match: ["bailout", "bails out", "bailed out", "escape-time"],
    body: "An escape-time fractal iterates a point and watches whether it runs off to infinity. The bailout is the radius past which it is declared gone (here |p| > 1000, tested as |p|² > 1e6): once past it, the orbit can only grow, so the loop stops early. The number of iterations it took, n, is what the distance is scaled by (s⁻ⁿ for the KIFS). Points in the shape never bail out and run the full 32.",
    links: [WIKI("Plotting_algorithms_for_the_Mandelbrot_set#Escape_time_algorithm")],
  },
  conformal: {
    term: "Conformal (angle-preserving)",
    match: ["conformal"],
    body: "A map is conformal when, over any small enough region, it is just a uniform scale plus a rotation or mirror: shapes keep their angles, circles stay circles, only their size changes. Sphere inversion is conformal (it bends lines into circles but never squashes a small shape unevenly). That is why a Kleinian or a Mandelbox sphere fold can still count as 'magnifying a copy of itself' for self-similarity.",
    links: [WIKI("Conformal_map"), WIKI("Inversive_geometry")],
  },
  "self-similar": {
    term: "Self-similar",
    match: ["self-similar", "self-similarity"],
    body: "A shape is exactly self-similar when a magnified piece of it is the whole shape again (the Menger sponge's sub-cubes are Menger sponges). For an iterated fractal that holds when every iteration is the same fixed map that magnifies: then the structure around a point is the next iterate's structure, scaled up. The Shape tab's Self-similar line says whether the current knobs allow it (a KIFS twist or a Mandelbox scale drift makes each iteration a different map; a noise displacement is not carried along). It matters for deep zoom: a self-similar shape could be drawn from a magnified shallower region.",
    links: [WIKI("Self-similarity")],
  },
  lipschitz: {
    term: "Lipschitz bound",
    match: ["Lipschitz"],
    body: "A function is 1-Lipschitz when it never changes faster than its input: |D(a) − D(b)| ≤ |a − b|. A true distance field is, and sphere tracing is safe exactly when the estimate is (a step of D can never cross a surface). The project's estimates are not quite: the Mandelbox's exceeds 1 by a few percent and the escape-time ones jump far from the surface, harmlessly, so the march-safety test checks the real property instead: full steps never skip a surface that quarter steps find.",
    links: [WIKI("Lipschitz_continuity")],
  },
  "sphere-fold": {
    term: "Sphere fold",
    match: ["sphere fold", "min sphere"],
    body: "Works on the point's distance r from the origin, using two radii. Inside the small sphere (r < min_radius), the point is scaled up by the constant fixed_radius² / min_radius². Between the two spheres, it is inverted (see sphere inversion): moved to the radius fixed_radius² / r, so points near the inner sphere land near the outer one and the other way round. Outside fixed_radius it doesn't change. This step turns the box's flat faces into the rounded, bubbly detail. It also multiplies the running derivative dz by the same factor.",
    links: [SYNTOPIA_MANDELBOX, WIKI("Inversive_geometry")],
  },
  inversion: {
    term: "Sphere inversion",
    match: ["inversion radius", "inversion", "inverts", "inverted"],
    body: "Inversion in a sphere of radius R moves a point at distance r from the centre to distance R² / r, in the same direction. Points just inside the sphere go just outside and the other way round. The centre goes out to infinity and faraway points crowd in near the centre. Points on the sphere stay put. It is turning space inside out around a sphere, and it bends straight lines and flat planes into circles and spheres, which is why it makes round shapes. The sphere fold inverts in the sphere of radius fixed_radius.",
    links: [WIKI("Inversive_geometry")],
  },
  julia: {
    term: "Julia set (Julia mode)",
    match: ["Julia"],
    body: "There are two ways to pick the constant c in the iteration z → f(z) + c. In plain Mandelbox mode, c is the starting point itself, so every point brings its own c. In a Julia mode, c is one fixed constant (here c_0..c_3) shared by every point. Each choice of c gives a different shape, often a more intricate one, and dragging the constant morphs it smoothly. The names come from the 2D Mandelbrot set and Julia sets.\nHere each of the four components can be switched separately (julia_0..julia_3), so the two modes can be mixed into a hybrid. Julia (all) switches all four.",
    links: [WIKI("Julia_set"), WIKI("Mandelbrot_set")],
  },
  orbit: {
    term: "Iteration and orbit",
    match: ["iterations", "iteration", "orbit point", /(?<=(?:its|4D|scalar) )orbit\b/gi],
    body: "To iterate a function is to feed it its own output again and again: z₁ = f(z₀), z₂ = f(z₁), and so on. The sequence of points visited is the orbit of the starting point. (It has nothing to do with the orbit camera.) For the Mandelbox, f is 'fold, fold, maybe rotate, stretch, add c', and the full estimate runs 32 iterations. If the orbit stays near the origin, the starting point is in the shape. If it flies away, it isn't, and how fast it flies away tells you roughly how far the surface is.",
    links: [WIKI("Orbit_(dynamics)"), WIKI("Iterated_function")],
  },
  derivative: {
    term: "Running derivative dz",
    match: ["derivative", /\bdz\b/g],
    body: "Next to z, each iteration updates one extra number, dz. It measures how much the whole chain of steps so far has magnified space around the point: the derivative of the final z with respect to the starting point, built up step by step with the chain rule. A mirror (box fold) doesn't magnify, so it leaves dz alone. The sphere fold multiplies dz by its scale factor, the stretch multiplies it by |box_scale|, and adding c contributes the + 1. Here that is `dz = dz * abs(box_scale) + 1.0`.\nThe distance estimate is then |z| / |dz|: how far out the orbit got, divided by how much space was magnified on the way.",
    links: [SYNTOPIA_MANDELBOX, WIKI("Chain_rule")],
  },
  "four-d": {
    term: "4D and the fourth coordinate w",
    match: ["4D", "fourth coordinate", "four-dimensional"],
    body: "A point here has four numbers, (x, y, z, w), instead of three. There's nothing mystical about it: the formula carries one extra coordinate along, and every fold, rotation and stretch acts on all four. We can't see 4D, so the renderer shows a 3D slice of it. It fixes w at one value (the w knob) and draws the 3D shape found at that w. Changing w slides the slice through the 4D shape, like a CT scanner moving through a body, with each position showing a different 3D cross-section.\nAt w = 0 with no rotation, the fourth coordinate stays 0 through every step, so you get exactly the classic 3D Mandelbox.",
    links: [WIKI("Four-dimensional_space")],
  },
  slice: {
    term: "Slice (cross-section)",
    match: [/\b(?:3D |w |vertical )?slices?\b/gi],
    body: "The shape you see when you cut a bigger shape with something flat. Slice an apple (3D) with a knife (a 2D plane) and the cut face is a 2D cross-section. This page uses the idea twice. The renderer draws a 3D slice of the 4D shape: all of its points at the chosen w. Several figures then draw a 2D slice of that 3D shape: a flat plane through it, coloured by distance to the surface.",
    links: [WIKI("Cross_section_(geometry)")],
  },
  rotation: {
    term: "4D rotation, in six planes",
    match: ["six-plane rotation", "4D rotation", "iteration rotation", "iteration angle", "six planes"],
    body: "In 3D we usually describe a rotation as turning 'about an axis', but what actually turns is a plane: rotating about z spins the x–y plane. In 4D there's no single axis left over to turn about, so rotations are named by their planes. Four axes make six planes, one for every pair: xy, xz, xw, yz, yw, zw. Each iter_rot_* knob turns one plane by an angle, inside every iteration, one after another in that fixed order. Order matters, because rotations done in a different order land somewhere else. A plane that includes w mixes the hidden fourth coordinate into the visible three.",
    links: [WIKI("Rotations_in_4-dimensional_Euclidean_space"), WIKI("Plane_of_rotation")],
  },
  topology: {
    term: "Topology",
    match: ["topology"],
    body: "The properties of a shape that survive stretching and bending without tearing: how many pieces it has, how many holes or tunnels run through it, what connects to what. Saying box_scale sets 'the overall topology' means it changes the large-scale structure, like a solid block with holes vs a spongy lattice vs scattered dust, and not just the fine detail.",
    links: [WIKI("Topology")],
  },
  dust: {
    term: "Fractal dust (chaos near the boundary)",
    match: [/\b(?:chaotic )?dust\b/gi],
    body: "Near a fractal's boundary the shape breaks up into countless tiny disconnected specks: the dust. Points there behave chaotically, meaning a tiny change in the starting point completely changes where its orbit ends up. Neighbouring pixels can disagree and the distance estimate becomes unreliable. Rays often run out of steps there without a clean hit, which is why the renderer shades those pixels as dust (ce = 1) instead of as a hit or a miss.",
    links: [WIKI("Chaos_theory"), WIKI("Cantor_set#Cantor_dust")],
  },

  // ---------------------------------------------------------------- distance + ray marching
  de: {
    term: "Distance estimator (DE)",
    match: ["distance estimator", "distance estimate", "distance estimation", "estimator", /\bde\([^)]*\)/g],
    body: "A function that gives, for any point in space, a safe lower bound on the distance to the fractal's surface: 'nothing is closer than d'. A fractal has no simple formula for its surface, but a DE can still be computed: run the iteration and divide |z| by the running derivative |dz|. The renderer never needs the exact surface, only how far it can safely step.\nde(p, 32) means the estimate at point p after 32 iterations. Fewer iterations is cheaper but blurrier. Its exact cousin for simple shapes is the signed distance function (SDF).",
    links: [{ url: "http://blog.hvidtfeldts.net/index.php/2011/06/distance-estimated-3d-fractals-part-i/", label: "Syntopia: Distance Estimated 3D Fractals, part I" },
      WIKI("Signed_distance_function")],
  },
  "ray-march": {
    term: "Ray marching",
    match: [/\bray[- ]?march\w*/gi, /\bmarch(?:es|ed|ing)?\b/gi],
    body: "A way to draw a shape that has no triangles, only a distance estimator. For each pixel, cast a ray from the eye through that pixel and walk ('march') along it in steps. At each step, ask the DE how far the nearest surface is and step exactly that far, which can never overshoot. When the distance gets tiny (below the hit threshold), the ray has hit the surface. If it leaves the scene or runs out of steps, it hasn't.\nHere every pixel's march runs on the GPU in the fragment shader, in two phases: a cheaper DE first (16 iterations, more when the camera is very close to the surface), then the 32-iteration one.",
    links: [WIKI("Ray_marching"), { url: "https://iquilezles.org/articles/raymarchingdf/", label: "Inigo Quilez: raymarching distance fields" }],
  },
  "sphere-tracing": {
    term: "Sphere tracing (the unbounding sphere)",
    match: [/\bsphere[- ]tracing\b/gi, /\bunbounding (?:circle|sphere)s?\b/gi],
    body: "The safe-step idea behind ray marching, named by John C. Hart in 1996. If the DE says the nearest surface is d away, then a whole ball of radius d around the current point is empty (the 'unbounding sphere'). So the ray can jump d along its direction without skipping past anything. Near a surface d shrinks, so the steps shrink too, and the ray creeps up to the surface instead of passing through it. The 2D march figure draws those balls as circles.",
    links: [WIKI("Ray_marching#Sphere_tracing")],
  },
  geometric: {
    term: "Shrinking geometrically",
    match: [/\bgeometric(?:ally)?\b/gi],
    body: "Each step is roughly a fixed fraction of the one before, like 1, ½, ¼, ⅛…: a geometric sequence. The ray gets close to the surface fast but never quite touches it. That's why the march needs a hit threshold to decide 'close enough'.",
    links: [WIKI("Geometric_progression")],
  },
  "pixel-cone": {
    term: "Pixel cone and level of detail",
    match: ["pixel cone", /\bcone\b/gi, "level of detail", "level-of-detail"],
    body: "A pixel doesn't see along a thin line. It sees a narrow cone that starts at the eye and widens with distance. At distance t, one pixel covers a patch about t × (the pixel's angle) wide, so detail finer than that can't show up in it anyway. The renderer uses this as its hit threshold: a ray stops when the DE drops below precision · t, a tolerance that grows in proportion to distance. That gives level of detail for free: far surfaces are resolved coarsely and near ones finely. detail divides the threshold (sharper), and detail_falloff makes it grow faster than linearly past detail_range · near_dist.",
    links: [WIKI("Level_of_detail_(computer_graphics)"), WIKI("Cone_tracing")],
  },

  ulp: {
    term: "ulp and the 32-bit grid",
    match: [/\bulp32\b/g, /\bulp\b/g, "32-bit grid", "float grid"],
    body: "'Unit in the last place': the gap between a floating-point number and the next one up. A 32-bit float keeps 24 significant bits, so near x the representable values sit on a grid 2^(floor(log2 x) − 23) apart: about 1.2e−7 for x between 1 and 2, twice that between 2 and 4. Anything the shader computes for a ray position snaps to that grid. When the hit threshold gets much finer than the grid, a ray can no longer land close enough to the surface to stop, which is why the fly camera has a zoom floor.",
    links: [WIKI("Unit_in_the_last_place"), WIKI("Single-precision_floating-point_format")],
  },

  // ---------------------------------------------------------------- deep zoom: perturbation
  perturbation: {
    term: "Perturbation (deep-zoom perturbation theory)",
    match: ["perturbation theory", "perturbation", "perturbed"],
    body: "Rather than computing a hard thing directly, compute one nearby thing exactly and then track only the small difference from it. Deep Mandelbrot-set zoomers work this way. One reference point's orbit is computed once in high precision on the CPU, and every pixel iterates only its tiny offset δ from that orbit in ordinary floats, because a small number keeps as many significant digits as a large one. Here the reference is the camera's eye, run in 64-bit once per frame. The GPU iterates each pixel's δ for the first k iterations, then hands off to the normal loop. The hard part is writing each fold's difference so that it never subtracts two nearly equal numbers.",
    links: [WIKI("Plotting_algorithms_for_the_Mandelbrot_set#Perturbation_theory_and_series_approximation"),
      { url: "https://mathr.co.uk/blog/2021-05-14_deep_zoom_theory_and_practice.html", label: "mathr: Deep zoom theory and practice" }],
  },
  "reference-orbit": {
    term: "Reference orbit",
    match: ["reference orbit", "reference orbits"],
    body: "The orbit of one chosen point (its iterates X_0, X_1, … X_32), computed in high precision, that every pixel's orbit is measured against. Here it is the eye's orbit: X_0 is the 64-bit eye, X_1 its first Mandelbox iterate, and so on, recomputed on the CPU whenever the camera moves (ReferenceOrbit.build). Alongside the points it records, per iteration, the gap from X to each fold's crease. With those gaps the GPU can tell which side of a crease each pixel falls on without ever holding X at full precision.",
    links: [WIKI("Plotting_algorithms_for_the_Mandelbrot_set#Perturbation_theory_and_series_approximation"),
      { url: "https://mathr.co.uk/blog/2021-05-14_deep_zoom_theory_and_practice.html", label: "mathr: Deep zoom theory and practice" }],
  },
  cancellation: {
    term: "Catastrophic cancellation",
    match: ["catastrophic cancellation", "cancellation", /\bnearly equal\b/gi],
    body: "What goes wrong when you subtract two nearly equal floating-point numbers: the leading digits cancel and only the rounded tail is left. A 32-bit float keeps about 7 significant digits whatever its size, so 1.0000001 − 1.0000000 gives 1.19e-7 against the true 1e-7: about one correct digit. That is why `eye + dir × t` fails at depth: the small offset is rounded away before the fractal maths starts, and P − X can't bring it back. Perturbation's formulas only ever subtract small numbers (gaps the CPU already computed in 64-bit), or use products, never the difference of two big ones.",
    links: [WIKI("Catastrophic_cancellation"), { url: "https://floating-point-gui.de/", label: "The Floating-Point Guide" }],
  },
  magnification: {
    term: "Magnification λ",
    match: ["magnification", /λ(?:_\w+)?/g],
    body: "How much the first i iterations stretch a tiny neighbourhood of the reference point: λ_i. Each iteration multiplies it by |box_scale| (2.09 by default), and by the sphere fold's factor when that fires (up to fixed² / min², about 2.04). So it grows exponentially: about 2.5 million after 20 iterations on the default view's centre ray. It is the shader's running derivative dz without the + 1s. It matters twice. A pixel's offset δ grows by λ_i, so after k iterations it is big enough for float32. And λ_32 sets how fine 32 iterations can resolve the surface.",
    links: [WIKI("Lyapunov_exponent"), SYNTOPIA_MANDELBOX],
  },
  "piecewise-linear": {
    term: "Piecewise-linear map",
    match: ["piecewise-linear", "piecewise linear"],
    body: "A function made of straight-line pieces joined at creases, like |x| or clamp(x, −1, 1). On each side of a crease it is linear (a scale, a shift, a mirror), and the rule switches where you cross one. The box fold, the KIFS abs and sort folds and the Kleinian's box fold are all piecewise-linear. That makes the difference between two points' images exact and cheap: it is the same linear piece applied to δ, unless the two points sit on different pieces (the case table on the Crossing a fold tab). The Mandelbulb's power map is curved everywhere, which is why the design leaves it out.",
    links: [WIKI("Piecewise_linear_function")],
  },
  "double-float": {
    term: "Double-float (two-float) arithmetic",
    match: ["two-float", "double-float", "double-double", "paired-float"],
    body: "Storing one number as the unevaluated sum of two floats, a big part plus a small correction (hi + lo). A pair of 32-bit floats then carries about 48 significant bits instead of 24. Each add or multiply becomes a dozen or so float operations that capture the rounding error exactly (the error-free transformations TwoSum and TwoProduct). That only works if the compiler computes each step exactly as written. A GPU compiler that fuses a multiply and an add, or reorders them, silently breaks it. It was the research note's alternative to perturbation: exact, but about 7× the cost per ray.",
    links: [WIKI("Quadruple-precision_floating-point_format#Double-double_arithmetic"), WIKI("2Sum")],
  },
  regime: {
    term: "Regime (of a radial fold)",
    match: ["regimes", "regime"],
    body: "Which of its three rules a radial fold applies to a point, decided by the point's distance r from the centre. For the sphere fold: inside (r < min_radius) every point is scaled by the same constant fixed² / min². In the shell (min_radius ≤ r < fixed_radius) the point is inverted, scaled by fixed² / r². Outside (r ≥ fixed_radius) nothing happens. When the reference X and the pixel P are in different regimes, their factors m and m' come from different rules. The spec writes m' − m separately for each pair, so it stays a small, precise number.",
    links: [SYNTOPIA_MANDELBOX, WIKI("Inversive_geometry")],
  },

  // ---------------------------------------------------------------- normals + fields
  normal: {
    term: "Surface normal",
    match: [/\bnormals?\b/gi],
    body: "The direction pointing straight out of a surface at a point, perpendicular to it, usually stored as a vector of length 1. Lighting depends on it: a patch whose normal points at the light is bright, and one turned away is dark. A fractal has no formula for its normal, so it is measured from the DE: the direction in which the distance grows fastest, which is its gradient.",
    links: [WIKI("Normal_(geometry)"), { url: "https://iquilezles.org/articles/normalsSDF/", label: "Inigo Quilez: normals for an SDF" }],
  },
  gradient: {
    term: "Gradient (∇)",
    match: ["gradient", "∇F"],
    body: "For a function of several variables, like a distance field F(x, y, z), the gradient ∇F ('nabla F') is the vector of its partial derivatives (∂F/∂x, ∂F/∂y, ∂F/∂z): how fast F changes along each axis. It points the way F increases fastest. For a distance field, that's straight away from the nearest surface, so the normalized gradient of the DE serves as the surface normal.",
    links: [WIKI("Gradient")],
  },
  "central-diff": {
    term: "Central differences",
    match: ["central differences", "central difference"],
    body: "Estimating a derivative numerically when all you can do is evaluate the function: sample it a small step δ either side and take (F(x + δ) − F(x − δ)) / 2δ. Doing that along x, y and z gives the gradient, and so the normal. The step size matters. Too big blurs fine detail, and too small drowns in floating-point noise. Here δ = hit_eps(total) · 40, so it scales with the pixel's footprint on the surface.",
    links: [WIKI("Finite_difference"), { url: "https://iquilezles.org/articles/normalsSDF/", label: "Inigo Quilez: normals for an SDF" }],
  },
  field: {
    term: "Scalar field",
    match: ["scalar field", "distance field", /(?<=different )field\b/gi],
    body: "A function that gives one number for every point in space, like the temperature at each spot in a room. The DE is one: the distance to the surface at each point. The Ice Fractal normal NF is computed from a different one, F(q) = |z16| − 8: how far the orbit got after 16 iterations, minus 8. That is roughly positive outside the shape and negative inside, but it is not a true distance.",
    links: [WIKI("Scalar_field")],
  },
  "first-order": {
    term: "To first order",
    match: ["to first order", "first-order", "first order"],
    body: "Keeping only the straight-line part of a Taylor expansion and ignoring the much smaller squared and higher terms: F(x + δ) ≈ F(x) + ∇F · δ for a small step δ. It is the standard way to say 'approximately, for small steps'. The NF formula here is that approximation of what the shader's differences actually compute.",
    links: [WIKI("Linear_approximation"), WIKI("Taylor%27s_theorem")],
  },

  // ---------------------------------------------------------------- shading + colour
  lighting: {
    term: "Ambient, diffuse, specular, shininess",
    match: ["ambient", "diffuse", "specular", "shininess"],
    body: "The classic recipe for faking light, from Phong's 1975 model. Start with l, how squarely the surface faces the light: the cosine of the angle between the normal and the light direction (here l = |dot(n, ldir)|), 1 face-on and 0 edge-on. Diffuse is matte brightness that follows l. Specular is the shiny highlight: l raised to a high power (the shininess) stays near 0 everywhere except where l is almost exactly 1, so a bigger exponent gives a smaller, sharper glint. Ambient is a constant floor, so nothing goes pitch black. Here lgt = diffuse·l + specular·l^shininess + ambient, defaulting to the site's 0.5, 1, 160, 0.1.",
    links: [WIKI("Phong_reflection_model"), WIKI("Lambertian_reflectance")],
  },
  "cosine-palette": {
    term: "Cosine palette",
    match: ["cosine palette"],
    body: "A way to get a smooth, endlessly repeating colour gradient from twelve numbers. Each colour channel (r, g, b) follows its own cosine wave as t goes from 0 to 1: palette(t) = A + B·cos(2π(C·t + D)). A sets the channel's average brightness, B how far it swings, C how many times it cycles, and D shifts the wave along, which is what makes the three channels peak at different t and so gives different hues. Popularised by Inigo Quilez. Here t is the step count, the radius or the facing direction, wrapped into 0..1 by fract.",
    links: [{ url: "https://iquilezles.org/articles/palettes/", label: "Inigo Quilez: palettes" }],
  },
  fract: {
    term: "fract (wrapping into 0..1)",
    match: [/\bfract(?=\()/g],
    body: "fract(x) = x − floor(x): the part after the decimal point, so 2.3 becomes 0.3 and −0.25 becomes 0.75. Applied to a growing input, it makes a sawtooth that climbs from 0 to 1 and jumps back, so anything indexed by it (like the palette) repeats. Multiplying the input by a frequency first makes it repeat more often, and adding an offset slides where it starts.",
    links: [WIKI("Fractional_part")],
  },
  luma: {
    term: "Luma and saturation",
    match: ["luma", "saturation"],
    body: "Luma is a colour's brightness as the eye sees it, a weighted sum that counts green most and blue least. Rec. 601 uses 0.299·r + 0.587·g + 0.114·b. Saturation here blends the colour with its own luma: 0 gives pure grey (luma in every channel), 1 leaves the colour as it is, and above 1 pushes it further from grey, which makes it more vivid.",
    links: [WIKI("Luma_(video)"), WIKI("Colorfulness#Saturation")],
  },

  // ---------------------------------------------------------------- vectors + cameras
  basis: {
    term: "Basis (camera axes)",
    match: [/\bbasis\b/gi],
    body: "Three perpendicular unit vectors that set up a local frame of directions. For a camera they are right, up and forward (in Godot, forward = −basis.z). Any direction can be written as 'some right + some up + some forward', and that is how each pixel's ray is built: forward + ndc.x·aspect·tan_half_fov·right + ndc.y·tan_half_fov·up. Turning the camera means rotating all three vectors together.",
    links: [WIKI("Basis_(linear_algebra)"), { url: "https://docs.godotengine.org/en/stable/tutorials/3d/using_transforms.html", label: "Godot docs: Using 3D transforms" }],
  },
  "yaw-pitch-roll": {
    term: "Yaw, pitch and roll",
    match: ["yaw", "pitch", "roll"],
    body: "The three ways to turn a camera, borrowed from aircraft. Yaw turns left and right (here about world +Z, which is up). Pitch tilts up and down (about the camera's own right vector). Roll tips the horizon sideways (about forward). These cameras never roll. Pitch stops just short of straight up or down (1° off ±Z) because at exactly vertical, 'which way is left?' has no answer and yaw becomes undefined. That trap is known as gimbal lock.",
    links: [WIKI("Aircraft_principal_axes"), WIKI("Gimbal_lock")],
  },
  fov: {
    term: "Field of view",
    match: ["field of view", /(?<![\w_])fov\b/gi],
    body: "How wide an angle the camera sees: here 40° from the bottom of the screen to the top. The ray through the top edge leaves 20° above forward, so its slope is tan 20° ≈ 0.364 (tan_half_fov). The horizontal angle follows from the screen's aspect ratio. A larger field of view is a wider-angle lens.",
    links: [WIKI("Field_of_view_in_video_games")],
  },
  ndc: {
    term: "NDC (normalized device coordinates)",
    match: [/\bndc\b/gi],
    body: "A pixel's position rescaled so the screen runs from −1 to +1 across and up, whatever its size in pixels, with (0, 0) at the centre. That makes ray building independent of resolution: ndc times the field-of-view slope (and the aspect ratio, for x) says how far right or up of forward the pixel's ray tilts.",
    links: [LEARNOPENGL_COORDS],
  },
  "view-space": {
    term: "View space",
    match: ["view space", "camera space"],
    body: "Coordinates measured from the camera instead of the world: x along the camera's right, y along its up, z toward the viewer. Converting a world direction into view space takes three dot products with the camera's basis vectors. Here nv = (dot(N, right), dot(N, up), dot(N, −forward)), so nv.z > 0 means the surface faces the camera.",
    links: [LEARNOPENGL_COORDS],
  },
  project: {
    term: "Project and unproject",
    match: ["unproject", /\bproject(?= *(?:\(|\/|and unproject))/g, "camera depth", "re-projected"],
    body: "Project: take a 3D point and find the pixel it appears at, with the same perspective maths the rays use (divide by the depth along forward, then scale by the field of view). Unproject: the reverse, from a pixel plus a chosen depth back to a 3D point. A pixel on its own stands for a whole ray of possible points, so unproject needs that depth. The Julia ring uses project to draw itself over the point, and unproject(mouse, depth) to move the point under the mouse while keeping it the same distance in front of the camera.",
    links: [WIKI("3D_projection#Perspective_projection")],
  },
  dot: {
    term: "Dot product",
    match: ["dot product", /\bdot(?=\()/g],
    body: "dot(a, b) = a.x·b.x + a.y·b.y + a.z·b.z. For two unit vectors it is the cosine of the angle between them: 1 for the same direction, 0 for perpendicular, −1 for opposite. With one unit vector, it is how far the other one reaches along that direction. dot(h, h) is the squared length of h.",
    links: [WIKI("Dot_product")],
  },
  normalize: {
    term: "Normalize",
    match: [/\bnormali[sz](?:e|ed|es|ing)\b/gi],
    body: "Scale a vector to length 1 while keeping its direction: v / |v|. Directions like normals, camera axes and ray directions are kept at unit length so dot products come out as cosines, and so speed doesn't depend on how a direction was put together. That's why holding two movement keys doesn't make you fly diagonally faster.",
    links: [WIKI("Unit_vector")],
  },
  degenerate: {
    term: "Degenerate",
    match: ["degenerate"],
    body: "A case where the maths collapses and stops making sense. Here it means an orientation whose forward or up vector is zero, or whose forward and up point the same way, so no right vector can be built from them (their cross product is zero). Such a camera has no defined left and right, so it is rejected.",
    links: [WIKI("Degeneracy_(mathematics)")],
  },

  // ---------------------------------------------------------------- control + smoothing
  smoothstep: {
    term: "smoothstep",
    match: ["smoothstep"],
    body: "A ramp from 0 to 1 with soft ends. smoothstep(a, b, x) is 0 below a and 1 above b; in between it takes the straight ramp s = (x − a)/(b − a) and bends it into s²·(3 − 2s), an S-curve whose slope is zero at both ends, so a blend driven by it starts and finishes without a visible kink. GLSL and GDScript both have it built in. The shader uses it to fade fog in and to crossfade the Ice Fractal normal into the true one between near_dist 2 and 0.1.",
    links: [WIKI("Smoothstep")],
  },
  ema: {
    term: "EMA (exponential moving average)",
    match: [/\bEMA\b/g, "exponential moving average"],
    body: "A running average that keeps no history: avg ← avg + α·(new − avg). Each new frame time pulls the average a fraction α (here 0.2) of the way toward it, so recent frames count most and older ones fade out exponentially. It smooths over a single slow frame, so the governor doesn't overreact.",
    links: [WIKI("Exponential_smoothing")],
  },
  hysteresis: {
    term: "Hysteresis (why the shedder is sticky)",
    match: ["sticky", /\bflap\b/gi],
    body: "Using different thresholds and waits for going up than for coming back down, so a system sitting near a boundary doesn't flip back and forth ('flap') every frame. The shedder sheds below 24 fps but only restores above 40 fps, and it waits longer to restore (2 s) than to shed (0.5 s). A shed soon after a restore doubles the next wait. A thermostat works the same way: it heats to 21° but only switches back on at 19°.",
    links: [WIKI("Hysteresis")],
  },
});
})();
