class_name SkillTreePage
extends JourneyPage
## SKILLS: the element's bending tree, the loadout and a detail panel with a live preview.
##
## * Tree: foundations (the core kit) on a shelf, then techniques by tier (rows, with the
##   tier's level) and branch (columns), connectors from each prerequisite (SkillTreeCanvas).
## * Detail (right): live TechniquePreview of the focused technique, kind / branch, costs,
##   damage, description, every requirement with its progress (level, prerequisite, practice,
##   master, quest, skill points) and the action: LEARN (spend skill points), EQUIP,
##   UNEQUIP, or SHOW ON MAP for a master's lesson.
## * Equipping: tap / click / A on a learned technique "arms" it (the loadout glows), then
##   tap / click / A on a slot places it; keys 1-4 equip the focused technique directly;
##   desktop drag & drop from the tree onto a slot, slot onto slot (swap), slot off the bar
##   (unequip); X / Delete on a slot unequips. Back leaves the arming first.

var element := ElementDefs.Element.NONE
var canvas: SkillTreeCanvas
var slots: Array[LoadoutSlot] = []
var preview: TechniquePreview
## Technique shown in the detail panel.
var selected: StringName = &""
## Technique waiting for a slot (&"" = none).
var armed: StringName = &""

var _emblem: TextureRect
var _art: Label
var _philosophy: Label
var _points: Label
var _points_box: Control
var _name: Label
var _kind: Label
var _stats: Label
var _hits: Label
var _desc: Label
var _req_title: Label
var _reqs: VBoxContainer
var _action: Button
var _action2: Button
var _loadout_hint: Label
var _glow: TextureRect
var _built_for := -99


func _build() -> void:
	var cols := HBoxContainer.new()
	cols.name = "Columns"
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override(&"separation", 26)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cols)
	var left := VBoxContainer.new()
	left.name = "Left"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.add_child(left)
	_build_header(left)
	canvas = SkillTreeCanvas.new()
	canvas.name = "Tree"
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(canvas)
	_build_loadout(left)
	_build_detail(cols)


func _build_header(parent: Control) -> void:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 74)
	h.add_theme_constant_override(&"separation", 18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	_emblem = TextureRect.new()
	_emblem.custom_minimum_size = Vector2(66, 66)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_emblem)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override(&"separation", 0)
	h.add_child(tv)
	_art = UiTheme.make_label("", UiTheme.title_font(700, 8), UiTheme.SIZE_H3 + 4, UiTheme.GOLD)
	tv.add_child(_art)
	_philosophy = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT_DIM)
	_philosophy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_philosophy.custom_minimum_size = Vector2(560, 0)
	tv.add_child(_philosophy)
	# skill points seal
	var pb := PanelContainer.new()
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.85), Color(UiTheme.GOLD, 0.55), 1.5)
	ps.content_margin_left = 22
	ps.content_margin_right = 22
	ps.content_margin_top = 8
	ps.content_margin_bottom = 8
	pb.add_theme_stylebox_override(&"panel", ps)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pb)
	_points_box = pb
	var pv := HBoxContainer.new()
	pv.add_theme_constant_override(&"separation", 12)
	pb.add_child(pv)
	var di := TextureRect.new()
	di.texture = UiTheme.icon("ui_diamond")
	di.custom_minimum_size = Vector2(26, 26)
	di.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	di.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	di.modulate = UiTheme.GOLD_HI
	di.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pv.add_child(di)
	var pc := VBoxContainer.new()
	pc.add_theme_constant_override(&"separation", -6)
	pv.add_child(pc)
	_points = UiTheme.make_label("0", UiTheme.title_font(800, 2), UiTheme.SIZE_H3 + 2, UiTheme.GOLD_HI, HORIZONTAL_ALIGNMENT_CENTER)
	pc.add_child(_points)
	pc.add_child(UiTheme.make_label("SKILL POINTS", UiTheme.title_font(600, 3), UiTheme.SIZE_TINY - 3, UiTheme.PARCHMENT_DIM, HORIZONTAL_ALIGNMENT_CENTER))


