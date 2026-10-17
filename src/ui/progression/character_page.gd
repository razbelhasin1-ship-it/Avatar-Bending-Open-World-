class_name CharacterPage
extends JourneyPage
## CHARACTER: who the player is on this journey - a live portrait (the player's own rig in
## a slow turn), element, nation and tagline, level and the experience toward the next one,
## body and bending numbers (health, chi, focus, poise, speeds, dodge), mastery (techniques
## known, skill points, the most practised techniques), the journey's record (GameState.stats)
## and the companion with the bond built together (CompanionBond).

var portrait: TechniquePreview

var _name: Label
var _title: Label
var _tagline: Label
var _level: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _body: GridContainer
var _mastery: VBoxContainer
var _record: GridContainer
var _comp_name: Label
var _comp_status: Label
var _bond_bar: ProgressBar
var _bond_text: Label
var _bond_detail: Label
var _comp_icon: TextureRect
var _glow: TextureRect
var _built_for := -99


func _build() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override(&"separation", 30)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	# left: portrait + identity
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override(&"separation", 6)
	h.add_child(left)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 560)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(stage)
	_glow = TextureRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.texture = SkillTreePage._radial_glow()
	stage.add_child(_glow)
	portrait = TechniquePreview.new()
	portrait.name = "Portrait"
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(portrait)
	_name = UiTheme.make_label("", UiTheme.title_font(800, 8), UiTheme.SIZE_H2, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_name)
	_title = UiTheme.make_label("", UiTheme.title_font(600, 3), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	left.add_child(_title)
	_tagline = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tagline.custom_minimum_size = Vector2(520, 0)
	left.add_child(_tagline)
	# right: numbers
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override(&"separation", 14)
	h.add_child(right)
	right.add_child(_build_level())
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override(&"separation", 20)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(mid)
	var col1 := VBoxContainer.new()
	col1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col1.add_theme_constant_override(&"separation", 14)
	mid.add_child(col1)
	var col2 := VBoxContainer.new()
	col2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col2.add_theme_constant_override(&"separation", 14)
	mid.add_child(col2)
	var bp := _section("BODY AND BENDING")
	col1.add_child(bp)
	_body = GridContainer.new()
	_body.columns = 2
	_body.add_theme_constant_override(&"h_separation", 24)
	_body.add_theme_constant_override(&"v_separation", 4)
	bp.get_child(0).add_child(_body)
	var mp := _section("MASTERY")
	col1.add_child(mp)
	_mastery = VBoxContainer.new()
	_mastery.add_theme_constant_override(&"separation", 4)
	mp.get_child(0).add_child(_mastery)
	var rp := _section("THE JOURNEY SO FAR")
	col2.add_child(rp)
	_record = GridContainer.new()
	_record.columns = 2
	_record.add_theme_constant_override(&"h_separation", 24)
	_record.add_theme_constant_override(&"v_separation", 4)
	rp.get_child(0).add_child(_record)
	col2.add_child(_build_companion())


func _section(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.6), Color(UiTheme.GOLD, 0.3), 1.0)
	ps.set_content_margin_all(20)
	ps.content_margin_top = 14
	p.add_theme_stylebox_override(&"panel", ps)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	p.add_child(v)
	v.add_child(UiTheme.make_label(title, UiTheme.title_font(700, 4), UiTheme.SIZE_TINY + 1, UiTheme.GOLD))
	return p


func _build_level() -> Control:
	var p := PanelContainer.new()
	var ps := UiFrameStyle.make(Color(UiTheme.INK, 0.7), Color(UiTheme.GOLD, 0.45), 1.5)
	ps.set_content_margin_all(22)
	p.add_theme_stylebox_override(&"panel", ps)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 26)
	p.add_child(h)
	var seal := Control.new()
	seal.custom_minimum_size = Vector2(112, 112)
	seal.draw.connect(func() -> void:
		var c := seal.size * 0.5
		var col := UiTheme.element_light(GameState.element)
		seal.draw_circle(c, 54.0, Color(UiTheme.INK_2, 1.0), true, -1.0, true)
		seal.draw_arc(c, 54.0, 0, TAU, 64, col, 3.0, true)
		seal.draw_arc(c, 46.0, 0, TAU, 64, Color(col, 0.4), 1.5, true)
		var f := UiTheme.title_font(800)
		var t := str(GameState.level)
		var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 48)
		seal.draw_string(f, c + Vector2(-ts.x * 0.5, 16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, UiTheme.GOLD_HI)
		var sf := UiTheme.title_font(600, 3)
		var st := "LEVEL"
		var sw := sf.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		seal.draw_string(sf, c + Vector2(-sw * 0.5, -22), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.PARCHMENT_DIM))
	h.add_child(seal)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override(&"separation", 8)
	h.add_child(v)
	_level = UiTheme.make_label("", UiTheme.title_font(700, 4), UiTheme.SIZE_BODY, UiTheme.PARCHMENT)
	v.add_child(_level)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 16)
	_xp_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UiTheme.INK, 0.9)
	bg.border_color = Color(UiTheme.GOLD, 0.4)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.GOLD
	fill.set_corner_radius_all(4)
	_xp_bar.add_theme_stylebox_override(&"background", bg)
	_xp_bar.add_theme_stylebox_override(&"fill", fill)
	v.add_child(_xp_bar)
	_xp_text = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT_DIM)
	v.add_child(_xp_text)
	return p


