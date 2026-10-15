class_name RebindPrompt
extends UiOverlay
## Press-to-bind capture for one action on one device ("kbm" / "pad").
## Keyboard capture is cancelled with Esc, controller capture with Menu (Start); it also
## times out after `timeout` seconds so the player can never get stuck. A conflicting
## binding shows a warning with SWAP / BIND ANYWAY / CANCEL.

signal finished(applied: bool)

var action: StringName = &""
var device := "kbm"
var timeout := 8.0
## Entry captured and waiting for conflict resolution.
var pending: Dictionary = {}
var conflicts: Array[StringName] = []

var swap_button: Button
var anyway_button: Button
var cancel_button: Button

var _capturing := false
var _guard := 0.0
var _left := 0.0
var _title: Label
var _body: Label
var _hint: Label
var _bar: ProgressBar
var _buttons: HBoxContainer


func _init() -> void:
	super()
	dim = 0.6


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	panel.add_child(v)
	_title = UiTheme.make_label("", UiTheme.title_font(600, 6), UiTheme.SIZE_SMALL, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_body = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_H3, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_body)
	_hint = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_hint)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 4)
	_bar.max_value = 1.0
	v.add_child(_bar)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override(&"separation", 14)
	v.add_child(_buttons)
	swap_button = _btn("SWAP", &"PrimaryButton")
	anyway_button = _btn("BIND ANYWAY", &"")
	cancel_button = _btn("CANCEL", &"")
	swap_button.pressed.connect(func() -> void: _commit(true))
	anyway_button.pressed.connect(func() -> void: _commit(false))
	cancel_button.pressed.connect(cancel)


func _btn(text: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(210, 64)
	if variation != &"":
		b.theme_type_variation = variation
	UiFx.wire(b)
	_buttons.add_child(b)
	return b


## Starts capturing a new binding for `p_action` on `p_device`.
func begin(p_action: StringName, p_device: String) -> void:
	action = p_action
	device = p_device
	pending = {}
	conflicts.clear()
	_title.text = "REBIND  ·  %s" % ("KEYBOARD & MOUSE" if device == "kbm" else "CONTROLLER")
	_body.text = "%s %s" % ["Press a key or mouse button for" if device == "kbm" else "Press a button for", RebindLogic.action_label(action).to_upper()]
	_hint.text = "Esc to cancel" if device == "kbm" else "Menu (Start) to cancel  ·  Esc on keyboard"
	_buttons.visible = false
	_bar.visible = true
	_capturing = true
	_guard = 0.18
	_left = timeout
	open()


func _initial_focus() -> Control:
	return null


func _process(delta: float) -> void:
	if not is_open or not _capturing:
		return
	_guard = maxf(0.0, _guard - delta)
	_left -= delta
	_bar.value = clampf(_left / timeout, 0.0, 1.0)
	if _left <= 0.0:
		cancel()


func _input(event: InputEvent) -> void:
	if not is_open or not _capturing:
		return
	# never let gameplay/menus see input while capturing
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
	if _guard > 0.0:
		return
	capture(event)


## Feeds one input event to the capture (also used by tests). Returns true if consumed.
func capture(event: InputEvent) -> bool:
	if not _capturing:
		return false
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		cancel()
		return true
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
		cancel()
		return true
	var e := RebindLogic.entry_from_event(event, device)
	if e.is_empty():
		return false
	_capturing = false
	pending = e
	conflicts = RebindLogic.find_conflicts(action, e)
	if conflicts.is_empty():
		_commit(false)
	else:
		_show_conflict()
	return true


func _show_conflict() -> void:
	var names: PackedStringArray = []
	for c: StringName in conflicts:
		names.append(RebindLogic.action_label(c).to_upper())
	_title.text = "BINDING CONFLICT"
	_body.text = "%s is already used by %s." % [UiInput.entry_label(pending), ", ".join(names)]
	_hint.text = "Swap gives %s your previous binding." % ", ".join(names) if not RebindLogic.current_entry(action, device).is_empty() else "Swap removes it from %s." % ", ".join(names)
	_bar.visible = false
	_buttons.visible = true
	UiFx.sound(UiFx.ERROR)
	UiFx.focus_silently(swap_button)


func _commit(swap: bool) -> void:
	if pending.is_empty():
		cancel()
		return
	RebindLogic.bind(action, pending, swap)
	UiFx.sound(UiFx.CONFIRM)
	pending = {}
	close()
	finished.emit(true)


func cancel() -> void:
	_capturing = false
	pending = {}
	if is_open:
		close()
	finished.emit(false)


func _on_back() -> void:
	cancel()


func _unhandled_input(event: InputEvent) -> void:
	# capture handles Esc itself; only the conflict view uses Back
	if is_open and not _capturing:
		super(event)
