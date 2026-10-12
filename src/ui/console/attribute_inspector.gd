class_name AttributeInspector
extends VBoxContainer
## A console pane: a scrolling list of group headings and one AttributeRow per
## spec, built once from the table. It can be limited to some groups (the Shape
## tab and the Colour tab each show their own) and can carry a header control
## that scrolls with the rows (the Colour tab's palette window). Two inspectors
## over one table stay in step: every row redraws from the table's `changed`. The inspector owns no state of its own: it
## shows the shape table, writes edits straight back into it, and forwards the
## per-frame resolved values to the rows so each can show what it is driving.
## Ported from Fractacular's AttributeInspector, simplified to one fixed table.

const SCROLLBAR_ALLOWANCE := 16.0

var _scroll: ScrollContainer
var _list: VBoxContainer
var _rows: Dictionary = {}
## Each group heading and the specs under it: a heading hides while every one
## of its rows does (another shape's group, say).
var _headings: Array = []   # of [Label, Array[AttributeSpec]]
var _table: AttributeTable
var _group_tooltips: Dictionary = {}
var _groups: Array = []
var _header: Control
var _scrolling := true
var _built := false
var _last_cost_values: Dictionary = {}


## Show the shape table, with the group heading tooltips: only the specs in
## `groups` when it is not empty, below `header` when one is given. Call before
## adding it to the tree (or right after; it builds lazily). With `scrolling`
## false the rows are laid out directly (no ScrollContainer of their own), for
## a pane that stacks several inspectors in one scrolling list.
func setup(table: AttributeTable, group_tooltips: Dictionary, groups: Array = [], header: Control = null, scrolling: bool = true) -> void:
	_table = table
	_group_tooltips = group_tooltips
	_groups = groups
	_header = header
	_scrolling = scrolling
	_build()
	_populate()


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 4)
	custom_minimum_size.x = AttributeRow.WIDE_ROW_MIN_WIDTH + (SCROLLBAR_ALLOWANCE if _scrolling else 0.0)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	if _scrolling:
		_scroll = ScrollContainer.new()
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(_scroll)
		_scroll.add_child(_list)
	else:
		add_child(_list)


func _populate() -> void:
	_last_cost_values.clear()
	if _table == null:
		return
	_rows.clear()
	_headings.clear()
	for c in _list.get_children():
		_list.remove_child(c)
		if c != _header:
			c.queue_free()
	if _header != null:
		_list.add_child(_header)

	var last_group := "￿"  # a value no real group can equal
	for spec in _table.specs:
		if not _groups.is_empty() and not _groups.has(spec.group):
			continue
		if spec.group != last_group:
			last_group = spec.group
			if spec.group != "":
				var heading := _make_heading(spec.group, String(_group_tooltips.get(spec.group, spec.group)))
				_list.add_child(heading)
				_headings.append([heading, []])
		if spec.group != "" and not _headings.is_empty():
			(_headings[-1][1] as Array).append(spec)
		var row := AttributeRow.new()
		row.setup(spec, _table)
		_list.add_child(row)
		_rows[spec.id] = row
	if not _table.changed.is_connected(_on_table_changed):
		_table.changed.connect(_on_table_changed)
	_refresh_headings()


func _on_table_changed(_id: StringName) -> void:
	_last_cost_values.clear()
	_refresh_headings()


func _refresh_headings() -> void:
	var values := _table.defaults()
	for entry in _headings:
		var shown := false
		for spec in entry[1]:
			if (spec as AttributeSpec).is_shown(values):
				shown = true
				break
		(entry[0] as Label).visible = shown


## The heading Label of `group`, or null (for tests).
func heading(group: String) -> Label:
	for entry in _headings:
		if (entry[0] as Label).text == group.to_upper():
			return entry[0]
	return null


## The axes available as binding sources: Array of {id, label}.
func set_sources(axis_list: Array) -> void:
	_last_cost_values.clear()
	for id in _rows:
		(_rows[id] as AttributeRow).set_sources(axis_list)


## Feed one frame of resolved values (id -> value) to the rows.
func set_resolved(values: Dictionary) -> void:
	var cost_changed := is_visible_in_tree() and values != _last_cost_values
	if cost_changed:
		_last_cost_values = values.duplicate()
	for id in _rows:
		var row := _rows[id] as AttributeRow
		row.set_resolved(values.get(id))
		if cost_changed and row.is_visible_in_tree():
			row.refresh_cost(values)


func row_count() -> int:
	return _rows.size()


func row(id: StringName) -> AttributeRow:
	return _rows.get(id)


func table() -> AttributeTable:
	return _table


## This inspector's ScrollContainer, or null when it was built without one.
func scroll_container() -> ScrollContainer:
	return _scroll


## Godot's default theme has no bold variant, so a heading is set apart by
## capitals, size and colour rather than weight.
func _make_heading(text: String, tooltip: String) -> Label:
	var heading := Label.new()
	heading.text = text.to_upper()
	heading.tooltip_text = tooltip
	heading.mouse_filter = Control.MOUSE_FILTER_STOP
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color(0.72, 0.82, 1.0))
	return heading
