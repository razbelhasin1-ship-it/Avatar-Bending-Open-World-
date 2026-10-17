class_name ConfirmDialog
extends UiOverlay
## Small modal question with up to three answers. Emits `answered(id)` with the chosen
## button id (or &"cancel" on Esc / B).
##
##   var d := ConfirmDialog.new()
##   add_child(d)
##   d.ask("UNSAVED CHANGES", "Apply your changes?", [[&"apply", "APPLY"], [&"discard", "DISCARD"]])
##   var id: StringName = await d.answered

signal answered(id: StringName)

var buttons: Dictionary = {}   # id -> Button
var _title: Label
var _text: Label
var _row: HBoxContainer


func _init() -> void:
	super()
	dim = 0.5


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 20)
	panel.add_child(v)
	_title = UiTheme.make_label("", UiTheme.title_font(600, 6), UiTheme.SIZE_SMALL + 2, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_text = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_BODY, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_text)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", 14)
	v.add_child(_row)


## Shows the dialog. `choices`: Array of [id: StringName, label: String]; the first is focused.
func ask(title: String, text: String, choices: Array) -> void:
	_title.text = title
	_text.text = text
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	buttons.clear()
	for i in choices.size():
		var spec: Array = choices[i]
		var b := Button.new()
		b.text = String(spec[1])
		b.custom_minimum_size = Vector2(200, 64)
		if i == 0:
			b.theme_type_variation = &"PrimaryButton"
		var id: StringName = spec[0]
		UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
		b.pressed.connect(func() -> void: _answer(id))
		b.name = "Choice%d" % i
		_row.add_child(b)
		buttons[id] = b
	_trap_focus()
	open()


## Keyboard / pad focus stays on the answers: left / right cycle through them, up / down and
## Tab stay in the row. Without explicit neighbours Godot picks the nearest focusable control in
## the direction, which can be a widget BEHIND the dim (a settings toggle next to APPLY): the
## press then changed a setting the player could not see and focus left the question.
func _trap_focus() -> void:
	var row: Array[Button] = []
	for c in _row.get_children():
		if c is Button and not c.is_queued_for_deletion():
			row.append(c as Button)
	var n := row.size()
	for i in n:
		var b := row[i]
		var prev := NodePath("../" + String(row[(i - 1 + n) % n].name))
		var next := NodePath("../" + String(row[(i + 1) % n].name))
		b.focus_neighbor_left = prev
		b.focus_neighbor_right = next
		b.focus_neighbor_top = NodePath(".")
		b.focus_neighbor_bottom = NodePath(".")
		b.focus_previous = prev
		b.focus_next = next


func _initial_focus() -> Control:
	return _row.get_child(0) as Control if _row.get_child_count() > 0 else null


func _answer(id: StringName) -> void:
	close()
	answered.emit(id)


func _on_back() -> void:
	_answer(&"cancel")
