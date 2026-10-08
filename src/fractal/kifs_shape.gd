class_name KifsShape
extends RefCounted
## The KIFS's knobs, in inspector order: the KIFS group (scale, fold set, the
## polyfold's k, the twist and the 4D offset) and the KIFS rotation group (the
## six angles of R1, before the fold, and of R2, after it). Ported from
## Fractacular's kifs technique; defaults make the Menger sponge.
##
## The ids are the shader uniform names and the FractalParams field names.

const F := AttributeSpec.Type.FLOAT
const ENUM := AttributeSpec.Type.ENUM

const AXES := ["x", "y", "z", "w"]
const OFFSET_DEFAULTS := [1.0, 1.0, 1.0, 0.0]


## The predicate for the polyfold's k: shown only with the Polyfold.
static func _polyfold_shown() -> Callable:
	return func(values: Dictionary) -> bool:
		return int(values.get(&"kifs_fold", 0)) == KifsEstimator.FoldSet.POLYFOLD


static func specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []

	out.append(AttributeSpec.make({
		"id": "kifs_scale", "label": "Scale", "type": F,
		"default": 3.0, "min": 1.05, "max": 4.0, "step": 0.01,
		"hard_min": 1.01, "hard_max": 6.0, "group": "KIFS",
		"tooltip": "The scale s every iteration multiplies by, away from the offset: p = s·p − (s − 1)·offset.",
		"effects": "3 with the Coordinate fold is the Menger sponge; 2 with the Diagonal fold is the Sierpinski tetrahedron. Lower values overlap the copies into a dense, blobby solid; higher values thin them to dust. It stops above 1, where there is no fractal.",
	}))
	out.append(AttributeSpec.make({
		"id": "kifs_fold", "label": "Fold set", "type": ENUM,
		"default": KifsEstimator.FoldSet.COORDINATE,
		"enum_labels": ["Coordinate", "Diagonal", "Polyfold"],
		"enum_values": [KifsEstimator.FoldSet.COORDINATE, KifsEstimator.FoldSet.DIAGONAL, KifsEstimator.FoldSet.POLYFOLD],
		"group": "KIFS",
		"tooltip": "The fold every iteration applies, which sets the shape's symmetry.",
		"effects": "Coordinate folds into the positive corner and sorts x >= y >= z: cube symmetry, the Menger sponge. Diagonal reflects across x = −y, x = −z, y = −z (and x = −w): tetrahedral symmetry, the Sierpinski tetrahedron at scale 2. Polyfold mirrors the xy angle into k-fold wedges before the Coordinate fold; it is sparser, so try a scale of 2 to 2.5.",
	}))
	out.append(AttributeSpec.make({
		"id": "kifs_poly_k", "label": "Polyfold k", "type": F,
		"default": 5.0, "min": 2.0, "max": 12.0, "step": 1.0,
		"hard_min": 2.0, "hard_max": 32.0, "group": "KIFS",
		"show_when": _polyfold_shown(),
		"tooltip": "The Polyfold's symmetry: the xy plane is folded into 2k mirror-image wedges. Rounded to a whole number.",
		"effects": "3 gives a triangular cross-section, 5 a five-pointed star, high values approach a cylinder. Bound to an axis it steps from one symmetry to the next.",
	}))
	out.append(AttributeSpec.make({
		"id": "kifs_twist", "label": "Twist", "type": F,
		"default": 0.0, "min": -45.0, "max": 45.0, "step": 0.1,
		"hard_min": -180.0, "hard_max": 180.0, "group": "KIFS",
		"tooltip": "Degrees of extra rotation in the xy plane that grows with the iteration: iteration i turns by twist × i.",
		"effects": "0 keeps the copies aligned. A few degrees spirals the fine detail about the z axis while the large shape barely moves; larger values shred it.",
	}))
	for i in 4:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "kifs_offset_%d" % i, "label": "Offset %s" % axis, "type": F,
			"default": OFFSET_DEFAULTS[i], "min": -3.0, "max": 3.0, "step": 0.01,
			"hard_min": -8.0, "hard_max": 8.0, "group": "KIFS",
			"tooltip": "The %s component of the offset: the fixed point every iteration scales away from." % axis,
			"effects": "(1, 1, 1, 0) is the corner of the unit cube, which makes the Menger sponge and the Sierpinski tetrahedron. Small changes move where the copies sit and reshape everything; the w component lifts the shape off the w = 0 slice.",
		}))

	for r in 2:
		var which := "rot%d" % (r + 1)
		for pair in MandelboxShape.PLANE_PAIRS:
			var a: String = AXES[pair[0]]
			var b: String = AXES[pair[1]]
			out.append(AttributeSpec.make({
				"id": "kifs_%s_%s%s" % [which, a, b], "label": "R%d %s%s" % [r + 1, a, b],
				"type": F, "default": 0.0,
				"min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
				"group": "KIFS rotation",
				"tooltip": "Degrees of rotation in the %s-%s plane, applied %s the fold in every iteration." % [a, b, "before" if r == 0 else "after"],
				"effects": "Rotating before the fold changes which part of space each fold sees: the copies turn against each other and the sponge breaks into twisted, asymmetric towers. Small angles go a long way; bind one to Time for a slow churn." if r == 0 else "Rotating after the fold turns the copies themselves before they are scaled, so the detail spins at every scale at once. 0 keeps the classic shapes.",
			}))
	return out


## Heading tooltips for the KIFS's groups.
static func group_tooltips() -> Dictionary:
	return {
		"KIFS": "KIFS: a kaleidoscopic IFS. Every iteration folds space into one wedge, then scales it away from the offset, so the shape is made of smaller copies of itself.",
		"KIFS rotation": "KIFS rotation: two 4D rotations inside every iteration, R1 before the fold and R2 after it. These change the fractal itself, not the view.",
	}
