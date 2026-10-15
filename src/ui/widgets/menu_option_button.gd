class_name MenuOptionButton
extends Button
## Numbered primary menu option ("01 — ENTER THE WORLD"). Focus/hover paints a brush
## stroke behind the label in the accent colour, slides the label right and brightens
## the number. Works identically with mouse, keyboard and controller (it is a Button).

const HEIGHT := 92.0

var number := "01"
var label_text := "OPTION"
## Ink of the highlight stroke (an element colour or gold).
var accent := UiTheme.GOLD
## Optional small caption under the label (e.g. "Continue · Level 4").
var caption := "":
	set(v):
		caption = v
		if _caption:
			_caption.text = v
			_caption.visible = not v.is_empty()

var _stroke: BrushStroke
var _num: Label
var _dash: Label
var _label: Label
var _caption: Label
var _row: HBoxContainer
var _diamond: TextureRect
var _hot := false
var _shift_tween: Tween


func _init(p_number: String = "01", p_label: String = "OPTION", p_accent: Color = UiTheme.GOLD) -> void:
	number = p_number
	label_text = p_label
	accent = p_accent


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(620, HEIGHT)
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(s, empty)
	_stroke = BrushStroke.new(Color(accent.darkened(0.28), 0.94), float(number.to_int()) * 2.37)
	_stroke.set_param(&"thickness", 0.66).set_param(&"tail", 0.3).set_param(&"dryness", 0.8)
	_stroke.position = Vector2(28, 10)
	_stroke.size = Vector2(560, HEIGHT - 22)
	_stroke.progress = 0.0
	add_child(_stroke)
	_diamond = TextureRect.new()
	_diamond.texture = UiTheme.icon("ui_diamond")
	_diamond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_diamond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_diamond.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_diamond.size = Vector2(14, 14)
	_diamond.position = Vector2(2, HEIGHT * 0.5 - 7)
	_diamond.modulate = Color(UiTheme.GOLD_HI, 0.0)
	_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_diamond)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", 18)
	_row.position = Vector2(30, 0)
	_row.size = Vector2(600, HEIGHT)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_num = UiTheme.make_label(number, UiTheme.title_font(600, 2), 26, Color(UiTheme.GOLD, 0.75))
	_dash = UiTheme.make_label("—", UiTheme.body_font(), 26, Color(UiTheme.GOLD, 0.5))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", -4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.make_label(label_text, UiTheme.title_font(700, 5), 40, UiTheme.PARCHMENT)
	_caption = UiTheme.make_label(caption, UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_MUTED)
	_caption.visible = not caption.is_empty()
	col.add_child(_label)
	col.add_child(_caption)
	for c: Control in [_num, _dash, col, _label, _caption]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_num)
	_row.add_child(_dash)
	_row.add_child(col)
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiFx.wire(self, {"press_sound": UiFx.CONFIRM})
	focus_entered.connect(_set_hot.bind(true))
	focus_exited.connect(_set_hot.bind(false))
	mouse_exited.connect(func() -> void:
		if not has_focus():
			_set_hot(false))
	_layout_row()
	resized.connect(_layout_row)


func _layout_row() -> void:
	if _row:
		_row.size = Vector2(size.x - 30, size.y)
		_row.position = Vector2(30 + (16.0 if _hot else 0.0), 0)
		var text_w := _row.get_combined_minimum_size().x
		_stroke.size = Vector2(clampf(text_w + 150.0, 260.0, size.x - 10.0), size.y - 22)


## True while highlighted (focused).
func is_hot() -> bool:
	return _hot


func _set_hot(on: bool) -> void:
	if on == _hot:
		return
	_hot = on
	if on:
		_stroke.sweep(0.34)
	else:
		_stroke.retract(0.2)
	if _shift_tween and _shift_tween.is_valid():
		_shift_tween.kill()
	_shift_tween = create_tween().set_parallel(true)
	_shift_tween.tween_property(_row, "position:x", 46.0 if on else 30.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_shift_tween.tween_property(_diamond, "modulate:a", 1.0 if on else 0.0, 0.18)
	_shift_tween.tween_property(_num, "theme_override_colors/font_color", UiTheme.GOLD_HI if on else Color(UiTheme.GOLD, 0.75), 0.18)
	_shift_tween.tween_property(_label, "theme_override_colors/font_color", Color("fff6e2") if on else UiTheme.PARCHMENT, 0.18)
	_shift_tween.tween_property(_dash, "theme_override_colors/font_color", Color(UiTheme.GOLD_HI, 0.9) if on else Color(UiTheme.GOLD, 0.5), 0.18)
