class_name JournalPage
extends JourneyPage
## JOURNAL: the quest log from the Quests API (docs/modules/quests_npcs.md "Journal API").
##
## * Left: ACTIVE / COMPLETED lists (tracked first, then main, side, travel), each row with the
##   quest's seal (main / side / travel / training), title, place and stage progress.
## * Right: a parchment journal page - nation seal, title, giver and place, the summary and
##   lore text, the stages reached so far (no spoilers) with their objectives and counts, the
##   rewards, and the actions: TRACK / UNTRACK (HUD tracker + compass, Quests.track), SHOW ON
##   MAP (map page centred on the objective) and ABANDON (side quests, confirmed).
## * Focus a row to read it; Enter / A tracks it, Y / M shows it on the map, X abandons.
##   Refreshes live on Quests.quest_changed.

const KIND_COLORS := {&"main": Color("b23a2c"), &"side": Color("c9962e"), &"travel": Color("3f7f8c"), &"training": Color("6b8f3a")}
const KIND_NAMES := {&"main": "MAIN QUEST", &"side": "SIDE QUEST", &"travel": "JOURNEY", &"training": "TRAINING"}
const INK := Color("2b1d14")
const INK_DIM := Color(0.17, 0.11, 0.08, 0.72)

var filter: StringName = &"active"
var selected: StringName = &""
var rows: Array[Button] = []
var entries: Array[Dictionary] = []

var _tab_active: Button
var _tab_done: Button
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _empty: Label
var _page: PanelContainer
var _page_scroll: ScrollContainer
var _body: VBoxContainer
var _track: Button
var _map: Button
var _abandon: Button
var _connected := false


