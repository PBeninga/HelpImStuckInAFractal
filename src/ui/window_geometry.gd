class_name WindowGeometry
extends RefCounted
## Where the main window sits on the desktop, and how the fullscreen layout
## splits it between the view and the docked console.
##
## The first launch opens the main window over half of its screen's pixels
## (each side scaled by sqrt(1/2), so it keeps the screen's shape), centred.
## Later launches put it back where the player left it (Settings remembers the
## rect) as long as that rect is still on a connected screen; a monitor that
## has since been unplugged falls back to the default. Reset puts it back at
## the default on whichever screen it is on now.
##
## Rects are in screen pixels (the OS window's client area, as Window.position
## and Window.size report it); the title bar sits above `position`. The pure
## functions take the screen geometry as arguments so tests can feed any
## desktop; the rest read it from the DisplayServer.

## The share of the opening screen's pixels a first-run main window covers.
const DEFAULT_AREA := 0.5
## The docked console's share of a fullscreen window's width; it never gets
## narrower than DOCK_MIN_POINTS (the console's own minimum width) or wider
## than DOCK_MAX_SHARE of the window, so the view always keeps the larger part.
const DOCK_SHARE := 0.4
const DOCK_MIN_POINTS := 700.0
const DOCK_MAX_SHARE := 0.6
## How much of a remembered window, in pixels, must still be on a screen for it
## to be put back there.
const MIN_ON_SCREEN := 100
## macOS's title bar, in points.
const TITLE_POINTS := 28

## Set once place_main_window() has placed the main window, so the title menu
## and the explorer (which both call it) place it only the first time.
static var _placed := false


## A first-run main window: DEFAULT_AREA of `screen_size`'s pixels in the
## screen's own proportions, shrunk to fit `usable` (the screen minus the menu
## bar and Dock) under its `title` px title bar, and centred there.
static func default_rect(screen_size: Vector2i, usable: Rect2i, title: int) -> Rect2i:
	var side := sqrt(DEFAULT_AREA)
	var size := Vector2i(roundi(screen_size.x * side), roundi(screen_size.y * side))
	var room := usable.size - Vector2i(0, title)
	size = size.min(room)
	var pos := usable.position + Vector2i(0, title) + (room - size) / 2
	return Rect2i(pos, size)


## Whether a remembered window `rect` can be put back: big enough to be a real
## window, with its top edge (where the title bar hangs) on one of `screens`
## and at least MIN_ON_SCREEN px of it showing there.
static func restorable(rect: Rect2i, screens: Array[Rect2i]) -> bool:
	if rect.size.x < MIN_ON_SCREEN or rect.size.y < MIN_ON_SCREEN:
		return false
	for s in screens:
		var shown := s.intersection(rect)
		if shown.size.x >= MIN_ON_SCREEN and shown.size.y >= MIN_ON_SCREEN \
				and rect.position.y >= s.position.y and rect.position.y < s.end.y:
			return true
	return false


## The docked console's width in points for a fullscreen window `width` points
## wide.
static func dock_width(width: float) -> float:
	return minf(maxf(width * DOCK_SHARE, DOCK_MIN_POINTS), width * DOCK_MAX_SHARE)


## The usable rect of every connected screen (empty headless).
static func screens() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for i in DisplayServer.get_screen_count():
		var r := DisplayServer.screen_get_usable_rect(i)
		if r.has_area():
			out.append(r)
	return out


## restorable() against the screens connected now.
static func restorable_now(rect: Rect2i) -> bool:
	return restorable(rect, screens())


## The title bar's height in pixels.
static func title_px() -> int:
	return UiScale.px(Vector2i(0, TITLE_POINTS)).y


## default_rect() on `screen`, or an empty rect when the display server has no
## screen to measure (headless).
static func default_rect_on(screen: int) -> Rect2i:
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var full := DisplayServer.screen_get_size(screen)
	if not usable.has_area() or full.x <= 0 or full.y <= 0:
		return Rect2i()
	return default_rect(full, usable, title_px())


## Once per process and never on the web (the canvas follows the page): if the
## main window is still at the project's default pixel size (nothing has placed
## it yet), put it back at `remembered` when that is still on a screen, else at
## default_rect() on the screen it opened on. Without a screen to measure
## (headless) it only keeps its point size on a HiDPI screen, grown about its
## centre. A window already resized, maximised or fullscreen is left alone.
static func place_main_window(window: Window, remembered: Rect2i = Rect2i()) -> void:
	if _placed or window == null or OS.has_feature("web"):
		return
	if window.mode != Window.MODE_WINDOWED or window.size != _default_window_size():
		return
	_placed = true
	if restorable_now(remembered):
		_put(window, remembered)
		return
	var rect := default_rect_on(window.current_screen)
	if rect.has_area():
		_put(window, rect)
		return
	var target := UiScale.px(_default_window_size())
	window.position -= (target - window.size) / 2
	window.size = target


## Put the main window back at default_rect() on the screen it is on now,
## leaving maximised or fullscreen first. Never on the web.
static func reset_main_window(window: Window) -> void:
	if window == null or OS.has_feature("web"):
		return
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	var rect := default_rect_on(window.current_screen)
	if rect.has_area():
		_put(window, rect)


static func _put(window: Window, rect: Rect2i) -> void:
	window.size = rect.size
	window.position = rect.position


static func _default_window_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
		ProjectSettings.get_setting("display/window/size/viewport_height", 800))
