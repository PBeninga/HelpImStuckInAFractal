class_name MandelbulbShape
extends RefCounted
## The Mandelbulb's knobs, in inspector order: the power, the two angle phases,
## and Julia mode with its three constants. White and Nylander's "triplex"
## power: write the point in spherical coordinates (radius r, polar angle
## theta from +z, azimuth phi about z), raise r to the power n and multiply
## both angles by n, then add c. The Mandelbulb is 3D, so the shared W row
## hides while it is drawn.
##
## The ids are the shader uniform names and the FractalParams field names.

const F := AttributeSpec.Type.FLOAT
const BOOL := AttributeSpec.Type.BOOL

const AXES := ["x", "y", "z"]
## A Julia constant inside the power-8 bulb's own reach, so Julia mode opens
## on a connected shape rather than dust.
const C_DEFAULTS := [-0.2, 0.6, 0.4]


## The predicate for the Julia constant rows: shown while Julia is on.
static func _julia_shown() -> Callable:
	return func(values: Dictionary) -> bool:
		return bool(values.get(&"mandelbulb_julia", false))


static func specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []
	out.append(AttributeSpec.make({
		"id": "mandelbulb_power", "label": "Power", "type": F,
		"default": 8.0, "min": 2.0, "max": 16.0, "step": 0.01,
		"hard_min": 1.5, "hard_max": 32.0, "group": "Mandelbulb",
		"tooltip": "The power n of the triplex map: every iteration raises the radius to n and multiplies both angles by n, then adds c.",
		"effects": "8 is the classic Mandelbulb, with its eight-fold lobes. Each lobe count follows the power: 2 is a smooth, nearly featureless blob, 3 and 4 give fat buds, high powers a spiky, many-lobed ball. Fractional powers tear a seam where the angle wraps. Bind it to Time to watch the bulb sprout lobes.",
	}))
	out.append(AttributeSpec.make({
		"id": "mandelbulb_phase_theta", "label": "Theta phase", "type": F,
		"default": 0.0, "min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
		"group": "Mandelbulb",
		"tooltip": "Degrees added to the polar angle (measured from +z) after it is multiplied by the power, every iteration.",
		"effects": "0 is the classic bulb, symmetric top to bottom. Any other value tips every iteration's copy, so the lobes lean and the poles twist into spirals; the shape changes, not just the view.",
	}))
	out.append(AttributeSpec.make({
		"id": "mandelbulb_phase_phi", "label": "Phi phase", "type": F,
		"default": 0.0, "min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
		"group": "Mandelbulb",
		"tooltip": "Degrees added to the azimuth (the angle about z) after it is multiplied by the power, every iteration.",
		"effects": "0 is the classic bulb. Other values turn each iteration's copy about z, so the ring of lobes around the equator swirls into a pinwheel.",
	}))
	out.append(AttributeSpec.make({
		"id": "mandelbulb_julia", "label": "Julia", "type": BOOL,
		"default": false, "group": "Mandelbulb",
		"tooltip": "Add the fixed constant below every iteration instead of the sample point's own position.",
		"effects": "Off is the Mandelbulb itself, where each point iterates from its own position. On is a Julia bulb: one shape per constant, often more intricate and lacier. The constant rows show while this is on.",
	}))
	for i in 3:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "mandelbulb_c_%d" % i, "label": "Constant %s" % axis, "type": F,
			"default": C_DEFAULTS[i], "min": -1.5, "max": 1.5, "step": 0.001,
			"hard_min": -4.0, "hard_max": 4.0, "group": "Mandelbulb",
			"show_when": _julia_shown(),
			"tooltip": "The %s component of the Julia constant, added every iteration while Julia is on." % axis,
			"effects": "Constants near the Mandelbulb's surface give the richest Julia bulbs; well inside it they are smooth blobs, and outside it (much past 1) they fall apart into dust. Bind one to an axis to morph the shape as you move.",
		}))
	return out


## Heading tooltips for the Mandelbulb's group.
static func group_tooltips() -> Dictionary:
	return {
		"Mandelbulb": "Mandelbulb: the 3D cousin of the Mandelbrot set (White and Nylander's). Every iteration raises the point to a power in spherical coordinates (the radius to the power, both angles times it) and adds c; the points whose orbit never escapes are the bulb.",
	}


## Whether the Mandelbulb is exactly self-similar (see
## MandelboxShape.self_similarity): never. Its power map stretches the polar
## and azimuthal directions by different amounts (it is not conformal: a small
## sphere does not stay a sphere), so each deep region is a distorted copy of a
## shallower one, never an exact magnification. The Mandelbrot set is the same
## way.
static func self_similarity(values: Dictionary, displaced := false) -> Dictionary:
	if displaced:
		return {"qualifies": false, "reason": "noise field displaces the surface"}
	if bool(values.get(&"mandelbulb_julia", false)):
		return {"qualifies": false, "reason": "Mandelbulb: the power map stretches unevenly, so deep copies are distorted"}
	return {"qualifies": false, "reason": "Mandelbulb: c follows the point, and the power map stretches unevenly"}
