extends TestCase
## progression_ui: the Journey Book (open / close / pause / tabs / input routing / pause-menu
## hook / touch groups), the skill tree (layout per element, requirements = can_unlock,
## learning with skill points, equip / swap / unequip, the live player's loadout, focus
## navigation), the world map (coordinate mapping, zoom / pan maths, known places, fast-travel
## guard rails + the travel call, the explored mask through a save round trip, visits), the
## journal (binding to the Quests journal API, track / untrack, completed list, abandon with
## its confirmation), the inventory (use a consumable), the character page, the level-up
## banner and the companion bond.

const BOOK := "res://scenes/ui/journey_book.tscn"

var _nodes: Array[Node] = []
var _quests_backup: Dictionary = {}


func before_each() -> void:
	GameState.reset()
	MapModel.travel_override = Callable()
	MapModel.combat_override = -1
	get_tree().paused = false


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for id: StringName in [&"pui_test_side", &"pui_test_main"]:
		if Quests.has_quest(id):
			Quests.unregister_quest(id)
	MapModel.travel_override = Callable()
	MapModel.combat_override = -1
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.reset()
	await frames(2)


func _add(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


func _book() -> JourneyBook:
	var b := (load(BOOK) as PackedScene).instantiate() as JourneyBook
	_add(b)
	return b


func _player(e: int) -> PlayerCharacter:
	var p := PlayerSim.player(self, e, Vector3.ZERO)
	_nodes.append(p)
	return p


func _action(a: StringName, pressed: bool = true) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)


# --- Journey Book --------------------------------------------------------------------------------

func test_book_opens_pauses_and_closes_every_way() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	var b := _book()
	await frames(2)
	expect(b.is_in_group(&"map_screen") and b.is_in_group(&"journal_screen"), "touch top bar groups (map / journal buttons)")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	expect(b.open(&"skills"), "opens")
	expect(get_tree().paused, "pauses the tree")
	expect(b.page == &"skills" and b.current_page() is SkillTreePage, "skills page shown")
	expect_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE, "mouse shown")
	# Esc (pause action) closes; the pause menu never sees it while the book is open
	_action(&"pause")
	await frames(2)
	_action(&"pause", false)
	expect(not b.is_open, "pause / Esc closes the book")
	expect(not get_tree().paused, "unpaused on close")
	# open_map / open_journal / open_skills open their page when closed
	_action(&"open_map")
	await frames(2)
	_action(&"open_map", false)
	expect(b.is_open and b.page == &"map", "open_map opens the map")
	# the same key again toggles it shut
	_action(&"open_map")
	await frames(2)
	_action(&"open_map", false)
	expect(not b.is_open, "open_map again closes")
	_action(&"open_journal")
	await frames(2)
	_action(&"open_journal", false)
	expect(b.is_open and b.page == &"journal", "open_journal opens the journal")
	# ui_cancel closes
	_action(&"ui_cancel")
	await frames(2)
	_action(&"ui_cancel", false)
	expect(not b.is_open, "ui_cancel (B / back button) closes")
	# CLOSE button
	b.open(&"inventory")
	await frames(2)
	(b.root.find_child("Close", true, false) as Button).pressed.emit()
	expect(not b.is_open, "CLOSE button closes")
	# dialogue starting closes it
	b.open(&"character")
	await frames(2)
	Events.dialogue_started.emit(self)
	expect(not b.is_open, "a dialogue starting closes the book")
	Events.dialogue_ended.emit(self)


func test_book_tabs_cycle_and_refuse_when_blocked() -> void:
	var b := _book()
	await frames(1)
	expect(not b.open(&"map"), "no journey yet: refused")
	GameState.new_game(ElementDefs.Element.FIRE)
	b.enabled = false
	expect(not b.open(&"map"), "disabled (arrival / loading): refused")
	b.enabled = true
	get_tree().paused = true
	expect(not b.open(&"map"), "another menu paused the game: refused")
	get_tree().paused = false
	expect(b.open(&"skills"), "opens")
	_key(KEY_E)
	await frames(2)
	expect_eq(b.page, &"map", "E -> next page")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	pad.pressed = true
	Input.parse_input_event(pad)
	await frames(2)
	expect_eq(b.page, &"journal", "RB -> next page")
	_key(KEY_Q)
	_key(KEY_Q)
	_key(KEY_Q)
	await frames(2)
	expect_eq(b.page, &"character", "Q wraps around backwards")
	for spec: Dictionary in JourneyBook.PAGES:
		b.show_page(spec["id"])
		await frames(1)
		expect(b.current_page() != null and b.current_page().visible, "page %s builds and shows" % spec["id"])
	b.close()


