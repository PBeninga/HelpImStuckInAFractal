class_name ShapeCatalogue
extends RefCounted
## Every knob in inspector order, for every shape: the Fractal group (which
## shape, and the fourth coordinate w), the Mandelbox's Box, Julia and
## Iteration rotation groups (MandelboxShape), KIFS and KIFS rotation
## (KifsShape), Kleinian (KleinianShape), then the rows every shape shares —
## the precision, the colour mode and the Palette mode's controls, the
## lighting, and the palette's twelve numbers. A shape's own rows show only
## while that shape is drawn. The console shows SHAPE_GROUPS on its Shape tab
## and COLOUR_GROUPS on its Colour tab.
##
## The ids are the shader uniform names and the FractalParams field names.

const F := AttributeSpec.Type.FLOAT
const ENUM := AttributeSpec.Type.ENUM

## What picks the position along the palette (the shader's palette_source).
enum PaletteSource { STEPS, RADIUS, NORMAL }

const CHANNEL_WORDS := ["red", "green", "blue"]
const PALETTE_VECTOR_TIPS := [
	"the middle level the channel oscillates around.",
	"the contrast: how far the channel swings either side of A.",
	"how many times the channel cycles across one pass of the palette.",
	"where the channel starts in its cycle, in turns (wraps at 1).",
]
const PALETTE_VECTOR_EFFECTS := [
	"0.5 is balanced. Lowering one channel's A tints the whole palette away from that colour; A above 1 − B clips the bright end flat.",
	"0 freezes the channel at its A level; 0.5 with A at 0.5 uses the full range. A sine binding here makes the channel pulse.",
	"1 is one smooth sweep. Different values per channel make long, non-repeating runs; a Linear binding to Time makes the colours ripple.",
	"Channels a third of a turn apart (0, 0.33, 0.67) make the default rainbow; all three equal gives greys. A Linear binding to Time cycles the channel's hue.",
]


## Which groups the console's two tabs show.
const SHAPE_GROUPS: Array[String] = ["Fractal", "Box", "Julia", "Iteration rotation",
	"KIFS", "KIFS rotation", "Kleinian", "Render"]
const COLOUR_GROUPS: Array[String] = ["Colour", "Lighting", "Palette"]


## A show_when for a row of `shape`'s: shown while that shape is drawn and
## `inner` (if any) also holds.
static func shown_for(shape: int, inner: Callable = Callable()) -> Callable:
	return func(values: Dictionary) -> bool:
		if int(values.get(&"shape", FractalParams.Shape.MANDELBOX)) != shape:
			return false
		return not inner.is_valid() or bool(inner.call(values))


## The predicate for the Palette mode's rows: shown only while the Colour mode
## is Palette.
static func _palette_shown() -> Callable:
	return func(values: Dictionary) -> bool:
		return int(values.get(&"color_mode", 0)) == Palette.MODE_ID


## Limit every spec in `list` to `shape`, keeping its own show_when.
static func _only_on(list: Array[AttributeSpec], shape: int) -> Array[AttributeSpec]:
	for s in list:
		s.show_when = shown_for(shape, s.show_when)
	return list


