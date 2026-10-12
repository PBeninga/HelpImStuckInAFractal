extends "res://src/ui/debug_overlay.gd"
## Read only gameplay telemetry, sampled once per second while visible.

const REFRESH_SECONDS := 1.0
var _game: Node
var _elapsed := 0.0

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
	if visible:
		_refresh()

func _release_game() -> void:
	if is_instance_valid(_game) and _game.tree_exiting.is_connected(_release_game):
		_game.tree_exiting.disconnect(_release_game)
	_game = null
	if visible:
		_refresh()

func _visibility_changed() -> void:
	set_process(visible)
	_elapsed = 0.0
	if visible:
		_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	var lines := PackedStringArray(["F4  GAMEPLAY", ""])
	if not is_instance_valid(_game) or _game.shape_run == null:
		lines.append("No active run")
	else:
		var params: FractalParams = _game.params
		var camera: CameraState = _game.camera
		var origin := params.run_origin
		var x: float = camera.eye_x() - origin[0]
		var y: float = camera.eye_y() - origin[1]
		var z: float = camera.eye_z() - origin[2]
		lines.append("Shape / level: %d / %d" % [params.gameplay_active + 1, _game.shapes().count()])
		lines.append("Distance from run origin: %.3f world units" % sqrt(x * x + y * y + z * z))
	lines.append("")
	lines.append("F4 to close · updates once per second")
	readout.text = "\n".join(lines)
	panel.reset_size()
	_place_panel()

func _place_panel() -> void:
	panel.position = Vector2(maxf(12.0, get_viewport().get_visible_rect().size.x - panel.size.x - 12.0), 12.0)
