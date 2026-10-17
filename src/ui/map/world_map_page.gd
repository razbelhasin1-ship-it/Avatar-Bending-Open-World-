class_name WorldMapPage
extends JourneyPage
## MAP: the parchment world map (MapCanvas) with a place card and a legend.
##
## * Hover / tap / reticle shows a place on the card: name, kind, region, whether it was
##   discovered, distance + direction, its description; quest markers show their quest.
## * FAST TRAVEL to known shrines, training grounds, villages, ports and cities (card button,
##   double-click, Enter / A on the reticle) after a confirmation, through the world scene's
##   TravelSystem.travel_to (MapModel.travel). Refused with a reason in combat, in the
##   training grounds, while travelling, when undiscovered or already there.
## * Zoom / pan: wheel + drag, pinch + drag, WASD / arrows / left stick + RT / LT or +/-;
##   on-screen + / - / centre buttons for touch. C / Y centres on the player.
## * open args: {"place": id}, {"quest": id}, {"npc": id, "label": text} (pins a master).

var canvas: MapCanvas
var card_place: Dictionary = {}

var _title: Label
var _kind: Label
var _state: Label
var _dist: Label
var _desc: Label
var _travel: Button
var _travel_why: Label
var _quest_btn: Button
var _legend: VBoxContainer
var _region: Label
var _explored: Label
var _sticky := false
var _pan_hold := 0.0


func _build() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override(&"separation", 24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var frame := PanelContainer.new()
	frame.name = "MapFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0.36, 0.26, 0.17)
	fs.border_color = Color(UiTheme.GOLD, 0.6)
	fs.set_border_width_all(2)
	fs.set_content_margin_all(6)
	fs.shadow_color = Color(0, 0, 0, 0.45)
	fs.shadow_size = 10
	frame.add_theme_stylebox_override(&"panel", fs)
	h.add_child(frame)
	var holder := Control.new()
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(holder)
	canvas = MapCanvas.new()
	canvas.name = "Canvas"
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(canvas)
	canvas.hovered.connect(_on_hover)
	canvas.clicked.connect(_on_click)
	canvas.activated.connect(func(p: Dictionary) -> void: _activate(p))
	_build_map_controls(holder)
	_build_card(h)


func _build_map_controls(holder: Control) -> void:
	# top-left: where you are
	var tl := PanelContainer.new()
	var ts := UiFrameStyle.make(Color(UiTheme.INK, 0.78), Color(UiTheme.GOLD, 0.45), 1.0)
	ts.content_margin_left = 18
	ts.content_margin_right = 18
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	tl.add_theme_stylebox_override(&"panel", ts)
	tl.position = Vector2(18, 18)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tl)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", 0)
	tl.add_child(tv)
	_region = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_SMALL, UiTheme.GOLD_HI)
	tv.add_child(_region)
	_explored = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT_DIM)
	tv.add_child(_explored)
	# top-right: zoom / centre (touch-sized)
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -UiTheme.touch_height(72) - 18
	tr.offset_right = -18
	tr.offset_top = 18
	tr.add_theme_constant_override(&"separation", 8)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tr)
	for spec: Array in [["+", "zoom_in"], ["−", "zoom_out"], ["◎", "centre"]]:
		var b := Button.new()
		b.name = "Map_%s" % spec[1]
		b.text = ""
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2.ONE * UiTheme.touch_height(72)
		b.tooltip_text = {"zoom_in": "Zoom in", "zoom_out": "Zoom out", "centre": "Centre on you"}[spec[1]]
		var kind: String = spec[1]
		b.draw.connect(func() -> void: _draw_map_button(b, kind))
		b.pressed.connect(_on_map_button.bind(kind))
		tr.add_child(b)


func _on_map_button(kind: String) -> void:
	UiFx.sound(UiFx.CLICK)
	match kind:
		"zoom_in":
			canvas.zoom_at(canvas.size * 0.5, 1.6)
		"zoom_out":
			canvas.zoom_at(canvas.size * 0.5, 1.0 / 1.6)
		_:
			centre_on_player()


