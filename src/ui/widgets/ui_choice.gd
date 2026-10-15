class_name UiChoice
extends Control
## "◀  Value  ▶" selector: Left/Right (keys, d-pad, stick) or clicking the arrows cycles
## through `items`; disabled items are skipped. Emits `value_changed(value)`.
##
##   var c := UiChoice.new()
##   c.set_items([{"value": "fxaa", "label": "FXAA"}, {"value": "taa", "label": "TAA", "disabled": true}])
##   c.select_value("fxaa")

signal value_changed(value: Variant)

var items: Array[Dictionary] = []
var index := 0
var disabled := false:
	set(v):
		disabled = v
		focus_mode = Control.FOCUS_NONE if v else Control.FOCUS_ALL
		queue_redraw()
## Wrap around at the ends.
var wrap := true

var _flash := 0.0
var _dir := 0
var _hover_arrow := 0


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(380, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	UiFx.wire(self)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_exited.connect(func() -> void:
		_hover_arrow = 0
		queue_redraw())


func set_items(p_items: Array) -> void:
	items.clear()
	for it: Dictionary in p_items:
		items.append(it)
	index = clampi(index, 0, maxi(items.size() - 1, 0))
	queue_redraw()


func select_value(v: Variant) -> void:
	for i in items.size():
		if items[i]["value"] == v:
			index = i
			queue_redraw()
			return


func get_value() -> Variant:
	return items[index]["value"] if index < items.size() else null


func get_label() -> String:
	return String(items[index].get("label", str(items[index]["value"]))) if index < items.size() else ""


## Steps by `dir` (+1/-1) skipping disabled entries. Returns true if the value changed.
func step(dir: int) -> bool:
	if disabled or items.is_empty():
		return false
	var i := index
	for _n in items.size():
		i += dir
		if i < 0 or i >= items.size():
			if not wrap:
				return false
			i = posmod(i, items.size())
		if not bool(items[i].get("disabled", false)):
			break
	if i == index or bool(items[i].get("disabled", false)):
		return false
	index = i
	_dir = dir
	_flash = 1.0
	queue_redraw()
	UiFx.sound(UiFx.CLICK)
	value_changed.emit(get_value())
	return true


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event.is_action_pressed(&"ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		step(1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			step(-1 if mb.position.x < size.x * 0.5 else 1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			step(-1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step(1)
			accept_event()
	elif event is InputEventMouseMotion:
		var a := -1 if (event as InputEventMouseMotion).position.x < size.x * 0.25 else (1 if (event as InputEventMouseMotion).position.x > size.x * 0.75 else 0)
		if a != _hover_arrow:
			_hover_arrow = a
			queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.0)
		queue_redraw()


func _draw() -> void:
	var focused := has_focus()
	var r := Rect2(Vector2.ZERO, size)
	var base := Color(UiTheme.INK, 0.55 if not focused else 0.85)
	draw_rect(r, base)
	if focused:
		draw_rect(r, Color(UiTheme.GOLD, 0.8), false, 1.5)
	else:
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(UiTheme.GOLD, 0.25), 1.0)
	var chev := UiTheme.icon("ui_chevron")
	var cs := size.y * 0.42
	var alpha := 0.35 if disabled else 1.0
	var col_l := UiTheme.GOLD_HI if (focused or _hover_arrow == -1) else Color(UiTheme.GOLD, 0.6)
	var col_r := UiTheme.GOLD_HI if (focused or _hover_arrow == 1) else Color(UiTheme.GOLD, 0.6)
	if chev:
		var nudge_l := -6.0 * _flash if _dir < 0 else 0.0
		var nudge_r := 6.0 * _flash if _dir > 0 else 0.0
		draw_set_transform(Vector2(18 + cs + nudge_l, (size.y - cs) * 0.5), 0.0, Vector2(-1, 1))
		draw_texture_rect(chev, Rect2(Vector2.ZERO, Vector2(cs, cs)), false, Color(col_l, alpha))
		draw_set_transform(Vector2(size.x - 18 - cs + nudge_r, (size.y - cs) * 0.5), 0.0, Vector2.ONE)
		draw_texture_rect(chev, Rect2(Vector2.ZERO, Vector2(cs, cs)), false, Color(col_r, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := UiTheme.title_font(600, 2)
	var fs := UiTheme.SIZE_SMALL + 2
	var text := get_label()
	var tc := UiTheme.PARCHMENT if not disabled else Color(UiTheme.PARCHMENT, 0.35)
	if focused:
		tc = UiTheme.GOLD_HI
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var pos := Vector2((size.x - ts.x) * 0.5, (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	# position pips
	if items.size() > 1 and items.size() <= 8:
		var pw := 10.0
		var gap := 6.0
		var total := items.size() * pw + (items.size() - 1) * gap
		var x0 := (size.x - total) * 0.5
		for i in items.size():
			var c := Color(UiTheme.GOLD, 0.9) if i == index else Color(UiTheme.PARCHMENT, 0.18 if not bool(items[i].get("disabled", false)) else 0.06)
			draw_rect(Rect2(x0 + i * (pw + gap), size.y - 8, pw, 2.5), c)
