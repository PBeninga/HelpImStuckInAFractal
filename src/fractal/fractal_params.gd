class_name FractalParams
extends Resource
## Every value the renderer, cameras and governor read: the list of shapes in
## the scene (each a ShapeParams of resolved shape knobs and placement, written
## once per frame from its AttributeTable by Main), the scene's LOOK (the
## RESOLVED colour, light and material knobs, named by catalogue id and written
## once per frame by apply_resolved() from the look table) and the preference
## and renderer fields (fast_controls, camera_mode, mouse_sensitivity, the level
## of detail, step and iteration budgets and minimum render scale), edited directly.
## Setters emit Resource's built-in `changed`; apply_resolved batches a frame's
## writes into at most one emit, and any shape's `changed` is relayed as this
## resource's, so one signal still means "re-render". Shape and look defaults
## favor performance, with coarse precision and unlit Grayscale
## (the level-of-detail defaults reproduce its plain pixel cone). A new
## FractalParams holds one default shape at the identity placement, which is
## exactly the single-shape viewer.

enum CameraMode { FLY, ORBIT }
## Which fractal de() draws: the `shape` catalogue row.
enum Shape { MANDELBOX, KIFS, KLEINIAN, MANDELBULB }

var gameplay := GameplaySettings.new()

## Colour-mode ids in the dropdown's order (ids match the site).
## Palette (20) is this project's own, past the site's range.
const COLOR_MODE_IDS: Array[int] = [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14, 20]
const COLOR_MODE_NAMES: Array[String] = [
	"Grayscale", "Ice Fractal", "Borg", "Rainbow", "Rainbow 2", "Rainbow 3",
	"Rainbow Metal", "Blue", "Blue 2", "Pink-Blue", "Ice Box", "Ice Box 2", "Gold",
	"Palette",
]

