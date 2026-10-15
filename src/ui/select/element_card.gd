class_name ElementCard
extends Button
## One element on the selection screen: live preview (ElementPreview) over a painted
## element gradient, emblem seal, name, tagline (exactly as in ElementDefs), combat
## philosophy, home region and companion. Focus/hover lifts and lights the card in the
## element colour and makes its preview render at full rate.

const SIZE := Vector2(420, 580)
const PREVIEW_H := 284.0

var element := ElementDefs.Element.NONE
var preview: ElementPreview
var chosen := false:
	set(v):
		chosen = v
		queue_redraw()

var _hot := 0.0
var _tween: Tween
var _name: Label
var _tagline: Label
var _philosophy: Label
var _emblem: TextureRect
var _info: Label
var _content: Control


func _init(p_element: int = ElementDefs.Element.NONE) -> void:
	element = p_element


func _ready() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = SIZE
	clip_contents = false
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(s, empty)
	var d := ElementDefs.get_data(element)
	var light := UiTheme.element_light(element)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	preview = ElementPreview.new()
	preview.name = "Preview"
	preview.position = Vector2(2, 2)
	preview.size = Vector2(SIZE.x - 4, PREVIEW_H)
	_content.add_child(preview)
	preview.setup(element)
	preview.active = false
	_emblem = TextureRect.new()
	_emblem.texture = UiTheme.emblem(element)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_emblem.size = Vector2(46, 46)
	_emblem.position = Vector2(SIZE.x * 0.5 - 23, PREVIEW_H - 23)
	_emblem.modulate = light
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_emblem)
	var v := VBoxContainer.new()
	v.position = Vector2(24, PREVIEW_H + 32)
	v.size = Vector2(SIZE.x - 48, SIZE.y - PREVIEW_H - 46)
	v.add_theme_constant_override(&"separation", 7)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(v)
	_name = UiTheme.make_label(String(d.get("name", "")).to_upper(), UiTheme.title_font(700, 6), 32, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_name)
	_tagline = UiTheme.make_label(String(d.get("tagline", "")), UiTheme.body_font(), 20, light.lerp(UiTheme.PARCHMENT, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline.custom_minimum_size = Vector2(SIZE.x - 48, 0)
	v.add_child(_tagline)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.GOLD, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	_philosophy = UiTheme.make_label(String(d.get("philosophy", "")), UiTheme.body_font(), 18, UiTheme.PARCHMENT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_philosophy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_philosophy.custom_minimum_size = Vector2(SIZE.x - 48, 0)
	v.add_child(_philosophy)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_info = UiTheme.make_label("%s\nCompanion · %s" % [d.get("home_name", ""), d.get("companion_name", "")], UiTheme.title_font(600, 1), 15, Color(UiTheme.GOLD, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	_info.add_theme_constant_override(&"line_spacing", 0)
	v.add_child(_info)
	for c in v.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFx.wire(self, {"press_sound": UiFx.SELECT_ELEMENT})
	focus_entered.connect(_set_hot.bind(true))
	focus_exited.connect(_set_hot.bind(false))
	pivot_offset = SIZE * 0.5


func _set_hot(on: bool) -> void:
	preview.active = on
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(t: float) -> void:
		_hot = t
		queue_redraw(), _hot, 1.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_content, "position:y", -10.0 if on else 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_name, "theme_override_colors/font_color", UiTheme.element_light(element).lerp(Color.WHITE, 0.35) if on else UiTheme.PARCHMENT, 0.2)


## Dims non-focused cards so the focused one leads.
func set_dimmed(on: bool) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate", Color(0.72, 0.72, 0.72, 1.0) if on else Color.WHITE, 0.2)


func _draw() -> void:
	var y := _content.position.y if _content else 0.0
	var r := Rect2(Vector2(0, y), SIZE)
	var ec := UiTheme.element_color(element)
	var light := UiTheme.element_light(element)
	# drop shadow
	draw_rect(Rect2(r.position + Vector2(8, 14), r.size), Color(0, 0, 0, 0.35 + 0.15 * _hot))
	# card body: element-tinted wash at the top fading into lacquer ink
	var top := Color(ec.lerp(UiTheme.PARCHMENT, 0.35), 1.0).darkened(0.25)
	var mid := ec.darkened(0.55)
	var ink := UiTheme.INK
	var ph := PREVIEW_H
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(r.size.x, ph), r.position + Vector2(0, ph)]),
			PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([r.position + Vector2(0, ph), r.position + Vector2(r.size.x, ph), r.end, r.position + Vector2(0, r.size.y)]),
			PackedColorArray([mid.lerp(ink, 0.6), mid.lerp(ink, 0.6), ink, ink]))
	# faint emblem watermark behind the figure
	var em := UiTheme.emblem(element)
	if em:
		var es := ph * 0.86
		draw_texture_rect(em, Rect2(r.position + Vector2((r.size.x - es) * 0.5, (ph - es) * 0.45), Vector2(es, es)), false, Color(1, 1, 1, 0.07))
	var g := UiTheme.grain_texture()
	draw_texture_rect(g, r, true, Color(1, 1, 1, 0.05))
	# emblem seal disc
	var seal_c := r.position + Vector2(r.size.x * 0.5, ph)
	draw_circle(seal_c, 33, UiTheme.INK, true, -1.0, true)
	draw_circle(seal_c, 33, Color(light, 0.8), false, 2.0, true)
	# frame: hairline, element glow when hot, gold double line when chosen
	var frame := Color(UiTheme.GOLD, 0.35).lerp(Color(light, 1.0), _hot)
	draw_rect(r, frame, false, 1.5 + _hot * 1.5)
	if _hot > 0.01:
		for k in 3:
			draw_rect(r.grow(2.0 + k * 3.0), Color(light, 0.18 * _hot * (1.0 - k * 0.3)), false, 2.0)
	if chosen:
		draw_rect(r.grow(-6.0), Color(UiTheme.GOLD_HI, 0.9), false, 1.5)
