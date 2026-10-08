class_name MandelboxShape
extends RefCounted
## The Mandelbox's own knobs, in inspector order: the Box group (the fold and
## its shape, the abs-fold hybrid, the sphere fold and the scale), per-component
## Julia with four constants, and the six iteration rotation angles. The shared
## rows (the shape switch, w, precision, colour, lighting, palette) are
## ShapeCatalogue's, which assembles every shape's rows and shows these only
## while the Mandelbox is drawn.
## Ranges are Fractacular's, widened where the site's slider went further;
## defaults are the site's, so the opening view is the one we have.
##
## The ids are the shader uniform names and the FractalParams field names.

const F := AttributeSpec.Type.FLOAT
const BOOL := AttributeSpec.Type.BOOL
const ENUM := AttributeSpec.Type.ENUM

enum FoldOrder { BOX_THEN_SPHERE, SPHERE_THEN_BOX }
## What the fold step reflects through (the shader's fold_shape).
enum FoldShape { BOX, CYLINDER, OCTAHEDRAL }

const AXES := ["x", "y", "z", "w"]
## The six coordinate pairs, in the shader's fixed rotation order.
const PLANE_PAIRS := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]


## The predicate for one Julia constant row: shown while its own toggle or the
## master toggle is on. A helper so the Callable captures one id, never a loop
## variable.
static func _julia_shown(julia_id: StringName) -> Callable:
	return func(values: Dictionary) -> bool:
		return bool(values.get(&"julia_all", false)) or bool(values.get(julia_id, false))