## The resolved LOOK fields (the scene-wide colour, light and material knobs),
## in catalogue order (ShapeCatalogue.scene_ids()). apply_resolved writes these;
## the per-shape fields are ShapeParams.RESOLVED_KEYS.
const RESOLVED_KEYS: Array[StringName] = [
	&"color_mode",
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_color", &"light_yaw", &"light_pitch", &"light_size", &"light_ambient",
	&"light_diffuse", &"shadows", &"fog_distance", &"fog_start", &"fog_tint",
	&"scatter_density", &"scatter_glow", &"scatter_brightness",
	&"exposure", &"saturation", &"surface_color", &"roughness", &"light_specular",
	&"texture_strength", &"bump_strength", &"palette_a_r", &"palette_a_g", &"palette_a_b",
	&"palette_b_r", &"palette_b_g", &"palette_b_b", &"palette_c_r", &"palette_c_g",
	&"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]

## The most shapes a scene holds: the shader's uniform arrays are this long.
const MAX_SHAPES := 8

## The shapes, outermost first by convention (the order only affects which
## shape's distance is tried first per march step). Never empty.
var shapes: Array[ShapeParams] = []

## Gameplay selection, independent of the inspector's `active` selection.
## -1 preserves the union for standalone editor/test resources without a run.
var gameplay_active := -1
## Gameplay threshold; never used to clip geometry.
var next_level_threshold := ShapeList.DEFAULT_NEXT_LEVEL_DISTANCE
## Rendering-only clipping radius, independent of stage objectives.
var render_escape_radius := 20.0
var run_origin: Array = [0.0, 0.0, 0.0]
var run_escaped := false

func visible_shape_indices() -> Array:
	return [clampi(gameplay_active, 0, shapes.size() - 1)] if gameplay_active >= 0 else range(shapes.size())

func render_escape_origin() -> Array:
	return run_origin if gameplay_active >= 0 else [0.0, 0.0, 0.0]

func is_escaped(camera: CameraState) -> bool:
	if gameplay_active >= 0:
		return run_escaped
	# Standalone preview resources have no ShapeRun; use their preview boundary.
	# Scale before squaring to avoid overflow for large world coordinates.
	var x := camera.eye_x() / next_level_threshold
	var y := camera.eye_y() / next_level_threshold
	var z := camera.eye_z() / next_level_threshold
	return x * x + y * y + z * z > 1.0

func copy_run_from(other: FractalParams) -> void:
	gameplay_active = other.gameplay_active
	next_level_threshold = other.next_level_threshold
	render_escape_radius = other.render_escape_radius
	run_origin = other.run_origin.duplicate()
	run_escaped = other.run_escaped


## The shape the console has selected: the Julia marker follows it, a new
## shape is placed relative to it, and the per-shape conveniences below
## (bound_half, julia_point…) answer for it.
var active: int = 0:
	set(v):
		v = clampi(v, 0, maxi(shapes.size() - 1, 0))
		if v == active:
			return
		active = v
		emit_changed()

## COLOR fields: pushed to the shader as a `Vector3`, not as the plain value.
## Kept out of LOOK_KEYS so every look key is a scalar.
const COLOR_KEYS: Array[StringName] = [&"light_color", &"fog_tint", &"surface_color"]

## The scalar colour, lighting and palette fields after color_mode (every
## resolved key past color_mode except the COLOR_KEYS): each is pushed to the
## shader uniform of the same name as it is.
const LOOK_KEYS: Array[StringName] = [
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_yaw", &"light_pitch", &"light_size", &"light_ambient", &"light_diffuse",
	&"shadows", &"fog_distance", &"fog_start", &"scatter_density", &"scatter_glow", &"scatter_brightness",
	&"exposure", &"saturation", &"roughness", &"light_specular",
	&"texture_strength", &"bump_strength",
	&"palette_a_r", &"palette_a_g", &"palette_a_b", &"palette_b_r", &"palette_b_g", &"palette_b_b",
	&"palette_c_r", &"palette_c_g", &"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]

# While true the look setters do not emit; apply_resolved emits once at the end.
var _suppress := false


func _init() -> void:
	gameplay.changed.connect(emit_changed)
	add_shape()


# ------------------------------------------------------------------ shapes

## The selected shape.
func active_shape() -> ShapeParams:
	return shapes[clampi(active, 0, shapes.size() - 1)]


## The i-th shape (the first by default).
func shape(i: int = 0) -> ShapeParams:
	return shapes[clampi(i, 0, shapes.size() - 1)]


func shape_count() -> int:
	return shapes.size()


## Append a shape (a fresh default one when none is given) and relay its
## `changed`. Returns it, or null once MAX_SHAPES are held.
func add_shape(s: ShapeParams = null) -> ShapeParams:
	if shapes.size() >= MAX_SHAPES:
		push_warning("FractalParams.add_shape: already holds %d shapes" % MAX_SHAPES)
		return null
	if s == null:
		s = ShapeParams.new()
	shapes.append(s)
	s.changed.connect(emit_changed)
	emit_changed()
	return s


## Drop the i-th shape. The scene keeps at least one; returns whether it did.
func remove_shape(i: int) -> bool:
	if shapes.size() <= 1 or i < 0 or i >= shapes.size():
		return false
	var s := shapes[i]
	if s.changed.is_connected(emit_changed):
		s.changed.disconnect(emit_changed)
	shapes.remove_at(i)
	if active >= shapes.size():
		active = shapes.size() - 1
	emit_changed()
	return true


## Grow or shrink the list to `n` shapes (1..MAX_SHAPES), keeping the leading
## ones: Main calls this to mirror the ShapeList.
func set_shape_count(n: int) -> void:
	n = clampi(n, 1, MAX_SHAPES)
	while shapes.size() < n:
		add_shape()
	while shapes.size() > n:
		remove_shape(shapes.size() - 1)


# --- Colour ---
@export var color_mode: int = 0:
	set(v): color_mode = v; _emit()
@export var palette_source: int = 0:
	set(v): palette_source = v; _emit()
@export var palette_frequency: float = 1.0:
	set(v): palette_frequency = v; _emit()
@export var palette_offset: float = 0.0:
	set(v): palette_offset = v; _emit()
@export var palette_occlusion: float = 0.5:
	set(v): palette_occlusion = v; _emit()

# --- Light (the defaults are the site's constants, so the picture is unchanged;
#     light_color pushed to the shader as a Vector3, see COLOR_KEYS) ---
@export var light_color: Color = Color(1, 1, 1, 1):
	set(v): light_color = v; _emit()
@export var light_yaw: float = 0.0:
	set(v): light_yaw = v; _emit()
@export var light_pitch: float = 0.0:
	set(v): light_pitch = v; _emit()
@export var light_size := 0.0:
	set(v): light_size = v; _emit()
@export var light_ambient: float = 0.1:
	set(v): light_ambient = v; _emit()
@export var light_diffuse: float = 0.5:
	set(v): light_diffuse = v; _emit()
@export var shadows := 0.0:
	set(v): shadows = v; _emit()

# --- Scattering (off at density 0, so the default is untouched) ---
@export var fog_distance := 0.0:
	set(v): fog_distance = maxf(v, 0.0); _emit()
@export var fog_start := 0.35:
	set(v): fog_start = clampf(v, 0.0, 0.99); _emit()
@export var fog_tint := Color(0.2, 0.2, 0.2):
	set(v): fog_tint = v; _emit()
@export var scatter_density := 0.0:
	set(v): scatter_density = v; _emit()
@export var scatter_glow := 0.0:
	set(v): scatter_glow = v; _emit()
@export var scatter_brightness := 1.0:
	set(v): scatter_brightness = v; _emit()

# --- Picture ---
@export var exposure: float = 1.0:
	set(v): exposure = v; _emit()
@export var saturation: float = 1.0:
	set(v): saturation = v; _emit()

# --- Surface (roughness 1/9 is the site's specular exponent 160;
#     surface_color pushed to the shader as a Vector3, see COLOR_KEYS) ---
@export var surface_color: Color = Color(1, 1, 1, 1):
	set(v): surface_color = v; _emit()
@export var roughness := 1.0 / 9.0:
	set(v): roughness = v; _emit()
@export var light_specular: float = 1.0:
	set(v): light_specular = v; _emit()

# --- Texture (the noise editor's Texture and Bump outputs scale by these;
#     1 is "full strength", but nothing wired means nothing changes) ---
@export var texture_strength := 0.0:
	set(v): texture_strength = v; _emit()
@export var bump_strength := 0.0:
	set(v): bump_strength = v; _emit()

# --- Palette: A + B cos(2π (C t + D)), per channel (see Palette) ---
@export var palette_a_r: float = 0.5:
	set(v): palette_a_r = v; _emit()
@export var palette_a_g: float = 0.5:
	set(v): palette_a_g = v; _emit()
@export var palette_a_b: float = 0.5:
	set(v): palette_a_b = v; _emit()
@export var palette_b_r: float = 0.5:
	set(v): palette_b_r = v; _emit()
@export var palette_b_g: float = 0.5:
	set(v): palette_b_g = v; _emit()
@export var palette_b_b: float = 0.5:
	set(v): palette_b_b = v; _emit()
@export var palette_c_r: float = 1.0:
	set(v): palette_c_r = v; _emit()
@export var palette_c_g: float = 1.0:
	set(v): palette_c_g = v; _emit()
@export var palette_c_b: float = 1.0:
	set(v): palette_c_b = v; _emit()
@export var palette_d_r: float = 0.0:
	set(v): palette_d_r = v; _emit()
@export var palette_d_g: float = 0.33:
	set(v): palette_d_g = v; _emit()
@export var palette_d_b: float = 0.67:
	set(v): palette_d_b = v; _emit()

# --- preferences (edited directly, not resolved) ---
## Scan one short band per frame; old rows decay with intentional motion trails.
@export var phosphor_enabled: bool = false:
	set(v): phosphor_enabled = v; emit_changed()
@export var phosphor_bands: int = 8:
	set(v): phosphor_bands = clampi(v, 2, 32); emit_changed()
## Seconds for unrefreshed history to decay to 37% brightness.
@export var phosphor_decay: float = 0.6:
	set(v): phosphor_decay = clampf(v, 0.05, 3.0); emit_changed()
@export var phosphor_glow: float = 0.5:
	set(v): phosphor_glow = clampf(v, 0.0, 2.0); emit_changed()

@export var fast_controls: bool = true:
	set(v): fast_controls = v; emit_changed()
@export var camera_mode: CameraMode = CameraMode.FLY:
	set(v): camera_mode = v; emit_changed()
@export var mouse_sensitivity: float = 0.1:
	set(v): mouse_sensitivity = v; emit_changed()

## Level of detail with distance. A ray stops once the distance estimate falls
## below hit_epsilon(t, near): the pixel cone `precision × t`, divided by
## `detail`, and coarsened by (t / start)^detail_falloff past start =
## detail_range × the camera's distance to the nearest surface. Measuring the
## range in that distance keeps it meaningful at any zoom depth; a falloff of 0
## is the plain cone. The shader's hit_eps() is the same formula.
const DETAIL_MIN := 0.1
const DETAIL_MAX := 10.0
const DETAIL_RANGE_MIN := 1.0
const DETAIL_RANGE_MAX := 1000.0
const DETAIL_FALLOFF_MAX := 3.0
const NEAR_FLOOR := 1e-14   # only guards against a zero: near must follow the camera below 1e-6
## The Kleinian's bounding cube: effectively none (ShapeParams.bound_half()).
const KLEINIAN_BOUND := ShapeParams.KLEINIAN_BOUND

## Per colour-mode id, in the dropdown's order.
const FOG_COLORS := {
	0: Vector3(0.22, 0.22, 0.22),    # Grayscale
	1: Vector3(0.14, 0.22, 0.36),    # Ice Fractal
	2: Vector3(0.10, 0.17, 0.10),    # Borg
	3: Vector3(0.24, 0.14, 0.30),    # Rainbow
	4: Vector3(0.20, 0.10, 0.24),    # Rainbow 2
	8: Vector3(0.14, 0.18, 0.30),    # Rainbow 3
	15: Vector3(0.20, 0.20, 0.27),   # Rainbow Metal
	5: Vector3(0.82, 0.88, 1.00),    # Blue (white background)
	6: Vector3(0.85, 0.90, 1.00),    # Blue 2 (white background)
	7: Vector3(0.30, 0.14, 0.27),    # Pink-Blue
	16: Vector3(0.12, 0.26, 0.34),   # Ice Box
	9: Vector3(0.12, 0.26, 0.34),    # Ice Box 2
	14: Vector3(0.28, 0.20, 0.06),   # Gold
	20: Vector3(0.18, 0.18, 0.22),   # Palette (any palette: a neutral dusk)
}

## The resolution governor never drops below min_render_scale while moving.
const RENDER_SCALE_FLOOR := 0.1

## The march's step budget: three quarters coarse and the rest fine. Defaults
## use 24 + 8 steps and 8 fractal iterations: the lowest supported budgets. Raise
## iterations to 32 and steps to 128 for the original full-detail budget. The
## shader loops are bounded for MAX_STEPS_MAX.
const MAX_STEPS_MIN := 32
const MAX_STEPS_MAX := 512

## The full shadow march, in steps, at load level 0. The view pushes
## `shadow_steps = round(SHADOW_STEPS × shed.shadow)` (Task 5), so the shed
## ladder halves it at level 1 and drops it to 0 from level 2.
const SHADOW_STEPS := 48

## Work budgets shared by the CPU distance estimates, camera and shader.
## The shader may use a lower iteration cap while load shedding; CPU collision
## and picking keep the saved budget so shedding does not change gameplay.
const FRACTAL_ITERATIONS_MIN := 8
const FRACTAL_ITERATIONS_MAX := 32
@export var fractal_iterations: int = 8:
	set(v): fractal_iterations = clampi(v, FRACTAL_ITERATIONS_MIN, FRACTAL_ITERATIONS_MAX); emit_changed()

## Radius multipliers for orbit escape only; geometry bounds stay unchanged.
## Larger margins delay early exits but never exceed the iteration budget.
const BAILOUT_MARGIN_MAX := 16.0
@export var kifs_bailout_margin: float = 1.0:
	set(v):
		kifs_bailout_margin = clampf(v, 1.0, BAILOUT_MARGIN_MAX) if is_finite(v) else 1.0
		emit_changed()
@export var mandelbulb_bailout_margin: float = 1.0:
	set(v):
		mandelbulb_bailout_margin = clampf(v, 1.0, BAILOUT_MARGIN_MAX) if is_finite(v) else 1.0
		emit_changed()


@export var detail: float = 1.0:
	set(v): detail = clampf(v, DETAIL_MIN, DETAIL_MAX); emit_changed()
@export var detail_range: float = 10.0:
	set(v): detail_range = clampf(v, DETAIL_RANGE_MIN, DETAIL_RANGE_MAX); emit_changed()
@export var detail_falloff: float = 0.0:
	set(v): detail_falloff = clampf(v, 0.0, DETAIL_FALLOFF_MAX); emit_changed()
@export var min_render_scale: float = 0.1:
	set(v): min_render_scale = clampf(v, RENDER_SCALE_FLOOR, 1.0); emit_changed()
## Painterly presentation has a persistent ray-resolution ceiling, including at
## rest. Brush size is in logical screen pixels, independent of ray resolution.
const PAINTERLY_SCALE_MAX := 0.75
const PAINTERLY_BRUSH_MIN := 4.0
const PAINTERLY_BRUSH_MAX := 40.0
@export var painterly_enabled: bool = false:
	set(v): painterly_enabled = v; emit_changed()
@export var painterly_scale: float = 0.3:
	set(v): painterly_scale = clampf(v, RENDER_SCALE_FLOOR, PAINTERLY_SCALE_MAX); emit_changed()
@export var painterly_brush_size: float = 12.0:
	set(v): painterly_brush_size = clampf(v, PAINTERLY_BRUSH_MIN, PAINTERLY_BRUSH_MAX); emit_changed()


@export var max_steps: int = 32:
	set(v): max_steps = clampi(v, MAX_STEPS_MIN, MAX_STEPS_MAX); emit_changed()


## The hit threshold at ray distance `t`, for a camera `near` from the nearest
## surface and a shape of the given precision (the active shape's when none is
## given). Mirrors hit_eps() in mandelbox.gdshader.
func hit_epsilon(t: float, near: float, precision: float = -1.0) -> float:
	if precision < 0.0:
		precision = active_shape().precision
	var eps := precision / detail * t
	if detail_falloff > 0.0:
		var start := detail_range * maxf(near, NEAR_FLOOR)
		if t > start:
			eps *= pow(t / start, detail_falloff)
	return eps


## The coarse pass's iteration count for shape `i` (the active one by default)
## with the camera `near` (world units) from the nearest surface: the shape's
## own rule (ShapeParams.coarse_iters) in its local units, at this view's
## detail.
func coarse_iters(near: float, i: int = -1) -> int:
	var s := active_shape() if i < 0 else shapes[clampi(i, 0, shapes.size() - 1)]
	return mini(fractal_iterations, s.coarse_iters(near / s.size, detail))


## The shading crossfade's band, in the camera's distance to the nearest
## surface: beyond NF_FADE_FAR the Ice Fractal colour modes light with their own
## normal (calc_nf), inside NF_FADE_NEAR with the true one (calc_normal).
const NF_FADE_NEAR := 0.1
const NF_FADE_FAR := 2.0


## How much of the Ice Fractal normal the shader's lighting uses for a camera
## `near` from the surface: 1 (all of it) from NF_FADE_FAR out, 0 inside
## NF_FADE_NEAR, an S-shaped blend between (smoothstep: eases in and out, so
## the change has no visible kink). The Ice Fractal normal samples a fixed 0.01
## from the hit point, which up close spans far more than a pixel and turns
## the shading to noise; the true normal's sample spacing follows the hit
## threshold instead. Exactly 1 at the default view (near ~6.57).
static func nf_weight(near: float) -> float:
	return smoothstep(NF_FADE_NEAR, NF_FADE_FAR, near)


## The gap between neighbouring 32-bit floats near x: 2^(floor(log2 |x|) − 23)
## (a 32-bit float keeps 23 bits after its leading one). Below the smallest
## normal 32-bit float the gap is the fixed 2^-149.
static func ulp32(x: float) -> float:
	x = absf(x)
	if x < pow(2.0, -126.0):
		return pow(2.0, -149.0)
	var e := floori(log(x) / log(2.0))
	# log() can round either way at an exact power of two.
	if pow(2.0, e + 1) <= x:
		e += 1
	elif pow(2.0, e) > x:
		e -= 1
	return pow(2.0, e - 23)


## The 32-bit floor at a world eye (64-bit components, as [x, y, z] or a
## PackedFloat64Array): recommended surface clearance while
## the shader forms ray positions in 32-bit floats, in world units. It is the
## floor (ShapeParams.zoom_floor) of the shape the eye is nearest to, in that
## shape's own frame, at this view's detail: about 1e-4 near the box at the
## default precision for one shape at the identity placement, and a thousandth
## of that for a shape a thousandth the size.
func floor32(eye) -> float:
	return zoom_floor_at(eye[0], eye[1], eye[2])


## Recommended rendering clearance (world units), using the nearest shape's
## 32-bit floor in its own frame. Player collision can shrink below this.
func zoom_floor(eye) -> float:
	return zoom_floor_at(eye[0], eye[1], eye[2])


func zoom_floor_at(ex: float, ey: float, ez: float) -> float:
	var nearest := DistanceEstimator.nearest_at(ex, ey, ez, self)
	return shapes[nearest["index"]].zoom_floor(ex, ey, ez, detail)


## The coarse share of a step budget: `budget`, or max_steps when it is 0 (the
## load shedder passes a smaller budget).
func coarse_steps(budget := 0) -> int:
	return (budget if budget > 0 else max_steps) * 3 / 4


func fine_steps(budget := 0) -> int:
	var b := budget if budget > 0 else max_steps
	return b - coarse_steps(b)


## The load shedder's fog tint for the current colour mode: a dark version of
## each palette, and a light one for the two modes drawn on white.
func fog_color() -> Vector3:
	return FOG_COLORS.get(color_mode, Vector3(0.2, 0.2, 0.2))


func _emit() -> void:
	if not _suppress:
		emit_changed()


## Write every listed resolved LOOK value (by catalogue id) in one batch,
## emitting `changed` at most once and only if something actually differed. A
## view with no active binding costs no signal per frame. Per-shape ids in
## `values` are ignored here: each ShapeParams takes its own.
func apply_resolved(values: Dictionary) -> void:
	var dirty := false
	_suppress = true
	for k in RESOLVED_KEYS:
		if not values.has(k):
			continue
		var v: Variant = values[k]
		if get(k) != v:
			set(k, v)
			dirty = true
	_suppress = false
	if dirty:
		emit_changed()


## Per-shape conveniences, answering for the ACTIVE shape (see ShapeParams).
func julia_point() -> Vector3:
	return active_shape().julia_point()


func julia_enabled() -> bool:
	return active_shape().julia_enabled()


func bound_half() -> float:
	return active_shape().bound_half()


func view_distance() -> float:
	return active_shape().view_distance()


## The furthest any ray may go before it stops, in world units, or 0 for no
## limit: the smallest View distance among the Kleinians in the scene.
func scene_view_distance() -> float:
	var out := 0.0
	for i in visible_shape_indices():
		var v := shapes[i].view_distance()
		if v > 0.0 and (out == 0.0 or v < out):
			out = v
	return out