func test_pause_menu_journey_row_returns_to_pause() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	var b := _book()
	var pm := (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	_add(pm)
	await frames(2)
	pm.open()
	var row := pm.root.find_child("JourneyRow", true, false) as Control
	expect(row != null and row.visible, "journey row shown when a Journey Book exists")
	expect_eq(pm.journey_buttons.size(), 5, "five journey buttons")
	pm.open_journey(&"map")
	await frames(1)
	expect(not pm.is_open, "pause menu steps aside")
	expect(b.is_open and b.page == &"map", "book opened on the map")
	expect(get_tree().paused, "still paused")
	b.close()
	await frames(2)
	expect(pm.is_open, "closing the book returns to the pause menu")
	pm.resume()
	b.enabled = false
	pm.open()
	expect(not row.visible, "no journey row while the book is disabled")
	pm.resume()


# --- skill tree ----------------------------------------------------------------------------------

func test_skill_tree_layout_every_element() -> void:
	for e: int in ElementDefs.ALL:
		var nodes := SkillTreeModel.nodes(e)
		expect(nodes.size() >= 6, "%s tree has techniques (%d)" % [ElementDefs.id_of(e), nodes.size()])
		var cells := {}
		var ids := {}
		var signatures := 0
		for n in nodes:
			ids[n["id"]] = true
		for n in nodes:
			var key := Vector2i(int(n["column"]), int(n["tier"]))
			expect(not cells.has(key), "%s: one technique per cell %s" % [n["id"], key])
			cells[key] = true
			var pre: StringName = n["requires"]
			expect(pre == &"" or ids.has(pre), "%s prerequisite %s is in the tree" % [n["id"], pre])
			if bool(n["signature"]):
				signatures += 1
			expect(not (n["def"] as AbilityDef).script_path.is_empty(), "%s is implemented" % n["id"])
		expect_eq(signatures, 1, "%s has one signature" % ElementDefs.id_of(e))
		expect(SkillTreeModel.foundations(e).size() >= 4, "%s foundations = core kit" % ElementDefs.id_of(e))
		expect(SkillTreeModel.tier_count(e) >= 4, "%s has at least 4 tiers" % ElementDefs.id_of(e))


func test_requirements_match_can_unlock_and_learning_spends_points() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	AbilityRegistry.grant_starters(ElementDefs.Element.WATER)
	var id := &"ice_trap"
	expect_eq(SkillTreeModel.state(id), SkillTreeModel.STATE_LOCKED, "locked at level 1")
	var reqs := SkillTreeModel.requirements(id)
	var kinds := reqs.map(func(r: Dictionary) -> StringName: return r["kind"])
	expect(kinds.has(&"level") and kinds.has(&"prerequisite") and kinds.has(&"practice") and kinds.has(&"skill_points"), "requirements listed: %s" % str(kinds))
	expect_eq(SkillTreeModel.blocker(id), AbilityRegistry.can_unlock(id), "blocker is can_unlock")
	expect_eq(SkillTreeModel.learn(id), &"level", "refused below the level")
	expect_eq(GameState.skill_points, 0, "nothing spent")
	GameState.level = 3
	expect_eq(SkillTreeModel.learn(id), &"practice", "then practice")
	GameState.ability_practice["ice_shards"] = 8
	expect_eq(SkillTreeModel.learn(id), &"skill_points", "then skill points")
	GameState.skill_points = 2
	expect_eq(SkillTreeModel.state(id), SkillTreeModel.STATE_AVAILABLE, "available")
	for r in SkillTreeModel.requirements(id):
		expect(bool(r["met"]), "requirement met: %s" % r["text"])
	expect_eq(SkillTreeModel.learn(id), &"", "learned")
	expect(GameState.is_unlocked(id), "unlocked in GameState")
	expect_eq(GameState.skill_points, 1, "one point spent")
	expect_eq(SkillTreeModel.slot_of(id), 3, "auto-equipped into the free slot 4")
	expect_eq(SkillTreeModel.state(id), SkillTreeModel.STATE_LEARNED, "learned state")
	expect_eq(SkillTreeModel.learn(id), &"unlocked", "cannot learn twice")
	# trainer techniques: the master's lesson is the requirement (no point cost line)
	var heal := SkillTreeModel.requirements(&"healing_waters")
	var hk := heal.map(func(r: Dictionary) -> StringName: return r["kind"])
	expect(hk.has(&"trainer") and not hk.has(&"skill_points"), "healing waters: taught by a master, no point cost: %s" % str(hk))
	GameState.set_flag("trained_yugoda_healing_waters", true)
	var met := false
	for r in SkillTreeModel.requirements(&"healing_waters"):
		if r["kind"] == &"trainer":
			met = bool(r["met"])
	expect(met, "the lesson flag satisfies the trainer requirement")


func test_equip_swap_unequip_and_refusals() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	AbilityRegistry.grant_starters(ElementDefs.Element.EARTH)
	var a := SkillTreeModel.equipped(0)
	var b := SkillTreeModel.equipped(1)
	expect(a != &"" and b != &"", "starters equipped")
	expect_eq(SkillTreeModel.equip(1, a), &"", "equip slot 1's technique into slot 2")
	expect_eq(SkillTreeModel.equipped(1), a, "moved")
	expect_eq(SkillTreeModel.equipped(0), b, "swapped with what was there")
	SkillTreeModel.unequip(0)
	expect_eq(SkillTreeModel.equipped(0), &"", "unequipped")
	expect_eq(SkillTreeModel.equip(0, &"earthquake"), &"not_technique", "the signature never goes into a technique slot")
	expect_eq(SkillTreeModel.equip(0, &"earth_punch"), &"not_technique", "the core kit is not slotted")
	expect_eq(SkillTreeModel.equip(0, &"earth_spikes"), &"locked", "an unlearned technique cannot be equipped")
	expect_eq(SkillTreeModel.equip(0, &"ice_shards"), &"element", "another element's technique is refused")
	expect_eq(SkillTreeModel.equip(7, a), &"slot", "slot range")
	expect_eq(SkillTreeModel.signature_id(ElementDefs.Element.EARTH), &"", "no signature yet")
	GameState.unlock_ability(&"earthquake", false)
	expect_eq(SkillTreeModel.signature_id(ElementDefs.Element.EARTH), &"earthquake", "signature in use once learned")


func test_equip_reloads_the_live_players_loadout() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	AbilityRegistry.grant_starters(ElementDefs.Element.FIRE)
	var p := _player(ElementDefs.Element.FIRE)
	await physics_frames(2)
	var first := SkillTreeModel.equipped(0)
	var second := SkillTreeModel.equipped(1)
	SkillTreeModel.equip(0, second)
	var d := p.controller.get_slot_def(&"technique_1")
	expect(d != null and d.id == second, "the player's technique_1 follows the loadout (%s)" % (d.id if d else &"none"))
	expect_eq(StringName(p.get_ability_slot_info(1).get("id", &"")), first, "HUD slot info follows the swap")
	SkillTreeModel.unequip(1)
	expect(p.controller.get_slot_def(&"technique_2") == null, "unequipped slot empties on the player")


func test_skill_page_learn_arm_equip_and_focus_navigation() -> void:
	GameState.new_game(ElementDefs.Element.AIR)
	AbilityRegistry.grant_starters(ElementDefs.Element.AIR)
	GameState.level = 3
	GameState.skill_points = 1
	GameState.ability_practice["air_push"] = 6
	var b := _book()
	b.pause_tree = false
	await frames(1)
	b.open(&"skills")
	await frames(3)
	var page := b.current_page() as SkillTreePage
	expect(page.canvas.nodes.size() == SkillTreeModel.nodes(ElementDefs.Element.AIR).size(), "all air techniques shown")
	expect(page.canvas.foundation_nodes.size() == SkillTreeModel.foundations(ElementDefs.Element.AIR).size(), "foundations shown")
	var focus := get_viewport().gui_get_focus_owner()
	expect(focus is SkillNode, "a technique is focused on open (controller / keyboard)")
	# keyboard / controller navigation moves between medallions
	UiFx.focus_silently(page.canvas.nodes[&"air_push"])
	await frames(1)
	_action(&"ui_right")
	await frames(2)
	_action(&"ui_right", false)
	var f2 := get_viewport().gui_get_focus_owner()
	expect(f2 is SkillNode and (f2 as SkillNode).id != &"air_push", "ui_right moves focus to the next technique (%s)" % (f2.name if f2 else "none"))
	expect(page.selected == (f2 as SkillNode).id if f2 is SkillNode else false, "focus selects (detail panel follows)")
	# learn wind blade (skip the dialog: the confirm is tested in the playtest)
	page.select(&"wind_blade")
	expect_eq(await page.learn_selected(true), &"", "learned from the page")
	expect(GameState.is_unlocked(&"wind_blade"), "wind blade unlocked")
	expect(page.canvas.nodes[&"wind_blade"].state == &"learned", "node shows learned")
	# arm + place in slot 1 (tap technique, tap slot)
	page.arm(&"wind_blade")
	expect_eq(page.armed, &"wind_blade", "armed")
	expect(page.slots[0].target, "slots glow while armed")
	page._on_slot_pressed(0)
	expect_eq(SkillTreeModel.equipped(0), &"wind_blade", "tap on slot 1 equips the armed technique")
	expect_eq(page.armed, &"", "disarmed after placing")
	# drag & drop data path
	page._on_slot_dropped(2, {"kind": &"technique", "id": &"air_sweep"})
	expect_eq(SkillTreeModel.equipped(2), &"air_sweep", "drop a technique on slot 3")
	page._on_slot_dropped(3, {"kind": &"slot", "index": 2})
	expect_eq(SkillTreeModel.equipped(3), &"air_sweep", "drop slot 3 on slot 4 moves it")
	page._on_slot_drag_out(3)
	expect_eq(SkillTreeModel.equipped(3), &"", "drag a slot off the bar to unequip")
	# Back first leaves arming, then closes
	page.arm(&"air_push")
	_action(&"ui_cancel")
	await frames(2)
	_action(&"ui_cancel", false)
	expect(b.is_open and page.armed == &"", "Back cancels arming first")
	_action(&"ui_cancel")
	await frames(2)
	_action(&"ui_cancel", false)
	expect(not b.is_open, "second Back closes")


# --- map ----------------------------------------------------------------------------------------

func test_map_coordinates_and_view_maths() -> void:
	for p: Vector3 in [Vector3(0, 0, 0), Vector3(-4000, 0, 3900), Vector3(2500, 0, 3350), Vector3(-300, 0, -3010)]:
		var uv := MapModel.world_to_uv(p)
		var back := MapModel.uv_to_world(uv)
		expect(Vector2(back.x, back.z).distance_to(Vector2(p.x, p.z)) < 0.5, "uv round trip %s" % p)
	expect(MapModel.world_to_uv(Vector3(-4096, 0, -4096)).distance_to(Vector2.ZERO) < 0.001, "north-west corner = uv 0,0")
	GameState.new_game(ElementDefs.Element.WATER)
	var c := MapCanvas.new()
	c.size = Vector2(1200, 800)
	_add(c)
	await frames(1)
	c.size = Vector2(1200, 800)
	c.focus_on(Vector3(500, 0, 400), 3.0, true)
	var s := c.world_to_local(Vector3(500, 0, 400))
	expect(s.distance_to(c.size * 0.5) < 1.0, "focus_on centres the place")
	var w := c.local_to_world(Vector2(300, 200))
	expect(c.world_to_local(w).distance_to(Vector2(300, 200)) < 0.5, "local <-> world round trip")
	var before := c.local_to_uv(Vector2(900, 300))
	c.zoom_at(Vector2(900, 300), 1.5)
	c.zoom = c.target_zoom
	c.center = c.target_center
	expect(c.local_to_uv(Vector2(900, 300)).distance_to(before) < 0.0005, "zoom keeps the point under the cursor")
	c.target_zoom = 99.0
	c._clamp_view()
	expect_near(c.target_zoom, MapCanvas.MAX_ZOOM, 0.001, "zoom clamped")
	c.focus_on(Vector3(-4090, 0, -4090), 2.0, true)
	expect(c.local_to_uv(Vector2.ZERO).x >= -0.0001 and c.local_to_uv(Vector2.ZERO).y >= -0.0001, "the view never shows beyond the map edge")
	c.cursor_mode = true
	expect(c.cursor_local().distance_to(c.world_to_local(Vector3(-4090, 0, -4090))) < 1.0, "the reticle reaches places at the edge")
	expect_near(c.metres_per_px(), 8192.0 / (800.0 * c.zoom), 0.01, "scale bar maths")


func test_map_knowledge_and_fast_travel_guard_rails() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	var home := MapModel.place_by_id(&"ba_sing_se")
	expect(MapModel.is_known(home), "home city known on a new game")
	expect(not MapModel.is_known(MapModel.place_by_id(&"omashu")), "other cities unknown until visited")
	expect(MapModel.is_lettered(MapModel.place_by_id(&"omashu")), "cities are lettered anyway")
	var shrine := MapModel.place_by_id(&"ek_moonmirror_pavilion")
	expect(not shrine.is_empty() and MapModel.is_travel_point(shrine), "shrines are travel points")
	expect_eq(MapModel.travel_block_reason(shrine), "Discover this place first.", "undiscovered refused")
	GameState.discover_poi(&"ek_moonmirror_pavilion")
	var p := _player(ElementDefs.Element.EARTH)
	p.global_position = Vector3(1868, 86, 242)
	await physics_frames(1)
	var calls: Array = []
	MapModel.travel_override = func(xf: Transform3D, opts: Dictionary) -> bool:
		calls.append([xf, opts])
		return true
	expect_eq(MapModel.travel_block_reason(shrine), "", "known shrine, calm, far away: allowed")
	MapModel.combat_override = 1
	expect_eq(MapModel.travel_block_reason(shrine), "Not while enemies are near.", "refused in combat")
	MapModel.combat_override = -1
	GameState.is_tutorial = true
	expect(MapModel.travel_block_reason(shrine) != "", "refused in the training grounds")
	GameState.is_tutorial = false
	p.global_position = shrine["position"] + Vector3(10, 0, 0)
	expect_eq(MapModel.travel_block_reason(shrine), "You are already here.", "refused when already there")
	p.global_position = Vector3(1868, 86, 242)
	var ok: bool = await MapModel.travel(shrine)
	expect(ok and calls.size() == 1, "travel calls the travel API once")
	if calls.size() == 1:
		var xf: Transform3D = calls[0][0]
		expect(xf.origin.distance_to(shrine["position"]) < 60.0, "lands next to the shrine (%.1f m)" % xf.origin.distance_to(shrine["position"]))
		expect(String((calls[0][1] as Dictionary).get("text", "")).contains(String(shrine["name"])), "travel text names the place")
	expect(not MapModel.is_travel_point(MapModel.place_by_id(&"ek_dustwind_camp")), "camps are not travel points")
	var port := MapModel.place_by_id(&"port_full_moon_bay")
	expect(not MapModel.is_known(port), "port unknown")
	GameState.discover_poi(&"ek_full_moon_bay")
	expect(MapModel.is_known(port), "discovering the dock makes the port known")
	var qt := MapModel.travel_transform(port)
	expect(qt.origin.distance_to(port["position"]) < 1.0, "port travel lands on the quay")
	# a village / port record and its discovery POI on the same spot are one marker
	var dock := MapModel.place_by_id(&"ek_full_moon_bay")
	expect_eq(StringName(dock.get("merged_into", &"")), &"port_full_moon_bay", "the dock POI merges into its port")
	expect_eq(StringName(MapModel.shown_place(dock)["id"]), &"port_full_moon_bay", "shown as the port")
	var names := {}
	var dupes: Array[String] = []
	for pl in MapModel.places():
		if pl.has("merged_into") or pl["kind"] == &"city":
			continue
		var key := "%s@%d,%d" % [pl["name"], int((pl["position"] as Vector3).x / 200.0), int((pl["position"] as Vector3).z / 200.0)]
		if names.has(key):
			dupes.append("%s (%s/%s %s + %s)" % [pl["name"], pl["kind"], pl["type"], pl["id"], names[key]])
		names[key] = "%s/%s %s" % [pl["kind"], pl["type"], pl["id"]]
	expect(dupes.is_empty(), "no place is marked twice on the map %s" % str(dupes))


func test_map_visits_and_reveal_survive_a_save() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	MapModel.ensure_seeded(Vector3.INF)
	var home := MapModel.place_by_id(&"northern_water_tribe")
	expect(MapModel.is_revealed(home["position"]), "home city revealed on a new journey")
	var far := Vector3(2000, 0, 200)
	expect(not MapModel.is_revealed(far), "Ba Sing Se not explored yet")
	var r0 := MapModel.revealed_ratio()
	MapModel.note_position(far)
	expect(MapModel.is_revealed(far), "walking there reveals it")
	expect(MapModel.revealed_ratio() > r0, "explored ratio grows")
	expect(MapModel.is_known(MapModel.place_by_id(&"ba_sing_se")), "walking into a city marks it visited")
	var json := JSON.stringify(GameState.to_dict())
	var data: Variant = JSON.parse_string(json)
	GameState.reset()
	expect(not MapModel.is_revealed(far), "reset clears it")
	GameState.from_dict(data)
	expect(MapModel.is_revealed(far), "the explored mask survives a JSON save round trip")
	expect(MapModel.is_known(MapModel.place_by_id(&"ba_sing_se")), "visits survive the save")
	var img := MapModel.reveal_image()
	expect(img.get_width() == MapModel.REVEAL_N and img.get_format() == Image.FORMAT_L8, "mask image for the shader")


func test_map_page_card_and_travel_flow() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	GameState.discover_poi(&"fn_eternal_flame")
	var p := _player(ElementDefs.Element.FIRE)
	p.global_position = WorldData.get_spawn(ElementDefs.Element.FIRE).origin
	var b := _book()
	b.pause_tree = false
	await frames(1)
	var trips: Array = []
	MapModel.travel_override = func(xf: Transform3D, _o: Dictionary) -> bool:
		trips.append(xf)
		return true
	b.open(&"map", {"place": &"fn_eternal_flame"})
	await frames(4)
	var page := b.current_page() as WorldMapPage
	expect(page.card_place.get("id", &"") == &"fn_eternal_flame", "open args select the place")
	var travel := page.find_child("FastTravel", true, false) as Button
	expect(travel.visible and not travel.disabled, "FAST TRAVEL offered for a discovered shrine")
	page.request_travel(page.card_place)
	await frames(2)
	var dlg := b.root.find_child("Confirm", true, false) as ConfirmDialog
	expect(dlg != null and dlg.is_open, "asks for confirmation")
	if dlg:
		(dlg.buttons[&"go"] as Button).pressed.emit()
	await frames(3)
	expect_eq(trips.size(), 1, "travelled after TRAVEL")
	expect(not b.is_open, "the book closed for the trip")
	# STAY keeps the book open and does not travel
	b.open(&"map", {"place": &"fn_eternal_flame"})
	await frames(4)
	page.request_travel(page.card_place)
	await frames(2)
	dlg = b.root.find_child("Confirm", true, false) as ConfirmDialog
	if dlg:
		(dlg.buttons[&"stay"] as Button).pressed.emit()
	await frames(2)
	expect_eq(trips.size(), 1, "STAY does not travel")
	expect(b.is_open, "STAY keeps the map open")
	MapModel.combat_override = 1
	page._show_card(page.card_place)
	expect(travel.disabled, "button disabled in combat")
	expect(await page.request_travel(page.card_place) == false, "refused in combat")
	MapModel.combat_override = -1
	b.close()


# --- journal ------------------------------------------------------------------------------------

func _test_quest(id: StringName, kind: StringName) -> Dictionary:
	return {"id": id, "title": "Test %s" % String(id), "kind": kind, "nation": &"water", "giver": &"", "location": "The test ice",
		"summary": "A summary for the journal.", "description": "Longer lore text.",
		"stages": [{"id": &"one", "text": "First stage text.", "objectives": [{"id": &"a", "type": &"interact", "key": &"pui_a", "count": 2, "text": "Touch the stone"}]},
			{"id": &"two", "text": "Second stage text.", "objectives": [{"id": &"b", "type": &"interact", "key": &"pui_b", "count": 1, "text": "Bow to the moon"}]}],
		"rewards": {"xp": 10}}


func test_journal_binds_to_the_quest_api() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	Quests.register_quest(_test_quest(&"pui_test_side", &"side"))
	Quests.register_quest(_test_quest(&"pui_test_main", &"main"))
	Quests.start(&"pui_test_side")
	Quests.start(&"pui_test_main")
	var b := _book()
	b.pause_tree = false
	await frames(1)
	b.open(&"journal", {"quest": &"pui_test_side"})
	await frames(3)
	var page := b.current_page() as JournalPage
	var ids := page.entries.map(func(e: Dictionary) -> StringName: return e["id"])
	expect(ids.has(&"pui_test_side") and ids.has(&"pui_test_main"), "active quests listed: %s" % str(ids))
	expect_eq(page.selected, &"pui_test_side", "opened on the requested quest")
	var text := _all_text(page)
	expect(text.contains("TEST PUI_TEST_SIDE") and text.contains("Touch the stone") and text.contains("0 / 2"), "detail shows title, objective and count")
	expect(text.contains("A summary for the journal."), "lore text shown")
	page.toggle_track()
	expect_eq(GameState.tracked_quest, &"pui_test_side", "TRACK sets the HUD tracker quest")
	page.toggle_track()
	expect_eq(GameState.tracked_quest, &"", "UNTRACK clears it")
	Quests.report(&"interact", &"pui_a", 2)
	await frames(2)
	expect(_all_text(page).contains("Second stage text."), "live refresh on quest_changed: next stage shown")
	Quests.force_complete(&"pui_test_main")
	await frames(1)
	page.set_filter(&"completed")
	await frames(1)
	expect(page.entries.map(func(e: Dictionary) -> StringName: return e["id"]).has(&"pui_test_main"), "completed list")
	page.set_filter(&"active")
	page.selected = &"pui_test_side"
	page.refresh()
	page.abandon_selected()
	await frames(2)
	var dlg := b.root.find_child("Confirm", true, false) as ConfirmDialog
	expect(dlg != null and dlg.is_open, "abandon asks first")
	if dlg:
		(dlg.buttons[&"abandon"] as Button).pressed.emit()
	await frames(2)
	expect_eq(Quests.state(&"pui_test_side"), Quests.STATE_NONE, "side quest abandoned")
	b.close()


func _all_text(n: Node) -> String:
	var parts := PackedStringArray()
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).is_visible_in_tree():
			parts.append((c as Label).text)
	return "\n".join(parts)


