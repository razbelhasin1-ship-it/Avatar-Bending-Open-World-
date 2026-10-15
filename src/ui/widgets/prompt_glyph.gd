class_name PromptGlyph
extends Control
## Input prompt badge drawn in code: a keycap for keyboard keys, a mouse with the
## button highlighted, or a controller glyph (face buttons in their colours, shoulders,
## triggers, d-pad arm, sticks). Follows the active device (UiInput) unless forced.
##
##   var g := PromptGlyph.for_action(&"interact")       # "E" or (Y)
##   var g2 := PromptGlyph.for_entries([{"type": "key", "code": KEY_Q}], [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}])

const PAD_COLORS := {
	JOY_BUTTON_A: Color("6dbb5a"), JOY_BUTTON_B: Color("d9574a"),
	JOY_BUTTON_X: Color("4f8fd6"), JOY_BUTTON_Y: Color("e3b33f"),
}

## Action whose binding is shown (ignored when explicit entries are set).
var action: StringName = &""
## &"" follows UiInput.device; &"kbm" or &"pad" forces one.
var forced_device: StringName = &""
## Glyph height in px (1080p design base).
var glyph_height := 40.0:
	set(v):
		glyph_height = v
		update_minimum_size()
		queue_redraw()
var _kbm_entries: Array = []
var _pad_entries: Array = []


static func for_action(p_action: StringName, height: float = 40.0) -> PromptGlyph:
	var g := PromptGlyph.new()
	g.action = p_action
	g.glyph_height = height
	return g


static func for_entries(kbm: Array, pad: Array, height: float = 40.0) -> PromptGlyph:
	var g := PromptGlyph.new()
	g._kbm_entries = kbm
	g._pad_entries = pad
	g.glyph_height = height
	return g


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiInput.ensure(get_tree()).device_changed.connect(_on_device_changed)
	Events.controls_changed.connect(_on_device_changed.bind(&""))
	update_minimum_size()


func _on_device_changed(_d: StringName) -> void:
	update_minimum_size()
	queue_redraw()


func current_device() -> StringName:
	var d := forced_device if forced_device != &"" else UiInput.device
	return &"pad" if d == &"pad" else &"kbm"


## Binding entries shown for the current device.
func entries() -> Array:
	var pad := current_device() == &"pad"
	var explicit: Array = _pad_entries if pad else _kbm_entries
	if not explicit.is_empty():
		return explicit
	if action == &"":
		return []
	var e := UiInput.action_entry(action, &"pad" if pad else &"kbm")
	return [] if e.is_empty() else [e]


## Plain text of the prompt ("E", "Space", "A") — for tests and accessibility.
func get_label() -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in entries():
		parts.append(UiInput.entry_label(e))
	return " ".join(parts)


func _get_minimum_size() -> Vector2:
	var w := 0.0
	var list := entries()
	for i in list.size():
		w += _entry_width(list[i])
		if i > 0:
			w += glyph_height * 0.18
	return Vector2(maxf(w, glyph_height), glyph_height)


func _entry_width(e: Dictionary) -> float:
	var h := glyph_height
	match String(e.get("type", "")):
		"key":
			var font := UiTheme.title_font(700)
			var fs := int(h * 0.48)
			var tw := font.get_string_size(UiInput.entry_label(e), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			return maxf(h, tw + h * 0.6)
		"mouse":
			return h * 0.75
		"joy_button":
			var b := int(e.get("button", 0))
			if b in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK]:
				return h * 1.5
			return h
		"joy_axis":
			var ax := int(e.get("axis", 0))
			return h * 1.3 if ax in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] else h
	return h


func _draw() -> void:
	var x := 0.0
	var list := entries()
	if list.is_empty():
		_draw_keycap(Rect2(0, 0, glyph_height, glyph_height), "—")
		return
	for e: Dictionary in list:
		var w := _entry_width(e)
		var r := Rect2(x, (size.y - glyph_height) * 0.5, w, glyph_height)
		match String(e.get("type", "")):
			"key": _draw_keycap(r, UiInput.entry_label(e))
			"mouse": _draw_mouse(r, int(e.get("button", 1)))
			"joy_button": _draw_pad_button(r, int(e.get("button", 0)))
			"joy_axis": _draw_pad_axis(r, int(e.get("axis", 0)), float(e.get("value", 1.0)))
		x += w + glyph_height * 0.18


func _text(r: Rect2, t: String, color: Color, scale: float = 0.48) -> void:
	var font := UiTheme.title_font(700)
	var fs := int(r.size.y * scale)
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := font.get_ascent(fs)
	var desc := font.get_descent(fs)
	var pos := Vector2(r.position.x + (r.size.x - ts.x) * 0.5, r.position.y + (r.size.y + asc - desc) * 0.5)
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _rounded(r: Rect2, radius: float, fill: Color, border: Color, bw: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(maxf(1.0, bw)))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw_keycap(r: Rect2, label: String) -> void:
	var inner := r.grow(-1.0)
	# raised key: darker lip at the bottom
	_rounded(inner, glyph_height * 0.16, Color(UiTheme.PARCHMENT, 0.92), Color(UiTheme.GOLD_HI, 0.0), 1.0)
	_rounded(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.86)), glyph_height * 0.16, Color("fbf3e1"), Color(0, 0, 0, 0), 0.0)
	_text(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.88)), label, UiTheme.INK)