func _build_loadout(parent: Control) -> void:
	var bar := PanelContainer.new()
	bar.name = "Loadout"
	var bs := UiFrameStyle.make(Color(UiTheme.INK_2, 0.7), Color(UiTheme.GOLD, 0.3), 1.0)
	bs.content_margin_left = 22
	bs.content_margin_right = 22
	bs.content_margin_top = 8
	bs.content_margin_bottom = 6
	bar.add_theme_stylebox_override(&"panel", bs)
	parent.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(h)
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(190, 0)
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lv.add_theme_constant_override(&"separation", 2)
	h.add_child(lv)
	lv.add_child(UiTheme.make_label("LOADOUT", UiTheme.title_font(700, 5), UiTheme.SIZE_SMALL + 2, UiTheme.GOLD))
	_loadout_hint = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT_MUTED)
	_loadout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_hint.custom_minimum_size = Vector2(190, 0)
	lv.add_child(_loadout_hint)
	for i in SkillTreeModel.SLOTS:
		var s := LoadoutSlot.new(i)
		s.name = "Slot%d" % (i + 1)
		h.add_child(s)
		slots.append(s)
	var sep := VSeparator.new()
	sep.add_theme_stylebox_override(&"separator", _vline())
	h.add_child(sep)
	var sig := LoadoutSlot.new(4)
	sig.name = "SlotSignature"
	h.add_child(sig)
	slots.append(sig)
	for s in slots:
		s.pressed.connect(_on_slot_pressed.bind(s.index))
		s.focus_entered.connect(_on_slot_focus.bind(s.index))
		s.dropped.connect(_on_slot_dropped)
		s.drag_out.connect(_on_slot_drag_out)


static func _radial_glow() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.34))
	g.add_point(0.55, Color(1, 1, 1, 0.08))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.62)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 256
	t.height = 128
	return t


func _vline() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(UiTheme.GOLD, 0.3)
	l.vertical = true
	l.thickness = 1
	return l


func _build_detail(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "Detail"
	panel.theme_type_variation = &"InkPanel"
	panel.custom_minimum_size = Vector2(640, 0)
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.62), Color(UiTheme.GOLD, 0.35), 1.0)
	ps.grain = 0.3
	ps.set_content_margin_all(24)
	ps.content_margin_top = 18
	panel.add_theme_stylebox_override(&"panel", ps)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var stage := Control.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(0, 286)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage)
	_glow = TextureRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.texture = _radial_glow()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_glow)
	preview = TechniquePreview.new()
	preview.name = "Preview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview)
	_name = UiTheme.make_label("", UiTheme.title_font(700, 5), UiTheme.SIZE_H3, UiTheme.PARCHMENT)
	v.add_child(_name)
	_kind = UiTheme.make_label("", UiTheme.title_font(600, 3), UiTheme.SIZE_TINY, UiTheme.GOLD)
	v.add_child(_kind)
	_stats = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT)
	v.add_child(_stats)
	_hits = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_DIM)
	v.add_child(_hits)
	_desc = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(580, 0)
	v.add_child(_desc)
	var sep := HSeparator.new()
	v.add_child(sep)
	_req_title = UiTheme.make_label("REQUIREMENTS", UiTheme.title_font(700, 4), UiTheme.SIZE_TINY, UiTheme.GOLD)
	v.add_child(_req_title)
	_reqs = VBoxContainer.new()
	_reqs.add_theme_constant_override(&"separation", 2)
	v.add_child(_reqs)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	v.add_child(row)
	_action = Button.new()
	_action.name = "Action"
	_action.theme_type_variation = &"PrimaryButton"
	_action.custom_minimum_size = Vector2(0, UiTheme.touch_height(64))
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFx.wire(_action, {"press_sound": UiFx.CONFIRM})
	_action.pressed.connect(_on_action.bind(0))
	row.add_child(_action)
	_action2 = Button.new()
	_action2.name = "Action2"
	_action2.custom_minimum_size = Vector2(0, UiTheme.touch_height(64))
	_action2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiFx.wire(_action2)
	_action2.pressed.connect(_on_action.bind(1))
	row.add_child(_action2)


# --- open / refresh -------------------------------------------------------------------------------

func on_open(args: Dictionary) -> void:
	var e := GameState.element if GameState.has_element() else ElementDefs.Element.WATER
	if e != _built_for:
		_built_for = e
		element = e
		canvas.setup(e)
		for id: StringName in canvas.nodes:
			_wire_node(canvas.nodes[id])
		for f in canvas.foundation_nodes:
			_wire_node(f)
		if preview.rig == null:
			var appearance: Dictionary = {}
			var p := player()
			if p != null and p.get("appearance") is Dictionary:
				appearance = p.get("appearance")
			preview.setup(e, appearance)
		_emblem.texture = UiTheme.emblem(e)
		_emblem.modulate = UiTheme.element_light(e)
		_glow.modulate = UiTheme.element_light(e)
		_art.text = String(SkillTreeModel.ART_NAMES.get(e, "Bending")).to_upper()
		_philosophy.text = String(SkillTreeModel.LORE.get(e, ElementDefs.get_data(e).get("philosophy", "")))
	armed = &""
	refresh()
	var want: StringName = StringName(str(args.get("focus", "")))
	if want == &"" or not canvas.nodes.has(want):
		want = _default_focus_id()
	select(want)
	if is_inside_tree() and canvas.nodes.has(want):
		UiFx.focus_silently(canvas.nodes[want])


