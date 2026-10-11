class_name MainMenu
extends Control
## The title screen: "Icebox Nav" over Engage Hyperdrive (story mode: the
## failed jump and the support call), Free Explore (the explorer), Settings and
## Quit. Settings swaps the list for the shared SettingsMenu.

const GAME_SCENE := "res://src/main.tscn"
const STORY_SCENE := "res://src/story/story.tscn"
## The main window's size in points (logical units); see UiScale.
const WINDOW_SIZE := Vector2i(1280, 800)

var story_button: Button
## Free Explore: the explorer without the story.
var play_button: Button
var settings_button: Button
var quit_button: Button
var settings_menu: SettingsMenu

var _list: VBoxContainer


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
	var tagline := Label.new()
	tagline.text = "Help, I'm stuck in a fractal"
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 22)
	tagline.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_list.add_child(tagline)
	_list.add_child(Control.new())   # a gap under the title
	story_button = MenuButtons.make("Engage Hyperdrive")
	play_button = MenuButtons.make("Free Explore")
	settings_button = MenuButtons.make("Settings")
	quit_button = MenuButtons.make("Quit")
	for b in [story_button, play_button, settings_button, quit_button]:
		_list.add_child(b)
	# A browser tab cannot be quit from inside the page.
	quit_button.visible = not OS.has_feature("web")
	stack.add_child(_list)

	settings_menu = SettingsMenu.new()
	settings_menu.visible = false
	stack.add_child(settings_menu)

	story_button.pressed.connect(play_story)
	play_button.pressed.connect(play)
	settings_button.pressed.connect(show_settings.bind(true))
	quit_button.pressed.connect(func(): get_tree().quit())
	settings_menu.back.connect(show_settings.bind(false))
	story_button.grab_focus.call_deferred()


func play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func play_story() -> void:
	get_tree().change_scene_to_file(STORY_SCENE)


func show_settings(on: bool) -> void:
	_list.visible = not on
	settings_menu.visible = on
	(settings_menu.back_button if on else settings_button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"cancel") and settings_menu.visible:
		show_settings(false)
		get_viewport().set_input_as_handled()
