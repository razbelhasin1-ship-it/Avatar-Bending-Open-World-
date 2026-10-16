class_name ShopPanel
extends CanvasLayer
## Merchant trade panel: BUY / SELL tabs over a blurred game, item rows (vector icon, name,
## description, owned count, price with a square-holed coin, action button), the purse, and a
## status line. Mouse, keyboard / controller (focus moves through the buttons, Q / E or the tab
## buttons switch tabs, Esc / B closes) and touch (rows >= 88 px when touch controls are on).
## The player is held in the Cinematic state while it is open; Events.dialogue_started / ended
## hide the touch overlay and the combat HUD.
##
##   ShopPanel.open_for(get_tree(), &"stall_water_fish", npc)   # returns the panel
##   panel.closed.connect(...)

signal closed

var shop: StringName = &""
var npc: Node3D = null
var tab: StringName = &"buy"
var is_open := false
var root: Control

var _title: Label
var _subtitle: Label
var _purse: Label
var _status: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _tab_buy: Button
var _tab_sell: Button
var _emblem: TextureRect
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _rows: Array[Button] = []
var _hold_t := 0.0


static func open_for(tree: SceneTree, shop_id: StringName, p_npc: Node3D = null) -> ShopPanel:
	var existing := tree.get_first_node_in_group(&"shop_panel") as ShopPanel
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var p := ShopPanel.new()
	p.shop = shop_id
	p.npc = p_npc
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(p)
	p.open()
	return p


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"shop_panel")
	UiInput.ensure(get_tree())
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = UiOverlay.BLUR_SHADER
	bm.set_shader_parameter(&"dim", 0.55)
	bg.material = bm
	root.add_child(bg)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InkPanel"
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -640
	panel.offset_right = 640
	panel.offset_top = -430
	panel.offset_bottom = 430
	root.add_child(panel)
	UiTheme.apply_safe_area(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 14)
	panel.add_child(v)
	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 22)
	v.add_child(head)
	_emblem = TextureRect.new()
	_emblem.custom_minimum_size = Vector2(84, 84)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	head.add_child(_emblem)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override(&"separation", 2)
	head.add_child(tv)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 6), UiTheme.SIZE_H2, UiTheme.GOLD)
	tv.add_child(_title)
	_subtitle = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	tv.add_child(_subtitle)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override(&"separation", 10)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	purse.add_child(ItemIcon.make_coin(38))
	_purse = UiTheme.make_label("0", UiTheme.title_font(700, 2), UiTheme.SIZE_H3, UiTheme.GOLD_HI)
	purse.add_child(_purse)
	var rule := BrushStroke.new(Color(UiTheme.SEAL, 0.9), 1.3)
	rule.set_param(&"thickness", 0.5).set_param(&"tail", 0.5)
	rule.custom_minimum_size = Vector2(0, 18)
	v.add_child(rule)
	# tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 14)
	v.add_child(tabs)
	_tab_buy = _tab_button("BUY", &"buy")
	_tab_sell = _tab_button("SELL", &"sell")
	tabs.add_child(_tab_buy)
	tabs.add_child(_tab_sell)
	# list
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 470)
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 8)
	_scroll.add_child(_list)
	# footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", 18)
	v.add_child(foot)
	_status = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	var close_b := Button.new()
	close_b.text = "CLOSE"
	close_b.theme_type_variation = &"GhostButton"
	close_b.custom_minimum_size = Vector2(200, UiTheme.touch_height(58))
	UiFx.wire(close_b, {"press_sound": UiFx.BACK})
	close_b.pressed.connect(close)
	foot.add_child(close_b)
	root.visible = false


func _tab_button(text: String, id: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, UiTheme.touch_height(58))
	b.theme_type_variation = &"GhostButton"
	UiFx.wire(b)
	b.pressed.connect(func() -> void: show_tab(id))
	return b


func open() -> void:
	if is_open:
		return
	is_open = true
	var d := MerchantStock.shop_def(shop)
	_title.text = String(d.get("name", "Merchant")).to_upper()
	var who := ""
	if npc != null and npc.has_method("display_name"):
		who = String(npc.call("display_name"))
	var nat := StringName(str(d.get("nation", "")))
	var e := ElementDefs.from_id(nat)
	_subtitle.text = who + ("  ·  " if who != "" and ElementDefs.is_valid(e) else "") + (String(ElementDefs.get_data(e).get("nation", "")) if ElementDefs.is_valid(e) else "")
	_emblem.texture = UiTheme.emblem(e) if ElementDefs.is_valid(e) else UiTheme.icon("icon_marker")
	_emblem.modulate = UiTheme.element_light(e) if ElementDefs.is_valid(e) else UiTheme.GOLD
	_mouse_before = Input.mouse_mode
	if not Settings.touch_controls_enabled():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hold_player()
	Events.dialogue_started.emit(npc)
	root.visible = true
	UiFx.fade_in(root, 0.18)
	UiFx.sound(UiFx.OPEN)
	show_tab(&"buy")


