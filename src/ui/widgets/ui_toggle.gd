class_name UiToggle
extends Button
## On/off switch drawn as a lacquer track with a sliding gold bead and an ON/OFF caption.
## Toggles with click, Enter/Space/A, or Left/Right when focused.

var _knob := 0.0
var _tween: Tween


func _init() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(380, 64)
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(s, empty)


func _ready() -> void:
	UiFx.wire(self)
	toggled.connect(_on_toggled)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_knob = 1.0 if button_pressed else 0.0


## Sets the state without emitting `toggled`.
func set_on(on: bool) -> void:
	set_pressed_no_signal(on)
	_knob = 1.0 if on else 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event.is_action_pressed(&"ui_left") and button_pressed:
		button_pressed = false
		accept_event()
	elif event.is_action_pressed(&"ui_right") and not button_pressed:
		button_pressed = true
		accept_event()


func _on_toggled(on: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_knob = v
		queue_redraw(), _knob, 1.0 if on else 0.0, 0.16).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var focused := has_focus()
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(UiTheme.INK, 0.85 if focused else 0.55))
	if focused:
		draw_rect(r, Color(UiTheme.GOLD, 0.8), false, 1.5)
	else:
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(UiTheme.GOLD, 0.25), 1.0)
	var a := 0.35 if disabled else 1.0
	var track := Rect2(Vector2(size.x * 0.5 - 44, size.y * 0.5 - 13), Vector2(88, 26))
	var on_col := UiTheme.GOLD.lerp(UiTheme.GOLD_HI, 0.3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK_3, a).lerp(Color(UiTheme.GOLD_DEEP, a), _knob)
	sb.border_color = Color(UiTheme.GOLD, 0.6 * a)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	sb.anti_aliasing = true
	draw_style_box(sb, track)
	var kx := lerpf(track.position.x + 13, track.end.x - 13, _knob)
	draw_circle(Vector2(kx, track.get_center().y), 10.5, Color(UiTheme.PARCHMENT.lerp(on_col, _knob), a), true, -1.0, true)
	var font := UiTheme.title_font(600, 3)
	var fs := UiTheme.SIZE_TINY
	var off_c := Color(UiTheme.PARCHMENT, (0.85 if _knob < 0.5 else 0.3) * a)
	var on_c := Color(UiTheme.GOLD_HI if focused else UiTheme.PARCHMENT, (0.95 if _knob >= 0.5 else 0.3) * a)
	var y := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(track.position.x - 70, y), "OFF", HORIZONTAL_ALIGNMENT_RIGHT, 52, fs, off_c)
	draw_string(font, Vector2(track.end.x + 18, y), "ON", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, on_c)
