class_name BindingResolver
extends RefCounted
## Pure functions that turn (table defaults, bindings, axis values, clock) into a
## Dictionary of attribute id -> value. No nodes, no rendering; unit-tested
## headlessly.
##
##   raw   = axis value (any axis id)   or   t   (&"time")   or   0 (unknown)
##   wave  = raw | sin(2π raw/period) | triangle(raw/period) in [-1, 1]
##   value = default + gain * wave, then wrap or clamp via the spec; INT rounds.
##
## COLOR defaults are non-bindable, so they pass through untouched: the
## `not spec.bindable` branch below returns the default Color as-is.


## Resolve every attribute for one frame.
static func resolve(table: AttributeTable, axis_values: Dictionary, t: float) -> Dictionary:
	var out := {}
	for s in table.specs:
		out[s.id] = resolve_value(s, table.get_default(s.id), table.binding(s.id), axis_values, t)
	return out


## The value set with every binding treated as inactive (the plain defaults).
static func resolve_defaults(table: AttributeTable) -> Dictionary:
	return table.defaults()


static func resolve_value(spec: AttributeSpec, default_value: Variant, binding: Binding, axis_values: Dictionary, t: float) -> Variant:
	if binding == null or not binding.is_active() or not spec.bindable:
		return default_value
	var raw := 0.0
	if binding.source == &"time":
		raw = t
	elif axis_values.has(binding.source):
		raw = float(axis_values[binding.source])
	# An unknown axis id leaves raw at 0, so a view bound to an axis the keymap
	# lacks shows its default, not garbage.
	var value := float(default_value) + binding.gain * waveform_value(raw, binding.waveform, binding.period)
	return spec.sanitize(value)


static func waveform_value(raw: float, waveform: Binding.Waveform, period: float) -> float:
	var p := maxf(period, 1e-6)
	match waveform:
		Binding.Waveform.SINE:
			return sin(TAU * raw / p)
		Binding.Waveform.TRIANGLE:
			# 0 at raw=0, +1 at p/4, 0 at p/2, -1 at 3p/4.
			return 1.0 - 4.0 * absf(fposmod(raw / p + 0.25, 1.0) - 0.5)
	return raw
