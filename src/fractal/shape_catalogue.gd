class_name ShapeCatalogue
extends RefCounted
## Every knob in inspector order, for every shape: the Placement group (where
## the shape sits in the scene: position, rotation, size), the Fractal group
## (which shape, and the fourth coordinate w), the Mandelbox's Box, Julia and
## Iteration rotation groups (MandelboxShape), KIFS and KIFS rotation
## (KifsShape), Kleinian (KleinianShape), Mandelbulb (MandelbulbShape), the
## precision, then the rows the whole SCENE shares — the colour mode and the
## Palette mode's controls, the lamp and its scattering, the surface's
## colour/roughness/specular, the texture and bump strengths, and the
## palette's twelve numbers. A shape's own rows show only while that shape is
## drawn.
##
## The scene is a list of shapes, each with its own table over shape_specs()
## (Placement + SHAPE_GROUPS: the ShapeParams fields), and one look table over
## scene_specs() (LIGHT_GROUPS + MATERIAL_GROUPS: the FractalParams fields).
## The console shows one collapsible shape panel per shape on its Shape tab,
## LIGHT_GROUPS on its Light tab (Light, Scattering, Picture) and
## MATERIAL_GROUPS on its Material tab (Colour, Surface, Texture, Palette).
##
## The ids are the shader uniform names (the per-shape ones as arrays indexed
## by shape; the Placement ids are consumed on the CPU into each shape's frame
## and are not uniforms) and the ShapeParams / FractalParams field names.

const F := AttributeSpec.Type.FLOAT
const ENUM := AttributeSpec.Type.ENUM
const COLOR := AttributeSpec.Type.COLOR

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


## Which groups the console's tabs show. SHAPE_GROUPS are per shape; the rest
## are the scene's.
const SHAPE_GROUPS: Array[String] = ["Placement", "Fractal", "Box", "Julia", "Iteration rotation",
	"KIFS", "KIFS rotation", "Kleinian", "Mandelbulb", "Render"]
const LIGHT_GROUPS: Array[String] = ["Light", "Scattering", "Picture"]
const MATERIAL_GROUPS: Array[String] = ["Colour", "Surface", "Texture", "Palette"]

## The Placement group's ids: resolved on the CPU into the shape's frame, never
## pushed as uniforms.
const PLACEMENT_IDS: Array[StringName] = [
	&"pos_x", &"pos_y", &"pos_z", &"rot_x", &"rot_y", &"rot_z", &"size",
]
const AXES := ["x", "y", "z"]


## A show_when for a row of `shape`'s: shown while that shape is drawn and
## `inner` (if any) also holds.
static func shown_for(shape: int, inner: Callable = Callable()) -> Callable:
	return func(values: Dictionary) -> bool:
		if int(values.get(&"shape", FractalParams.Shape.MANDELBOX)) != shape:
			return false
		return not inner.is_valid() or bool(inner.call(values))


## The predicate for the W row: shown unless the shape is the Mandelbulb, which
## is 3D and never reads w.
static func _not_3d() -> Callable:
	return func(values: Dictionary) -> bool:
		return int(values.get(&"shape", FractalParams.Shape.MANDELBOX)) != FractalParams.Shape.MANDELBULB


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
	out.append_array(shape_specs())
	out.append_array(scene_specs())
	return out


