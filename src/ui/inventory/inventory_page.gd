class_name InventoryPage
extends JourneyPage
## INVENTORY: what the journey has gathered - items (TradeGoods catalog: herbs, food, drink,
## supplies, trinkets, materials, goods, quest items) with their vector icons and counts, the
## purse, and the collectibles of the world: places discovered per nation.
##
## * ITEMS: category filters, a grid of tiles (focus / hover / tap shows the detail), the
##   detail card (description, category, origin, value, effect) and USE for consumables
##   (TradeGoods.use_item on the live player: heals / restores chi, refuses when full).
## * DISCOVERIES: per region, places found / total with a brushed progress bar and the names
##   of the places found (undiscovered ones stay a count, no spoilers).

const CATEGORY_NAMES := {&"all": "ALL", &"herb": "HERBS", &"food": "FOOD", &"drink": "DRINK", &"supply": "SUPPLIES",
	&"trinket": "TRINKETS", &"material": "MATERIALS", &"goods": "GOODS", &"quest": "QUEST"}
const REGIONS: Array[StringName] = [&"water_tribe", &"earth_kingdom", &"fire_nation", &"air_temple", &"wilds"]

var view: StringName = &"items"
var category: StringName = &"all"
var selected: StringName = &""
var tiles: Array[Button] = []

var _items_btn: Button
var _disc_btn: Button
var _purse: Label
var _cats: HBoxContainer
var _cat_buttons: Dictionary = {}
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _empty: Label
var _items_view: Control
var _disc_view: ScrollContainer
var _disc_list: VBoxContainer
var _icon_holder: CenterContainer
var _name: Label
var _kind: Label
var _desc: Label
var _effect: Label
var _value: Label
var _use: Button
var _detail: PanelContainer
## Frame the selection last changed (a click / tap that focuses a tile only selects it).
var _select_frame := -1
## The tile press under way began on the already-selected tile (a second press uses it).
var _press_uses := false


func _build() -> void:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override(&"separation", 12)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 12)
	v.add_child(top)
	_items_btn = _toggle("ITEMS", func() -> void: set_view(&"items"))
	_disc_btn = _toggle("DISCOVERIES", func() -> void: set_view(&"discoveries"))
	top.add_child(_items_btn)
	top.add_child(_disc_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override(&"separation", 10)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(purse)
	purse.add_child(ItemIcon.make_coin(36))
	_purse = UiTheme.make_label("0", UiTheme.title_font(700, 2), UiTheme.SIZE_H3, UiTheme.GOLD_HI)
	purse.add_child(_purse)
	purse.add_child(UiTheme.make_label("COPPER", UiTheme.title_font(600, 3), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED))
	# items view
	_items_view = HBoxContainer.new()
	_items_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_items_view as HBoxContainer).add_theme_constant_override(&"separation", 26)
	v.add_child(_items_view)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 12)
	_items_view.add_child(left)
	_cats = HBoxContainer.new()
	_cats.add_theme_constant_override(&"separation", 6)
	left.add_child(_cats)
	for c: StringName in CATEGORY_NAMES:
		var b := Button.new()
		b.text = CATEGORY_NAMES[c]
		b.theme_type_variation = &"GhostButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, UiTheme.touch_height(48))
		b.add_theme_font_size_override(&"font_size", UiTheme.SIZE_TINY + 1)
		var cc := c
		b.pressed.connect(func() -> void:
			UiFx.sound(UiFx.CLICK)
			set_category(cc))
		_cats.add_child(b)
		_cat_buttons[c] = b
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_grid_scroll)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override(&"h_separation", 12)
	_grid.add_theme_constant_override(&"v_separation", 12)
	_grid_scroll.add_child(_grid)
	_empty = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_empty)
	_build_detail()
	# discoveries view
	_disc_view = ScrollContainer.new()
	_disc_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_disc_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_disc_view)
	_disc_list = VBoxContainer.new()
	_disc_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_disc_list.add_theme_constant_override(&"separation", 16)
	_disc_view.add_child(_disc_list)


func _toggle(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, UiTheme.touch_height(56))
	b.pressed.connect(func() -> void:
		UiFx.sound(UiFx.CLICK)
		cb.call())
	return b


