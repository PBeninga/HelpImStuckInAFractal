class_name UiScale
extends RefCounted
## Owns the one fact "how many pixels is a logical unit". The project leaves
## HiDPI on, so on a 2x screen (a Retina Mac, or a browser at devicePixelRatio
## 2) window sizes are physical pixels and, unscaled, every font, grip and
## dropdown came out half size. Each native window applies factor() as its
## content scale and sizes itself in px(). (Where the main window opens, and how
## big, is WindowGeometry's.)
##
## An EMBEDDED window (the noise window: the project embeds sub-windows, and
## headless and the web embed every one, the console included) is drawn inside
## its embedder's canvas and so already inherits the embedder's scale: it keeps
## factor 1 and is sized in logical units, or it would scale twice. The console
## sets force_native, so on the desktop it is a native window like the root.
##
## The main window also follows its own size (follow_size): the menus and HUD
## are laid out for a 1280x800-point window, so a bigger window (maximised, full
## screen, a large browser tab) multiplies its content scale by how much bigger
## it is, and the UI grows with it instead of shrinking into the middle. It never
## shrinks below factor(): a small window keeps readable text.

## The most a big window multiplies the scale by.
const MAX_FIT := 4.0

## Tests set this to stand in for the screen's scale; 0 means ask the display.
static var override := 0.0

## Pixels per logical unit: the override, else the screen's scale clamped into
## [1, 4]. Headless reports 1.
static func factor() -> float:
	if override > 0.0:
		return override
	return clampf(DisplayServer.screen_get_scale(), 1.0, 4.0)


## The content scale `window` should use: factor() when it is (or will be) a
## native window, 1 when it is embedded.
static func factor_for(window: Window) -> float:
	return 1.0 if _is_embedded(window) else factor()


## Give `window` its content scale. A window already using a stretch mode is
## left alone: someone else (the UI test driver's root) owns its scaling.
## Idempotent.
static func apply(window: Window) -> void:
	if window == null or window.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		return
	window.content_scale_factor = factor_for(window)


## `logical` in pixels: at factor() by default, or at the factor `window` uses.
static func px(logical: Vector2i, window: Window = null) -> Vector2i:
	var f := factor() if window == null else factor_for(window)
	return Vector2i(roundi(logical.x * f), roundi(logical.y * f))


## How much bigger a window of `window_px` pixels is than `base_px` (the design
## size in pixels): the smaller of the two ratios, so the design still fits, and
## never below 1 or above MAX_FIT.
static func fit(window_px: Vector2i, base_px: Vector2i) -> float:
	if base_px.x <= 0 or base_px.y <= 0:
		return 1.0
	var r := minf(float(window_px.x) / base_px.x, float(window_px.y) / base_px.y)
	return clampf(r, 1.0, MAX_FIT)


## Keep `window`'s content scale at factor() * fit() of its size against
## `logical` (the design size in points), now and on every resize. Like apply(),
## a stretched window is left alone, and so is an embedded one (it inherits its
## embedder's scale). Idempotent: the root outlives the scene that asked.
static func follow_size(window: Window, logical: Vector2i) -> void:
	if window == null or _is_embedded(window):
		return
	window.set_meta(&"ui_scale_logical", logical)
	if not window.has_meta(&"ui_scale_following"):
		window.set_meta(&"ui_scale_following", true)
		window.size_changed.connect(_refit.bind(window))
	_refit(window)


static func _refit(window: Window) -> void:
	if window.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		return
	var logical: Vector2i = window.get_meta(&"ui_scale_logical", _default_window_size())
	var f := factor() * fit(window.size, px(logical))
	if not is_equal_approx(window.content_scale_factor, f):
		window.content_scale_factor = f


## Points per unit of `window`'s canvas: above 1 once follow_size() has grown
## its content scale past factor().
static func points_per_unit(window: Window) -> float:
	return window.content_scale_factor / factor()


