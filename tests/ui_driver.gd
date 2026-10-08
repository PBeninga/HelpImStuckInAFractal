class_name UiDriver
extends RefCounted
## Drives the real GUI headlessly with synthetic mouse and keyboard input, the
## way a player does. Built by a test with its SceneTree:
##
##   var ui := UiDriver.new(self)
##   await ui.setup()
##   await ui.click(console.inspector().row(&"box_scale").value_control())
##
## Why it works: in headless the root window is 64x64 and every Window is
## *embedded* in it. `setup()` gives the root a 1280x800 logical surface
## (CONTENT_SCALE_MODE_CANVAS_ITEMS), so embedded windows and popups lay out at
## their true size. Every mouse event is pushed through the ROOT with
## `push_input(ev, true)` at global coordinates (the control's rect mapped
## through the position and content scale of each embedded window it sits in,
## see window_transform()), so it goes through the same
## hit-testing and sub-window dispatch a real click does. Pushing into a
## sub-window directly delivers nothing: the embedder owns dispatch.
##
## Action keys go through `Input.parse_input_event` (so `_unhandled_input` and
## Input.is_action_pressed see them); typed text is pushed through the root to
## the focused LineEdit.

const SURFACE := Vector2i(1280, 800)
## How far a popup scan steps down the menu, in logical pixels.
const POPUP_SCAN_STEP := 4.0

var tree: SceneTree
var root: Window
## The last mouse position pushed, in root (global) coordinates.
var mouse := Vector2.ZERO
var _buttons := 0


func _init(scene_tree: SceneTree) -> void:
	tree = scene_tree
	root = scene_tree.root


## Make the headless root a real 1280x800 logical surface.
func setup() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = SURFACE
	await frames(1)


## Wait `n` process frames.
func frames(n: int = 1) -> void:
	for i in n:
		await tree.process_frame


## Wait `seconds` of process time.
func wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await tree.process_frame
		t += root.get_process_delta_time()


# ------------------------------------------------------------ coordinates

## The transform from `window`'s canvas to root coordinates. Each embedded
## window draws its canvas at its position in its embedder, stretched by its
## content scale (the console's zoom is one), so a canvas point p lands at
## `position + final_transform * p` one level up, and so on to the root.
func window_transform(window: Window) -> Transform2D:
	var xf := Transform2D.IDENTITY
	var w := window
	while w != null and w != root and w.is_embedded():
		xf = Transform2D(0.0, Vector2(w.position)) * w.get_final_transform() * xf
		w = _embedder(w)
	return xf


## The top-left of `window` in root coordinates.
func window_origin(window: Window) -> Vector2:
	return window_point(window, Vector2.ZERO)


## A control's rect in root coordinates.
func global_rect(control: Control) -> Rect2:
	return window_transform(control.get_window()) * control.get_global_rect()


## The global point at `fraction` (0..1 each way) across a control's rect.
func global_point(control: Control, fraction: Vector2 = Vector2(0.5, 0.5)) -> Vector2:
	var r := global_rect(control)
	return r.position + r.size * fraction


func global_center(control: Control) -> Vector2:
	return global_point(control)


## A point given in a control's own coordinates (a TabBar's get_tab_rect(),
## say), in root coordinates.
func control_point(control: Control, local: Vector2) -> Vector2:
	return window_transform(control.get_window()) * (control.get_global_transform() * local)


## A point inside a window (a popup, say), `local` pixels from its top-left in
## its embedder's units (0..size), in root coordinates.
func window_point(window: Window, local: Vector2) -> Vector2:
	if window == root or not window.is_embedded():
		return local
	return window_transform(_embedder(window)) * (Vector2(window.position) + local)


# ------------------------------------------------------------ mouse

## Move the mouse to a control's centre or to a global point.
func move_to(target: Variant) -> void:
	var to: Vector2 = _point(target)
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - mouse
	# PopupMenu ignores motion with zero velocity (keyboard navigation guard),
	# so a synthetic move always carries some.
	ev.velocity = ev.relative * 60.0 if not ev.relative.is_zero_approx() else Vector2(1, 1)
	ev.button_mask = _buttons
	mouse = to
	root.push_input(ev, true)
	await frames(1)


## Press (or release) a mouse button at the current mouse position.
func button(index: MouseButton, pressed: bool, double_click: bool = false) -> void:
	var bit := _mask_bit(index)
	if pressed:
		_buttons |= bit
	else:
		_buttons &= ~bit
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = pressed
	ev.double_click = double_click
	ev.position = mouse
	ev.global_position = mouse
	ev.button_mask = _buttons
	if index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		ev.factor = 1.0
	root.push_input(ev, true)
	await frames(1)