static func specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []

	# --- Fractal ---
	out.append(AttributeSpec.make({
		"id": "shape", "label": "Fractal", "type": ENUM,
		"default": FractalParams.Shape.MANDELBOX,
		"enum_labels": ["Mandelbox", "KIFS", "Kleinian"],
		"enum_values": [FractalParams.Shape.MANDELBOX, FractalParams.Shape.KIFS, FractalParams.Shape.KLEINIAN],
		"group": "Fractal",
		"tooltip": "Which fractal is drawn. Each has its own rows below; only the chosen one's are shown.",
		"effects": "Mandelbox is the site's box-and-sphere-fold solid. KIFS is the kaleidoscopic family: the Menger sponge, the Sierpinski tetrahedron and their rotated, twisted relatives. Kleinian is a pseudo-Kleinian limit set, an endless lattice of curved sheets and rings whose rays stop at its View distance. The camera stays put, so fly out (or Reset camera) to frame the new shape.",
	}))
	out.append(AttributeSpec.make({
		"id": "w", "label": "W", "type": F,
		"default": 0.0, "min": -4.0, "max": 4.0, "step": 0.01, "group": "Fractal",
		"tooltip": "The fourth coordinate of the sample point. Every shape is a 4D field; the viewer flies through the w = 0 slice by default.",
		"effects": "0 is the familiar 3D shape. Moving w slides the whole view to a different 3D slice of the 4D shape, which can reveal entirely new structure. Bind it to an axis or Time to glide between slices.",
	}))

	out.append_array(_only_on(MandelboxShape.specs(), FractalParams.Shape.MANDELBOX))
	out.append_array(_only_on(KifsShape.specs(), FractalParams.Shape.KIFS))
	out.append_array(_only_on(KleinianShape.specs(), FractalParams.Shape.KLEINIAN))

	# --- Render ---
	out.append(AttributeSpec.make({
		"id": "precision", "label": "Precision", "type": F,
		"default": 0.000025, "min": 1e-6, "max": 1e-3, "step": 1e-6, "log": true,
		"group": "Render",
		"tooltip": "The surface threshold: the ray stops when the distance estimate drops below precision times the distance travelled.",
		"effects": "Smaller values resolve finer detail at the cost of more steps (and a slower frame); larger values are faster but rounder and noisier near the surface. The default (2.5e-5) is the site's. The slider is logarithmic.",
	}))

	# --- Colour ---
	var mode_values: Array[int] = []
	var mode_labels: Array[String] = []
	for i in FractalParams.COLOR_MODE_IDS.size():
		mode_values.append(FractalParams.COLOR_MODE_IDS[i])
		mode_labels.append(FractalParams.COLOR_MODE_NAMES[i])
	out.append(AttributeSpec.make({
		"id": "color_mode", "label": "Colour", "type": ENUM,
		"default": 1, "enum_labels": mode_labels, "enum_values": mode_values,
		"group": "Colour",
		"tooltip": "How the surface is coloured. Thirteen modes are the site's looks, keyed off the step count, the surface normal and the camera; Palette paints with your own cosine palette from the Colour window.",
		"effects": "Ice Fractal is the default blue-white look and uses the field normal for modes 1 through 9 on the Mandelbox outside Julia mode (the true surface normal everywhere else). Grayscale is the cheapest (no normal, no lighting). Rainbow and Ice Box modes map the orbit or the normal through a hue ramp. Palette runs the step count, the radius or the normal through the palette above.",
	}))
	out.append(AttributeSpec.make({
		"id": "palette_source", "label": "Palette input", "type": ENUM,
		"default": PaletteSource.STEPS,
		"enum_labels": ["Steps", "Radius", "Normal"],
		"enum_values": [PaletteSource.STEPS, PaletteSource.RADIUS, PaletteSource.NORMAL],
		"group": "Colour", "show_when": _palette_shown(),
		"tooltip": "Which value picks the position along the palette at each pixel.",
		"effects": "Steps is the march's step count: open faces sit at the start of the palette and deep crevices further along, the same quantity the Ice modes are built on. Radius is the hit point's squared distance from the centre, so the colour runs in shells. Normal is the surface's facing (its z component), so the colour follows the slope like a landscape lit from above.",
	}))
	out.append(AttributeSpec.make({
		"id": "palette_frequency", "label": "Palette frequency", "type": F,
		"default": 1.0, "min": 0.0, "max": 8.0, "step": 0.01,
		"hard_min": -64.0, "hard_max": 64.0,
		"group": "Colour", "show_when": _palette_shown(),
		"tooltip": "How fast the input runs along the palette: position = fract(input × frequency + offset).",
		"effects": "1 spreads the input's range over one pass of the palette. Higher values repeat the palette in bands (contour lines on Radius, rings in the crevices on Steps); 0 paints one flat colour picked by the offset.",
	}))
	out.append(AttributeSpec.make({
		"id": "palette_offset", "label": "Palette offset", "type": F,
		"default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001, "wrap": true,
		"group": "Colour", "show_when": _palette_shown(),
		"tooltip": "Where on the palette the input starts, in whole passes (it wraps at 1).",
		"effects": "Slides every pixel along the palette by the same amount. Bind it to Time for a colour cycle that flows through the surface.",
	}))
	out.append(AttributeSpec.make({
		"id": "palette_occlusion", "label": "Palette occlusion", "type": F,
		"default": 0.5, "min": 0.0, "max": 1.0, "step": 0.01,
		"group": "Colour", "show_when": _palette_shown(),
		"tooltip": "How much the step count darkens the palette colour, a cheap stand-in for ambient occlusion.",
		"effects": "0 leaves crevices as bright as open faces (flat, poster-like); 1 lets the deepest crevices fall to black, the depth cue every site mode relies on. 0.5 is a balance.",
	}))

	# --- Lighting ---
	out.append(AttributeSpec.make({
		"id": "light_ambient", "label": "Ambient", "type": F,
		"default": 0.1, "min": 0.0, "max": 1.0, "step": 0.01, "hard_max": 4.0,
		"group": "Lighting",
		"tooltip": "Light every surface gets whichever way it faces.",
		"effects": "0.1 is the site's. Raising it lifts the shadowed sides and flattens the picture; 0 leaves faces turned away from the light black (in the modes that multiply by the light).",
	}))
	out.append(AttributeSpec.make({
		"id": "light_diffuse", "label": "Diffuse", "type": F,
		"default": 0.5, "min": 0.0, "max": 2.0, "step": 0.01, "hard_max": 8.0,
		"group": "Lighting",
		"tooltip": "Matte light: brightest where the surface faces the light, falling off as it turns away (|N·L|).",
		"effects": "0.5 is the site's. More gives stronger form and contrast between faces; 0 leaves only ambient and the specular glints.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_specular", "label": "Specular", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 16.0,
		"group": "Lighting",
		"tooltip": "The strength of the glints where a surface faces the light almost exactly.",
		"effects": "1 is the site's: the bright sparkle on the ice. 0 removes the glints for a chalky look; above 1 they bloom.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_shininess", "label": "Shininess", "type": F,
		"default": 160.0, "min": 1.0, "max": 512.0, "step": 0.1, "log": true,
		"group": "Lighting",
		"tooltip": "The specular exponent: how tightly the glints are focused ((N·L) to this power).",
		"effects": "160 is the site's: pin-point sparkles. Low values (4 to 20) spread the glint into a broad sheen, like wet plastic; very high values leave only a few pixels lit. The slider is logarithmic.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_yaw", "label": "Light yaw", "type": F,
		"default": 0.0, "min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
		"group": "Lighting",
		"tooltip": "Degrees to swing the light left or right, about the camera's up axis.",
		"effects": "0 is the site's headlight, which follows the camera. Turning it rakes the light across the surface so the relief shows; bind it to Time and the light orbits.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_pitch", "label": "Light pitch", "type": F,
		"default": 0.0, "min": -90.0, "max": 90.0, "step": 0.1,
		"group": "Lighting",
		"tooltip": "Degrees to tip the light up or down, about the camera's right axis.",
		"effects": "0 is the site's headlight. Positive raises the light above the view, negative drops it below; either way the light rakes across faces it used to hit head on.",
	}))
	out.append(AttributeSpec.make({
		"id": "exposure", "label": "Exposure", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 16.0,
		"group": "Lighting",
		"tooltip": "Multiplies the final colour of every mode but Grayscale.",
		"effects": "1 leaves the picture alone. Above 1 brightens it (the bright end clips to white first); below 1 darkens it.",
	}))
	out.append(AttributeSpec.make({
		"id": "saturation", "label": "Saturation", "type": F,
		"default": 1.0, "min": 0.0, "max": 2.0, "step": 0.01, "hard_max": 4.0,
		"group": "Lighting",
		"tooltip": "How colourful the final picture is, in every mode but Grayscale.",
		"effects": "1 leaves the colours alone, 0 is greys, above 1 pushes the colours harder (the ice goes electric blue).",
	}))

	# --- Palette (the twelve cosine-palette numbers, edited in the Colour window) ---
	for v in 4:
		for ch in 3:
			var r: Vector2 = Palette.RANGES[v]
			out.append(AttributeSpec.make({
				"id": Palette.id(v, ch),
				"label": "%s %s" % [Palette.VECTOR_NAMES[v], CHANNEL_WORDS[ch]],
				"type": F, "default": Palette.DEFAULT_COMPONENTS[v * 3 + ch],
				"min": r.x, "max": r.y, "step": Palette.STEP,
				"hard_max": 16.0 if v == 2 else r.y,
				"wrap": v == 3,
				"group": "Palette", "show_when": _palette_shown(),
				"tooltip": "%s, %s channel: %s" % [Palette.VECTOR_NAMES[v], CHANNEL_WORDS[ch], PALETTE_VECTOR_TIPS[v]],
				"effects": PALETTE_VECTOR_EFFECTS[v],
			}))

	return out


## Heading tooltips, one per group: each shape's own, plus Fractal, Render,
## Colour, Lighting and Palette.
static func group_tooltips() -> Dictionary:
	var out := {
		"Fractal": "Fractal: which shape is drawn, and the 3D slice of its 4D field the camera flies through. The rows below change with the shape.",
		"Render": "Render: how finely the ray march resolves the surface. A look-and-cost knob, not a shape knob.",
		"Colour": "Colour: which colouring mode paints the surface and, for the Palette mode, what runs it along the palette.",
		"Lighting": "Lighting: the light every lit colour mode shares, a headlight following the camera by default. Each value's default is the site's, so the default picture is unchanged until you move one.",
		"Palette": "Palette: the twelve numbers of the cosine palette color(t) = A + B · cos(2π (C·t + D)), one row per vector and channel. The Colour window's sliders edit the same values; these rows add a Source, gain and waveform to each, so a channel can pulse, ripple or cycle on its own.",
	}
	out.merge(MandelboxShape.group_tooltips())
	out.merge(KifsShape.group_tooltips())
	out.merge(KleinianShape.group_tooltips())
	return out


## Every catalogue id, in order. Equals the shader's shape-uniform set.
static func catalogue_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in specs():
		out.append(s.id)
	return out
