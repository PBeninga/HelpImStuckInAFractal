extends "res://tests/test_case.gd"
## UiScale: the factor honours the override and clamps the screen's scale; apply()
## scales a native window and leaves an embedded one (and a stretched one) alone;
## px() converts logical units; fit_main_window() keeps a default-sized main
## window at its point size once; center_over() centres an embedded window in
## its embedder; beside_position() keeps a native window off the main window;
## fit() and follow_size() grow the main window's scale with its size.


func run() -> void:
	# --- factor: the screen's scale (headless reports 1), clamped into [1, 4] ---
	UiScale.override = 0.0
	var screen := DisplayServer.screen_get_scale()
	check_approx(UiScale.factor(), clampf(screen, 1.0, 4.0), "factor() is the screen scale, clamped")
	check(UiScale.factor() >= 1.0 and UiScale.factor() <= 4.0, "factor() stays within [1, 4]")
	UiScale.override = 2.0
	check_approx(UiScale.factor(), 2.0, "an override replaces the screen scale")

	# --- px: logical units to pixels ---
	check_eq(UiScale.px(Vector2i(1000, 700)), Vector2i(2000, 1400), "px() doubles at factor 2")
	UiScale.override = 1.5
	check_eq(UiScale.px(Vector2i(1000, 700)), Vector2i(1500, 1050), "px() scales by a fractional factor")
	UiScale.override = 2.0

	# --- apply: a native window takes the factor; an embedded one keeps 1 ---
	var embedding: bool = root.gui_embed_subwindows
	root.gui_embed_subwindows = false   # windows made now would be native
	var native := Window.new()
	native.content_scale_factor = 1.0
	UiScale.apply(native)
	check_eq(native.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, "apply() keeps the content scale mode DISABLED")
	check_approx(native.content_scale_factor, 2.0, "apply() gives a native window the factor")
	UiScale.apply(native)
	check_approx(native.content_scale_factor, 2.0, "apply() is idempotent")
	check_eq(UiScale.px(Vector2i(1000, 700), native), Vector2i(2000, 1400), "px() for a native window uses the factor")
	native.free()
	root.gui_embed_subwindows = true    # headless: every window is embedded
	var embedded := Window.new()
	embedded.content_scale_factor = 3.0
	UiScale.apply(embedded)
	check_approx(embedded.content_scale_factor, 1.0,
		"an embedded window keeps factor 1: it is drawn inside its embedder's scale")
	check_eq(UiScale.px(Vector2i(1000, 700), embedded), Vector2i(1000, 700), "px() for an embedded window is 1:1")
	embedded.free()
	root.gui_embed_subwindows = embedding

	# a window someone else stretches (the UI test driver's root) is left alone
	var stretched := Window.new()
	stretched.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	stretched.content_scale_factor = 1.0
	UiScale.apply(stretched)
	check_eq(stretched.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "a stretched window keeps its mode")
	check_approx(stretched.content_scale_factor, 1.0, "and its factor")
	stretched.free()

	# --- fit_main_window: once, and only at the project's default pixel size ---
	var default_size := Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))
	var resized := Window.new()
	resized.size = Vector2i(900, 600)
	UiScale.fit_main_window(resized, Vector2i(1280, 800))
	check_eq(resized.size, Vector2i(900, 600), "a window the player resized is left alone")
	resized.free()
	var main_window := Window.new()
	main_window.size = default_size
	UiScale.fit_main_window(main_window, Vector2i(1280, 800))
	check_eq(main_window.size, Vector2i(2560, 1600), "a default-sized window keeps its point size at factor 2")
	main_window.size = default_size
	UiScale.fit_main_window(main_window, Vector2i(1280, 800))
	check_eq(main_window.size, default_size, "the fit happens once per process")
	main_window.free()

	# --- fit: how much bigger than the design a window is, within [1, MAX_FIT] ---
	check_approx(UiScale.fit(Vector2i(1280, 800), Vector2i(1280, 800)), 1.0, "the design size fits at 1")
	check_approx(UiScale.fit(Vector2i(2560, 1600), Vector2i(1280, 800)), 2.0, "twice the size fits at 2")
	check_approx(UiScale.fit(Vector2i(5120, 1600), Vector2i(1280, 800)), 2.0,
		"an ultra-wide window fits by its height, so the design still fits")
	check_approx(UiScale.fit(Vector2i(640, 400), Vector2i(1280, 800)), 1.0, "a small window never shrinks the UI")
	check_approx(UiScale.fit(Vector2i(100000, 100000), Vector2i(1280, 800)), UiScale.MAX_FIT, "capped at MAX_FIT")
	check_approx(UiScale.fit(Vector2i(1280, 800), Vector2i.ZERO), 1.0, "a degenerate base fits at 1")

	# --- follow_size: the content scale is factor() * fit() of the window ---
	UiScale.override = 2.0
	root.gui_embed_subwindows = false
	var big := Window.new()
	big.size = Vector2i(5120, 3200)    # pixels: 2x the design at factor 2
	UiScale.follow_size(big, Vector2i(1280, 800))
	check_approx(big.content_scale_factor, 4.0, "a window twice the design's points scales by 2 * factor()")
	check_eq(big.content_scale_mode, Window.CONTENT_SCALE_MODE_DISABLED, "follow_size() keeps the mode DISABLED")
	big.size = Vector2i(2560, 1600)
	UiScale.follow_size(big, Vector2i(1280, 800))   # idempotent: refits, no second connection
	check_approx(big.content_scale_factor, 2.0, "back at the design size it is factor()")
	check_eq(big.size_changed.get_connections().size(), 1, "follow_size() connects once")
	big.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	big.content_scale_factor = 1.0
	big.size = Vector2i(5120, 3200)
	big.size_changed.emit()
	check_approx(big.content_scale_factor, 1.0, "a stretched window is left alone")
	big.free()
	root.gui_embed_subwindows = embedding
	var inner := Window.new()      # headless embeds: an embedded window is skipped
	inner.content_scale_factor = 1.0
	inner.size = Vector2i(5120, 3200)
	UiScale.follow_size(inner, Vector2i(1280, 800))
	check_approx(inner.content_scale_factor, 1.0, "an embedded window inherits its scale instead")
	inner.free()

	# --- center_over: an embedded window centres in its embedder's visible rect ---
	UiScale.override = 0.0
	var holder := SubViewportContainer.new()
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 600)
	vp.gui_embed_subwindows = true
	holder.add_child(vp)
	root.add_child(holder)
	var w := Window.new()
	w.size = Vector2i(400, 200)
	vp.add_child(w)
	await frames(1)
	check(w.is_embedded(), "a window under an embedding viewport is embedded")
	UiScale.center_over(w, root)
	check_eq(w.position, Vector2i(200, 200), "center_over centres it in the embedder's rect")
	w.size = Vector2i(1000, 900)
	UiScale.center_over(w, root)
	check_eq(w.position, Vector2i(0, w.get_theme_constant(&"title_height")),
		"a window bigger than its embedder is pinned top-left, title bar still visible")
	holder.queue_free()
	await frames(1)

	# --- beside_position: never over the parent while there is room elsewhere ---
	UiScale.override = 1.0
	var parent := Rect2i(100, 100, 1280, 800)
	var wide: Array[Rect2i] = [Rect2i(0, 0, 3000, 1200)]
	check_eq(UiScale.beside_position(Vector2i(1000, 700), 28, parent, wide), Vector2i(1388, 100),
		"right of the parent, a gap away, top-aligned")
	var left_room: Array[Rect2i] = [Rect2i(-1200, 0, 2600, 1200)]
	check_eq(UiScale.beside_position(Vector2i(1000, 700), 28, parent, left_room), Vector2i(-908, 100),
		"left of the parent when the right has no room")
	var laptop: Array[Rect2i] = [Rect2i(0, 25, 1728, 1080), Rect2i(1728, 0, 1920, 1080)]
	check_eq(UiScale.beside_position(Vector2i(1000, 700), 28, Rect2i(224, 150, 1280, 800), laptop),
		Vector2i(1728 + 460, 28 + 176), "centred on another screen when neither side fits")
	var alone: Array[Rect2i] = [laptop[0]]
	check_eq(UiScale.beside_position(Vector2i(1000, 700), 28, Rect2i(300, 150, 1280, 800), alone),
		Vector2i(0, 150), "no room anywhere: against the screen edge with more room")
	check_eq(UiScale.beside_position(Vector2i(1000, 700), 28, Rect2i(100, 800, 1280, 800), wide).y, 500,
		"kept on screen vertically")
	UiScale.override = 0.0