# --- inventory, character, level-up, bond ---------------------------------------------------------

func test_inventory_uses_a_consumable_on_the_player() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	GameState.add_item(&"arctic_moss", 2)
	GameState.add_item(&"waterskin", 1)
	var p := _player(ElementDefs.Element.WATER)
	await physics_frames(1)
	p.health.health = p.health.max_health - 40.0
	var b := _book()
	b.pause_tree = false
	await frames(1)
	b.open(&"inventory")
	await frames(3)
	var page := b.current_page() as InventoryPage
	expect(page.tiles.size() == 2, "two kinds of items shown")
	page.selected = &"arctic_moss"
	expect(page.use_selected(), "used the moss")
	expect_eq(GameState.item_count(&"arctic_moss"), 1, "one consumed")
	expect(p.health.health > p.health.max_health - 40.0, "healed")
	p.health.health = p.health.max_health
	page.selected = &"arctic_moss"
	expect(not page.use_selected(), "refused at full health")
	expect_eq(GameState.item_count(&"arctic_moss"), 1, "nothing consumed")
	page.selected = &"waterskin"
	expect(not page.use_selected(), "supplies are not usable")
	# a click / tap on a tile that is not selected only selects it; the next press uses it
	p.health.health = p.health.max_health - 40.0
	page.selected = &"waterskin"
	page.refresh()
	await frames(1)
	var tile := page.find_child("Item_arctic_moss", true, false) as Button
	expect(tile != null, "moss tile")
	if tile:
		tile.grab_focus()
		tile.button_down.emit()
		tile.pressed.emit()
		expect_eq(page.selected, &"arctic_moss", "the press selected the moss")
		expect_eq(GameState.item_count(&"arctic_moss"), 1, "... without using it")
		await frames(1)
		tile.button_down.emit()
		tile.pressed.emit()
		expect_eq(GameState.item_count(&"arctic_moss"), 0, "a second press on the selected tile uses it")
	page.set_view(&"discoveries")
	await frames(1)
	expect(_all_text(page).contains("places discovered"), "discoveries view")
	b.close()