func _build() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override(&"separation", 26)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(600, 0)
	left.add_theme_constant_override(&"separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 10)
	left.add_child(tabs)
	_tab_active = _filter_button("ACTIVE", &"active")
	_tab_done = _filter_button("COMPLETED", &"completed")
	tabs.add_child(_tab_active)
	tabs.add_child(_tab_done)
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	_list_scroll.add_child(_list)
	_empty = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size = Vector2(540, 0)
	left.add_child(_empty)
	# the parchment page
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(right)
	_page = PanelContainer.new()
	_page.name = "Page"
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := UiFrameStyle.make(Color(0.93, 0.87, 0.74, 0.97), Color(UiTheme.GOLD_DEEP, 0.9), 2.0)
	ps.grain = 1.0
	ps.sheen = 0.05
	ps.corner_ornaments = true
	ps.ornament_size = 48.0
	ps.set_content_margin_all(40)
	ps.content_margin_top = 30
	_page.add_theme_stylebox_override(&"panel", ps)
	right.add_child(_page)
	_page_scroll = ScrollContainer.new()
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(_page_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 10)
	_page_scroll.add_child(_body)
	var act := HBoxContainer.new()
	act.add_theme_constant_override(&"separation", 12)
	right.add_child(act)
	_track = _action_button("TRACK", "icon_marker", &"PrimaryButton")
	_track.pressed.connect(toggle_track)
	act.add_child(_track)
	_map = _action_button("SHOW ON MAP", "icon_map", &"")
	_map.pressed.connect(show_on_map)
	act.add_child(_map)
	_abandon = _action_button("ABANDON", "ui_close", &"DangerButton")
	_abandon.pressed.connect(abandon_selected)
	act.add_child(_abandon)


func _filter_button(text: String, id: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220, UiTheme.touch_height(56))
	b.pressed.connect(func() -> void:
		UiFx.sound(UiFx.CLICK)
		set_filter(id))
	return b


func _action_button(text: String, icon: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UiTheme.icon(icon)
	b.add_theme_constant_override(&"icon_max_width", 26)
	if variation != &"":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, UiTheme.touch_height(62))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFx.wire(b, {"press_sound": UiFx.CONFIRM})
	return b


# --- data ---------------------------------------------------------------------------------------

func on_open(args: Dictionary) -> void:
	if not _connected and Quests != null:
		_connected = true
		Quests.quest_changed.connect(func(_q: StringName) -> void:
			if is_visible_in_tree():
				refresh())
	var want := StringName(str(args.get("quest", "")))
	if want != &"" and Quests.state(want) == Quests.STATE_COMPLETED:
		filter = &"completed"
	elif want != &"":
		filter = &"active"
	if want == &"" and selected == &"":
		want = GameState.tracked_quest
	if want != &"":
		selected = want
	refresh()


func set_filter(f: StringName) -> void:
	filter = f
	selected = &""
	refresh()


func refresh() -> void:
	entries = Quests.journal(filter) if Quests != null else ([] as Array[Dictionary])
	var n_active := (Quests.journal(&"active") if Quests != null else []).size()
	var n_done := (Quests.journal(&"completed") if Quests != null else []).size()
	_tab_active.text = "ACTIVE  %d" % n_active
	_tab_done.text = "COMPLETED  %d" % n_done
	_tab_active.theme_type_variation = &"PrimaryButton" if filter == &"active" else &"GhostButton"
	_tab_done.theme_type_variation = &"PrimaryButton" if filter == &"completed" else &"GhostButton"
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	rows.clear()
	for e in entries:
		var r := _row(e)
		_list.add_child(r)
		rows.append(r)
	_empty.visible = entries.is_empty()
	_empty.text = "No quests under way. People across the four nations need help: look for the gold seal above their heads." if filter == &"active" \
		else "Nothing finished yet. Completed quests are kept here with their story."
	var found := false
	for e in entries:
		if e["id"] == selected:
			found = true
	if not found:
		selected = entries[0]["id"] if not entries.is_empty() else &""
	_show(selected)
	var r2 := _row_for(selected)
	if r2 and is_visible_in_tree():
		UiFx.focus_silently(r2)


func _row_for(id: StringName) -> Button:
	for r in rows:
		if StringName(r.get_meta(&"quest", &"")) == id:
			return r
	return null


func _row(e: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Row_%s" % String(e["id"])
	b.set_meta(&"quest", e["id"])
	b.custom_minimum_size = Vector2(0, UiTheme.touch_height(84))
	b.focus_mode = Control.FOCUS_ALL
	var kind: StringName = e.get("kind", &"side")
	var kc: Color = KIND_COLORS.get(kind, UiTheme.GOLD)
	var tracked := bool(e.get("tracked", false))
	var done := String(e.get("state", "")) != "active"
	var id: StringName = e["id"]
	b.draw.connect(func() -> void: _draw_row(b, kc, tracked, done))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 68
	hb.offset_right = -18
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override(&"separation", 0)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tv)
	var t := UiTheme.make_label(String(e["title"]), UiTheme.title_font(700, 2), UiTheme.SIZE_SMALL + 1, UiTheme.PARCHMENT if not done else UiTheme.PARCHMENT_DIM)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(t)
	var stages: Array = e.get("stages", [])
	var sub := "%s  ·  %s" % [String(KIND_NAMES.get(kind, "QUEST")).capitalize(), String(e.get("location", ""))] if String(e.get("location", "")) != "" else String(KIND_NAMES.get(kind, "QUEST")).capitalize()
	if done:
		sub = ("Completed" if String(e["state"]) == "completed" else "Failed") + "  ·  " + String(e.get("location", ""))
	var s := UiTheme.make_label(sub, UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(s)
	if not done:
		var total := maxi(1, (Quests.get_def(id).get("stages", []) as Array).size()) if Quests != null else maxi(1, stages.size())
		var prog := UiTheme.make_label("%d / %d" % [int(e.get("stage", 0)) + 1, total], UiTheme.title_font(700, 1), UiTheme.SIZE_TINY, Color(kc.lightened(0.3), 0.9))
		prog.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(prog)
	UiFx.wire(b)
	b.focus_entered.connect(func() -> void:
		selected = id
		_show(id)
		b.queue_redraw())
	b.focus_exited.connect(b.queue_redraw)
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(func() -> void:
		if selected != id:
			selected = id
			_show(id)
		elif not done:
			toggle_track())
	var empty := StyleBoxEmpty.new()
	for st: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		b.add_theme_stylebox_override(st, empty)
	return b


func _draw_row(b: Button, kc: Color, tracked: bool, done: bool) -> void:
	var r := Rect2(Vector2.ZERO, b.size)
	var hot := b.has_focus() or b.is_hovered()
	var sel := StringName(b.get_meta(&"quest", &"")) == selected
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK_3, 0.92) if (hot or sel) else Color(UiTheme.INK_2, 0.6)
	sb.border_color = Color(UiTheme.GOLD, 0.8 if hot else (0.45 if sel else 0.15))
	sb.set_border_width_all(2 if hot else 1)
	sb.set_corner_radius_all(6)
	b.draw_style_box(sb, r)
	# kind seal
	var c := Vector2(36, r.size.y * 0.5)
	b.draw_circle(c, 20.0, Color(kc, 0.95 if not done else 0.45), true, -1.0, true)
	b.draw_arc(c, 20.0, 0, TAU, 32, Color(UiTheme.PARCHMENT, 0.5), 1.5, true)
	var ic := UiTheme.icon("ui_check" if done else ("icon_marker" if tracked else "icon_quest"))
	if ic:
		b.draw_texture_rect(ic, Rect2(c - Vector2(12, 12), Vector2(24, 24)), false, UiTheme.PARCHMENT)
	if hot:
		b.draw_rect(Rect2(Vector2(0, 6), Vector2(4, r.size.y - 12)), UiTheme.GOLD_HI)
	if tracked and not done:
		var f := UiTheme.title_font(700, 2)
		b.draw_string(f, Vector2(r.size.x - 108, 20), "TRACKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.GOLD_HI)


# --- the parchment page --------------------------------------------------------------------------

func _ink(text: String, font: Font, size: int, color: Color = INK) -> Label:
	var l := UiTheme.make_label(text, font, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _show(id: StringName) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_page_scroll.scroll_vertical = 0
	var e: Dictionary = Quests.journal_entry(id) if Quests != null and id != &"" else {}
	_track.visible = not e.is_empty() and String(e.get("state", "")) == "active"
	_map.visible = not e.is_empty() and String(e.get("state", "")) == "active"
	_abandon.visible = not e.is_empty() and String(e.get("state", "")) == "active" and e.get("kind", &"") != &"main"
	if e.is_empty():
		_body.add_child(_ink("THE JOURNAL", UiTheme.title_font(800, 6), UiTheme.SIZE_H2))
		_body.add_child(_ink("Every road you take and every promise you make is written here.", UiTheme.body_font(), UiTheme.SIZE_BODY, INK_DIM))
		return
	_track.text = "UNTRACK" if bool(e["tracked"]) else "TRACK"
	_map.disabled = not (e.get("target", Vector3.INF) as Vector3).is_finite()
	var kind: StringName = e.get("kind", &"side")
	var kc: Color = KIND_COLORS.get(kind, UiTheme.GOLD)
	# header: kind + nation seal
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 12)
	_body.add_child(top)
	var ne := ElementDefs.from_id(StringName(str(e.get("nation", ""))))
	if ElementDefs.is_valid(ne):
		var em := TextureRect.new()
		em.texture = UiTheme.emblem(ne)
		em.custom_minimum_size = Vector2(40, 40)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		em.modulate = UiTheme.element_color(ne).darkened(0.25)
		top.add_child(em)
	var kl := UiTheme.make_label(String(KIND_NAMES.get(kind, "QUEST")) + ("  ·  TRACKED" if bool(e["tracked"]) else ""), UiTheme.title_font(700, 5), UiTheme.SIZE_TINY, kc.darkened(0.2))
	kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(kl)
	_body.add_child(_ink(String(e["title"]).to_upper(), UiTheme.title_font(800, 5), UiTheme.SIZE_H2 - 2))
	var who := PackedStringArray()
	if String(e.get("giver_name", "")) != "":
		who.append("From %s" % String(e["giver_name"]))
	if String(e.get("location", "")) != "":
		who.append(String(e["location"]))
	if not who.is_empty():
		_body.add_child(_ink("  ·  ".join(who), UiTheme.title_font(600, 2), UiTheme.SIZE_SMALL - 2, INK_DIM))
	var rule := BrushStroke.new(Color(UiTheme.SEAL, 0.85), 4.4)
	rule.set_param(&"thickness", 0.4).set_param(&"tail", 0.6)
	rule.custom_minimum_size = Vector2(0, 14)
	_body.add_child(rule)
	if String(e.get("summary", "")) != "":
		_body.add_child(_ink(String(e["summary"]), UiTheme.body_font(), UiTheme.SIZE_BODY - 1))
	if String(e.get("description", "")) != "" and String(e["description"]) != String(e.get("summary", "")):
		_body.add_child(_ink(String(e["description"]), UiTheme.body_font(), UiTheme.SIZE_SMALL, INK_DIM))
	# stages reached (newest first for active quests)
	var stages: Array = e.get("stages", [])
	var order: Array = stages.duplicate()
	if String(e["state"]) == "active":
		order.reverse()
	for st: Dictionary in order:
		_body.add_child(_stage_block(st, String(e["state"]) == "active"))
	if String(e.get("rewards_text", "")) != "":
		var rw := HBoxContainer.new()
		rw.add_theme_constant_override(&"separation", 10)
		_body.add_child(rw)
		rw.add_child(UiTheme.make_label("REWARD", UiTheme.title_font(700, 4), UiTheme.SIZE_TINY, Color("7a4a14")))
		var rl := _ink(String(e["rewards_text"]), UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, INK)
		rl.custom_minimum_size = Vector2(480, 0)
		rw.add_child(rl)


func _stage_block(st: Dictionary, active_quest: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 4)
	var cur := bool(st.get("current", false))
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	v.add_child(head)
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(18, 18)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var done := bool(st.get("done", false))
	mark.draw.connect(func() -> void:
		var c := mark.size * 0.5
		mark.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(8, 0), c + Vector2(0, 8), c + Vector2(-8, 0)]),
			UiTheme.SEAL if cur else (Color("6b5a3a") if done else INK_DIM)))
	head.add_child(mark)
	var tl := _ink(String(st.get("text", "")), UiTheme.body_font(), UiTheme.SIZE_SMALL if cur else UiTheme.SIZE_SMALL - 2,
		INK if cur or not active_quest else INK_DIM)
	head.add_child(tl)
	if cur or not active_quest:
		for o: Dictionary in st.get("objectives", []):
			v.add_child(_objective_row(o))
	return v


