class_name MainMenu
extends Control
## The title screen: "Icebox Nav" over Play Game, Settings and Quit. Settings
## swaps the list for the shared SettingsMenu. Play loads the explorer.

const GAME_SCENE := "res://src/main.tscn"
## The main window's size in points (logical units); see UiScale.
const WINDOW_SIZE := Vector2i(1280, 800)

var play_button: Button
var settings_button: Button
var quit_button: Button
var settings_menu: SettingsMenu

var _list: VBoxContainer


func _ready() -> void:
	# The game starts here, so this is where a HiDPI screen first gets its scale.
	UiScale.apply(get_window())
	UiScale.fit_main_window(get_window(), WINDOW_SIZE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
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

	play_button.pressed.connect(play)
	settings_button.pressed.connect(show_settings.bind(true))
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.back.connect(show_settings.bind(false))
	play_button.grab_focus.call_deferred()


func play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func show_settings(on: bool) -> void:
	_list.visible = not on
	settings_menu.visible = on
	(settings_menu.back_button if on else settings_button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and settings_menu.visible:
		show_settings(false)
		get_viewport().set_input_as_handled()