## Motion, press, frame, release, frame — at a control's centre.
func click(control: Control, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await click_at(global_center(control), index)


func click_at(point: Vector2, index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await move_to(point)
	await button(index, true)
	await button(index, false)


func right_click(target: Variant) -> void:
	await click_at(_point(target), MOUSE_BUTTON_RIGHT)


## Press at `from`, move in `steps` motions to `to`, release.
func drag(from: Variant, to: Variant, steps: int = 8) -> void:
	var a: Vector2 = _point(from)
	var b: Vector2 = _point(to)
	await move_to(a)
	await button(MOUSE_BUTTON_LEFT, true)
	for i in range(1, steps + 1):
		await move_to(a.lerp(b, float(i) / steps))
	await button(MOUSE_BUTTON_LEFT, false)


## Wheel clicks over a control (or a global point): press and release each.
func wheel(target: Variant, down: bool = true, times: int = 1) -> void:
	await move_to(_point(target))
	var index := MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	for i in times:
		await button(index, true)
		await button(index, false)


## Wheel over a ScrollContainer until `control` sits wholly inside it, the way a
## player scrolls a long list to reach a row. Returns true when it got there.
func scroll_to(scroll: ScrollContainer, control: Control, max_clicks: int = 200) -> bool:
	for i in max_clicks:
		var view := global_rect(scroll)
		var r := global_rect(control)
		if view.encloses(r):
			return true
		var down := r.get_center().y > view.get_center().y
		var before := scroll.scroll_vertical
		# over the left edge, where the row labels are, never a value widget
		await wheel(Vector2(view.position.x + 10.0, view.get_center().y), down)
		if scroll.scroll_vertical == before:
			return view.encloses(global_rect(control))
	return false


## A trackpad two-finger scroll (what macOS produces). `delta` is in the
## gesture's own units: a ScrollContainer moves `page * delta / 8` per event, so
## Vector2(0, 1) is an eighth of a page down.
func pan(target: Variant, delta: Vector2) -> void:
	await move_to(_point(target))
	var ev := InputEventPanGesture.new()
	ev.position = mouse
	ev.delta = delta
	root.push_input(ev, true)
	await frames(1)


# ------------------------------------------------------------ keyboard

## A key event with keycode, physical keycode and unicode filled in.
func key_event(physical: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.keycode = physical
	ev.pressed = pressed
	ev.echo = false
	ev.shift_pressed = shift
	ev.unicode = _unicode_for(physical, shift) if pressed else 0
	return ev


## A key down or up through Input, so actions and `_unhandled_input` see it.
func key(physical: Key, pressed: bool) -> void:
	Input.parse_input_event(key_event(physical, pressed))
	await frames(1)


## Press and release a key.
func tap(physical: Key) -> void:
	await key(physical, true)
	await key(physical, false)


## Hold a key down for `seconds` of process time.
func hold(physical: Key, seconds: float) -> void:
	await key(physical, true)
	await wait(seconds)
	await key(physical, false)


## Push a key event through the root's GUI pass (to whatever has focus).
func gui_key(physical: Key, pressed: bool, shift: bool = false, unicode: int = -1) -> void:
	var ev := key_event(physical, pressed, shift)
	if unicode >= 0 and pressed:
		ev.unicode = unicode
	root.push_input(ev, true)
	await frames(1)


## Click a LineEdit, select all, type `text` one key per character, press Enter.
func type_text(line_edit: LineEdit, text: String, submit: bool = true) -> void:
	await click(line_edit)
	line_edit.select_all()
	for ch in text:
		var code := ch.unicode_at(0)
		var physical := _physical_for(ch)
		await gui_key(physical, true, false, code)
		await gui_key(physical, false)
	if submit:
		await gui_key(KEY_ENTER, true)
		await gui_key(KEY_ENTER, false)


# ------------------------------------------------------------ popups

## Open an OptionButton's popup with a click and click the item labelled `label`.
## Returns true when the item was found and clicked.
func select_option(option: OptionButton, label: String) -> bool:
	await click(option)
	var popup := option.get_popup()
	if not popup.visible:
		return false
	return await select_popup_item(popup, label)


## Click the item labelled `label` in an open PopupMenu. PopupMenu has no item
## rects, so the mouse walks down the menu until `get_focused_item()` reports
## the wanted index under it, then clicks there.
func select_popup_item(popup: PopupMenu, label: String) -> bool:
	var index := popup_index(popup, label)
	if index < 0 or not popup.visible:
		return false
	var x := popup.size.x * 0.5
	var y := 1.0
	while y < popup.size.y:
		var at := window_point(popup, Vector2(x, y))
		await move_to(at)
		if popup.get_focused_item() == index:
			await button(MOUSE_BUTTON_LEFT, true)
			await button(MOUSE_BUTTON_LEFT, false)
			return true
		y += POPUP_SCAN_STEP
	return false


## The index of the item labelled `label`, or -1.
func popup_index(popup: PopupMenu, label: String) -> int:
	for i in popup.item_count:
		if not popup.is_item_separator(i) and popup.get_item_text(i) == label:
			return i
	return -1


# ------------------------------------------------------------ helpers

func _point(target: Variant) -> Vector2:
	if target is Control:
		return global_center(target)
	return target


## The viewport an embedded window is embedded in: the nearest ancestor viewport
## that embeds sub-windows (or the root).
func _embedder(window: Window) -> Window:
	var n := window.get_parent()
	while n != null:
		var vp := n.get_viewport() if not (n is Viewport) else n as Viewport
		if vp == root:
			return root
		if vp is Window and (vp as Window).gui_embed_subwindows:
			return vp
		n = vp.get_parent()
	return root


func _mask_bit(index: MouseButton) -> int:
	match index:
		MOUSE_BUTTON_LEFT:
			return MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			return MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return MOUSE_BUTTON_MASK_MIDDLE
	return 0


func _unicode_for(physical: Key, shift: bool) -> int:
	if physical >= KEY_A and physical <= KEY_Z:
		return physical + (0 if shift else 32)
	if (physical >= KEY_0 and physical <= KEY_9) or physical == KEY_SPACE \
			or physical == KEY_PERIOD or physical == KEY_MINUS or physical == KEY_COMMA:
		return physical
	return 0


func _physical_for(ch: String) -> Key:
	var up := ch.to_upper()
	var code := up.unicode_at(0)
	if (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9):
		return code as Key
	match ch:
		".":
			return KEY_PERIOD
		"-":
			return KEY_MINUS
		",":
			return KEY_COMMA
		" ":
			return KEY_SPACE
	return KEY_UNKNOWN