func _objective_row(o: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(22, 0)
	h.add_child(spacer)
	var done := bool(o.get("done", false))
	var box := Control.new()
	box.custom_minimum_size = Vector2(24, 24)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.draw.connect(func() -> void:
		var r := Rect2(Vector2(2, 2), Vector2(20, 20))
		box.draw_rect(r, Color(INK, 0.75), false, 2.0)
		if done:
			box.draw_line(Vector2(5, 12), Vector2(10, 18), UiTheme.SEAL, 3.0, true)
			box.draw_line(Vector2(10, 18), Vector2(21, 3), UiTheme.SEAL, 3.0, true))
	h.add_child(box)
	var txt := String(o.get("text", ""))
	var n := int(o.get("target", 1))
	if n > 1:
		txt += "   %d / %d" % [mini(int(o.get("count", 0)), n), n]
	if bool(o.get("optional", false)):
		txt += "  (optional)"
	var l := _ink(txt, UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, INK if not done else Color(INK, 0.5))
	l.custom_minimum_size = Vector2(560, 0)
	h.add_child(l)
	return h


# --- actions ------------------------------------------------------------------------------------

func toggle_track() -> void:
	if selected == &"" or Quests == null or not Quests.is_active(selected):
		return
	if GameState.tracked_quest == selected:
		Quests.track(&"")
		_status("No quest tracked.", UiTheme.PARCHMENT_DIM)
	else:
		Quests.track(selected)
		_status("Tracking %s." % String(Quests.get_def(selected).get("title", "")), UiTheme.SUCCESS)
	refresh()


func show_on_map() -> void:
	if selected == &"" or book == null:
		return
	book.call(&"show_page", &"map", {"quest": selected})


func abandon_selected() -> void:
	if selected == &"" or Quests == null:
		return
	var d := Quests.get_def(selected)
	if d.get("kind", &"") == &"main":
		_status("Main quests cannot be abandoned.", UiTheme.DANGER)
		return
	var ok := true
	if book is JourneyBook:
		var ans: StringName = await (book as JourneyBook).confirm("ABANDON QUEST", "Abandon %s? You can take it up again from %s." % [String(d.get("title", "")), NpcRegistry.display_name(StringName(str(d.get("giver", "")))) if String(d.get("giver", "")) != "" else "where you found it"],
			[[&"keep", "KEEP IT"], [&"abandon", "ABANDON"]])
		ok = ans == &"abandon"
	if ok and Quests.abandon(selected):
		_status("Quest abandoned.", UiTheme.PARCHMENT_DIM)
		selected = &""
		refresh()


func _status(text: String, color: Color) -> void:
	if book != null and book.has_method("set_status"):
		book.call("set_status", text, color)


# --- input ---------------------------------------------------------------------------------------

func initial_focus() -> Control:
	return _row_for(selected)


func handle_input(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_Y:
				show_on_map()
				return true
			JOY_BUTTON_X:
				abandon_selected()
				return true
	if event is InputEventKey and (event as InputEventKey).pressed:
		match (event as InputEventKey).physical_keycode:
			KEY_T:
				toggle_track()
				return true
			KEY_TAB:
				set_filter(&"completed" if filter == &"active" else &"active")
				return true
	return false


func hints() -> Array:
	return [
		{"kbm": [{"type": "key", "code": KEY_Q}, {"type": "key", "code": KEY_E}],
			"pad": [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], "text": "Pages"},
		{"kbm": [{"type": "key", "code": KEY_TAB}], "pad": [], "text": "Active / Completed"},
		{"action": &"ui_accept", "text": "Track"},
		{"kbm": [{"type": "key", "code": KEY_M}], "pad": [{"type": "joy_button", "button": JOY_BUTTON_Y}], "text": "Map"},
	]