## The per-shape specs: Placement, then SHAPE_GROUPS. One AttributeTable per
## shape in the scene runs over these.
static func shape_specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []

	# --- Placement ---
	for i in 3:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "pos_%s" % axis, "label": "Position %s" % axis, "type": F,
			"default": 0.0, "min": -10.0, "max": 10.0, "step": 1e-6,
			"hard_min": -1e6, "hard_max": 1e6, "group": "Placement",
			"tooltip": "The %s coordinate of the shape's centre in the world (fractal coordinates). The shape's own origin sits here." % axis,
			"effects": "0 for every component puts the shape at the world origin, where the site's single box sits. Move a nested shape here, into a cavity of its parent; the sliders cover +/-10 and the box takes any typed value. Bind it to Time or an axis to send the shape drifting.",
		}))
	for i in 3:
		var axis: String = AXES[i]
		out.append(AttributeSpec.make({
			"id": "rot_%s" % axis, "label": "Rotation %s" % axis, "type": F,
			"default": 0.0, "min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
			"group": "Placement",
			"tooltip": "Degrees of rotation of the whole shape about the world %s axis. The three are applied x, then y, then z." % axis,
			"effects": "0 keeps the shape's lattice aligned with the world axes. Turning a nested shape a few degrees makes it read as a separate object inside its parent rather than a copy of the same lattice. Bind one to Time for a slow tumble.",
		}))
	out.append(AttributeSpec.make({
		"id": "size", "label": "Size", "type": F,
		"default": 1.0, "min": 1e-4, "max": 10.0, "step": 1e-9, "log": true,
		"hard_min": 1e-9, "hard_max": 1e3, "group": "Placement",
		"tooltip": "The shape's scale in the world: one local unit (the Mandelbox is about two across) is this many world units.",
		"effects": "1 is the site's box. A tenth is a shape that fits inside a cavity of the full-size one; a hundredth fits inside that. Each nested level should be an order of magnitude smaller than the one around it, and the march keeps full detail at any size because every shape is evaluated in its own frame. The slider is logarithmic.",
	}))

	# --- Fractal ---
	out.append(AttributeSpec.make({
		"id": "shape", "label": "Fractal", "type": ENUM,
		"default": FractalParams.Shape.MANDELBOX,
		"enum_labels": ["Mandelbox", "KIFS", "Kleinian", "Mandelbulb"],
		"enum_values": [FractalParams.Shape.MANDELBOX, FractalParams.Shape.KIFS, FractalParams.Shape.KLEINIAN,
			FractalParams.Shape.MANDELBULB],
		"group": "Fractal",
		"tooltip": "Which fractal is drawn. Each has its own rows below; only the chosen one's are shown.",
		"effects": "Mandelbox is the site's box-and-sphere-fold solid. KIFS is the kaleidoscopic family: the Menger sponge, the Sierpinski tetrahedron and their rotated, twisted relatives. Kleinian is a pseudo-Kleinian limit set, an endless lattice of curved sheets and rings whose rays stop at its View distance. Mandelbulb is the 3D cousin of the Mandelbrot set: a lobed, budding ball about 2.2 across. The camera stays put, so fly out to frame the new shape, or use Gameplay’s Return to spawn.",
	}))
	out.append(AttributeSpec.make({
		"id": "w", "label": "W", "type": F,
		"default": 0.0, "min": -4.0, "max": 4.0, "step": 0.01, "group": "Fractal",
		"show_when": _not_3d(),
		"tooltip": "The fourth coordinate of the sample point. Every shape but the Mandelbulb is a 4D field; the viewer flies through the w = 0 slice by default. Hidden on the Mandelbulb, which is 3D.",
		"effects": "0 is the familiar 3D shape. Moving w slides the whole view to a different 3D slice of the 4D shape, which can reveal entirely new structure. Bind it to an axis or Time to glide between slices.",
	}))

	out.append_array(_only_on(MandelboxShape.specs(), FractalParams.Shape.MANDELBOX))
	out.append_array(_only_on(KifsShape.specs(), FractalParams.Shape.KIFS))
	out.append_array(_only_on(KleinianShape.specs(), FractalParams.Shape.KLEINIAN))
	out.append_array(_only_on(MandelbulbShape.specs(), FractalParams.Shape.MANDELBULB))

	# --- Render ---
	out.append(AttributeSpec.make({
		"id": "precision", "label": "Precision", "type": F,
		"default": 0.000025, "min": 1e-6, "max": 1e-3, "step": 1e-6, "log": true,
		"group": "Render",
		"tooltip": "The surface threshold: the ray stops when the distance estimate drops below precision times the distance travelled.",
		"effects": "Smaller values resolve finer detail at the cost of more steps (and a slower frame); larger values are faster but rounder and noisier near the surface. The default (2.5e-5) is the site's. The slider is logarithmic.",
	}))
	return out