func on_close() -> void:
	_disarm()


func initial_focus() -> Control:
	return canvas.nodes.get(selected, null) as Control


func _default_focus_id() -> StringName:
	for n in canvas.layout:
		if SkillTreeModel.state(n["id"]) == SkillTreeModel.STATE_AVAILABLE:
			return n["id"]
	for i in SkillTreeModel.SLOTS:
		if SkillTreeModel.equipped(i) != &"":
			return SkillTreeModel.equipped(i)
	return canvas.layout[0]["id"] if not canvas.layout.is_empty() else &""


func _wire_node(n: SkillNode) -> void:
	if n.has_meta(&"page_wired"):
		return
	n.set_meta(&"page_wired", true)
	n.pressed.connect(func() -> void: _on_node_pressed(n))
	n.focus_entered.connect(func() -> void: select(n.id))


## Re-reads states, slots and the points counter from GameState.
func refresh() -> void:
	for id: StringName in canvas.nodes:
		var n: SkillNode = canvas.nodes[id]
		var d := n.def
		n.set_state(SkillTreeModel.state(id), SkillTreeModel.slot_of(id), SkillTreeModel.is_trainer_taught(d) and not GameState.is_unlocked(id))
		n.armed = id == armed
	for f in canvas.foundation_nodes:
		f.set_state(&"learned", -1, false)
	for i in SkillTreeModel.SLOTS:
		slots[i].set_technique(SkillTreeModel.equipped(i), element)
		slots[i].target = armed != &""
	slots[4].set_technique(SkillTreeModel.signature_id(element), element)
	slots[4].target = false
	_points.text = str(GameState.skill_points)
	_points.add_theme_color_override(&"font_color", UiTheme.GOLD_HI if GameState.skill_points > 0 else UiTheme.PARCHMENT_MUTED)
	if armed != &"":
		_loadout_hint.text = "Choose a slot for %s." % SkillTreeModel.display_name(armed)
		_loadout_hint.add_theme_color_override(&"font_color", UiTheme.GOLD_HI)
	else:
		_loadout_hint.text = "Tap a learned technique, then a slot." if UiInput.device == &"touch" else "Select a learned technique, then a slot. Drag and drop works too."
		_loadout_hint.add_theme_color_override(&"font_color", UiTheme.PARCHMENT_MUTED)
	canvas.queue_redraw()
	_refresh_detail()


# --- selection + detail ----------------------------------------------------------------------------

func select(id: StringName) -> void:
	if id == &"":
		return
	var changed := id != selected
	selected = id
	_refresh_detail()
	if changed:
		preview.show_technique(AbilityRegistry.get_def(id))


func _refresh_detail() -> void:
	var d := AbilityRegistry.get_def(selected)
	if d == null:
		_name.text = ""
		_kind.text = ""
		_stats.text = ""
		_hits.text = ""
		_desc.text = ""
		_action.visible = false
		_action2.visible = false
		return
	_name.text = d.display_name.to_upper()
	var kind := SkillTreeModel.slot_label(d).to_upper()
	var br := StringName(str(d.unlock.get("branch", "")))
	if br != &"":
		kind += "  ·  %s" % SkillTreeModel.branch_name(br).to_upper()
	if d.slot == AbilityDef.Slot.TECHNIQUE or d.slot == AbilityDef.Slot.SIGNATURE:
		kind += "  ·  TIER %s" % SkillTreeCanvas._roman(int(d.unlock.get("tier", 1)))
	_kind.text = kind
	_stats.text = SkillTreeModel.stat_line(d)
	_hits.text = SkillTreeModel.hit_line(d)
	_desc.text = d.description
	for c in _reqs.get_children():
		_reqs.remove_child(c)
		c.queue_free()
	var reqs := SkillTreeModel.requirements(selected)
	var st := SkillTreeModel.state(selected)
	_req_title.visible = not reqs.is_empty() or SkillTreeModel.is_foundation(d)
	if SkillTreeModel.is_foundation(d):
		_req_title.text = "CORE KIT"
		_reqs.add_child(_req_row(true, "Always known  ·  %s" % _foundation_input(d)))
	elif d.starter:
		_req_title.text = "REQUIREMENTS"
		_reqs.add_child(_req_row(true, "Known from the start of your journey"))
	else:
		_req_title.text = "REQUIREMENTS"
	for r in reqs:
		_reqs.add_child(_req_row(bool(r["met"]), String(r["text"])))
	_set_actions(d, st)


