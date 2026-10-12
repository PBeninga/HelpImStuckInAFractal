class_name MainMenu
extends Control
## The title screen: "Icebox Nav" over Play Game, Settings and Quit. Settings
## swaps the list for the shared SettingsMenu. The console edits a prepared
## explorer; Play activates that same instance, preserving unsaved edits.

const GAME_SCENE := "res://src/main.tscn"
## The main window's size in points (logical units); see UiScale.
const WINDOW_SIZE := Vector2i(1280, 800)

var play_button: Button
var settings_button: Button
var quit_button: Button
var settings_menu: SettingsMenu

var _list: VBoxContainer
var _center: CenterContainer
var _prepared_game: Main
var _leaving := false


func _ready() -> void:
	# The game starts here, so this is where a HiDPI screen first gets its scale
	# and the window its place (where the player last left it).
	UiScale.apply(get_window())
	WindowGeometry.place_main_window(get_window(), Settings.window_rect(&"main"))
	UiScale.follow_size(get_window(), WINDOW_SIZE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	_center = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 48)
	center.add_child(stack)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Icebox Nav"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	_list.add_child(title)
	_list.add_child(Control.new())   # a gap under the title
	play_button = MenuButtons.make("Play Game")
	settings_button = MenuButtons.make("Settings")
	quit_button = MenuButtons.make("Quit")
	for b in [play_button, settings_button, quit_button]:
		_list.add_child(b)
	# A browser tab cannot be quit from inside the page.
	quit_button.visible = not OS.has_feature("web")
	stack.add_child(_list)

	settings_menu = SettingsMenu.new()
	settings_menu.visible = false
	stack.add_child(settings_menu)

	play_button.pressed.connect(play, CONNECT_DEFERRED)
	settings_button.pressed.connect(show_settings.bind(true))
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.back.connect(show_settings.bind(false))
	play_button.grab_focus.call_deferred()
	_prepare_game.call_deferred()


func _prepare_game() -> void:
	if _leaving or is_instance_valid(_prepared_game) or not is_inside_tree():
		return
	_prepared_game = load(GAME_SCENE).instantiate() as Main
	_prepared_game.preparing = true
	# Keep it under the root so Play never removes its windows or signal
	# subscriptions from the tree. Only the menu is the active scene for now.
	get_tree().root.add_child(_prepared_game)
	get_tree().root.move_child(_prepared_game, get_index())


func _process(_delta: float) -> void:
	if is_instance_valid(_prepared_game):
		# Leave room for the console when fullscreen docks it inside this window.
		_center.offset_right = _prepared_game.view.offset_right


func _exit_tree() -> void:
	if is_instance_valid(_prepared_game):
		_prepared_game.queue_free()


func play() -> void:
	if _leaving:
		return
	_prepare_game()
	_leaving = true
	var game := _prepared_game
	_prepared_game = null
	game.begin_play()
	get_tree().current_scene = game
	queue_free()


func show_settings(on: bool) -> void:
	_list.visible = not on
	settings_menu.visible = on
	(settings_menu.back_button if on else settings_button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel") and settings_menu.visible:
		show_settings(false)
		get_viewport().set_input_as_handled()
