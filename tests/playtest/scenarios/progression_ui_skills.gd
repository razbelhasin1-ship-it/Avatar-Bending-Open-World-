extends RefCounted
## Skill tree page over the combat arena (real PlayerCharacter + HUD): the tree in mixed
## states, the live technique preview, learning with a skill point through the confirm
## dialog (keyboard), arming + equipping into a slot (controller-style ui actions), quick
## equip with a number key, unequip, and the result on the HUD loadout after closing.
## Env: ELEMENT=water|earth|fire|air (default water), ALL=1 (one tree shot per element).


func run(p: Playtest) -> void:
	var elements: Array[int] = []
	if OS.get_environment("ALL") == "1":
		elements = [ElementDefs.Element.WATER, ElementDefs.Element.EARTH, ElementDefs.Element.FIRE, ElementDefs.Element.AIR]
	else:
		var e := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
		elements = [e if ElementDefs.is_valid(e) else ElementDefs.Element.WATER]
	for e in elements:
		await _run_element(p, e, elements.size() == 1)


func _run_element(p: Playtest, e: int, full: bool) -> void:
	GameState.new_game(e)
	AbilityRegistry.grant_starters(e)
	GameState.level = 5
	GameState.skill_points = 2
	var tree := SkillTreeModel.nodes(e)
	# practice the first starter enough to open its tier-2 follow-up
	for n in tree:
		if int(n["tier"]) == 2 and n["requires"] != &"":
			GameState.ability_practice[String(n["requires"])] = 10
			break
	await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait(1.5)
	var book := (load("res://scenes/ui/journey_book.tscn") as PackedScene).instantiate() as JourneyBook
	p.scene().add_child(book)
	await p.frames(2)
	p.check(book.open(&"skills"), "book opens on the skills page")
	await p.wait(0.8)
	var page := book.current_page() as SkillTreePage
	p.check(page != null and page.canvas.nodes.size() == tree.size(), "every technique of the tree is shown (%d)" % tree.size())
	p.check(p.get_tree().paused, "the game is paused while the book is open")
	await p.wait(1.2)
	await p.screenshot("skills_%s_overview" % ElementDefs.id_of(e))
	if not full:
		book.close()
		await p.wait(0.3)
		return
	# the live preview: a starter technique performed by the player's rig, effects on its events
	var starter_id: StringName = SkillTreeModel.equipped(0)
	UiFx.focus_silently(page.canvas.nodes[starter_id])
	var fired0 := page.preview.flourish.fired
	var clips0 := page.preview.clips_played
	for i in 4:
		await p.wait(0.45)
		await p.screenshot("skills_%s_preview_%d" % [ElementDefs.id_of(e), i])
	await p.wait(1.5)
	p.check(page.preview.clips_played > clips0, "the preview plays the technique's clips (%d)" % (page.preview.clips_played - clips0))
	p.check(page.preview.flourish.fired > fired0, "the preview's effects fire on the clip events (%d)" % (page.preview.flourish.fired - fired0))
	# desktop drag & drop with real mouse events: technique medallion -> loadout slot 4
	SkillTreeModel.unequip(3)
	page.refresh()
	await p.frames(2)
	var src: SkillNode = page.canvas.nodes[SkillTreeModel.equipped(1)]
	var from := src.get_global_rect().get_center()
	var to := page.slots[3].get_global_rect().get_center()
	await _mouse_drag(p, from, to)
	await p.wait(0.3)
	p.check(SkillTreeModel.equipped(3) == src.id, "mouse drag from the tree onto slot 4 equips it (%s)" % SkillTreeModel.equipped(3))
	# learn the first available technique with the keyboard (Enter -> confirm LEARN)
	var learnable := SkillTreeModel.learnable(e)
	p.check(not learnable.is_empty(), "something is learnable at level 5 with 2 skill points")
	if not learnable.is_empty():
		var id: StringName = learnable[0]
		var n: SkillNode = page.canvas.nodes[id]
		UiFx.focus_silently(n)
		await p.frames(2)
		await p.wait(0.6)
		await p.screenshot("skills_%s_learnable_selected" % ElementDefs.id_of(e))
		await _key(p, KEY_ENTER)
		await p.wait(0.4)
		await p.screenshot("skills_%s_learn_confirm" % ElementDefs.id_of(e))
		await _key(p, KEY_ENTER)
		await p.wait(0.6)
		p.check(GameState.is_unlocked(id), "learned %s through the confirm dialog" % id)
		p.check(GameState.skill_points < 2, "a skill point was spent")
		await p.screenshot("skills_%s_learned" % ElementDefs.id_of(e))
		# if it was not auto-equipped it is armed: place it in slot 4 with ui_accept on the slot
		if SkillTreeModel.slot_of(id) < 0:
			UiFx.focus_silently(page.slots[3])
			await p.frames(1)
			await p.tap(&"ui_accept")
			await p.wait(0.3)
		p.check(SkillTreeModel.slot_of(id) >= 0, "the new technique sits in a slot")
	# quick-equip: focus a learned technique, press 1
	var starter: StringName = SkillTreeModel.equipped(1)
	if starter != &"":
		UiFx.focus_silently(page.canvas.nodes[starter])
		await p.frames(1)
		await _key(p, KEY_1)
		await p.wait(0.3)
		p.check(SkillTreeModel.equipped(0) == starter, "key 1 equips the focused technique into slot 1")
	# unequip slot 3 with Delete
	UiFx.focus_silently(page.slots[2])
	await p.frames(1)
	var before := SkillTreeModel.equipped(2)
	await _key(p, KEY_DELETE)
	await p.wait(0.3)
	p.check(before == &"" or SkillTreeModel.equipped(2) == &"", "Delete unequips the focused slot")
	await p.screenshot("skills_%s_loadout_edit" % ElementDefs.id_of(e))
	# a locked node explains itself
	for nn in tree:
		if SkillTreeModel.state(nn["id"]) == SkillTreeModel.STATE_LOCKED:
			UiFx.focus_silently(page.canvas.nodes[nn["id"]])
			await p.wait(0.8)
			await p.screenshot("skills_%s_locked_detail" % ElementDefs.id_of(e))
			break
	# close with Esc: the HUD shows the new loadout
	await _key(p, KEY_ESCAPE)
	await p.wait(0.5)
	p.check(not book.is_open and not p.get_tree().paused, "Esc closes the book and unpauses")
	var pl := p.player() as PlayerCharacter
	if pl:
		var info := pl.get_ability_slot_info(0)
		p.check(StringName(info.get("id", &"")) == SkillTreeModel.equipped(0), "the player's slot 1 matches the loadout")
	await p.wait(0.6)
	await p.screenshot("skills_%s_hud_after" % ElementDefs.id_of(e))


## Left-button drag in canvas coordinates (pushed through the viewport like a real mouse).
func _mouse_drag(p: Playtest, from: Vector2, to: Vector2) -> void:
	var vp := p.get_viewport()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(down, true)
	await p.frames(2)
	for i in 12:
		var mm := InputEventMouseMotion.new()
		var at := from.lerp(to, float(i + 1) / 12.0)
		mm.position = at
		mm.global_position = at
		mm.relative = (to - from) / 12.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm, true)
		await p.frames(1)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	up.global_position = to
	vp.push_input(up, true)
	await p.frames(2)


func _key(p: Playtest, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await p.frames(1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await p.frames(2)
