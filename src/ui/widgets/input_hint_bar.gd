class_name InputHintBar
extends HBoxContainer
## Row of input hints ("[Enter] Select   [Esc] Back") that swaps glyphs when the player
## switches between keyboard/mouse and controller.
##
##   var bar := InputHintBar.new()
##   bar.set_hints([{"action": &"ui_accept", "text": "Select"}, {"action": &"ui_cancel", "text": "Back"}])
##   bar.set_hints([{"kbm": [{"type": "key", "code": KEY_Q}], "pad": [...], "text": "Tabs"}])

var glyph_height := 34.0


func _ready() -> void:
	add_theme_constant_override(&"separation", 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Key / button hints mean nothing on a touchscreen: the bar steps aside while touch is used.
	UiInput.ensure(get_tree()).device_changed.connect(func(_d: StringName) -> void: _sync_touch())
	_sync_touch()


func _sync_touch() -> void:
	modulate.a = 0.0 if UiInput.device == &"touch" else 1.0


## Replaces the hints. Each: {"action": StringName} or {"kbm": Array, "pad": Array}, plus "text".
func set_hints(hints: Array) -> void:
	for c in get_children():
		c.queue_free()
	for h: Dictionary in hints:
		var item := HBoxContainer.new()
		item.add_theme_constant_override(&"separation", 10)
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g: PromptGlyph
		if h.has("action"):
			g = PromptGlyph.for_action(h["action"], glyph_height)
		else:
			g = PromptGlyph.for_entries(h.get("kbm", []), h.get("pad", []), glyph_height)
		item.add_child(g)
		var l := UiTheme.make_label(String(h.get("text", "")), UiTheme.title_font(600, 2), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(l)
		add_child(item)


## Standard pairs used across menus.
static func navigate_select_back(include_back: bool = true) -> Array:
	var arr: Array = [
		{"kbm": [{"type": "key", "code": KEY_UP}, {"type": "key", "code": KEY_DOWN}],
				"pad": [{"type": "joy_button", "button": JOY_BUTTON_DPAD_UP}, {"type": "joy_button", "button": JOY_BUTTON_DPAD_DOWN}], "text": "Navigate"},
		{"action": &"ui_accept", "text": "Select"},
	]
	if include_back:
		arr.append({"action": &"ui_cancel", "text": "Back"})
	return arr
