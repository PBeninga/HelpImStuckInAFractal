extends "res://src/ui/debug_overlay.gd"
## Read only gameplay telemetry, refreshed on camera and run changes while visible.

var _game: Node

func _init() -> void:
	shortcut_key = KEY_F4
	shortcut_name = "GameplayShortcut"

func _ready() -> void:
	super._ready()
	# Keep both diagnostics readable when F3 and F4 are open together.
	panel.resized.connect(_place_panel)
	get_viewport().size_changed.connect(_place_panel)

func watch_game(game: Node) -> void:
	_release_game()
	_game = game
	game.tree_exiting.connect(_release_game, CONNECT_ONE_SHOT)
	game.camera.changed.connect(_refresh_if_visible)
	game.shape_run.changed.connect(_refresh_if_visible)
	game.shape_run.units_changed.connect(_refresh_if_visible)
	game.shapes().next_level_distance_changed.connect(_boundary_changed)
	_refresh_if_visible()

func _release_game() -> void:
	if is_instance_valid(_game):
		if _game.tree_exiting.is_connected(_release_game):
			_game.tree_exiting.disconnect(_release_game)
		_game.camera.changed.disconnect(_refresh_if_visible)
		_game.shape_run.changed.disconnect(_refresh_if_visible)
		_game.shape_run.units_changed.disconnect(_refresh_if_visible)
		_game.shapes().next_level_distance_changed.disconnect(_boundary_changed)
	_game = null
	_refresh_if_visible()

func _visibility_changed() -> void:
	set_process(false)
	_refresh_if_visible()

func _boundary_changed(_index: int) -> void:
	_refresh_if_visible()

func _refresh_if_visible() -> void:
	# Loading replaces the shape list before resetting the old active stage.
	if is_instance_valid(_game) and _game._loading:
		return
	if visible:
		_refresh()

func _refresh() -> void:
	var lines := PackedStringArray(["F4  GAMEPLAY", ""])
	if not is_instance_valid(_game) or _game.shape_run == null:
		lines.append("No active run")
	else:
		var params: FractalParams = _game.params
		var distance: float = _game.shape_run.distance_from_origin()
		# Retain small nonzero distances even when they fall below three decimals.
		var distance_text := DecimalSpinBox.format(distance) if distance > 0.0 and distance < 0.001 else "%.3f" % distance
		lines.append("Shape / level: %d / %d" % [params.gameplay_active + 1, _game.shapes().count()])
		lines.append("Distance from origin (spawn): %s world units" % distance_text)
		lines.append("Level boundary: > %.3f world units from origin" % params.next_level_threshold)
		var run: ShapeRun = _game.shape_run
		if run.escaped:
			lines.append("Status: Escaped")
		elif run.transitioning():
			lines.append("Status: Transitioning")
		else:
			lines.append("Status: Fly beyond the level boundary")
	lines.append("")
	lines.append("1 world unit = 1 second of travel at current speed")
	lines.append("F4 to close · updates with movement and speed")
	readout.text = "\n".join(lines)
	panel.reset_size()
	_place_panel()

func _place_panel() -> void:
	panel.position = Vector2(maxf(12.0, get_viewport().get_visible_rect().size.x - panel.size.x - 12.0), 12.0)
