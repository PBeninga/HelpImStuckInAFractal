class_name PaletteCurves
extends Control
## The three cosine curves behind the palette, plotted over t ∈ [0, 1].
##
## The strip below it shows *what* colour comes out; this shows *why*. A flat
## line is a channel with no contrast, a line pinned to the top or the bottom
## is one being clamped away, and two lines in step are a palette that can
## only make greys. None of that is visible in the strip alone.
##
## Drawn as three polylines in `_draw()`, so it needs no texture and works the
## same whether or not anything has been rendered yet.

const TOOLTIP := "The red, green and blue curves the palette is made of, plotted left to right over one pass. Height is the channel's level: a flat line is a channel that never varies, a line squashed against the top or bottom is one being clamped, and curves in step make greys."

## Points per curve. Cheap, and smooth enough for four cycles of C.
const SAMPLES := 128

const CHANNEL_COLORS := [
	Color(1.0, 0.45, 0.45), Color(0.45, 1.0, 0.5), Color(0.5, 0.65, 1.0)]

var _palette: Palette
var _redraws := 0


## Which palette to plot. Call before adding the plot to the tree.
func setup(palette: Palette) -> void:
	_palette = palette


func _ready() -> void:
	custom_minimum_size.y = 90
	tooltip_text = TOOLTIP
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _palette != null:
		_palette.changed.connect(_on_palette_changed)


## The sampled curve for one channel (0 = r, 1 = g, 2 = b) as levels in
## [0, 1], left to right. Exposed so the plot can be checked without pixels.
func channel_levels(channel: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _palette == null:
		return out
	for i in SAMPLES:
		var t := float(i) / float(SAMPLES - 1)
		var c := _palette.color_at(t)
		out.append([c.r, c.g, c.b][clampi(channel, 0, 2)])
	return out


func redraw_count() -> int:
	return _redraws


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.25), false, 1.0)
	if _palette == null:
		return
	for channel in 3:
		var levels := channel_levels(channel)
		var points := PackedVector2Array()
		for i in levels.size():
			var x := float(i) / float(maxi(levels.size() - 1, 1)) * w
			# Level 1 is the top of the box, so the y axis is flipped.
			points.append(Vector2(x, h - levels[i] * h))
		draw_polyline(points, CHANNEL_COLORS[channel], 1.5, true)


func _on_palette_changed() -> void:
	_redraws += 1
	queue_redraw()