func _draw_mouse(r: Rect2, button: int) -> void:
	var w := r.size.x * 0.82
	var body := Rect2(r.position + Vector2((r.size.x - w) * 0.5, 0), Vector2(w, r.size.y))
	_rounded(body, w * 0.48, Color(UiTheme.INK, 0.85), UiTheme.PARCHMENT, 2.0)
	var half := body.size.x * 0.5
	var top := Rect2(body.position + Vector2(3, 3), Vector2(half - 4, body.size.y * 0.42))
	match button:
		MOUSE_BUTTON_LEFT:
			_rounded(top, w * 0.3, UiTheme.GOLD_HI, Color(0, 0, 0, 0), 0.0)
		MOUSE_BUTTON_RIGHT:
			_rounded(Rect2(top.position + Vector2(half - 2, 0), top.size), w * 0.3, UiTheme.GOLD_HI, Color(0, 0, 0, 0), 0.0)
		MOUSE_BUTTON_MIDDLE:
			_rounded(Rect2(body.position + Vector2(half - 3, 6), Vector2(6, body.size.y * 0.28)), 3.0, UiTheme.GOLD_HI, Color(0, 0, 0, 0), 0.0)
		_:
			_text(body, str(button), UiTheme.GOLD_HI, 0.36)
	draw_line(body.position + Vector2(half, 3), body.position + Vector2(half, body.size.y * 0.44), UiTheme.PARCHMENT, 1.5, true)


func _draw_pad_button(r: Rect2, b: int) -> void:
	var h := r.size.y
	if PAD_COLORS.has(b):
		var c: Color = PAD_COLORS[b]
		var center := r.get_center()
		draw_circle(center, h * 0.48, Color(UiTheme.INK, 0.92), true, -1.0, true)
		draw_circle(center, h * 0.46, c, false, maxf(2.0, h * 0.07), true)
		_text(r, UiInput.PAD_BUTTONS.get(b, "?"), c.lightened(0.15), 0.52)
		return
	match b:
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK:
			_rounded(r.grow(-1.0), h * 0.32, Color(UiTheme.INK, 0.92), UiTheme.PARCHMENT, 2.0)
			_text(r, UiInput.PAD_BUTTONS.get(b, "?"), UiTheme.PARCHMENT, 0.42)
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT:
			_draw_dpad(r, b)
		JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK:
			_draw_stick(r, "L" if b == JOY_BUTTON_LEFT_STICK else "R", true)
		_:
			draw_circle(r.get_center(), h * 0.46, Color(UiTheme.INK, 0.92), true, -1.0, true)
			draw_circle(r.get_center(), h * 0.46, UiTheme.PARCHMENT, false, 2.0, true)
			_text(r, UiInput.entry_label({"type": "joy_button", "button": b}).left(3), UiTheme.PARCHMENT, 0.4)


func _draw_pad_axis(r: Rect2, axis: int, value: float) -> void:
	match axis:
		JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT:
			var h := r.size.y
			var body := r.grow(-1.0)
			_rounded(body, h * 0.22, Color(UiTheme.INK, 0.92), UiTheme.PARCHMENT, 2.0)
			_text(r, "LT" if axis == JOY_AXIS_TRIGGER_LEFT else "RT", UiTheme.PARCHMENT, 0.42)
		JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
			_draw_stick(r, "L", false, axis, value)
		_:
			_draw_stick(r, "R", false, axis, value)


func _draw_stick(r: Rect2, letter: String, press: bool, axis: int = -1, value: float = 0.0) -> void:
	var c := r.get_center()
	var rad := r.size.y * 0.46
	draw_circle(c, rad, Color(UiTheme.INK, 0.92), true, -1.0, true)
	draw_circle(c, rad, UiTheme.PARCHMENT, false, 2.0, true)
	draw_circle(c, rad * 0.62, Color(UiTheme.PARCHMENT, 0.18), true, -1.0, true)
	if axis >= 0:
		var dir := Vector2.ZERO
		if axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]:
			dir = Vector2(signf(value), 0)
		else:
			dir = Vector2(0, signf(value))
		var tip := c + dir * rad * 0.95
		var side := Vector2(-dir.y, dir.x) * rad * 0.28
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * rad * 0.35 + side, tip - dir * rad * 0.35 - side]), UiTheme.GOLD_HI)
	_text(Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), letter + ("3" if press else ""), UiTheme.PARCHMENT, 0.42)


func _draw_dpad(r: Rect2, b: int) -> void:
	var c := r.get_center()
	var s := r.size.y
	var arm := s * 0.30
	var len := s * 0.48
	var base := Color(UiTheme.INK, 0.92)
	draw_rect(Rect2(c.x - arm * 0.5, c.y - len, arm, len * 2.0), base)
	draw_rect(Rect2(c.x - len, c.y - arm * 0.5, len * 2.0, arm), base)
	var hi := UiTheme.GOLD_HI
	match b:
		JOY_BUTTON_DPAD_UP: draw_rect(Rect2(c.x - arm * 0.5, c.y - len, arm, len - arm * 0.5), hi)
		JOY_BUTTON_DPAD_DOWN: draw_rect(Rect2(c.x - arm * 0.5, c.y + arm * 0.5, arm, len - arm * 0.5), hi)
		JOY_BUTTON_DPAD_LEFT: draw_rect(Rect2(c.x - len, c.y - arm * 0.5, len - arm * 0.5, arm), hi)
		JOY_BUTTON_DPAD_RIGHT: draw_rect(Rect2(c.x + arm * 0.5, c.y - arm * 0.5, len - arm * 0.5, arm), hi)
	draw_rect(Rect2(c.x - arm * 0.5, c.y - len, arm, len * 2.0), UiTheme.PARCHMENT, false, 1.5)
	draw_rect(Rect2(c.x - len, c.y - arm * 0.5, len * 2.0, arm), UiTheme.PARCHMENT, false, 1.5)
