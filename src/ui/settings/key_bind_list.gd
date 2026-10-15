class_name KeyBindList
extends VBoxContainer
## Rebinding table of the controls tab: every rebindable action (InputDefaults) grouped by
## Movement / Camera / Bending / World / Menus with a keyboard & mouse column and a
## controller column. Each cell is a focusable button showing the current binding glyph;
## activating it asks the owner to capture a new binding (`rebind_requested`).

signal rebind_requested(action: StringName, device: String)
signal reset_requested
## Help text for the focused cell.
signal cell_focused(text: String)

var buttons: Dictionary = {}   # "action|device" -> Button
var reset_button: Button
var disabled := false


func _ready() -> void:
	add_theme_constant_override(&"separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 18)
	add_child(head)
	var a := UiTheme.make_label("ACTION", UiTheme.title_font(600, 4), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(a)
	for t: String in ["KEYBOARD & MOUSE", "CONTROLLER"]:
		var l := UiTheme.make_label(t, UiTheme.title_font(600, 4), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		l.custom_minimum_size = Vector2(230, 0)
		head.add_child(l)
	for g: Dictionary in RebindLogic.grouped_actions():
		var gl := UiTheme.make_label(String(g["group"]).to_upper(), UiTheme.title_font(600, 6), UiTheme.SIZE_TINY, UiTheme.GOLD)
		var gm := MarginContainer.new()
		gm.add_theme_constant_override(&"margin_top", 16)
		gm.add_child(gl)
		add_child(gm)
		for action: StringName in g["actions"]:
			add_child(_row(action))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	add_child(spacer)
	reset_button = Button.new()
	reset_button.text = "RESET ALL BINDINGS"
	reset_button.custom_minimum_size = Vector2(360, 64)
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	UiFx.wire(reset_button)
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	reset_button.focus_entered.connect(func() -> void: cell_focused.emit("Restore every key and button to its default."))
	add_child(reset_button)
	refresh()


func _row(action: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	row.custom_minimum_size = Vector2(0, 62)
	var l := UiTheme.make_label(RebindLogic.action_label(action), UiTheme.body_font(1), UiTheme.SIZE_BODY - 2, UiTheme.PARCHMENT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	for device: String in ["kbm", "pad"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(230, 56)
		b.name = "%s_%s" % [action, device]
		var g := PromptGlyph.new()
		g.forced_device = StringName(device)
		g.glyph_height = 36
		g.set_anchors_preset(Control.PRESET_CENTER)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(g)
		b.set_meta(&"glyph", g)
		UiFx.wire(b)
		b.pressed.connect(func() -> void:
			if not disabled:
				rebind_requested.emit(action, device))
		b.focus_entered.connect(func() -> void:
			l.add_theme_color_override(&"font_color", UiTheme.GOLD_HI)
			cell_focused.emit("%s · %s. Select to rebind." % [RebindLogic.action_label(action), "Keyboard & mouse" if device == "kbm" else "Controller"]))
		b.focus_exited.connect(func() -> void: l.add_theme_color_override(&"font_color", UiTheme.PARCHMENT))
		buttons["%s|%s" % [action, device]] = b
		row.add_child(b)
	return row


## Re-reads every binding from Settings.
func refresh() -> void:
	for key: String in buttons:
		var parts := key.split("|")
		var action := StringName(parts[0])
		var device := parts[1]
		var b: Button = buttons[key]
		var g: PromptGlyph = b.get_meta(&"glyph")
		var e := RebindLogic.current_entry(action, device)
		if device == "kbm":
			g._kbm_entries = [e] if not e.is_empty() else []
		else:
			g._pad_entries = [e] if not e.is_empty() else []
		g.update_minimum_size()
		g.size = g.get_combined_minimum_size()
		g.position = (b.custom_minimum_size - g.size) * 0.5
		g.queue_redraw()
		b.tooltip_text = UiInput.entry_label(e) if not e.is_empty() else "Unbound"


func set_disabled(on: bool, reason: String = "") -> void:
	disabled = on
	for b: Button in buttons.values():
		b.disabled = on
		b.tooltip_text = reason if on else b.tooltip_text
	reset_button.disabled = on


func get_button(action: StringName, device: String) -> Button:
	return buttons.get("%s|%s" % [action, device])