func _build_companion() -> Control:
	var p := _section("COMPANION")
	var v: VBoxContainer = p.get_child(0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 16)
	v.add_child(h)
	_comp_icon = TextureRect.new()
	_comp_icon.texture = UiTheme.icon("icon_paw")
	_comp_icon.custom_minimum_size = Vector2(54, 54)
	_comp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_comp_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_comp_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	h.add_child(_comp_icon)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override(&"separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	_comp_name = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_BODY, UiTheme.PARCHMENT)
	tv.add_child(_comp_name)
	_comp_status = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_MUTED)
	tv.add_child(_comp_status)
	_bond_text = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_SMALL, UiTheme.GOLD_HI)
	v.add_child(_bond_text)
	_bond_bar = ProgressBar.new()
	_bond_bar.custom_minimum_size = Vector2(0, 12)
	_bond_bar.show_percentage = false
	_bond_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.SEAL.lightened(0.15)
	fill.set_corner_radius_all(3)
	_bond_bar.add_theme_stylebox_override(&"fill", fill)
	v.add_child(_bond_bar)
	_bond_detail = UiTheme.make_label("", UiTheme.body_font(), UiTheme.SIZE_TINY, UiTheme.PARCHMENT_DIM)
	_bond_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bond_detail.custom_minimum_size = Vector2(380, 0)
	v.add_child(_bond_detail)
	return p


# --- refresh --------------------------------------------------------------------------------------

func on_open(_args: Dictionary) -> void:
	var e := GameState.element if GameState.has_element() else ElementDefs.Element.WATER
	if e != _built_for:
		_built_for = e
		if portrait.rig == null:
			var appearance: Dictionary = {}
			var p := player()
			if p != null and p.get("appearance") is Dictionary:
				appearance = p.get("appearance")
			portrait.setup(e, appearance, true)
			portrait.show_idle()
		_glow.modulate = UiTheme.element_light(e)
	CompanionBond.sync()
	refresh()