func _draw_map_button(b: Button, kind: String) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	var c := r.get_center()
	var hot := b.is_hovered() or b.button_pressed
	b.draw_circle(c, r.size.x * 0.46, Color(UiTheme.INK, 0.82 if not hot else 0.95), true, -1.0, true)
	b.draw_arc(c, r.size.x * 0.46, 0, TAU, 40, Color(UiTheme.GOLD, 0.7 if not hot else 1.0), 2.0, true)
	var col := UiTheme.PARCHMENT if not hot else UiTheme.GOLD_HI
	var s := r.size.x * 0.2
	match kind:
		"zoom_in":
			b.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, 3.0, true)
			b.draw_line(c - Vector2(0, s), c + Vector2(0, s), col, 3.0, true)
		"zoom_out":
			b.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), col, 3.0, true)
		_:
			b.draw_arc(c, s, 0, TAU, 32, col, 2.5, true)
			b.draw_circle(c, 3.5, col, true, -1.0, true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				b.draw_line(c + d * (s + 3.0), c + d * (s + 9.0), col, 2.5, true)


func _build_card(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "Card"
	panel.custom_minimum_size = Vector2(500, 0)
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.62), Color(UiTheme.GOLD, 0.35), 1.0)
	ps.grain = 0.3
	ps.set_content_margin_all(26)
	panel.add_theme_stylebox_override(&"panel", ps)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 4), UiTheme.SIZE_H3, UiTheme.PARCHMENT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(440, 0)
	v.add_child(_title)
	_kind = UiTheme.make_label("", UiTheme.title_font(600, 3), UiTheme.SIZE_TINY, UiTheme.GOLD)
	v.add_child(_kind)
	_state = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL - 1, UiTheme.SUCCESS)
	v.add_child(_state)
	_dist = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL - 2, UiTheme.PARCHMENT_DIM)
	v.add_child(_dist)
	var rule := BrushStroke.new(Color(UiTheme.SEAL, 0.85), 2.2)
	rule.set_param(&"thickness", 0.45).set_param(&"tail", 0.5)
	rule.custom_minimum_size = Vector2(0, 14)
	v.add_child(rule)
	_desc = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(440, 0)
	v.add_child(_desc)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer)
	_travel = Button.new()
	_travel.name = "FastTravel"
	_travel.text = "FAST TRAVEL"
	_travel.icon = UiTheme.icon("map_travel")
	_travel.add_theme_constant_override(&"icon_max_width", 30)
	_travel.theme_type_variation = &"PrimaryButton"
	_travel.custom_minimum_size = Vector2(0, UiTheme.touch_height(64))
	_travel.focus_mode = Control.FOCUS_NONE
	UiFx.wire(_travel, {"press_sound": UiFx.CONFIRM})
	_travel.pressed.connect(func() -> void: request_travel(card_place))
	v.add_child(_travel)
	_travel_why = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	_travel_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_travel_why)
	_quest_btn = Button.new()
	_quest_btn.name = "OpenQuest"
	_quest_btn.text = "OPEN IN JOURNAL"
	_quest_btn.icon = UiTheme.icon("icon_journal")
	_quest_btn.add_theme_constant_override(&"icon_max_width", 28)
	_quest_btn.custom_minimum_size = Vector2(0, UiTheme.touch_height(60))
	_quest_btn.focus_mode = Control.FOCUS_NONE
	UiFx.wire(_quest_btn)
	_quest_btn.pressed.connect(func() -> void:
		if card_place.get("kind") == &"quest" and book != null:
			book.call(&"show_page", &"journal", {"quest": card_place["id"]}))
	v.add_child(_quest_btn)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	v.add_child(UiTheme.make_label("LEGEND", UiTheme.title_font(700, 4), UiTheme.SIZE_TINY, UiTheme.GOLD))
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override(&"separation", 2)
	v.add_child(_legend)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 4)
	_legend.add_child(grid)
	for spec: Array in [["map_player", "You", UiTheme.element_light(GameState.element)], ["icon_paw", "Companion", UiTheme.PARCHMENT_DIM],
			["map_travel", "Fast-travel point", UiTheme.GOLD], ["map_city", "City", UiTheme.PARCHMENT],
			["icon_marker", "Quest objective", MapOverlay.QUEST], ["map_giver", "Quest offered", UiTheme.SEAL.lightened(0.2)],
			["map_unknown", "Undiscovered", UiTheme.PARCHMENT_MUTED], ["map_port", "Ferry route", Color(0.55, 0.78, 0.85)]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var ic := TextureRect.new()
		ic.texture = UiTheme.icon(spec[0])
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		ic.modulate = spec[2]
		row.add_child(ic)
		row.add_child(UiTheme.make_label(spec[1], UiTheme.body_font(), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT_DIM))
		grid.add_child(row)


# --- open ---------------------------------------------------------------------------------------

func on_open(args: Dictionary) -> void:
	var pl := player()
	MapModel.ensure_seeded(pl.global_position if pl else Vector3.INF)
	if pl:
		MapModel.note_position(pl.global_position)
	canvas.refresh_reveal()
	canvas.overlay.player = pl
	var comp: Variant = pl.call("get_companion") if pl != null and pl.has_method("get_companion") else null
	canvas.overlay.companion = comp as Node3D if comp is Node3D and is_instance_valid(comp) else null
	canvas.overlay.quest_markers = Quests.map_markers() if Quests != null else ([] as Array[Dictionary])
	canvas.overlay.pin = {}
	_sticky = false
	canvas.select({})
	var region := GameState.region if GameState.region != &"" else (WorldData.get_region(pl.global_position.x, pl.global_position.z) if pl else &"")
	_region.text = (WorldData.get_region_name(region) if region != &"" else "The Wilds").to_upper()
	var known := 0
	for p in MapModel.places():
		if p["kind"] == &"poi" and MapModel.is_known(p):
			known += 1
	_explored.text = "%d%% of the world explored  ·  %d of %d places discovered" % [int(round(MapModel.revealed_ratio() * 100.0)), known, WorldData.get_pois().size()]
	# where to look
	await get_tree().process_frame
	if args.has("npc"):
		var pos := NpcRegistry.position_of(StringName(str(args["npc"])))
		if pos.is_finite():
			canvas.overlay.pin = {"position": pos, "label": String(args.get("label", NpcRegistry.display_name(StringName(str(args["npc"])))))}
			canvas.focus_on(pos, 3.2, true)
			_show_card({"id": &"pin", "kind": &"pin", "name": canvas.overlay.pin["label"], "position": pos})
			_sticky = true
			return
	if args.has("quest"):
		var q := StringName(str(args["quest"]))
		for m in canvas.overlay.quest_markers:
			if m["quest"] == q:
				canvas.focus_on(m["position"], 2.6, true)
				var e := {"id": q, "kind": &"quest", "marker": m["kind"], "objective": m.get("objective", &""), "name": String(m.get("text", "")),
					"position": m["position"], "tracked": bool(m.get("tracked", false))}
				canvas.select(e)
				_show_card(e)
				_sticky = true
				return
	if args.has("place"):
		var p2 := MapModel.place_by_id(StringName(str(args["place"])))
		if not p2.is_empty():
			canvas.focus_on(p2["position"], 2.6, true)
			canvas.select(p2)
			_show_card(p2)
			_sticky = true
			return
	if pl:
		canvas.focus_on(pl.global_position, 2.2, true)
	_show_card({})


func on_close() -> void:
	canvas.cursor_mode = false


func initial_focus() -> Control:
	return null


func centre_on_player() -> void:
	var pl := player()
	if pl:
		canvas.focus_on(pl.global_position)


# --- card ---------------------------------------------------------------------------------------

func _on_hover(p: Dictionary) -> void:
	if _sticky and not canvas.cursor_mode:
		return
	_show_card(p)


func _on_click(p: Dictionary) -> void:
	if p.is_empty():
		_sticky = false
		canvas.select({})
		_show_card({})
		return
	UiFx.sound(UiFx.CLICK)
	_sticky = true
	canvas.select(p)
	_show_card(p)


func _show_card(p: Dictionary) -> void:
	card_place = p
	_quest_btn.visible = false
	_travel.visible = false
	_travel_why.text = ""
	var pl := player()
	if p.is_empty():
		_title.text = "THE FOUR NATIONS"
		_kind.text = "WORLD MAP"
		_state.text = ""
		_dist.text = ""
		var tips := "Hover or tap a place to read about it. Fast travel to shrines, training grounds, villages, ports and cities you have visited (gold badge)."
		if UiInput.device == &"pad":
			tips = "Move the reticle with the left stick, zoom with the triggers. Press A on a place you know to travel there."
		_desc.text = tips
		return
	var kind: StringName = p.get("kind", &"")
	_title.text = String(p.get("name", "")).to_upper()
	if kind == &"quest":
		var entry := Quests.journal_entry(p["id"]) if Quests != null else {}
		_kind.text = ("QUEST OFFERED" if p.get("marker") == &"giver" else "QUEST OBJECTIVE") + ("  ·  TRACKED" if bool(p.get("tracked", false)) else "")
		_title.text = String(entry.get("title", p.get("name", ""))).to_upper()
		_state.text = String(p.get("name", "")) if p.get("marker") != &"giver" else "Speak to %s" % String(entry.get("giver_name", "the quest giver"))
		_state.add_theme_color_override(&"font_color", MapOverlay.QUEST.lightened(0.2))
		_desc.text = String(entry.get("summary", ""))
		_quest_btn.visible = p.get("marker") != &"giver" or Quests.state(p["id"]) != &"none"
		_dist.text = _distance(pl, p["position"])
		return
	if kind == &"pin":
		_kind.text = "BENDING MASTER"
		_state.text = "Speak to them to train."
		_state.add_theme_color_override(&"font_color", UiTheme.GOLD_HI)
		_desc.text = "Masters teach the advanced techniques of your art. Find them and ask for a lesson."
		_dist.text = _distance(pl, p["position"])
		return
	var known := MapModel.is_known(p)
	var region := WorldData.get_region_name(StringName(p.get("region", &"")))
	_kind.text = ("%s  ·  %s" % [MapModel.type_name(p), region]).to_upper()
	if not known and kind == &"poi":
		_title.text = "UNDISCOVERED"
		_state.text = "Not yet found"
		_state.add_theme_color_override(&"font_color", UiTheme.PARCHMENT_MUTED)
		_desc.text = "Something waits here. Travel there on foot to discover it."
	else:
		_state.text = ("Visited" if kind != &"poi" else "Discovered") if known else "Not yet visited"
		_state.add_theme_color_override(&"font_color", UiTheme.SUCCESS if known else UiTheme.PARCHMENT_MUTED)
		_desc.text = _description(p)
	_dist.text = _distance(pl, p["position"])
	if MapModel.is_travel_point(p):
		_travel.visible = true
		var why := MapModel.travel_block_reason(p)
		_travel.disabled = why != ""
		_travel_why.text = why if why != "" else ("Press %s on the map to travel." % _accept_label() if UiInput.device != &"touch" else "")


func _accept_label() -> String:
	return "A" if UiInput.device == &"pad" else "Enter"


func _distance(pl: Node3D, pos: Vector3) -> String:
	if pl == null:
		return ""
	var d := pl.global_position.distance_to(pos)
	if d < 30.0:
		return "You are here"
	var b := MapModel.bearing_text(pl.global_position, pos)
	return "%s %s of you" % [MapModel.distance_text(d), b]


func _description(p: Dictionary) -> String:
	var d := String(p.get("description", ""))
	if d != "":
		return d
	match p.get("kind", &""):
		&"city":
			var r := WorldData.get_region_name(StringName(p.get("region", &"")))
			return "%s of %s." % [MapModel.type_name(p), r] if MapModel.type_name(p) != "" else r
		&"port":
			var lines := PackedStringArray()
			for rt in TravelSystem.routes_from(p["id"]):
				lines.append(TravelSystem.port_label(TravelSystem.port_by_id(rt["to"])))
			return ("Ferries sail from here to %s." % ", ".join(lines)) if not lines.is_empty() else "A harbour on the coast."
		&"village":
			return "A %s." % MapModel.type_name(p).to_lower()
	return ""


# --- fast travel --------------------------------------------------------------------------------

func _activate(p: Dictionary) -> void:
	if p.get("kind") == &"quest":
		if book != null:
			book.call(&"show_page", &"journal", {"quest": p["id"]})
		return
	if MapModel.is_travel_point(p):
		request_travel(p)


## Confirms, closes the book and fast travels. Returns true when the trip happened.
func request_travel(p: Dictionary) -> bool:
	var why := MapModel.travel_block_reason(p)
	if why != "":
		UiFx.sound(UiFx.ERROR)
		_status(why, UiTheme.DANGER)
		UiFx.shake(_travel, 6.0, 0.25)
		return false
	if book is JourneyBook:
		var ans: StringName = await (book as JourneyBook).confirm("FAST TRAVEL", "Travel to %s?" % String(p["name"]),
			[[&"go", "TRAVEL"], [&"stay", "STAY"]])
		if ans != &"go":
			return false
		(book as JourneyBook).return_to_pause = false
		(book as JourneyBook).close()
	await get_tree().process_frame
	var ok: bool = await MapModel.travel(p)
	if ok:
		Events.notify.emit("Arrived at %s" % String(p["name"]), &"info")
	return ok


func _status(text: String, color: Color) -> void:
	if book != null and book.has_method("set_status"):
		book.call("set_status", text, color)


# --- input ---------------------------------------------------------------------------------------

func handle_input(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event.is_action_pressed(&"ui_accept"):
		var p := canvas.hover if canvas.cursor_mode else (canvas.selected if not canvas.selected.is_empty() else canvas.hover)
		if not p.is_empty():
			canvas.select(p)
			_show_card(p)
			_activate(p)
		return true
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_C, KEY_HOME:
				centre_on_player()
				return true
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				canvas.zoom_at(canvas.size * 0.5, 1.4)
				return true
			KEY_MINUS, KEY_KP_SUBTRACT:
				canvas.zoom_at(canvas.size * 0.5, 1.0 / 1.4)
				return true
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y:
		centre_on_player()
		return true
	return false


func page_process(delta: float) -> void:
	# continuous pan (WASD, arrows, left stick) and zoom (RT / LT) under the reticle
	var v := Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_forward", &"move_back"))
	v += Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
	if v.length() > 1.0:
		v = v.normalized()
	canvas.panning = v.length() > 0.15
	if canvas.panning:
		if not canvas.cursor_mode:
			canvas.cursor_mode = true
			_sticky = false
		_pan_hold = minf(_pan_hold + delta, 1.0)
		var speed := 520.0 * (0.55 + 0.45 * _pan_hold)
		canvas.move_cursor(v * speed * delta)
	else:
		_pan_hold = 0.0
	var zin := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var zout := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if zin > 0.2 or zout > 0.2:
		canvas.cursor_mode = true
		canvas.zoom_at(canvas.cursor_local(), 1.0 + (zin - zout) * delta * 1.8)


func hints() -> Array:
	return [
		{"kbm": [{"type": "key", "code": KEY_Q}, {"type": "key", "code": KEY_E}],
			"pad": [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], "text": "Pages"},
		{"kbm": [{"type": "key", "code": KEY_W}, {"type": "key", "code": KEY_A}, {"type": "key", "code": KEY_S}, {"type": "key", "code": KEY_D}],
			"pad": [{"type": "joy_axis", "axis": JOY_AXIS_LEFT_X, "value": 1.0}], "text": "Pan"},
		{"kbm": [{"type": "mouse", "button": MOUSE_BUTTON_MIDDLE}],
			"pad": [{"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}, {"type": "joy_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}], "text": "Zoom"},
		{"kbm": [{"type": "key", "code": KEY_C}], "pad": [{"type": "joy_button", "button": JOY_BUTTON_Y}], "text": "Centre"},
		{"action": &"ui_accept", "text": "Travel"},
	]
