class_name PaletteStrip
extends Control
## The palette drawn end to end: t running 0 → 1 from left to right.
##
## It is the answer to "what will the fractal actually look like?", which is
## why it is worth its height in the window — twelve sliders say nothing on
## their own. Drawn as a row of `draw_rect` slices rather than a texture or a
## gradient resource, so there is nothing to allocate, nothing to free when
## the palette changes, and nothing that needs a GPU to exist.

const TOOLTIP := "The palette from end to end: the run of colours the Palette colour mode paints with. Palette offset picks where on this strip the surface starts and Palette frequency how fast it runs through."

## Enough slices that the seams are invisible at any sensible window width.
const SLICES := 256

var _palette: Palette
var _redraws := 0


## Which palette to draw. Call before adding the strip to the tree.
func setup(palette: Palette) -> void:
	_palette = palette


func _ready() -> void:
	custom_minimum_size.y = 40
	tooltip_text = TOOLTIP
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _palette != null:
		_palette.changed.connect(_on_palette_changed)


## The colour this strip paints a fraction of the way across it. The tests use
## it to check the strip against the model without needing a rendered pixel.
func color_at_fraction(fraction: float) -> Color:
	if _palette == null:
		return Color.BLACK
	return _palette.color_at(clampf(fraction, 0.0, 1.0))


## How many times the palette has asked for a repaint. Headless-safe: it
## counts the requests, not the draws, which is what the wiring is about.
func redraw_count() -> int:
	return _redraws


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var step := w / float(SLICES)
	for i in SLICES:
		var t := (float(i) + 0.5) / float(SLICES)
		# One extra pixel of width so neighbouring slices overlap instead of
		# leaving hairline gaps where the rounding falls badly.
		draw_rect(Rect2(float(i) * step, 0.0, step + 1.0, h), color_at_fraction(t))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 1.0)


func _on_palette_changed() -> void:
	_redraws += 1
	queue_redraw()