func _foundation_input(d: AbilityDef) -> String:
	var action: StringName = &""
	match d.slot:
		AbilityDef.Slot.LIGHT: action = &"attack_light"
		AbilityDef.Slot.HEAVY: action = &"attack_heavy"
		AbilityDef.Slot.DEFENSE: action = &"block"
		AbilityDef.Slot.DODGE: action = &"dodge"
		_: action = &"jump"
	if UiInput.device == &"touch":
		return "on its touch button"
	var lbl := UiInput.action_label(action)
	return ("on %s" % lbl) if lbl != "" else ""


func _req_row(met: bool, text: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := TextureRect.new()
	ic.texture = UiTheme.icon("ui_check" if met else "ui_diamond")
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = UiTheme.SUCCESS if met else Color(UiTheme.DANGER, 0.9)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not met:
		ic.custom_minimum_size = Vector2(14, 14)
	h.add_child(ic)
	var l := UiTheme.make_label(text, UiTheme.body_font(), UiTheme.SIZE_SMALL - 2, UiTheme.PARCHMENT if met else UiTheme.PARCHMENT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


## Primary / secondary buttons for the selected technique.
func _set_actions(d: AbilityDef, st: StringName) -> void:
	_action.visible = true
	_action2.visible = false
	_action.disabled = false
	_action.set_meta(&"kind", &"")
	_action2.set_meta(&"kind", &"")
	var sig := d.slot == AbilityDef.Slot.SIGNATURE
	if SkillTreeModel.is_foundation(d):
		_action.visible = false
		return
	if st == SkillTreeModel.STATE_LEARNED:
		if sig:
			_action.text = "SIGNATURE  ·  READY ON FULL FOCUS"
			_action.disabled = true
			return
		var s := SkillTreeModel.slot_of(selected)
		if armed == selected:
			_action.text = "CHOOSE A SLOT"
			_action.set_meta(&"kind", &"cancel_arm")
		else:
			_action.text = "EQUIP" if s < 0 else "MOVE TO ANOTHER SLOT"
			_action.set_meta(&"kind", &"arm")
		if s >= 0:
			_action2.visible = true
			_action2.text = "UNEQUIP"
			_action2.set_meta(&"kind", &"unequip")
		return
	if st == SkillTreeModel.STATE_AVAILABLE:
		var c := SkillTreeModel.cost(d)
		_action.text = "LEARN  ·  %d SKILL POINT%s" % [c, "" if c == 1 else "S"] if c > 0 else "LEARN"
		_action.set_meta(&"kind", &"learn")
		return
	# locked
	var why := SkillTreeModel.blocker(selected)
	if why == &"trainer" or (SkillTreeModel.is_trainer_taught(d) and why == &"skill_points"):
		var m := SkillTreeModel.master_for(element)
		_action.text = ("FIND %s ON THE MAP" % String(m.get("name", "YOUR MASTER")).to_upper()) if not m.is_empty() else "TAUGHT BY A MASTER"
		_action.set_meta(&"kind", &"show_master")
		_action.disabled = m.is_empty()
		return
	_action.text = "LOCKED  ·  %s" % SkillTreeModel.lock_text(selected).to_upper()
	_action.disabled = true


func _on_action(which: int) -> void:
	var b := _action if which == 0 else _action2
	match StringName(str(b.get_meta(&"kind", &""))):
		&"learn":
			learn_selected()
		&"arm":
			arm(selected)
		&"cancel_arm":
			_disarm()
			refresh()
		&"unequip":
			var s := SkillTreeModel.slot_of(selected)
			if s >= 0:
				unequip_slot(s)
		&"show_master":
			var m := SkillTreeModel.master_for(element)
			if not m.is_empty() and book != null:
				book.call(&"show_page", &"map", {"npc": m["id"], "label": "%s  ·  %s" % [m["name"], m.get("title", "")]})


# --- actions ----------------------------------------------------------------------------------------

func _on_node_pressed(n: SkillNode) -> void:
	select(n.id)
	if n.foundation:
		return
	match SkillTreeModel.state(n.id):
		SkillTreeModel.STATE_LEARNED:
			if n.def.slot == AbilityDef.Slot.SIGNATURE:
				_status("%s is your signature: press %s when Focus is full." % [n.def.display_name, _signature_key()], UiTheme.PARCHMENT_DIM)
				return
			if armed == n.id:
				_disarm()
				refresh()
			else:
				arm(n.id)
		SkillTreeModel.STATE_AVAILABLE:
			learn_selected()
		_:
			n.flash_fail()
			UiFx.sound(UiFx.ERROR)
			_status(SkillTreeModel.lock_text(n.id), UiTheme.DANGER)


func _signature_key() -> String:
	if UiInput.device == &"touch":
		return "the Signature button"
	var l := UiInput.action_label(&"ability_special")
	return l if l != "" else "the signature button"


## Asks, then spends the skill points (SkillTreeModel.learn). Returns the result reason.
func learn_selected(skip_confirm: bool = false) -> StringName:
	var id := selected
	var d := AbilityRegistry.get_def(id)
	if d == null:
		return &"unknown"
	var why := SkillTreeModel.blocker(id)
	if why != &"":
		UiFx.sound(UiFx.ERROR)
		_status(SkillTreeModel.lock_text(id), UiTheme.DANGER)
		return why
	if not skip_confirm and book is JourneyBook:
		var c := SkillTreeModel.cost(d)
		var answer: StringName = await (book as JourneyBook).confirm("LEARN %s" % d.display_name.to_upper(),
			"Spend %d skill point%s to learn %s?" % [c, "" if c == 1 else "s", d.display_name], [[&"learn", "LEARN"], [&"cancel", "NOT YET"]])
		if answer != &"learn":
			if canvas.nodes.has(id):
				UiFx.focus_silently(canvas.nodes[id])
			return &"cancelled"
	var r := SkillTreeModel.learn(id)
	if r != &"":
		_status(SkillTreeModel.lock_text(id), UiTheme.DANGER)
		return r
	Audio.play_ui(&"ui_levelup")
	Events.notify.emit("New technique: %s" % d.display_name, &"unlock")
	refresh()
	if canvas.nodes.has(id):
		var n: SkillNode = canvas.nodes[id]
		n.bloom()
		UiFx.focus_silently(n)
	var s := SkillTreeModel.slot_of(id)
	_status("%s learned%s." % [d.display_name, ("  ·  equipped in slot %d" % (s + 1)) if s >= 0 else "  ·  choose a slot to equip it"], UiTheme.SUCCESS)
	if s < 0 and d.slot == AbilityDef.Slot.TECHNIQUE:
		arm(id)
	return &""


## Waits for a slot for `id` (slots glow; pad / keyboard focus moves to the loadout).
func arm(id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	if d == null or d.slot != AbilityDef.Slot.TECHNIQUE or not GameState.is_unlocked(id):
		return
	armed = id
	select(id)
	refresh()
	refresh_hints()
	UiFx.sound(UiFx.CLICK)
	_status("Choose a slot for %s." % d.display_name, UiTheme.GOLD_HI)
	# Keyboard / controller activation: carry focus to the loadout (a mouse or a tap stays put).
	if UiInput.device == &"pad" or Input.is_action_pressed(&"ui_accept"):
		var target := SkillTreeModel.slot_of(id)
		if target < 0:
			target = GameState.equipped_abilities.find(&"")
		UiFx.focus_silently(slots[maxi(target, 0)])


func _disarm() -> void:
	if armed == &"":
		return
	armed = &""
	refresh_hints()


## Equips (or swaps) through the model; feedback on the slot.
func equip_to_slot(slot: int, id: StringName) -> StringName:
	var r := SkillTreeModel.equip(slot, id)
	if r == &"":
		UiFx.sound(UiFx.CONFIRM)
		slots[slot].flash(UiTheme.SUCCESS)
		UiFx.pop(slots[slot], 1.1, 0.2)
		_status("%s equipped in slot %d." % [SkillTreeModel.display_name(id), slot + 1], UiTheme.SUCCESS)
	else:
		UiFx.sound(UiFx.ERROR)
		slots[slot].flash(UiTheme.DANGER)
		_status("%s cannot go in a technique slot." % SkillTreeModel.display_name(id) if r == &"not_technique" else "Learn %s first." % SkillTreeModel.display_name(id), UiTheme.DANGER)
	_disarm()
	refresh()
	return r


func unequip_slot(slot: int) -> void:
	var id := SkillTreeModel.equipped(slot)
	if id == &"":
		return
	SkillTreeModel.unequip(slot)
	UiFx.sound(UiFx.BACK)
	slots[slot].flash(UiTheme.PARCHMENT_DIM)
	_status("%s unequipped." % SkillTreeModel.display_name(id), UiTheme.PARCHMENT_DIM)
	refresh()


func _on_slot_pressed(index: int) -> void:
	if index >= 4:
		var sid := SkillTreeModel.signature_id(element)
		if sid != &"":
			select(sid)
			_status("Your signature: press %s when Focus is full." % _signature_key(), UiTheme.PARCHMENT_DIM)
		else:
			_status("Learn your element's signature technique to fill this slot.", UiTheme.PARCHMENT_DIM)
		return
	if armed != &"":
		var id := armed
		equip_to_slot(index, id)
		return
	var cur := SkillTreeModel.equipped(index)
	if cur != &"":
		select(cur)
		_status("Slot %d: %s. Select another technique to replace it." % [index + 1, SkillTreeModel.display_name(cur)], UiTheme.PARCHMENT_DIM)
	else:
		_status("Empty slot. Choose a learned technique first.", UiTheme.PARCHMENT_DIM)


func _on_slot_focus(index: int) -> void:
	if armed != &"":
		return
	var id := SkillTreeModel.equipped(index) if index < 4 else SkillTreeModel.signature_id(element)
	if id != &"":
		select(id)


func _on_slot_dropped(index: int, data: Dictionary) -> void:
	match data.get("kind"):
		&"technique":
			equip_to_slot(index, StringName(str(data.get("id", ""))))
		&"slot":
			var from := int(data.get("index", -1))
			var id := SkillTreeModel.equipped(from)
			if id != &"":
				equip_to_slot(index, id)


func _on_slot_drag_out(index: int) -> void:
	unequip_slot(index)


func _status(text: String, color: Color) -> void:
	if book != null and book.has_method("set_status"):
		book.call("set_status", text, color)


# --- input ---------------------------------------------------------------------------------------

func handle_back() -> bool:
	if armed != &"":
		var id := armed
		_disarm()
		refresh()
		_status("", UiTheme.PARCHMENT_DIM)
		if canvas.nodes.has(id):
			UiFx.focus_silently(canvas.nodes[id])
		return true
	return false


func handle_input(event: InputEvent) -> bool:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	# 1-4 on the keyboard: equip the focused technique into that slot.
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		for i in SkillTreeModel.SLOTS:
			if InputMap.has_action(StringName("ability_%d" % (i + 1))) and k.is_action(StringName("ability_%d" % (i + 1)), true):
				var id := armed if armed != &"" else selected
				var d := AbilityRegistry.get_def(id)
				if d != null and d.slot == AbilityDef.Slot.TECHNIQUE and GameState.is_unlocked(id):
					equip_to_slot(i, id)
					return true
		if (k.physical_keycode == KEY_DELETE or k.physical_keycode == KEY_BACKSPACE) and focus is LoadoutSlot:
			unequip_slot((focus as LoadoutSlot).index)
			return true
	# X on a focused slot (controller): unequip.
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_X:
		if focus is LoadoutSlot and (focus as LoadoutSlot).index < 4:
			unequip_slot((focus as LoadoutSlot).index)
			return true
	return false


func hints() -> Array:
	var hs: Array = [{"kbm": [{"type": "key", "code": KEY_Q}, {"type": "key", "code": KEY_E}],
		"pad": [{"type": "joy_button", "button": JOY_BUTTON_LEFT_SHOULDER}, {"type": "joy_button", "button": JOY_BUTTON_RIGHT_SHOULDER}], "text": "Pages"}]
	if armed != &"":
		hs.append({"action": &"ui_accept", "text": "Place in slot"})
		hs.append({"kbm": [{"type": "key", "code": KEY_1}], "pad": [], "text": "1-4 Quick slot"})
	else:
		hs.append({"action": &"ui_accept", "text": "Learn / Equip"})
		hs.append({"kbm": [{"type": "key", "code": KEY_DELETE}], "pad": [{"type": "joy_button", "button": JOY_BUTTON_X}], "text": "Unequip slot"})
	return hs


func page_process(_delta: float) -> void:
	pass