func _build_detail() -> void:
	_detail = PanelContainer.new()
	_detail.custom_minimum_size = Vector2(560, 0)
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.62), Color(UiTheme.GOLD, 0.35), 1.0)
	ps.grain = 0.3
	ps.set_content_margin_all(28)
	_detail.add_theme_stylebox_override(&"panel", ps)
	_items_view.add_child(_detail)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	_detail.add_child(v)
	_icon_holder = CenterContainer.new()
	_icon_holder.custom_minimum_size = Vector2(0, 170)
	v.add_child(_icon_holder)
	_name = UiTheme.make_label("", UiTheme.title_font(700, 4), UiTheme.SIZE_H3, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_name)
	_kind = UiTheme.make_label("", UiTheme.title_font(600, 3), UiTheme.SIZE_TINY, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_kind)
	var rule := BrushStroke.new(Color(UiTheme.SEAL, 0.85), 1.7)
	rule.set_param(&"thickness", 0.45).set_param(&"tail", 0.5)
	rule.custom_minimum_size = Vector2(0, 14)
	v.add_child(rule)
	_desc = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(500, 0)
	v.add_child(_desc)
	_effect = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.SUCCESS)
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_effect)
	var vh := HBoxContainer.new()
	vh.add_theme_constant_override(&"separation", 8)
	v.add_child(vh)
	vh.add_child(ItemIcon.make_coin(24))
	_value = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT_DIM)
	vh.add_child(_value)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_use = Button.new()
	_use.name = "Use"
	_use.text = "USE"
	_use.theme_type_variation = &"PrimaryButton"
	_use.custom_minimum_size = Vector2(0, UiTheme.touch_height(64))
	UiFx.wire(_use, {"press_sound": UiFx.CONFIRM})
	_use.pressed.connect(use_selected)
	v.add_child(_use)


# --- refresh --------------------------------------------------------------------------------------

func on_open(_args: Dictionary) -> void:
	refresh()


func set_view(v: StringName) -> void:
	view = v
	refresh()


func set_category(c: StringName) -> void:
	category = c
	selected = &""
	refresh()


func owned_items() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: Variant in GameState.inventory:
		var id := StringName(str(k))
		if int(GameState.inventory[k]) <= 0:
			continue
		if category != &"all":
			var cat := TradeGoods.category(id)
			if cat != category and not (category == &"food" and cat == &"drink" and false):
				continue
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ca := TradeGoods.CATEGORIES.find(TradeGoods.category(a))
		var cb := TradeGoods.CATEGORIES.find(TradeGoods.category(b))
		if ca != cb:
			return ca < cb
		return TradeGoods.display_name(a) < TradeGoods.display_name(b))
	return out


func refresh() -> void:
	_purse.text = str(GameState.currency)
	_items_btn.theme_type_variation = &"PrimaryButton" if view == &"items" else &"GhostButton"
	_disc_btn.theme_type_variation = &"PrimaryButton" if view == &"discoveries" else &"GhostButton"
	_items_view.visible = view == &"items"
	_disc_view.visible = view == &"discoveries"
	for c: StringName in _cat_buttons:
		var b: Button = _cat_buttons[c]
		b.add_theme_color_override(&"font_color", UiTheme.GOLD_HI if c == category else UiTheme.PARCHMENT_MUTED)
	if view == &"discoveries":
		_build_discoveries()
		refresh_hints()
		return
	for t in _grid.get_children():
		_grid.remove_child(t)
		t.queue_free()
	tiles.clear()
	var items := owned_items()
	for id in items:
		var t := _tile(id)
		_grid.add_child(t)
		tiles.append(t)
	_empty.visible = items.is_empty()
	_empty.text = "Your pack is empty." if category == &"all" else "Nothing of this kind in your pack."
	if not items.has(selected):
		selected = items[0] if not items.is_empty() else &""
	_show(selected)
	var cur := _tile_for(selected)
	if cur and is_visible_in_tree():
		UiFx.focus_silently(cur)
	refresh_hints()


func _tile_for(id: StringName) -> Button:
	for t in tiles:
		if StringName(t.get_meta(&"item", &"")) == id:
			return t
	return null