static func specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []

	# --- Box ---
	out.append(AttributeSpec.make({
		"id": "box_scale", "label": "Scale", "type": F,
		"default": -2.09, "min": -5.0, "max": 3.0, "step": 0.01,
		"hard_min": -6.0, "hard_max": 6.0, "group": "Box",
		"tooltip": "The multiplier applied after the two folds. This is the Mandelbox's primary topology knob.",
		"effects": "2 is the classic box. -1.5 is the famous 'amazing box', all curved shells. |s| < 1 collapses the solid into dust. Negative values invert the lattice, turning beams into holes. Values past +/-3 are mostly noise but worth a look. Bind it to an axis for a continuous tour of the whole family.",
	}))
	out.append(AttributeSpec.make({
		"id": "fold_limit", "label": "Fold limit", "type": F,
		"default": 1.0, "min": 0.0, "max": 3.0, "step": 0.01, "group": "Box",
		"tooltip": "Half-width L of the box fold: any component outside +/-L is reflected back inside as clamp(p, -L, L)*2 - p.",
		"effects": "1 is standard. Smaller values fold sooner, producing tighter, busier lattices; larger values leave more of the point untouched and give sparse, blobby shapes.",
	}))
	out.append(AttributeSpec.make({
		"id": "min_radius", "label": "Min radius", "type": F,
		"default": 0.7, "min": 0.0, "max": 2.0, "step": 0.01, "group": "Box",
		"tooltip": "Inner radius mR of the sphere fold: points closer than this to the origin are inflated by (fR/mR) squared.",
		"effects": "The ratio Fixed radius / Min radius sets the thickness of the shells. 0.5 with a fixed radius of 1 is standard; raising it toward the fixed radius thins the shells to filaments, lowering it fattens them into blobs.",
	}))
	out.append(AttributeSpec.make({
		"id": "fixed_radius", "label": "Fixed radius", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "group": "Box",
		"tooltip": "Outer radius fR of the sphere fold: points between the min and fixed radius are inverted through the sphere of this radius.",
		"effects": "1 is standard. Larger values push the structure outward into wide shells; values below the min radius disable the inversion and leave a plain folded lattice.",
	}))
	out.append(AttributeSpec.make({
		"id": "fold_order", "label": "Fold order", "type": ENUM,
		"default": FoldOrder.BOX_THEN_SPHERE,
		"enum_labels": ["Box → Sphere", "Sphere → Box"],
		"enum_values": [FoldOrder.BOX_THEN_SPHERE, FoldOrder.SPHERE_THEN_BOX],
		"group": "Box",
		"tooltip": "Which fold runs first inside each iteration.",
		"effects": "Box then Sphere is the standard Mandelbox. Sphere then Box is a different fractal with the same knobs: usually rounder, with the box lattice showing through the shells rather than the other way round.",
	}))
	out.append(AttributeSpec.make({
		"id": "fold_shape", "label": "Fold shape", "type": ENUM,
		"default": FoldShape.BOX,
		"enum_labels": ["Box", "Cylinder", "Octahedral"],
		"enum_values": [FoldShape.BOX, FoldShape.CYLINDER, FoldShape.OCTAHEDRAL],
		"group": "Box",
		"tooltip": "What the fold reflects the point back inside of: the box (every component within +/-Fold limit), a cylinder (the xy radius within Fold limit) or an octahedron (|x| + |y| + |z| within Fold limit).",
		"effects": "Box is the classic Mandelbox. Cylinder rounds the lattice about the z axis into rings and tubes. Octahedral cuts it along diagonal planes into faceted, crystal-like shells. Fold limit sets the size of each.",
	}))
	out.append(AttributeSpec.make({
		"id": "hybrid_mix", "label": "Hybrid mix", "type": F,
		"default": 0.0, "min": 0.0, "max": 1.0, "step": 0.01, "group": "Box",
		"tooltip": "On the hybrid iterations (Hybrid every), how far the fold morphs from the box fold toward the abs fold, KIFS's fold into the positive corner. The box fold reflects each component back inside [-L, L]; the morph slides that interval to [0, infinity), where it is |x|.",
		"effects": "0 is the plain Mandelbox, and Hybrid every does nothing. 1 swaps in the abs fold outright on those iterations, the classic box/abs (KIFS) hybrid. In between the shape morphs continuously; bind it to an axis or Time to sweep from one to the other. The hybrid iterations use this morph whatever the Fold shape.",
	}))
	out.append(AttributeSpec.make({
		"id": "hybrid_every", "label": "Hybrid every", "type": ENUM,
		"default": 2,
		"enum_labels": ["Every iteration", "Every 2nd", "Every 3rd"],
		"enum_values": [1, 2, 3],
		"group": "Box",
		"tooltip": "Which iterations the hybrid mix applies on.",
		"effects": "Every 2nd alternates the two folds, the classic hybrid; every 3rd keeps more of the box; every iteration is the most KIFS-like, and at a mix of 1 needs a gentler Scale (try -1.5) or nothing is left. Does nothing while Hybrid mix is 0.",
	}))
	out.append(AttributeSpec.make({
		"id": "scale_drift", "label": "Scale drift", "type": F,
		"default": 0.0, "min": -0.1, "max": 0.1, "step": 0.001,
		"hard_min": -1.0, "hard_max": 1.0, "group": "Box",
		"tooltip": "Added to Scale once per iteration: iteration i uses Scale + drift x i.",
		"effects": "0 keeps the scale constant. A small drift makes the fine detail a different fractal from the large shapes: away from zero it grows blockier, toward zero wispier. The deepest iterations feel it most, so 0.01 to 0.03 is already a lot.",
	}))

	# --- Julia ---
	out.append(AttributeSpec.make({
		"id": "julia_all", "label": "Julia (all)", "type": BOOL,
		"default": false, "group": "Julia",
		"tooltip": "Master switch: add the constant on every component, whatever the four per-component boxes say.",
		"effects": "Off with no component checked is the plain Mandelbox, where each pixel iterates from its own position. On is the Julia Mandelbox: one single shape. Every constant row becomes visible while this is on.",
	}))
	for i in 4:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "julia_%d" % i, "label": "Julia %s" % axis, "type": BOOL,
			"default": false, "group": "Julia",
			"tooltip": "Add the fixed constant on the %s component instead of the sample point's own %s coordinate." % [axis, axis],
			"effects": "Unchecked, %s behaves Mandelbrot-like (each pixel starts from itself). Checked, it behaves Julia-like. Checking some components and not others gives hybrids that exist in neither the classic Mandelbox nor the classic Julia box." % axis,
		}))
	var c_defaults := [-0.23, 1.512, 1.892, 0.0]
	for i in 4:
		var axis: String = AXES[i]
		var julia_id := StringName("julia_%d" % i)
		out.append(AttributeSpec.make({
			"id": "c_%d" % i, "label": "Constant %s" % axis, "type": F,
			"default": c_defaults[i], "min": -4.0, "max": 4.0, "step": 0.001,
			"hard_min": -16.0, "hard_max": 16.0, "group": "Julia",
			"show_when": _julia_shown(julia_id),
			"tooltip": "The %s component of the Julia constant. Used while Julia %s (or Julia (all)) is checked; the row is hidden otherwise." % [axis, axis],
			"effects": "Small constants (inside +/-1) give dense, connected boxes; larger ones blow the structure apart into dust. Bind a constant to an axis and the whole shape morphs as you move, the most direct way to explore the family.",
		}))

	# --- Iteration rotation ---
	for pair in PLANE_PAIRS:
		var a: String = AXES[pair[0]]
		var b: String = AXES[pair[1]]
		out.append(AttributeSpec.make({
			"id": "iter_rot_%s%s" % [a, b], "label": "Iter rotation %s%s" % [a, b],
			"type": F, "default": 0.0,
			"min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
			"group": "Iteration rotation",
			"tooltip": "Degrees of rotation in the %s-%s plane, applied inside every iteration between the folds and the scale." % [a, b],
			"effects": "0 leaves the lattice axis-aligned. A few degrees twists the beams into spirals; tens of degrees shred the box into curved filaments. Because the rotation compounds once per iteration, tiny changes here matter more than anywhere else - try 1-5 degrees first, and bind one angle to Time for a slow churn.",
		}))

	return out


## Heading tooltips for the Mandelbox's groups.
static func group_tooltips() -> Dictionary:
	return {
		"Box": "Box: the fold-and-scale step repeated at every pixel. The fold reflects the point back inside a box, cylinder or octahedron of size Fold limit (or, on hybrid iterations, morphs toward the abs fold); the sphere fold inflates points inside Min radius and inverts the shell out to Fixed radius; then everything is multiplied by Scale (plus any drift).",
		"Julia": "Julia: which components add a fixed constant instead of the pixel's own coordinate. None checked is the plain Mandelbox; all four checked is a Julia Mandelbox; mixtures are hybrids.",
		"Iteration rotation": "Iteration rotation: a 4D rotation applied inside every iteration, between the folds and the scale. This changes the fractal itself, not just the view.",
	}
