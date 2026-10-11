class_name SessionLaunch
extends RefCounted
## Whether this boot was started by a Claude Code session and so runs out of the
## way: its window parked off screen bar a few pixels, with tools/launch.sh
## handing focus back. The same rules as Spellgraft's SessionLaunch /
## BackgroundWindow.
##
## - `-- --background-window` parks the window.
## - Otherwise a Claude Code session (CLAUDECODE=1, inherited by every game it
##   launches) parks it too, unless `-- --foreground-window` or FRACTAL_PLAY=1
##   hands the launch to a person.

const CLAUDE_SESSION_VAR := "CLAUDECODE"
## "1" hands a Claude-launched game back to a person: a normal window and focus.
const PLAY_VAR := "FRACTAL_PLAY"
const BACKGROUND_FLAG := "--background-window"
const FOREGROUND_FLAG := "--foreground-window"
## Window pixels left on screen, per side of the corner square. Godot draws no
## frame unless part of the window is visible, so a few stay showing.
const VISIBLE_CORNER_PIXELS := 4


## Pure: `args` are the command-line (user) args, `env` looks a variable up
## (returning "" when unset).
static func parks_window(args: PackedStringArray, env: Callable) -> bool:
	if BACKGROUND_FLAG in args:
		return true
	if FOREGROUND_FLAG in args:
		return false
	return env.call(CLAUDE_SESSION_VAR) == "1" and env.call(PLAY_VAR) != "1"


static func is_requested() -> bool:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return false
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return parks_window(args, OS.get_environment)


## Float the window above every other and park it in the usable area's
## bottom-right corner. Captures read the viewport texture, not the screen, so
## they still come out full size.
static func park_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(usable.end - Vector2i(VISIBLE_CORNER_PIXELS, VISIBLE_CORNER_PIXELS))
