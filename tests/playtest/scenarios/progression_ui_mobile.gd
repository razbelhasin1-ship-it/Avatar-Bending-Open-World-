extends RefCounted
## The Journey Book by TOUCH ONLY (simulated InputEventScreenTouch / ScreenDrag through the
## real GUI path, mouse emulated from touch like a phone) over the combat arena: the HUD's
## touch top bar shows the Map / Journal buttons because the book exists -> tap Map -> drag
## pans, two-finger pinch zooms, tap a place shows its card -> tap the SKILLS tab -> tap a
## learned technique then tap an empty slot (tap-to-select, tap-slot) -> JOURNAL tab ->
## tap outside the sheet closes. Checks every tappable control is >= 88 design px.
## Run: MOBILE=1 RENDERER=mobile tools/playtest.sh progression_ui_mobile <out> 1600x720

const Util := preload("res://tests/playtest/scenarios/mobile_touch_util.gd")

var p: Playtest
var t: Util


func run(pt: Playtest) -> void:
	p = pt
	t = Util.new(pt)
	var snap := Settings.snapshot()
	if not Settings.touch_controls_enabled():
		p.note("run with MOBILE=1 for the phone state; forcing touch.controls=on")
		Settings.set_value("touch", "controls", "on")
		Settings.apply_controls()
	var e := ElementDefs.Element.WATER
	GameState.new_game(e)
	AbilityRegistry.grant_starters(e)
	GameState.level = 4
	GameState.skill_points = 1
	GameState.ability_practice["ice_shards"] = 9
	GameState.unlock_ability(&"ice_trap", false)
	SkillTreeModel.unequip(2)
	Quests.start(&"wt_born_of_the_tide")
	await p.load_scene("res://scenes/dev/combat_arena.tscn", {"element": e})
	await p.wait(1.5)
	# the arena flattens WorldData for its courtyard; the map needs the world's records
	WorldData.use_flat_world(false)
	var book := (load("res://scenes/ui/journey_book.tscn") as PackedScene).instantiate() as JourneyBook
	p.scene().add_child(book)
	await p.frames(3)
	# first tap on the open ground puts the UI in touch mode
	var vp := p.get_viewport()
	var vis := vp.get_visible_rect().size
	t.down(0, vp.get_screen_transform() * (vis * Vector2(0.7, 0.45)))
	await p.frames(2)
	t.up(0)
	await p.wait(0.8)
	var hud := p.get_tree().get_first_node_in_group(&"hud") as Hud
	if hud == null:
		for n in p.scene().get_children():
			if n is Hud:
				hud = n
	var ov: TouchOverlay = hud.touch if hud else null
	p.check(ov != null and ov.active, "touch overlay active")
	if ov == null:
		return
	await p.wait(0.5)
	p.check(ov.buttons[&"map"].visible and ov.buttons[&"journal"].visible, "the top bar offers Map and Journal (the book exists)")
	await p.screenshot("mobile_hud_topbar")
	await t.tap_button(ov, &"map")
	await p.wait(0.8)
	p.check(book.is_open and book.page == &"map", "tapping Map opens the map")
	_check_touch_sizes(book)
	var page := book.current_page() as WorldMapPage
	var c := page.canvas
	await p.wait(0.6)
	# one-finger drag pans
	var mid := t.to_screen(c, c.size * 0.5)
	var before := c.center
	await t.drag(1, mid, mid + Vector2(260, 80), 8)
	await p.wait(0.3)
	p.check(c.center.distance_to(before) > 0.005, "a finger drag pans the map")
	# pinch zooms
	var z0 := c.zoom
	t.down(1, mid - Vector2(60, 0))
	t.down(2, mid + Vector2(60, 0))
	await p.frames(2)
	for i in 8:
		t.move(1, mid - Vector2(60 + 18 * (i + 1), 0))
		t.move(2, mid + Vector2(60 + 18 * (i + 1), 0))
		await p.frames(1)
	t.up(1)
	t.up(2)
	await p.wait(0.4)
	p.check(c.zoom > z0 * 1.3, "a pinch zooms in (%.2f -> %.2f)" % [z0, c.zoom])
	# tap a known city: the home city marker
	c.focus_on(MapModel.place_by_id(&"northern_water_tribe")["position"], 2.0, true)
	await p.wait(0.4)
	var city_at := t.to_screen(c, c.world_to_local(MapModel.place_by_id(&"northern_water_tribe")["position"]))
	t.down(1, city_at)
	await p.frames(2)
	t.up(1)
	await p.wait(0.4)
	p.check(page.card_place.get("id", &"") == &"northern_water_tribe", "a tap on the city shows its card")
	await p.screenshot("mobile_map_card")
	# skills tab by tap
	var tab_skills := book.root.find_child("Tab_skills", true, false) as Button
	await _tap(tab_skills)
	await p.wait(0.8)
	p.check(book.page == &"skills", "tapping the SKILLS tab")
	var sp := book.current_page() as SkillTreePage
	_check_touch_sizes(book)
	await p.screenshot("mobile_skills")
	await _tap(sp.canvas.nodes[&"ice_trap"])
	await p.wait(0.3)
	p.check(sp.armed == &"ice_trap", "tap a learned technique arms it")
	await p.screenshot("mobile_skills_armed")
	await _tap(sp.slots[2])
	await p.wait(0.4)
	p.check(SkillTreeModel.equipped(2) == &"ice_trap", "tap a slot places it (tap-to-select, tap-slot)")
	await p.screenshot("mobile_skills_equipped")
	# journal tab
	await _tap(book.root.find_child("Tab_journal", true, false) as Button)
	await p.wait(0.6)
	p.check(book.page == &"journal", "tapping the JOURNAL tab")
	_check_touch_sizes(book)
	await p.screenshot("mobile_journal")
	# inventory: tap a tile, it shows in the detail panel
	GameState.add_item(&"healing_salve", 2)
	GameState.add_item(&"sea_prunes", 3)
	await _tap(book.root.find_child("Tab_inventory", true, false) as Button)
	await p.wait(0.6)
	p.check(book.page == &"inventory", "tapping the INVENTORY tab")
	var ip := book.current_page() as InventoryPage
	var tile := book.root.find_child("Item_sea_prunes", true, false) as Control
	var pl := p.player() as PlayerCharacter
	if pl:
		pl.health.health = pl.health.max_health * 0.5
	if tile:
		await _tap(tile)
		await p.wait(0.3)
	p.check(ip != null and ip.selected == &"sea_prunes" and GameState.item_count(&"sea_prunes") == 3, "a first tap selects an item tile (does not use it)")
	if tile:
		await _tap(tile)
		await p.wait(0.3)
	p.check(GameState.item_count(&"sea_prunes") == 2, "a second tap on the selected tile uses it")
	_check_touch_sizes(book)
	await p.screenshot("mobile_inventory")
	# character
	await _tap(book.root.find_child("Tab_character", true, false) as Button)
	await p.wait(1.2)
	p.check(book.page == &"character", "tapping the CHARACTER tab")
	await p.screenshot("mobile_character")
	# tap outside the sheet (the dimmed margin) closes
	var bd := book.root.get_node("Backdrop") as Control
	t.down(1, t.to_screen(bd, Vector2(8, bd.size.y * 0.5)))
	await p.frames(2)
	t.up(1)
	await p.wait(0.4)
	p.check(not book.is_open and not p.get_tree().paused, "a tap outside the sheet closes the book")
	Settings.restore_snapshot(snap)
	Settings.apply()


func _tap(c: Control) -> void:
	var at := t.to_screen(c, c.size * 0.5)
	t.down(1, at)
	await p.frames(2)
	t.up(1)
	await p.frames(3)


func _check_touch_sizes(book: JourneyBook) -> void:
	var small: Array[String] = []
	for b in book.root.find_children("*", "BaseButton", true, false):
		var bb := b as BaseButton
		if not bb.is_visible_in_tree() or bb is SkillNode or bb.get_parent() is GridContainer:
			continue
		if bb.size.y < UiTheme.TOUCH_TARGET - 0.5:
			small.append("%s (%d)" % [bb.name, int(bb.size.y)])
	p.check(small.is_empty(), "every tappable control on the %s page is >= 88 px tall %s" % [book.page, str(small)])
