extends RefCounted
## The Journey Book's other pages over the combat arena (real PlayerCharacter + HUD) with a
## lived-in journey: the level-up banner over the HUD, the pause menu's journey row (opened
## from the pause menu, back to it on close), the journal with real quests (active, tracked,
## completed; track / untrack with the keyboard, stage log), the inventory (items, use a
## consumable, discoveries) and the character page (portrait, level / XP, stats, bond).
## Env: ELEMENT=water|earth|fire|air (default fire), SHOTS=prefix.

var p: Playtest


func run(pt: Playtest) -> void:
	p = pt
	var e := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	if not ElementDefs.is_valid(e):
		e = ElementDefs.Element.FIRE
	var tag := String(ElementDefs.id_of(e))
	GameState.new_game(e)
	AbilityRegistry.grant_starters(e)
	GameState.level = 4
	GameState.xp = 260
	GameState.currency = 145
	GameState.play_time = 2.6 * 3600.0
	for it: Array in [[&"fire_lily", 3], [&"healing_salve", 1], [&"fire_flakes", 4], [&"komodo_jerky", 2], [&"jasmine_tea", 1],
			[&"flame_charm", 1], [&"silk_scarf", 1], [&"lamp_oil", 2], [&"arrows", 12], [&"jade_figurine", 1]]:
		GameState.add_item(it[0], it[1])
	GameState.stats.merge({"enemies_defeated": 23, "camps_cleared": 2, "abilities_used": 311, "lessons_learned": 1, "spars_won": 1,
		"companion_rides": 9, "companion_flown_m": 6400, "companion_ridden_m": 900}, true)
	var n := 0
	for poi: Dictionary in WorldData.get_pois():
		if n < 14 and (poi["region"] == &"fire_nation" or n % 3 == 0):
			GameState.discover_poi(StringName(poi["id"]))
			n += 1
	# real quests from the content: the opening chain of the element (+ one finished)
	var opening := {ElementDefs.Element.WATER: [&"wt_born_of_the_tide", &"wt_first_form"], ElementDefs.Element.EARTH: [&"ek_stone_beneath_the_sky", &"ek_rooted"],
		ElementDefs.Element.FIRE: [&"fn_a_spark_returns", &"fn_breath_of_fire"], ElementDefs.Element.AIR: [&"at_first_breath", &"at_leaves_on_the_wind"]}
	var chain: Array = opening[e]
	if Quests.has_quest(chain[0]):
		Quests.start(chain[0])
		Quests.force_complete(chain[0])
	if Quests.has_quest(chain[1]) and not Quests.is_active(chain[1]):
		Quests.start(chain[1])
	var side := 0
	for id: StringName in Quests.order:
		var d := Quests.get_def(id)
		if side < 2 and d.get("kind") == &"side" and StringName(str(d.get("nation", ""))) == ElementDefs.id_of(e) and Quests.state(id) == &"none":
			Quests.start(id)
			side += 1
	await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait(1.5)
	var book := (load("res://scenes/ui/journey_book.tscn") as PackedScene).instantiate() as JourneyBook
	p.scene().add_child(book)
	var layer := CanvasLayer.new()
	layer.layer = 38
	p.scene().add_child(layer)
	var banner := LevelUpBanner.new()
	banner.book = book
	layer.add_child(banner)
	var pm := (load("res://scenes/ui/pause_menu.tscn") as PackedScene).instantiate() as PauseMenu
	pm.save_override = func() -> bool: return true
	p.scene().add_child(pm)
	await p.frames(2)
	# level-up moment over the HUD
	GameState.add_xp(GameState.xp_for_level(GameState.level) - GameState.xp + 5)
	await p.wait(1.2)
	p.check(banner.is_showing, "level-up banner shows")
	await p.screenshot("pages_%s_levelup" % tag)
	await p.wait(4.0)
	# pause menu journey row
	await p.tap(&"pause")
	await p.wait(0.5)
	p.check(pm.is_open, "pause menu open")
	var row := pm.root.find_child("JourneyRow", true, false) as Control
	p.check(row != null and row.visible, "journey row on the pause menu")
	await p.screenshot("pages_%s_pause_row" % tag)
	pm.journey_buttons[2].pressed.emit()
	await p.wait(0.6)
	p.check(book.is_open and book.page == &"journal" and not pm.is_open, "journal opened from the pause menu")
	var jp := book.current_page() as JournalPage
	p.check(jp.entries.size() >= 2, "active quests listed (%d)" % jp.entries.size())
	await p.wait(0.5)
	await p.screenshot("pages_%s_journal" % tag)
	# track the second quest with the keyboard: Down + Enter
	await _key(KEY_DOWN)
	await p.wait(0.2)
	var focused_q := jp.selected
	await _key(KEY_ENTER)
	await p.wait(0.3)
	p.check(GameState.tracked_quest == focused_q, "Enter tracks the focused quest (%s)" % focused_q)
	await p.screenshot("pages_%s_journal_tracked" % tag)
	await _key(KEY_TAB)
	await p.wait(0.4)
	p.check(jp.filter == &"completed", "Tab shows completed quests")
	await p.screenshot("pages_%s_journal_completed" % tag)
	# inventory
	book.show_page(&"inventory")
	await p.wait(0.6)
	var ip := book.current_page() as InventoryPage
	p.check(ip.tiles.size() >= 8, "inventory tiles (%d)" % ip.tiles.size())
	var pl := p.player() as PlayerCharacter
	if pl:
		pl.health.health = pl.health.max_health * 0.5
	ip.selected = &"fire_lily"
	ip.refresh()
	await p.wait(0.4)
	await p.screenshot("pages_%s_inventory" % tag)
	await _key(KEY_ENTER)
	await p.wait(0.4)
	p.check(GameState.item_count(&"fire_lily") == 2, "Enter on the focused herb uses it")
	ip.set_view(&"discoveries")
	await p.wait(0.4)
	await p.screenshot("pages_%s_discoveries" % tag)
	# character
	book.show_page(&"character")
	await p.wait(2.0)
	await p.screenshot("pages_%s_character" % tag)
	# close: back to the pause menu, then resume
	await _key(KEY_ESCAPE)
	await p.wait(0.5)
	p.check(not book.is_open and pm.is_open, "closing the book returns to the pause menu")
	await _key(KEY_ESCAPE)
	await p.wait(0.4)
	p.check(not pm.is_open and not p.get_tree().paused, "Esc resumes the game")


func _key(code: Key) -> void:
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
