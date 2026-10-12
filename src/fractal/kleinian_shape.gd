class_name KleinianShape
extends RefCounted
## The pseudo-Kleinian's knobs, in inspector order: the fold box (one half-width
## per axis), the inversion radius, the 4D shift, the sheet thickness and the
## view distance that ends its rays. Knighty's form; the box defaults are his.
##
## The ids are the shader uniform names and the FractalParams field names.

const F := AttributeSpec.Type.FLOAT

const AXES := ["x", "y", "z", "w"]
const BOX_DEFAULTS := [0.92436, 0.90756, 0.92436, 0.92436]


static func specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []
	for i in 4:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "kleinian_box_%d" % i, "label": "Box %s" % axis, "type": F,
			"default": BOX_DEFAULTS[i], "min": 0.1, "max": 2.0, "step": 0.001,
			"hard_min": 0.01, "hard_max": 4.0, "group": "Kleinian",
			"tooltip": "Half-width of the fold box along %s: a component outside +/- this is reflected back inside, every iteration." % axis,
			"effects": "Knighty's defaults (about 0.92) give the classic lattice of rings. Raising one axis stretches the cells along it; equal values give a cubic lattice; lowering a value packs the structure tighter.",
		}))
	out.append(AttributeSpec.make({
		"id": "kleinian_radius", "label": "Inversion radius", "type": F,
		"default": 1.0, "min": 0.1, "max": 2.0, "step": 0.001,
		"hard_min": 0.01, "hard_max": 4.0, "group": "Kleinian",
		"tooltip": "Radius of the inversion sphere: points inside it are pushed out through it, points outside are left alone.",
		"effects": "1 is the default. Larger values invert more of each cell, so the rings fatten and the gaps close; smaller values leave mostly the bare box lattice.",
	}))
	for i in 4:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "kleinian_shift_%d" % i, "label": "Shift %s" % axis, "type": F,
			"default": 0.0, "min": -1.0, "max": 1.0, "step": 0.001,
			"hard_min": -4.0, "hard_max": 4.0, "group": "Kleinian",
			"tooltip": "The %s component added after the inversion, every iteration." % axis,
			"effects": "0 keeps the lattice symmetric. Small shifts slide each generation of rings off the last, so the structure tilts and spirals; the w component moves to a different 3D slice of the 4D set.",
		}))
	out.append(AttributeSpec.make({
		"id": "kleinian_thickness", "label": "Thickness", "type": F,
		"default": 0.01, "min": 0.0, "max": 0.2, "step": 0.001,
		"hard_min": 0.0, "hard_max": 1.0, "group": "Kleinian",
		"tooltip": "How thick the base sheets are before the folds copy them everywhere.",
		"effects": "0.01 is Knighty's. Thicker sheets give solid, chunky walls; 0 leaves surfaces a pixel thick, like lace.",
	}))
	out.append(AttributeSpec.make({
		"id": "kleinian_view_distance", "label": "View distance", "type": F,
		"default": 1.0, "min": 1.0, "max": 100.0, "step": 0.1, "log": true,
		"hard_min": 0.5, "hard_max": 1000.0, "group": "Kleinian",
		"tooltip": "How far a ray goes from the camera before it stops. The Kleinian fills space, so without a limit every ray would march on through it.",
		"effects": "1 is the cheap starting horizon; raise it to 10 to see a few cells in every direction. The last third fades into the background, a soft horizon. Raising it shows more of the lattice at more cost per frame; lowering it is the cheapest way to speed up a slow view. The slider is logarithmic.",
	}))
	return out


## Heading tooltips for the Kleinian's group.
static func group_tooltips() -> Dictionary:
	return {
		"Kleinian": "Kleinian: a pseudo-Kleinian limit set (Knighty's). Every iteration folds the point back into a box and inverts it through a sphere; what the folds keep returning is the set, an endless lattice of curved sheets and rings.",
	}


## Whether the Kleinian is exactly self-similar (see
## MandelboxShape.self_similarity): its iteration is one fixed map (the shift
## is a constant, as in Julia mode), and its inversion magnifies everything
## inside the sphere; an inversion bends as it magnifies, but over a small
## region it is an even scale plus a mirror (conformal), as the Mandelbox's
## sphere fold is. A noise field's displacement is not carried along.
static func self_similarity(values: Dictionary, displaced := false) -> Dictionary:
	if displaced:
		return {"qualifies": false, "reason": "noise field displaces the surface"}
	return {"qualifies": true, "reason": "Kleinian: one fixed map, magnifying inside the inversion sphere"}