func _tile(id: StringName) -> Button:
	var b := Button.new()
	b.name = "Item_%s" % String(id)
	b.set_meta(&"item", id)
	b.custom_minimum_size = Vector2(150, 168)
	b.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, empty)
	var icon := ItemIcon.make(id, 84)
	icon.position = Vector2(33, 16)
	b.add_child(icon)
	var count := GameState.item_count(id)
	b.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, b.size)
		var hot := b.has_focus() or b.is_hovered()
		var sel := StringName(b.get_meta(&"item", &"")) == selected
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UiTheme.INK_3, 0.92) if (hot or sel) else Color(UiTheme.INK_2, 0.65)
		sb.border_color = Color(UiTheme.GOLD, 0.85 if hot else (0.5 if sel else 0.18))
		sb.set_border_width_all(2 if hot else 1)
		sb.set_corner_radius_all(10)
		b.draw_style_box(sb, r)
		var f := UiTheme.title_font(600, 1)
		var name_text := TradeGoods.display_name(id)
		var fs := 15
		while f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > r.size.x - 14 and fs > 11:
			fs -= 1
		var w := f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		b.draw_string(f, Vector2((r.size.x - w) * 0.5, r.size.y - 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.PARCHMENT if hot else UiTheme.PARCHMENT_DIM)
		if count > 1:
			var c := Vector2(r.size.x - 24, 22)
			b.draw_circle(c, 15.0, UiTheme.GOLD, true, -1.0, true)
			var ct := "×%d" % count if count < 100 else "99+"
			var cf := UiTheme.title_font(800)
			var cw := cf.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			b.draw_string(cf, c + Vector2(-cw * 0.5, 5), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.INK)
		if TradeGoods.category(id) == &"quest":
			b.draw_string(UiTheme.title_font(700, 2), Vector2(10, 22), "QUEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.SEAL.lightened(0.3)))
	UiFx.wire(b)
	b.focus_entered.connect(func() -> void:
		if selected != id:
			_select_frame = Engine.get_process_frames()
		selected = id
		_show(id)
		for t in tiles:
			t.queue_redraw())
	b.mouse_exited.connect(b.queue_redraw)
	# a click / tap focuses (selects) the tile in the same frame it goes down: only a press that
	# starts on the tile already selected uses it (Enter / A on a focused tile always does)
	b.button_down.connect(func() -> void:
		_press_uses = selected == id and _select_frame != Engine.get_process_frames())
	b.pressed.connect(func() -> void:
		if _press_uses and selected == id and TradeGoods.is_usable(id):
			use_selected()
		else:
			if selected != id:
				_select_frame = Engine.get_process_frames()
			selected = id
			_show(id)
		_press_uses = false)
	return b


func _show(id: StringName) -> void:
	for c in _icon_holder.get_children():
		_icon_holder.remove_child(c)
		c.queue_free()
	if id == &"":
		_name.text = ""
		_kind.text = ""
		_desc.text = "Herbs, food and drink you gather or buy can be used here to heal or restore chi."
		_effect.text = ""
		_value.text = ""
		_use.visible = false
		return
	var info := TradeGoods.info(id)
	_icon_holder.add_child(ItemIcon.make(id, 150))
	_name.text = String(info["name"]).to_upper()
	var nat := ElementDefs.from_id(StringName(str(info.get("nation", ""))))
	var origin := String(ElementDefs.get_data(nat).get("nation", "")) if ElementDefs.is_valid(nat) else ""
	_kind.text = ("%s%s  ·  ×%d" % [String(CATEGORY_NAMES.get(StringName(str(info["category"])), "ITEM")), ("  ·  " + origin.to_upper()) if origin != "" else "", GameState.item_count(id)])
	_desc.text = String(info.get("desc", ""))
	var use: Dictionary = info.get("use", {})
	var parts := PackedStringArray()
	if int(use.get("heal", 0)) > 0:
		parts.append("Restores %d health" % int(use["heal"]))
	if int(use.get("chi", 0)) > 0:
		parts.append("%d chi" % int(use["chi"]))
	_effect.text = "  ·  ".join(parts)
	var sell := TradeGoods.sell_price(id)
	_value.text = ("Worth %d copper  ·  merchants pay %d" % [int(info["value"]), sell]) if sell > 0 else ("Worth %d copper  ·  not for sale" % int(info["value"]) if StringName(str(info["category"])) != &"quest" else "Needed for a quest  ·  not for sale")
	_use.visible = TradeGoods.is_usable(id)
	_use.text = "USE"
	_use.disabled = player() == null


## Uses one of the selected consumable on the live player.
func use_selected() -> bool:
	if selected == &"" or not TradeGoods.is_usable(selected):
		return false
	var id := selected
	if TradeGoods.use_item(id, player()):
		Audio.play_ui(&"pickup", -6.0)
		_status("Used %s." % TradeGoods.display_name(id), UiTheme.SUCCESS)
		refresh()
		return true
	UiFx.sound(UiFx.ERROR)
	_status("You are already at full strength.", UiTheme.PARCHMENT_DIM)
	return false


func _status(text: String, color: Color) -> void:
	if book != null and book.has_method("set_status"):
		book.call("set_status", text, color)


# --- discoveries ----------------------------------------------------------------------------------

func _build_discoveries() -> void:
	for c in _disc_list.get_children():
		_disc_list.remove_child(c)
		c.queue_free()
	var total_known := 0
	var total := 0
	for r in REGIONS:
		var pois := WorldData.get_pois_in_region(r)
		if pois.is_empty():
			continue
		var known: Array[String] = []
		for p in pois:
			if GameState.discovered_pois.has(String(p["id"])):
				known.append(String(p["name"]))
		total_known += known.size()
		total += pois.size()
		_disc_list.add_child(_region_row(r, known, pois.size()))
	var head_text := "%d of %d places discovered across the four nations  ·  %d%% of the world explored" % [total_known, total, int(round(MapModel.revealed_ratio() * 100.0))]
	if total == 0:
		head_text = "%d places discovered. The world's records are not at hand here (training grounds)." % GameState.discovered_pois.size()
	var head := UiTheme.make_label(head_text, UiTheme.title_font(600, 2), UiTheme.SIZE_SMALL, UiTheme.GOLD)
	_disc_list.add_child(head)
	_disc_list.move_child(head, 0)


func _region_row(r: StringName, known: Array[String], n: int) -> Control:
	var p := PanelContainer.new()
	var ps := UiFrameStyle.make(Color(UiTheme.INK_2, 0.7), Color(UiTheme.GOLD, 0.25), 1.0)
	ps.set_content_margin_all(18)
	p.add_theme_stylebox_override(&"panel", ps)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 20)
	p.add_child(h)
	var e := _region_element(r)
	var em := TextureRect.new()
	em.texture = UiTheme.emblem(e) if ElementDefs.is_valid(e) else UiTheme.icon("map_landmark")
	em.custom_minimum_size = Vector2(64, 64)
	em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	em.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	em.modulate = UiTheme.element_light(e) if ElementDefs.is_valid(e) else UiTheme.PARCHMENT_DIM
	h.add_child(em)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", 6)
	h.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var name := UiTheme.make_label(WorldData.get_region_name(r).to_upper(), UiTheme.title_font(700, 4), UiTheme.SIZE_SMALL + 2, UiTheme.PARCHMENT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	top.add_child(UiTheme.make_label("%d / %d" % [known.size(), n], UiTheme.title_font(700, 2), UiTheme.SIZE_SMALL + 2, UiTheme.GOLD_HI))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.show_percentage = false
	bar.max_value = n
	bar.value = known.size()
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.element_light(e) if ElementDefs.is_valid(e) else UiTheme.GOLD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"fill", fill)
	v.add_child(bar)
	var list := UiTheme.make_label(", ".join(known) if not known.is_empty() else "Nothing found here yet.", UiTheme.body_font(), UiTheme.SIZE_TINY + 1, UiTheme.PARCHMENT_DIM if not known.is_empty() else UiTheme.PARCHMENT_MUTED)
	list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(list)
	return p


static func _region_element(r: StringName) -> int:
	match r:
		&"water_tribe": return ElementDefs.Element.WATER
		&"earth_kingdom": return ElementDefs.Element.EARTH
		&"fire_nation": return ElementDefs.Element.FIRE
		&"air_temple": return ElementDefs.Element.AIR
	return ElementDefs.Element.NONE


# --- input ---------------------------------------------------------------------------------------

func initial_focus() -> Control:
	return _tile_for(selected) if view == &"items" else null


func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).physical_keycode == KEY_TAB:
			set_view(&"discoveries" if view == &"items" else &"items")
			return true
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
		set_view(&"discoveries" if view == &"items" else &"items")
		return true
	return false


func hints() -> Array:
	return [
		{"kbm": [{"type": "key", "code": KEY_Q}, {"type": "key", "code": KEY_E}],
			"pad": [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], "text": "Pages"},
		{"kbm": [{"type": "key", "code": KEY_TAB}], "pad": [{"type": "joy_button", "button": JOY_BUTTON_Y}], "text": "Items / Discoveries"},
		{"action": &"ui_accept", "text": "Use"},
	]