func close() -> void:
	if not is_open:
		return
	is_open = false
	var pl := Quests.get_player()
	if pl is PlayerCharacter:
		(pl as PlayerCharacter).exit_cinematic()
	Events.dialogue_ended.emit(npc)
	if _mouse_before == Input.MOUSE_MODE_CAPTURED:
		var sc := get_tree().get_first_node_in_group(&"playable_scene")
		if sc != null and sc.has_method("capture_mouse"):
			sc.call("capture_mouse")
	UiFx.sound(UiFx.CLOSE)
	closed.emit()
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


func _hold_player() -> void:
	var pl := Quests.get_player()
	if pl is PlayerCharacter:
		(pl as PlayerCharacter).enter_cinematic(600.0)


func _process(delta: float) -> void:
	if not is_open:
		return
	_hold_t += delta
	if _hold_t > 30.0:
		_hold_t = 0.0
		_hold_player()
	_purse.text = str(GameState.currency)


func show_tab(id: StringName) -> void:
	tab = id
	_tab_buy.theme_type_variation = &"PrimaryButton" if id == &"buy" else &"GhostButton"
	_tab_sell.theme_type_variation = &"PrimaryButton" if id == &"sell" else &"GhostButton"
	_rebuild()


func _rebuild(focus_index: int = 0) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if tab == &"buy":
		for r in MerchantStock.stock(shop):
			_list.add_child(_row(r["item"], int(r["price"]), int(r["left"]), true))
	else:
		var sell := MerchantStock.sellable()
		for r2 in sell:
			_list.add_child(_row(r2["item"], int(r2["price"]), int(r2["count"]), false))
		if sell.is_empty():
			var l := UiTheme.make_label("You have nothing this merchant wants to buy.", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_MUTED)
			_list.add_child(l)
	if not _rows.is_empty():
		UiFx.focus_silently(_rows[clampi(focus_index, 0, _rows.size() - 1)])
	elif is_instance_valid(_tab_buy):
		UiFx.focus_silently(_tab_sell if tab == &"sell" else _tab_buy)


func _row(item: StringName, price: int, count: int, buying: bool) -> Control:
	var info := TradeGoods.info(item)
	var p := PanelContainer.new()
	p.theme_type_variation = &"RowPanel"
	p.custom_minimum_size = Vector2(0, UiTheme.touch_height(84))
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 18)
	p.add_child(h)
	var icon := ItemIcon.make(item, 60)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override(&"separation", 0)
	h.add_child(tv)
	tv.add_child(UiTheme.make_label(String(info["name"]), UiTheme.body_font(), UiTheme.SIZE_BODY - 2, UiTheme.PARCHMENT))
	var desc := UiTheme.make_label(String(info["desc"]), UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	tv.add_child(desc)
	var own_text := ""
	if buying:
		var owned := GameState.item_count(item)
		own_text = ("owned %d" % owned) if owned > 0 else ""
		if count >= 0:
			own_text += ("   " if own_text != "" else "") + ("%d left" % count if count > 0 else "sold out")
	else:
		own_text = "×%d" % count
	var own := UiTheme.make_label(own_text, UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	own.custom_minimum_size = Vector2(150, 0)
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	own.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(own)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override(&"separation", 6)
	ph.custom_minimum_size = Vector2(110, 0)
	ph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(ph)
	ph.add_child(ItemIcon.make_coin(26))
	var afford := not buying or GameState.currency >= price
	ph.add_child(UiTheme.make_label(str(price), UiTheme.title_font(700, 1), UiTheme.SIZE_BODY, UiTheme.GOLD_HI if afford else UiTheme.DANGER))
	var b := Button.new()
	b.text = "BUY" if buying else "SELL"
	b.theme_type_variation = &"PrimaryButton" if buying else &"GhostButton"
	b.custom_minimum_size = Vector2(150, UiTheme.touch_height(60))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = buying and count == 0
	UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
	var idx := _rows.size()
	b.pressed.connect(func() -> void:
		if buying:
			_buy(item, idx)
		else:
			_sell(item, idx))
	h.add_child(b)
	_rows.append(b)
	return p


func _buy(item: StringName, idx: int) -> void:
	var r := MerchantStock.buy(shop, item)
	match r:
		&"":
			_status.text = "Bought %s." % TradeGoods.display_name(item)
			_status.add_theme_color_override(&"font_color", UiTheme.SUCCESS)
			Audio.play_ui(&"pickup", -4.0)
		&"coins":
			_status.text = "Not enough coins."
			_status.add_theme_color_override(&"font_color", UiTheme.DANGER)
			UiFx.sound(&"ui_error")
			UiFx.shake(_purse, 6.0, 0.3)
		&"sold_out":
			_status.text = "Sold out until tomorrow."
			_status.add_theme_color_override(&"font_color", UiTheme.DANGER)
			UiFx.sound(&"ui_error")
	_rebuild(idx)


func _sell(item: StringName, idx: int) -> void:
	var got := MerchantStock.sell(item)
	if got > 0:
		_status.text = "Sold %s for %d coins." % [TradeGoods.display_name(item), got]
		_status.add_theme_color_override(&"font_color", UiTheme.SUCCESS)
		Audio.play_ui(&"pickup", -6.0)
	_rebuild(idx)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_Q or k == KEY_E:
			get_viewport().set_input_as_handled()
			show_tab(&"sell" if tab == &"buy" else &"buy")


func row_buttons() -> Array[Button]:
	return _rows