func refresh() -> void:
	var e := GameState.element
	var d := ElementDefs.get_data(e)
	_name.text = GameState.player_name.to_upper()
	_title.text = "%s of the %s" % [ElementDefs.display_name(e), String(d.get("nation", ""))] if ElementDefs.is_valid(e) else ""
	_tagline.text = "“%s”" % String(d.get("tagline", "")) if ElementDefs.is_valid(e) else ""
	# level + experience
	var need := GameState.xp_for_level(GameState.level)
	if GameState.level >= GameState.MAX_LEVEL:
		_level.text = "MASTER  ·  LEVEL %d" % GameState.level
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
		_xp_text.text = "The highest level a bender can reach."
	else:
		_level.text = "LEVEL %d  ·  %d skill point%s to spend" % [GameState.level, GameState.skill_points, "" if GameState.skill_points == 1 else "s"]
		_xp_bar.max_value = float(need)
		_xp_bar.value = float(GameState.xp)
		_xp_text.text = "%d / %d XP  ·  %d to level %d (+1 skill point)" % [GameState.xp, need, need - GameState.xp, GameState.level + 1]
	_fill_grid(_body, _body_rows())
	for c in _mastery.get_children():
		_mastery.remove_child(c)
		c.queue_free()
	for line in _mastery_lines():
		var l := UiTheme.make_label(line, UiTheme.body_font(), UiTheme.SIZE_SMALL - 2, UiTheme.PARCHMENT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mastery.add_child(l)
	_fill_grid(_record, _record_rows())
	_refresh_companion()


func _fill_grid(g: GridContainer, rows: Array) -> void:
	for c in g.get_children():
		g.remove_child(c)
		c.queue_free()
	for r: Array in rows:
		g.add_child(UiTheme.make_label(String(r[0]), UiTheme.body_font(), UiTheme.SIZE_SMALL - 2, UiTheme.PARCHMENT_MUTED))
		g.add_child(UiTheme.make_label(String(r[1]), UiTheme.title_font(700, 1), UiTheme.SIZE_SMALL - 1, UiTheme.PARCHMENT))


func _body_rows() -> Array:
	var rows: Array = []
	var p := player()
	var hp := Vector2(100, 100)
	var poise := 0.0
	if p != null:
		var h: Variant = p.get("health")
		if h is HealthComponent:
			hp = Vector2((h as HealthComponent).health, (h as HealthComponent).max_health)
			poise = (h as HealthComponent).max_poise
	rows.append(["Health", "%d / %d" % [int(round(hp.x)), int(round(hp.y))]])
	rows.append(["Chi", "%d" % int(PlayerResources.CHI_MAX)])
	rows.append(["Focus for the signature", "%d" % int(PlayerResources.FOCUS_MAX)])
	if poise > 0.0:
		rows.append(["Poise", "%d" % int(round(poise))])
	var prof := LocomotionProfile.for_element(GameState.element)
	rows.append(["Run  ·  sprint", "%.1f  ·  %.1f m/s" % [prof.run_speed, prof.sprint_speed]])
	if prof.skate_speed > 0.0:
		rows.append(["Skating on snow and ice", "%.0f m/s" % prof.skate_speed])
	var kit := AbilityRegistry.core_kit(GameState.element)
	if kit.has(&"dodge"):
		rows.append([(kit[&"dodge"] as AbilityDef).display_name, "%.1f m%s" % [prof.dodge_distance, ("  ·  i-frames" if prof.dodge_iframes > 0.0 else "  ·  poise armor")]])
	if prof.air_jumps > 0:
		rows.append(["Air jumps", "%d  ·  glide" % prof.air_jumps])
	rows.append(["Knockback taken", "×%.1f" % prof.knockback_mult])
	return rows


func _mastery_lines() -> Array[String]:
	var out: Array[String] = []
	var e := GameState.element
	var tree := SkillTreeModel.nodes(e)
	var known := 0
	for n in tree:
		if GameState.is_unlocked(n["id"]):
			known += 1
	out.append("%d of %d techniques learned  ·  %d skill point%s unspent" % [known, tree.size(), GameState.skill_points, "" if GameState.skill_points == 1 else "s"])
	var sig := SkillTreeModel.signature_id(e)
	out.append(("Signature: %s" % SkillTreeModel.display_name(sig)) if sig != &"" else "Signature technique not learned yet")
	var practiced: Array = []
	for k: Variant in GameState.ability_practice:
		practiced.append([String(k), int(GameState.ability_practice[k])])
	practiced.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var parts := PackedStringArray()
	for i in mini(3, practiced.size()):
		parts.append("%s ×%d" % [SkillTreeModel.display_name(StringName(practiced[i][0])), int(practiced[i][1])])
	if not parts.is_empty():
		out.append("Most practised: %s" % ", ".join(parts))
	return out


func _record_rows() -> Array:
	var s := GameState.stats
	var quests_done := 0
	for k: Variant in GameState.quests:
		if String((GameState.quests[k] as Dictionary).get("state", "")) == "completed":
			quests_done += 1
	return [
		["Time travelled", SaveChooser.format_play_time(GameState.play_time)],
		["Places discovered", "%d" % GameState.discovered_pois.size()],
		["World explored", "%d%%" % int(round(MapModel.revealed_ratio() * 100.0))],
		["Quests completed", "%d" % quests_done],
		["Enemies defeated", "%d" % int(s.get("enemies_defeated", 0))],
		["Camps cleared", "%d" % int(s.get("camps_cleared", 0))],
		["Lessons with masters", "%d" % int(s.get("lessons_learned", 0))],
		["Spars won", "%d" % int(s.get("spars_won", 0))],
		["Techniques used", "%d" % int(s.get("abilities_used", 0))],
		["Coins", "%d" % GameState.currency],
	]


func _refresh_companion() -> void:
	var comp_type := String(GameState.companion.get("type", ""))
	var nm := String(GameState.companion.get("name", ""))
	if nm == "":
		nm = String(comp_type).capitalize()
	_comp_name.text = nm.to_upper() if nm != "" else "NO COMPANION"
	var status := ""
	var p := player()
	if p != null and p.has_method("get_companion"):
		var c: Variant = p.call("get_companion")
		if c is Node and is_instance_valid(c) and (c as Node).has_method("get_status_text"):
			status = String((c as Node).call("get_status_text"))
	_comp_status.text = status if status != "" else ("Waiting for you" if comp_type != "" else "")
	_comp_icon.modulate = UiTheme.element_light(GameState.element)
	var pts := CompanionBond.points()
	var t := CompanionBond.tier(pts)
	_bond_text.text = "BOND  ·  %s" % String(t["name"]).to_upper()
	_bond_bar.value = CompanionBond.tier_progress(pts)
	_bond_detail.text = "%d rides  ·  %.1f km ridden  ·  %.1f km flown  ·  %.1f h together.  Ride and travel together to deepen it." % [
		CompanionBond.rides(), CompanionBond.ridden_km(), CompanionBond.flown_km(), CompanionBond.hours_together()]


func page_process(_delta: float) -> void:
	pass
