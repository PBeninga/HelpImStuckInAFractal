class_name FractalParams
extends Resource
## Every value the renderer, cameras and governor read. The shape fields are the
## RESOLVED knob values, named by catalogue id and written once per frame by
## apply_resolved(); the preference and renderer fields (fast_controls,
## camera_mode, mouse_sensitivity, the level of detail, step budget and minimum
## render scale) are still edited directly. Setters emit Resource's built-in
## `changed`; apply_resolved batches a frame's writes into at most one emit.
## Defaults match the site (the level-of-detail defaults reproduce its plain
## pixel cone).

enum CameraMode { FLY, ORBIT }

## Colour-mode ids in the dropdown's order (ids match the site).
## Palette (20) is this project's own, past the site's range.
const COLOR_MODE_IDS: Array[int] = [0, 1, 2, 3, 4, 8, 15, 5, 6, 7, 16, 9, 14, 20]
const COLOR_MODE_NAMES: Array[String] = [
	"Grayscale", "Ice Fractal", "Borg", "Rainbow", "Rainbow 2", "Rainbow 3",
	"Rainbow Metal", "Blue", "Blue 2", "Pink-Blue", "Ice Box", "Ice Box 2", "Gold",
	"Palette",
]

## The resolved shape fields, in catalogue order. apply_resolved writes these.
const RESOLVED_KEYS: Array[StringName] = [
	&"box_scale", &"fold_limit", &"min_radius", &"fixed_radius", &"fold_order", &"w",
	&"julia_all", &"julia_0", &"julia_1", &"julia_2", &"julia_3",
	&"c_0", &"c_1", &"c_2", &"c_3",
	&"iter_rot_xy", &"iter_rot_xz", &"iter_rot_xw", &"iter_rot_yz", &"iter_rot_yw", &"iter_rot_zw",
	&"precision",
	&"color_mode", &"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_ambient", &"light_diffuse", &"light_specular", &"light_shininess",
	&"light_yaw", &"light_pitch", &"exposure", &"saturation",
	&"palette_a_r", &"palette_a_g", &"palette_a_b", &"palette_b_r", &"palette_b_g", &"palette_b_b",
	&"palette_c_r", &"palette_c_g", &"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]

## The colour, lighting and palette fields after color_mode: each is pushed to
## the shader uniform of the same name as it is.
const LOOK_KEYS: Array[StringName] = [
	&"palette_source", &"palette_frequency", &"palette_offset", &"palette_occlusion",
	&"light_ambient", &"light_diffuse", &"light_specular", &"light_shininess",
	&"light_yaw", &"light_pitch", &"exposure", &"saturation",
	&"palette_a_r", &"palette_a_g", &"palette_a_b", &"palette_b_r", &"palette_b_g", &"palette_b_b",
	&"palette_c_r", &"palette_c_g", &"palette_c_b", &"palette_d_r", &"palette_d_g", &"palette_d_b",
]

# While true the shape setters do not emit; apply_resolved emits once at the end.
var _suppress := false

# --- Box ---
@export var box_scale: float = -2.09:
	set(v): box_scale = v; _emit()
@export var fold_limit: float = 1.0:
	set(v): fold_limit = v; _emit()
@export var min_radius: float = 0.7:
	set(v): min_radius = v; _emit()
@export var fixed_radius: float = 1.0:
	set(v): fixed_radius = v; _emit()
@export var fold_order: int = 0:
	set(v): fold_order = v; _emit()
@export var w: float = 0.0:
	set(v): w = v; _emit()

# --- Julia ---
@export var julia_all: bool = false:
	set(v): julia_all = v; _emit()
@export var julia_0: bool = false:
	set(v): julia_0 = v; _emit()
@export var julia_1: bool = false:
	set(v): julia_1 = v; _emit()
@export var julia_2: bool = false:
	set(v): julia_2 = v; _emit()
@export var julia_3: bool = false:
	set(v): julia_3 = v; _emit()
@export var c_0: float = -0.23:
	set(v): c_0 = v; _emit()
@export var c_1: float = 1.512:
	set(v): c_1 = v; _emit()
@export var c_2: float = 1.892:
	set(v): c_2 = v; _emit()
@export var c_3: float = 0.0:
	set(v): c_3 = v; _emit()

# --- Iteration rotation (degrees) ---
@export var iter_rot_xy: float = 0.0:
	set(v): iter_rot_xy = v; _emit()
@export var iter_rot_xz: float = 0.0:
	set(v): iter_rot_xz = v; _emit()
@export var iter_rot_xw: float = 0.0:
	set(v): iter_rot_xw = v; _emit()
@export var iter_rot_yz: float = 0.0:
	set(v): iter_rot_yz = v; _emit()
@export var iter_rot_yw: float = 0.0:
	set(v): iter_rot_yw = v; _emit()
@export var iter_rot_zw: float = 0.0:
	set(v): iter_rot_zw = v; _emit()

# --- Render ---
@export var precision: float = 0.000025:
	set(v): precision = v; _emit()

# --- Colour ---
@export var color_mode: int = 1:
	set(v): color_mode = v; _emit()
@export var palette_source: int = 0:
	set(v): palette_source = v; _emit()
@export var palette_frequency: float = 1.0:
	set(v): palette_frequency = v; _emit()
@export var palette_offset: float = 0.0:
	set(v): palette_offset = v; _emit()
@export var palette_occlusion: float = 0.5:
	set(v): palette_occlusion = v; _emit()

# --- Lighting (the defaults are the site's constants) ---
@export var light_ambient: float = 0.1:
	set(v): light_ambient = v; _emit()
@export var light_diffuse: float = 0.5:
	set(v): light_diffuse = v; _emit()
@export var light_specular: float = 1.0:
	set(v): light_specular = v; _emit()
@export var light_shininess: float = 160.0:
	set(v): light_shininess = v; _emit()
@export var light_yaw: float = 0.0:
	set(v): light_yaw = v; _emit()
@export var light_pitch: float = 0.0:
	set(v): light_pitch = v; _emit()
@export var exposure: float = 1.0:
	set(v): exposure = v; _emit()
@export var saturation: float = 1.0:
	set(v): saturation = v; _emit()

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
const NEAR_FLOOR := 1e-6   # the near distance never reaches 0 (a camera on the surface)

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

## The march's step budget: three quarters coarse (N = coarse_iters(), 16 at
## the default view) and the rest fine (N=32), so the default 128 is the
## original 96 + 32. The shader's loops are
## bounded for MAX_STEPS_MAX.
const MAX_STEPS_MIN := 32
const MAX_STEPS_MAX := 512

@export var detail: float = 1.0:
	set(v): detail = clampf(v, DETAIL_MIN, DETAIL_MAX); emit_changed()
@export var detail_range: float = 10.0:
	set(v): detail_range = clampf(v, DETAIL_RANGE_MIN, DETAIL_RANGE_MAX); emit_changed()
@export var detail_falloff: float = 0.0:
	set(v): detail_falloff = clampf(v, 0.0, DETAIL_FALLOFF_MAX); emit_changed()
@export var min_render_scale: float = 0.25:
	set(v): min_render_scale = clampf(v, RENDER_SCALE_FLOOR, 1.0); emit_changed()
@export var max_steps: int = 128:
	set(v): max_steps = clampi(v, MAX_STEPS_MIN, MAX_STEPS_MAX); emit_changed()


## The hit threshold at ray distance `t`, for a camera `near` from the nearest
## surface. Mirrors hit_eps() in mandelbox.gdshader.
func hit_epsilon(t: float, near: float) -> float:
	var eps := precision / detail * t
	if detail_falloff > 0.0:
		var start := detail_range * maxf(near, NEAR_FLOOR)
		if t > start:
			eps *= pow(t / start, detail_falloff)
	return eps


## The fewest iterations the march's coarse pass uses (the site's fixed count),
## and the box half-size its count is worked out against.
const COARSE_ITERS_MIN := 16
const COARSE_BOX_HALF := 2.0


## How many iterations the march's coarse pass needs for a camera `near` from
## the nearest surface. Each iteration adds detail |box_scale| times finer, so
## stopping after n leaves a smoother surface about COARSE_BOX_HALF /
## |box_scale|^n away from the real one. The coarse pass stops at twice the hit
## threshold, 2 × eps × near (eps = precision / detail), so it needs that gap
## under the threshold: n = log(box / (2 eps near)) / log|box_scale|, rounded
## up, kept in [16, 32]. 16 at the default view, so the site's picture is
## unchanged; it rises inside about 0.3 of the surface and reaches 32 by about
## 3e-6. A |box_scale| of 1 or less has no shrinking detail: 32. Uses the
## unshed detail: the still frame renders at load level 0.
func coarse_iters(near: float) -> int:
	var s := absf(box_scale)
	if s <= 1.0:
		return DistanceEstimator.ITERATIONS
	var gap := maxf(2.0 * precision / detail * maxf(near, 0.0), 1e-300)
	var n := ceilf(log(COARSE_BOX_HALF / gap) / log(s))
	return clampi(int(minf(n, 1e6)), COARSE_ITERS_MIN, DistanceEstimator.ITERATIONS)


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


## The zoom floor sits where the hit threshold is this many times finer than
## the 32-bit grid. Measured: hits start failing at a distance of 1e-4 with
## ulp32 ~1.2e-7 and eps 2.5e-5, which is ulp32 / (48 × eps).
const ZOOM_FLOOR_DIVISOR := 50.0


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


## How close the fly camera may come to the surface with its eye at `eye`. The
## shader works out ray positions in 32-bit floats, which near `eye` can only
## land on a grid ulp32(largest |coordinate|) apart; once the hit threshold
## (eps × distance, eps = precision / detail) is much finer than that grid,
## rays reach the surface only by luck and the picture breaks into speckle and
## pits. The floor is ulp32 / (ZOOM_FLOOR_DIVISOR × eps): about 1e-4 near the
## box at the default precision. A higher Detail (a finer threshold) and a
## larger eye coordinate (Julia mode's bigger box) both push it further out.
## Uses the unshed detail, like coarse_iters.
func zoom_floor(eye: Vector3) -> float:
	var m := maxf(absf(eye.x), maxf(absf(eye.y), absf(eye.z)))
	return ulp32(m) / (ZOOM_FLOOR_DIVISOR * maxf(precision / detail, 1e-30))


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


## Write every listed resolved value (by catalogue id) in one batch, emitting
## `changed` at most once and only if something actually differed. A view with
## no active binding costs no signal per frame.
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


## The Julia constant's first three components, for the marker and orbit camera.
func julia_point() -> Vector3:
	return Vector3(c_0, c_1, c_2)


## Whether the master Julia toggle is on (drives the on-screen marker).
func julia_enabled() -> bool:
	return julia_all