## The scene's specs: LIGHT_GROUPS and MATERIAL_GROUPS, shared by every shape.
## The one look table runs over these.
static func scene_specs() -> Array[AttributeSpec]:
	var out: Array[AttributeSpec] = []

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

	# --- Light ---
	out.append(AttributeSpec.make({
		"id": "light_color", "label": "Light colour", "type": COLOR,
		"default": Color(1, 1, 1), "group": "Light",
		"tooltip": "The colour of the lamp. Every lit mode's colour is multiplied by it.",
		"effects": "White (the default) leaves every mode exactly as it is. Warm it for a sunset, cool it for moonlight; it also tints the scattering haze.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_yaw", "label": "Light yaw", "type": F,
		"default": 0.0, "min": -180.0, "max": 180.0, "step": 0.1, "wrap": true,
		"group": "Light",
		"tooltip": "Degrees to swing the light left or right, about the camera's up axis.",
		"effects": "0 is the site's headlight, which follows the camera. Turning it rakes the light across the surface so the relief shows; bind it to Time and the light orbits.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_pitch", "label": "Light pitch", "type": F,
		"default": 0.0, "min": -90.0, "max": 90.0, "step": 0.1,
		"group": "Light",
		"tooltip": "Degrees to tip the light up or down, about the camera's right axis.",
		"effects": "0 is the site's headlight. Positive raises the light above the view, negative drops it below; either way the light rakes across faces it used to hit head on.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_size", "label": "Light size", "type": F,
		"default": 0.0, "min": 0.0, "max": 30.0, "step": 0.1, "hard_max": 89.0,
		"group": "Light",
		"tooltip": "How wide the lamp is, in degrees. A point light at 0; a broad source above it.",
		"effects": "0 is the site's pin-sharp glints and hard shadows. Widening it spreads the glint into a soft sheen and softens the shadow edge (a wider penumbra).",
	}))
	out.append(AttributeSpec.make({
		"id": "light_ambient", "label": "Ambient", "type": F,
		"default": 0.1, "min": 0.0, "max": 1.0, "step": 0.01, "hard_max": 4.0,
		"group": "Light",
		"tooltip": "Light every surface gets whichever way it faces.",
		"effects": "0.1 is the site's. Raising it lifts the shadowed sides and flattens the picture; 0 leaves faces turned away from the light black (in the modes that multiply by the light).",
	}))
	out.append(AttributeSpec.make({
		"id": "light_diffuse", "label": "Diffuse", "type": F,
		"default": 0.5, "min": 0.0, "max": 2.0, "step": 0.01, "hard_max": 8.0,
		"group": "Light",
		"tooltip": "Matte light: brightest where the surface faces the light, falling off as it turns away (|N·L|).",
		"effects": "0.5 is the site's. More gives stronger form and contrast between faces; 0 leaves only ambient and the specular glints.",
	}))
	out.append(AttributeSpec.make({
		"id": "shadows", "label": "Shadows", "type": F,
		"default": 0.0, "min": 0.0, "max": 1.0, "step": 0.01,
		"group": "Light",
		"tooltip": "How dark the lamp's shadows are. 0 is off (no shadow ray cast).",
		"effects": "0 is the site's look, with no shadow march. Towards 1 the surface casts shadows of itself, which costs one extra ray per pixel and drops out first under load. Only works when the light is swung off the headlight (Light yaw or pitch non-zero); a headlight casts no visible shadow.",
	}))

	# --- Scattering ---
	out.append(AttributeSpec.make({
		"id": "fog_distance", "label": "Fog distance", "type": F,
		"default": 0.0, "min": 0.0, "max": 400.0, "step": 0.1, "hard_max": 1000000.0,
		"group": "Scattering",
		"tooltip": "Distance from the camera where fog becomes fully opaque and rays stop. 0 is off.",
		"effects": "In multiples of the camera's distance to the nearest surface, so it follows your zoom. Shorter distances skip more distant geometry and its shading. Also clips shadow rays to the same fog sphere. Stays active when still, independently of Density and the performance governor.",
	}))
	out.append(AttributeSpec.make({
		"id": "fog_start", "label": "Fog fade start", "type": F,
		"default": 0.35, "min": 0.0, "max": 0.99, "step": 0.01,
		"group": "Scattering",
		"tooltip": "Where fog starts fading in, as a fraction of Fog distance.",
		"effects": "0 fades from the camera; 0.35 leaves the first 35% clear; near 1 makes a narrow fog wall. Fog always reaches full opacity at Fog distance. Has no effect when Fog distance is 0.",
	}))
	out.append(AttributeSpec.make({
		"id": "fog_tint", "label": "Fog colour", "type": COLOR,
		"default": Color(0.2, 0.2, 0.2), "group": "Scattering",
		"tooltip": "The solid colour at and beyond the fog wall.",
		"effects": "Distant surfaces and the background fade into this colour, concealing the ray cutoff. Independent of the light-tinted Density haze. Has no effect when Fog distance is 0.",
	}))
	out.append(AttributeSpec.make({
		"id": "scatter_density", "label": "Density", "type": F,
		"default": 0.0, "min": 0.0, "max": 0.5, "step": 0.001, "hard_max": 10.0,
		"group": "Scattering",
		"tooltip": "How thick the haze filling the space is. 0 is off.",
		"effects": "Measured in near-distance units, so it looks the same at any zoom. Small values add depth; large values wash the scene toward the light's colour.",
	}))
	out.append(AttributeSpec.make({
		"id": "scatter_glow", "label": "Glow", "type": F,
		"default": 0.0, "min": 0.0, "max": 0.95, "step": 0.01,
		"group": "Scattering",
		"tooltip": "How much the haze bunches around the light's direction (a forward-scatter bias).",
		"effects": "0 is an even haze. Towards 1 it becomes a bright beam around the lamp, like looking near the sun through mist. (It sets the g in the Henyey-Greenstein phase: how sharply light prefers to carry on forwards.)",
	}))
	out.append(AttributeSpec.make({
		"id": "scatter_brightness", "label": "Brightness", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 16.0,
		"group": "Scattering",
		"tooltip": "How bright the haze is, multiplied by the light's colour.",
		"effects": "1 is a middling haze. Below 1 is a dim fog; above 1 blooms the beam. 0 makes the haze black (a dark fog).",
	}))

	# --- Picture ---
	out.append(AttributeSpec.make({
		"id": "exposure", "label": "Exposure", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 16.0,
		"group": "Picture",
		"tooltip": "Multiplies the final colour of every mode but Grayscale.",
		"effects": "1 leaves the picture alone. Above 1 brightens it (the bright end clips to white first); below 1 darkens it.",
	}))
	out.append(AttributeSpec.make({
		"id": "saturation", "label": "Saturation", "type": F,
		"default": 1.0, "min": 0.0, "max": 2.0, "step": 0.01, "hard_max": 4.0,
		"group": "Picture",
		"tooltip": "How colourful the final picture is, in every mode but Grayscale.",
		"effects": "1 leaves the colours alone, 0 is greys, above 1 pushes the colours harder (the ice goes electric blue).",
	}))

	# --- Surface ---
	out.append(AttributeSpec.make({
		"id": "surface_color", "label": "Surface colour", "type": COLOR,
		"default": Color(1, 1, 1), "group": "Surface",
		"tooltip": "A colour the surface is multiplied by, under every lit mode.",
		"effects": "White (the default) leaves every mode as it is. Use it to tint the whole surface without changing its shading.",
	}))
	out.append(AttributeSpec.make({
		"id": "roughness", "label": "Roughness", "type": F,
		"default": 1.0 / 9.0, "min": 0.02, "max": 1.0, "step": 0.001, "log": true,
		"group": "Surface",
		"tooltip": "How rough the surface is: low is glassy with tight glints, high is matte. Replaces the old Shininess.",
		"effects": "1/9 (the default) is the site's pin-point sparkle. Towards 1 the glint spreads into a broad sheen; towards 0.02 it tightens to a few pixels. (The specular exponent is 2/roughness² − 2, so smaller roughness means a tighter highlight.) The slider is logarithmic.",
	}))
	out.append(AttributeSpec.make({
		"id": "light_specular", "label": "Specular", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 16.0,
		"group": "Surface",
		"tooltip": "The strength of the glints where a surface faces the light almost exactly.",
		"effects": "1 is the site's: the bright sparkle on the ice. 0 removes the glints for a chalky look; above 1 they bloom.",
	}))

	# --- Texture ---
	out.append(AttributeSpec.make({
		"id": "texture_strength", "label": "Texture", "type": F,
		"default": 1.0, "min": 0.0, "max": 1.0, "step": 0.01,
		"group": "Texture",
		"tooltip": "How much the noise editor's Texture output recolours the surface. 0 leaves the colour alone.",
		"effects": "The surface colour is multiplied by a blend from white toward the Texture colour by this amount. 1 uses the Texture output in full; nothing wired means nothing changes whatever this is.",
	}))
	out.append(AttributeSpec.make({
		"id": "bump_strength", "label": "Bump", "type": F,
		"default": 1.0, "min": 0.0, "max": 4.0, "step": 0.01, "hard_max": 64.0,
		"group": "Texture",
		"tooltip": "How much the noise editor's Bump output tilts the surface normal (a fake relief; the surface does not actually move).",
		"effects": "0 is flat. Larger values deepen the apparent bumps and grooves. Nothing wired means nothing changes; press N to open the editor.",
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


## Heading tooltips, one per group: each shape's own, plus Placement, Fractal,
## Render, Colour, Light, Scattering, Picture, Surface, Texture and Palette.
static func group_tooltips() -> Dictionary:
	var out := {
		"Placement": "Placement: where this shape sits in the scene. A world point is moved by -Position, rotated back by the three Rotations and divided by Size before the fractal is evaluated, so the shape itself is the same at any size. Nest shapes by placing a smaller one inside a cavity of a larger one.",
		"Fractal": "Fractal: which shape is drawn, and the 3D slice of its 4D field the camera flies through (the Mandelbulb is 3D, so it has no slice). The rows below change with the shape.",
		"Render": "Render: how finely the ray march resolves the surface. A look-and-cost knob, not a shape knob.",
		"Colour": "Colour: which colouring mode paints the surface and, for the Palette mode, what runs it along the palette.",
		"Light": "Light: the one lamp every lit colour mode shares, a headlight following the camera by default. Each value's default is the site's, so the default picture is unchanged until you move one.",
		"Scattering": "Scattering: a persistent fog wall that stops rays at Fog distance (0 is off), plus light-tinted haze controlled by Density (0 is off).",
		"Picture": "Picture: adjustments on the final colour of every mode but Grayscale.",
		"Surface": "Surface: what the surface is made of — its colour, how rough it is, and how strong the glints are.",
		"Texture": "Texture: the noise editor's Texture and Bump outputs drive these. Nothing wired, nothing changes; press N to open the editor.",
		"Palette": "Palette: the twelve numbers of the cosine palette color(t) = A + B · cos(2π (C·t + D)), one row per vector and channel. The Colour window's sliders edit the same values; these rows add a Source, gain and waveform to each, so a channel can pulse, ripple or cycle on its own.",
	}
	out.merge(MandelboxShape.group_tooltips())
	out.merge(KifsShape.group_tooltips())
	out.merge(KleinianShape.group_tooltips())
	out.merge(MandelbulbShape.group_tooltips())
	return out


## Whether the fractal being drawn is exactly self-similar, for the Shape
## tab's read-only line: each shape's own rule (MandelboxShape, KifsShape,
## KleinianShape, MandelbulbShape .self_similarity). `values` maps catalogue ids to resolved
## values, missing ids reading as their defaults; `displaced` is whether a
## noise field moves the surface. Returns {"qualifies": bool, "reason": String}.
static func self_similarity(values: Dictionary, displaced := false) -> Dictionary:
	match int(values.get(&"shape", FractalParams.Shape.MANDELBOX)):
		FractalParams.Shape.KIFS:
			return KifsShape.self_similarity(values, displaced)
		FractalParams.Shape.KLEINIAN:
			return KleinianShape.self_similarity(values, displaced)
		FractalParams.Shape.MANDELBULB:
			return MandelbulbShape.self_similarity(values, displaced)
	return MandelboxShape.self_similarity(values, displaced)


## Every catalogue id, in order: shape_ids() then scene_ids().
static func catalogue_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in specs():
		out.append(s.id)
	return out


## The per-shape ids, in order: ShapeParams.RESOLVED_KEYS.
static func shape_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in shape_specs():
		out.append(s.id)
	return out


## The scene's ids, in order: FractalParams.RESOLVED_KEYS.
static func scene_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in scene_specs():
		out.append(s.id)
	return out


## The per-shape ids the shader declares as uniform arrays: shape_ids() without
## the Placement group.
static func shader_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in shape_ids():
		if not PLACEMENT_IDS.has(id):
			out.append(id)
	return out
