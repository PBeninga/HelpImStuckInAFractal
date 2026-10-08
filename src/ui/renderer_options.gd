class_name RendererOptions
extends VBoxContainer
## The settings menu's Renderer tab. Edits the open view's FractalParams: how
## detail falls off with distance from the camera, the march's step budget, Fast
## Controls and the lowest render scale it may use. These are saved with the view.
## Its Reset camera button asks Main to put the camera back where the current
## file has it.

signal reset_camera_requested

var detail_slider: HSlider
var range_slider: HSlider
var falloff_slider: HSlider
var steps_slider: HSlider
var fast_check: CheckBox
var min_scale_slider: HSlider
var reset_button: Button
var reset_camera_button: Button

var _params: FractalParams
var _values := {}   # slider -> its value Label
var _syncing := false


func _init() -> void:
	name = "Renderer"
	add_theme_constant_override("separation", 12)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)

	detail_slider = _slider(grid, "Detail", FractalParams.DETAIL_MIN, FractalParams.DETAIL_MAX, 0.01, true,
		"Scales the precision everywhere. Higher resolves finer structure and costs more steps.")
	range_slider = _slider(grid, "Full-detail range", FractalParams.DETAIL_RANGE_MIN, FractalParams.DETAIL_RANGE_MAX, 0.1, true,
		"How far full detail reaches, in multiples of the camera's distance to the nearest surface. Beyond it, detail falls off.")
	falloff_slider = _slider(grid, "Detail falloff", 0.0, FractalParams.DETAIL_FALLOFF_MAX, 0.05, false,
		"How quickly detail coarsens past the full-detail range. 0 keeps the plain pixel cone: detail matched to the pixel at every distance.")
	steps_slider = _slider(grid, "Max march steps", FractalParams.MAX_STEPS_MIN, FractalParams.MAX_STEPS_MAX, 16, false,
		"The step budget per ray (three quarters coarse, a quarter fine). Rays that run out render as the darkest shade.")
	min_scale_slider = _slider(grid, "Min resolution", FractalParams.RENDER_SCALE_FLOOR, 1.0, 0.05, false,
		"With Fast Controls on, the lowest render scale used while moving to hold 30 fps.")

	fast_check = CheckBox.new()
	fast_check.text = "Fast Controls"
	fast_check.tooltip_text = "Lower the resolution while moving to hold 30 fps; render one full frame when still."
	add_child(fast_check)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	reset_button = Button.new()
	reset_button.text = "Reset renderer defaults"
	buttons.add_child(reset_button)
	reset_camera_button = Button.new()
	reset_camera_button.text = "Reset camera"
	reset_camera_button.tooltip_text = "Put the camera's position, view and speed factor back where the current save file has them (the starting view when no file is loaded)."
	buttons.add_child(reset_camera_button)

	detail_slider.value_changed.connect(func(v): _write(func(): _params.detail = v))
	range_slider.value_changed.connect(func(v): _write(func(): _params.detail_range = v))
	falloff_slider.value_changed.connect(func(v): _write(func(): _params.detail_falloff = v))
	steps_slider.value_changed.connect(func(v): _write(func(): _params.max_steps = int(v)))
	min_scale_slider.value_changed.connect(func(v): _write(func(): _params.min_render_scale = v))
	fast_check.toggled.connect(func(on): _write(func(): _params.fast_controls = on))
	reset_button.pressed.connect(reset_defaults)
	reset_camera_button.pressed.connect(reset_camera_requested.emit)


func setup(params: FractalParams) -> void:
	if _params != null and _params.changed.is_connected(_refresh):
		_params.changed.disconnect(_refresh)
	_params = params
	params.changed.connect(_refresh)
	_refresh()


## Put every option on this tab back to FractalParams' defaults.
func reset_defaults() -> void:
	if _params == null:
		return
	var d := FractalParams.new()
	_params.detail = d.detail
	_params.detail_range = d.detail_range
	_params.detail_falloff = d.detail_falloff
	_params.max_steps = d.max_steps
	_params.min_render_scale = d.min_render_scale
	_params.fast_controls = d.fast_controls


func _write(action: Callable) -> void:
	if _syncing or _params == null:
		return
	action.call()


func _refresh() -> void:
	if _params == null:
		return
	_syncing = true
	detail_slider.set_value_no_signal(_params.detail)
	range_slider.set_value_no_signal(_params.detail_range)
	falloff_slider.set_value_no_signal(_params.detail_falloff)
	steps_slider.set_value_no_signal(_params.max_steps)
	min_scale_slider.set_value_no_signal(_params.min_render_scale)
	fast_check.set_pressed_no_signal(_params.fast_controls)
	_values[detail_slider].text = "x%.2f" % _params.detail
	_values[range_slider].text = "%.1fx" % _params.detail_range
	_values[falloff_slider].text = "off" if _params.detail_falloff == 0.0 else "%.2f" % _params.detail_falloff
	_values[steps_slider].text = str(_params.max_steps)
	_values[min_scale_slider].text = "%d%%" % roundi(_params.min_render_scale * 100.0)
	min_scale_slider.editable = _params.fast_controls
	_syncing = false


func _slider(grid: GridContainer, label: String, lo: float, hi: float, step: float,
		exponential: bool, tip: String) -> HSlider:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS   # so the tooltip shows
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.exp_edit = exponential
	s.tooltip_text = tip
	s.custom_minimum_size = Vector2(240, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new()
	v.custom_minimum_size = Vector2(64, 0)
	grid.add_child(l)
	grid.add_child(s)
	grid.add_child(v)
	_values[s] = v
	return s