func test_character_page_and_companion_bond() -> void:
	GameState.new_game(ElementDefs.Element.AIR)
	GameState.level = 4
	GameState.xp = 100
	GameState.stats["companion_rides"] = 10
	GameState.stats["companion_flown_m"] = 5000
	var pts := CompanionBond.points()
	expect(pts >= 90, "rides + km flown build the bond (%d)" % pts)
	expect_eq(String(CompanionBond.tier(pts)["name"]), "Familiar", "tier by points")
	CompanionBond.sync()
	expect_eq(int(GameState.companion["bond"]), pts, "stored in GameState.companion.bond")
	var b := _book()
	b.pause_tree = false
	await frames(1)
	b.open(&"character")
	await frames(3)
	var t := _all_text(b.current_page())
	expect(t.contains("LEVEL 4") and t.contains("XP"), "level + experience")
	expect(t.contains("FAMILIAR"), "bond tier shown")
	expect(t.contains("Airbender of the Air Nomads"), "title from the element")
	expect_eq(CharacterPage._play_time(30.0), "just begun", "play time under a minute")
	expect_eq(CharacterPage._play_time(14.0 * 60.0), "14 min", "minutes")
	expect_eq(CharacterPage._play_time(2.6 * 3600.0), "2 hr 36 min", "hours + minutes")
	b.close()


func test_level_up_banner_prompts_for_skills() -> void:
	GameState.new_game(ElementDefs.Element.WATER)
	AbilityRegistry.grant_starters(ElementDefs.Element.WATER)
	GameState.ability_practice["ice_shards"] = 8
	var b := _book()
	b.pause_tree = false
	var layer := CanvasLayer.new()
	_add(layer)
	var banner := LevelUpBanner.new()
	banner.book = b
	layer.add_child(banner)
	await frames(1)
	GameState.add_xp(GameState.xp_for_level(1) + GameState.xp_for_level(2) + 5)
	await frames(2)
	expect(banner.is_showing and banner.shown == 1, "one banner for two levels at once")
	expect_eq(GameState.level, 3, "reached level 3")
	expect(_all_text(banner).contains("LEVEL 3"), "shows the new level")
	expect(_all_text(banner).contains("Ice Trap"), "names what became learnable")
	banner.open_skills()
	await frames(2)
	expect(b.is_open and b.page == &"skills", "the prompt opens the skill tree")
	expect(not banner.visible, "the banner steps aside")
	b.close()
