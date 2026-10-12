class_name RenderCost
extends RefCounted
## Qualitative cost of the CURRENT setting, not a GPU timer or FPS prediction.
## Zero means no known optional work, not that geometry cannot affect a march.
## Only called by the UI; never traces rays or evaluates a distance estimator.

const GREEN := Color(0.35, 0.9, 0.45)
const YELLOW := Color(1.0, 0.8, 0.2)
const RED := Color(1.0, 0.3, 0.25)
const LEGEND := "Estimated cost: green = low, yellow = moderate, red = high. Not measured GPU time; camera, geometry, noise and early exits also affect rendering."

static func tint(cost: float) -> Color:
	var t := clampf(cost, 0.0, 1.0)
	return GREEN.lerp(YELLOW, t * 2.0) if t <= 0.5 else YELLOW.lerp(RED, (t - 0.5) * 2.0)

static func ramp(value: float, lo: float, hi: float, logarithmic := false) -> float:
	if logarithmic:
		return clampf(log(maxf(value, lo) / lo) / log(hi / lo), 0.0, 1.0)
	return clampf((value - lo) / (hi - lo), 0.0, 1.0)

static func score(id: StringName, value: float, values: Dictionary) -> float:
	var key := String(id)
	if id == &"precision":
		return 1.0 - ramp(value, 1e-6, 1e-3, true)
	if id == &"kleinian_view_distance":
		return ramp(value, 1.0, 100.0, true)
	if key.begins_with("iter_rot_") or key.begins_with("kifs_rot"):
		var prefix := key.substr(0, key.length() - 2)
		var total := 0.0
		for plane in ["xy", "xz", "xw", "yz", "yw", "zw"]:
			total += absf(float(values.get(StringName(prefix + plane), 0.0)))
		return 0.5 if total > 1e-6 else 0.0
	if id == &"kifs_twist":
		return 0.75 if value != 0.0 else 0.0
	if key.begins_with("kleinian_shift_"):
		return 1.0 if value != 0.0 else 0.0
	if id == &"hybrid_mix":
		return 0.5 if value > 0.0 else 0.0
	if id == &"scatter_density":
		return 0.5 if value > 0.0 else 0.0
	if id == &"scatter_glow":
		return 0.5 if float(values.get(&"scatter_density", 0.0)) > 0.0 else 0.0
	if id == &"shadows":
		var swung := float(values.get(&"light_yaw", 0.0)) != 0.0 or float(values.get(&"light_pitch", 0.0)) != 0.0
		return 1.0 if value > 0.0 and swung and int(values.get(&"color_mode", 0)) != 0 else 0.0
	if id == &"bump_strength":
		return 0.75 if value != 0.0 and int(values.get(&"color_mode", 0)) != 0 else 0.0
	return 0.0

static func explanation(id: StringName) -> String:
	var key := String(id)
	if id == &"precision":
		return "Smaller thresholds generally need more march steps; larger thresholds sacrifice detail."
	if id == &"kleinian_view_distance":
		return "A longer horizon permits more marching through the lattice."
	if key.begins_with("iter_rot_") or key.begins_with("kifs_rot"):
		return "Any active angle enables this whole six-plane rotation group inside every orbit iteration. Tiny angles cost the same operations as large ones. All six at zero skips the group."
	if id == &"kifs_twist":
		return "Nonzero enables trigonometry inside the orbit. A tiny twist costs the same operations as a large one."
	if key.begins_with("kleinian_shift_"):
		return "Nonzero shifts can prevent the unchanged-point early exit, increasing orbit work. The effect depends on geometry."
	if id == &"hybrid_mix":
		return "Any positive mix enables hybrid fold work; strength is not proportional to cost."
	if id == &"shadows":
		return "An extra shadow march when strength is positive, the lamp is off-axis, and colour is not Grayscale. Load shedding can skip it."
	if id == &"bump_strength":
		return "Potential six noise samples when nonzero, a bump graph is connected, and colour is not Grayscale. No graph means no extra work."
	if id == &"texture_strength":
		return "Texture graph cost depends on its nodes. This strength does not change its sample count. Grayscale skips it."
	if id == &"scatter_glow":
		return "Glow uses the same phase arithmetic at every value, including zero. Density controls whether haze work runs."
	if id == &"scatter_density":
		return "Enables per-pixel haze arithmetic; no additional rays."
	return "No known extra sampling is enabled by this slider alone. Geometry changes can still alter march length and early exits; green does not guarantee a faster frame."
