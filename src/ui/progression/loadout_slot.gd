class_name LoadoutSlot
extends Button
## One loadout slot on the skill tree page: the four technique slots (keys 1-4 / d-pad) and
## the signature (R / RB). Shows the equipped technique's icon and name, its key glyph, and
## glows while a technique is "armed" for equipping (tap a technique, then tap a slot).
## Desktop drag & drop: drop a technique from the tree here, drag a slot onto another slot
## to swap, drag it off the bar to unequip. The signature slot only shows the learned
## signature (the controller always uses the element's signature).

signal dropped(index: int, data: Dictionary)
signal drag_out(index: int)

## 0..3 = technique slots, 4 = signature.
var index := 0
var signature := false
var id: StringName = &""
var element := ElementDefs.Element.NONE
## A technique is armed and this slot accepts it.
var target := false

var _icon: Texture2D
var _glyph: PromptGlyph
var _t := 0.0
var _flash := 0.0
var _flash_color := UiTheme.SUCCESS


func _init(p_index: int = 0) -> void:
	index = p_index
	signature = p_index >= 4
	flat = true
	text = ""
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(118, 128) if not signature else Vector2(128, 128)


func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(s, empty)
	UiFx.wire(self)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	_glyph = PromptGlyph.for_action(&"ability_special" if signature else StringName("ability_%d" % (index + 1)), 28)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)
	resized.connect(_place_glyph)
	_place_glyph()


func _place_glyph() -> void:
	if _glyph:
		_glyph.size = _glyph.get_combined_minimum_size()
		_glyph.position = Vector2((size.x - _glyph.size.x) * 0.5, _box().end.y - _glyph.size.y * 0.5)


func set_technique(p_id: StringName, p_element: int) -> void:
	id = p_id
	element = p_element
	_icon = null
	var d := AbilityRegistry.get_def(id) if id != &"" else null
	if d:
		_icon = UiTheme.texture(d.icon) if d.icon != "" else null
		if _icon == null:
			_icon = UiTheme.emblem(element)
	queue_redraw()


func flash(color: Color) -> void:
	_flash = 1.0
	_flash_color = color
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if target or _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.2)
		queue_redraw()


func _box() -> Rect2:
	var s := 84.0 if not signature else 92.0
	return Rect2(Vector2((size.x - s) * 0.5, 4.0), Vector2(s, s))


func _draw() -> void:
	var b := _box()
	var c := b.get_center()
	var hot := has_focus() or is_hovered()
	var light := UiTheme.element_light(element if ElementDefs.is_valid(element) else GameState.element)
	var empty := id == &""
	var border := Color(UiTheme.GOLD, 0.45)
	if not empty:
		border = light
	if target:
		var k := 0.5 + 0.5 * sin(_t * 6.0)
		border = UiTheme.GOLD_HI.lerp(UiTheme.GOLD, k)
	if _flash > 0.0:
		border = border.lerp(_flash_color, _flash)
	if signature:
		var rad := b.size.x * 0.5
		draw_circle(c + Vector2(0, 3), rad, Color(0, 0, 0, 0.35), true, -1.0, true)
		draw_circle(c, rad - 1.0, Color(UiTheme.INK, 0.92 if not empty else 0.5), true, -1.0, true)
		draw_arc(c, rad - 1.0, 0, TAU, 72, border, 3.0 if not empty else 1.5, true)
		draw_arc(c, rad - 8.0, 0, TAU, 72, Color(border, border.a * 0.45), 1.5, true)
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.INK, 0.92) if not empty else Color(UiTheme.INK, 0.45)
		sb.border_color = border if not empty or target else Color(UiTheme.PARCHMENT, 0.22)
		sb.set_border_width_all(3 if (not empty or target) else 1)
		sb.set_corner_radius_all(16)
		sb.anti_aliasing = true
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 3)
		draw_style_box(sb, b)
	if empty:
		# empty: a faint brushed plus
		var pc := Color(UiTheme.PARCHMENT, 0.28 if not target else 0.7)
		draw_line(c - Vector2(16, 0), c + Vector2(16, 0), pc, 3.0, true)
		draw_line(c - Vector2(0, 16), c + Vector2(0, 16), pc, 3.0, true)
	elif _icon:
		var isz := b.size.x * 0.6
		draw_texture_rect(_icon, Rect2(c - Vector2(isz, isz) * 0.5 - Vector2(0, 4), Vector2(isz, isz)), false, Color("fff6e2"))
	if hot:
		var g := b.grow(8.0)
		var L := 18.0
		var w := 2.5
		for corner: Vector2 in [g.position, Vector2(g.end.x, g.position.y), Vector2(g.position.x, g.end.y), g.end]:
			var sx := 1.0 if corner.x <= g.position.x + 0.1 else -1.0
			var sy := 1.0 if corner.y <= g.position.y + 0.1 else -1.0
			draw_rect(Rect2(corner + Vector2(0.0 if sx > 0 else -L, 0.0 if sy > 0 else -w), Vector2(L, w)), UiTheme.GOLD_HI)
			draw_rect(Rect2(corner + Vector2(0.0 if sx > 0 else -w, 0.0 if sy > 0 else -L), Vector2(w, L)), UiTheme.GOLD_HI)
	# name under the slot
	var font := UiTheme.title_font(600, 1)
	var fs := 16
	var label := SkillTreeModel.display_name(id).to_upper() if not empty else ("SIGNATURE" if signature else "EMPTY")
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while tw > size.x + 8.0 and fs > 12:
		fs -= 1
		tw = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2((size.x - tw) * 0.5, size.y - 4.0)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.PARCHMENT, 0.85 if not empty else 0.4))


# --- drag & drop ---------------------------------------------------------------------------------

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if signature or not (data is Dictionary):
		return false
	var d := data as Dictionary
	if d.get("kind") == &"technique":
		var def := AbilityRegistry.get_def(StringName(str(d.get("id", ""))))
		return def != null and def.slot == AbilityDef.Slot.TECHNIQUE
	return d.get("kind") == &"slot" and int(d.get("index", -1)) != index


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(index, data as Dictionary)


func _get_drag_data(_at: Vector2) -> Variant:
	if signature or id == &"" or UiInput.device == &"touch":
		return null
	var pv := TextureRect.new()
	pv.texture = _icon
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pv.size = Vector2(64, 64)
	pv.position = -pv.size * 0.5
	var holder := Control.new()
	holder.add_child(pv)
	set_drag_preview(holder)
	_dragging = true
	return {"kind": &"slot", "index": index, "id": id}


var _dragging := false


func _notification(what: int) -> void:
	# A slot dragged and released somewhere that accepted nothing: unequip it.
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		var vp := get_viewport() if is_inside_tree() else null
		if vp and not vp.gui_is_drag_successful():
			drag_out.emit(index)