## Put `window` over `parent_window`. Embedded: centred in the embedder's
## visible rect, never above its top-left (the title bar stays reachable).
## Native: centred over the parent window in screen pixels.
static func center_over(window: Window, parent_window: Window) -> void:
	if window.is_embedded():
		var embedder := _embedder(window)
		if embedder == null:
			return
		var rect := embedder.get_visible_rect()
		var top_left := Vector2i(rect.position) + (Vector2i(rect.size) - window.size) / 2
		var title := window.get_theme_constant(&"title_height")
		window.position = Vector2i(maxi(top_left.x, int(rect.position.x)),
			maxi(top_left.y, int(rect.position.y) + title))
	elif parent_window != null:
		window.position = parent_window.position + (parent_window.size - window.size) / 2


## Put a native `window` BESIDE `parent_window`, never over it: on macOS (Godot
## 4.6.1, GL Compatibility) a native window overlapping the main window corrupts
## the main window's picture. An embedded window is centred over instead.
static func place_beside(window: Window, parent_window: Window) -> void:
	if window.is_embedded() or parent_window == null:
		center_over(window, parent_window)
		return
	var screens: Array[Rect2i] = []
	var current := parent_window.current_screen
	screens.append(DisplayServer.screen_get_usable_rect(current))
	for i in DisplayServer.get_screen_count():
		if i != current:
			screens.append(DisplayServer.screen_get_usable_rect(i))
	# A hidden native window has no OS window yet to measure.
	var title := WindowGeometry.title_px()
	window.position = beside_position(window.size, title,
		Rect2i(parent_window.position, parent_window.size), screens)


## Where a window of `size` (client area; `title` px of title bar sit above it)
## goes so it does not cover `parent` (client rect, in screen pixels), as a pure
## function of the geometry. `screens` are usable rects, the parent's first.
## In order: right of the parent, left of it, on another screen (centred),
## and, when nothing fits, against the side of the parent's screen with more
## room (overlap is then unavoidable; the player can drag it away).
static func beside_position(size: Vector2i, title: int, parent: Rect2i, screens: Array[Rect2i]) -> Vector2i:
	var gap := px(Vector2i(8, 8)).x
	if screens.is_empty() or not screens[0].has_area():
		return Vector2i(parent.end.x + gap, parent.position.y)
	var home := screens[0]
	var y := clampi(parent.position.y, home.position.y + title, maxi(home.position.y + title, home.end.y - size.y))
	var right := parent.end.x + gap
	if right + size.x <= home.end.x:
		return Vector2i(right, y)
	var left := parent.position.x - gap - size.x
	if left >= home.position.x:
		return Vector2i(left, y)
	for i in range(1, screens.size()):
		var s := screens[i]
		if s.size.x >= size.x and s.size.y >= size.y + title:
			return s.position + Vector2i(0, title) + (s.size - Vector2i(0, title) - size) / 2
	if home.end.x - parent.end.x >= parent.position.x - home.position.x:
		return Vector2i(maxi(home.position.x, home.end.x - size.x), y)
	return Vector2i(home.position.x, y)


static func _default_window_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
		ProjectSettings.get_setting("display/window/size/viewport_height", 800))


## In the tree, ask the window. Not yet (ConsoleWindow sizes itself before Main
## adds it): it will be native when it forces that and the display server has
## native sub-windows (headless and the web do not), otherwise embedded exactly
## when the root embeds sub-windows, which Godot forces on headless and the web.
static func _is_embedded(window: Window) -> bool:
	if window.is_inside_tree():
		return window.is_embedded()
	if window.force_native and DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root != null and tree.root.gui_embed_subwindows


## The viewport an embedded window is drawn in: the nearest viewport above it
## that embeds sub-windows. (Window.get_embedder() is not exposed to scripts.)
static func _embedder(window: Window) -> Viewport:
	var parent := window.get_parent()
	var vp: Viewport = parent.get_viewport() if parent != null else null
	while vp != null and not vp.gui_embed_subwindows:
		var above := vp.get_parent()
		vp = above.get_viewport() if above != null else null
	return vp
