class_name TitleCard
extends Control
## Animated brush-stroke banner for arrivals and region discovery
## ("THE NORTHERN WATER TRIBE"): an ink stroke sweeps across the upper third, a small
## caption and the title letters fade in over it with a cinnabar seal stamped with the
## element glyph, holds, then everything dries away. Titles queue if one is showing.
##
##   card.show_title("The Northern Water Tribe", "Arrival", ElementDefs.Element.WATER)
##   await card.finished
##   card.show_region(&"fire_nation")       # region discovery helper

signal finished

const REGION_ELEMENT := {
	&"water_tribe": ElementDefs.Element.WATER, &"earth_kingdom": ElementDefs.Element.EARTH,
	&"fire_nation": ElementDefs.Element.FIRE, &"air_temple": ElementDefs.Element.AIR,
}

var showing := false
var current_title := ""

var _queue: Array[Array] = []
var _stroke: BrushStroke
var _title: Label
var _caption: Label
var _seal: Control
var _seal_glyph := ""
var _seal_color := UiTheme.SEAL
var _box: Control
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_box = Control.new()
	_box.anchor_left = 0.5
	_box.anchor_right = 0.5
	_box.offset_left = -760
	_box.offset_right = 760
	_box.offset_top = 170
	_box.offset_bottom = 370
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_stroke = BrushStroke.new(Color(0.06, 0.045, 0.04, 0.82), 4.4)
	_stroke.set_param(&"thickness", 0.8).set_param(&"tail", 0.32).set_param(&"head", 0.06).set_param(&"dryness", 0.7)
	_stroke.position = Vector2(80, 30)
	_stroke.size = Vector2(1360, 150)
	_stroke.progress = 0.0
	_box.add_child(_stroke)
	_caption = UiTheme.make_label("", UiTheme.title_font(600, 10), UiTheme.SIZE_SMALL, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_caption.position = Vector2(0, 46)
	_caption.size = Vector2(1520, 30)
	_box.add_child(_caption)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 16), 62, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_title.position = Vector2(0, 78)
	_title.size = Vector2(1520, 80)
	_title.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override(&"shadow_outline_size", 10)
	_box.add_child(_title)
	_seal = Control.new()
	_seal.size = Vector2(76, 76)
	_seal.position = Vector2(1300, 64)
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal.draw.connect(_draw_seal)
	_box.add_child(_seal)
	_box.modulate.a = 0.0
	visible = false


## Queues a banner. `element` tints the seal/caption (NONE = gold, no glyph).
func show_title(title: String, caption: String = "", element: int = ElementDefs.Element.NONE, hold: float = 3.2) -> void:
	if showing:
		_queue.append([title, caption, element, hold])
		return
	_play(title, caption, element, hold)


## Region discovery banner using WorldData names ("THE FIRE NATION").
func show_region(region_id: StringName, caption: String = "Region Discovered") -> void:
	show_title(region_title(region_id), caption, REGION_ELEMENT.get(region_id, ElementDefs.Element.NONE))


static func region_title(region_id: StringName) -> String:
	var n := WorldData.get_region_name(region_id)
	if n.begins_with("The "):
		return n
	return "The " + n


func _play(title: String, caption: String, element: int, hold: float) -> void:
	showing = true
	current_title = title
	visible = true
	_title.text = title.to_upper()
	_caption.text = caption.to_upper()
	_caption.visible = not caption.is_empty()
	var d := ElementDefs.get_data(element)
	_seal_glyph = String(d.get("glyph", ""))
	_seal_color = UiTheme.SEAL
	_caption.add_theme_color_override(&"font_color", UiTheme.element_light(element) if ElementDefs.is_valid(element) else UiTheme.GOLD)
	_seal.visible = not _seal_glyph.is_empty()
	_layout()
	_seal.queue_redraw()
	_title.visible_ratio = 0.0
	_title.modulate.a = 1.0
	_seal.scale = Vector2.ONE * 1.6
	_seal.pivot_offset = _seal.size * 0.5
	_seal.modulate.a = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_box.modulate.a = 1.0
	_stroke.sweep(0.55)
	UiFx.sound(&"ui_discovery")
	_tween = create_tween()
	_tween.tween_interval(0.25)
	_tween.tween_property(_title, "visible_ratio", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_seal, "modulate:a", 1.0, 0.08)
	_tween.parallel().tween_property(_seal, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold)
	_tween.tween_property(_box, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_done)


## Fits long titles inside the stroke and stamps the seal just past the last letter, so
## the seal never covers text ("THE NORTHERN WATER TRIBE" shrinks slightly).
func _layout() -> void:
	const BASE_SIZE := 62
	const GAP := 28.0
	var font := _title.get_theme_font(&"font")
	var seal_w := (_seal.size.x + GAP) if _seal.visible else 0.0
	var max_w := _title.size.x - 2.0 * (_seal.size.x + GAP)
	var w := font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_SIZE).x
	var fs := BASE_SIZE
	if w > max_w:
		fs = maxi(40, floori(BASE_SIZE * max_w / w))
		w = font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_title.add_theme_font_size_override(&"font_size", fs)
	# centre the title + seal group on the box
	_title.position.x = -seal_w * 0.5
	var text_right := _title.size.x * 0.5 + w * 0.5 - seal_w * 0.5
	_seal.position = Vector2(text_right + GAP, _title.position.y + (_title.size.y - _seal.size.y) * 0.5 - 4.0)


func _done() -> void:
	showing = false
	visible = false
	finished.emit()
	if not _queue.is_empty():
		var n: Array = _queue.pop_front()
		_play(n[0], n[1], n[2], n[3])


## Skips the current banner (cinematic skip).
func skip() -> void:
	if showing:
		if _tween and _tween.is_valid():
			_tween.kill()
		_box.modulate.a = 0.0
		_done()


func _draw_seal() -> void:
	var r := Rect2(Vector2.ZERO, _seal.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _seal_color
	sb.set_corner_radius_all(8)
	sb.anti_aliasing = true
	_seal.draw_style_box(sb, r)
	_seal.draw_rect(r.grow(-6.0), Color(UiTheme.PARCHMENT, 0.75), false, 2.0)
	var f := UiTheme.brush_font()
	var fs := 52
	var ts := f.get_string_size(_seal_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_seal.draw_string(f, Vector2((r.size.x - ts.x) * 0.5, r.size.y * 0.5 + fs * 0.36), _seal_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PARCHMENT)
