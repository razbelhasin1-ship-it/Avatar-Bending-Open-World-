extends RefCounted
## World map through the real world scene: open with the open_map action (M / View / the
## touch top-bar button send it), the explored mask around the home city, discovered vs
## undiscovered places, the place card, zoom and pan by mouse wheel / drag events and by the
## controller reticle (move actions), the combat guard, and a real fast travel with the
## confirmation answered by keyboard (Enter) through TravelSystem.travel_to.
## Env: ELEMENT=water|earth|fire|air (default water), QUICK=1 (no travel).

var p: Playtest
var w: WorldScene


func run(pt: Playtest) -> void:
	p = pt
	var e := ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	if not ElementDefs.is_valid(e):
		e = ElementDefs.Element.WATER
	GameState.new_game(e)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": e, "skip_intro": true, "time_of_day": 11.0}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 300.0)
	p.check(ok, "world ready")
	if not ok:
		return
	var book := p.get_tree().get_first_node_in_group(&"journey_book") as JourneyBook
	p.check(book != null, "the progression hook installed the Journey Book")
	if book == null:
		return
	p.check(p.get_tree().get_first_node_in_group(&"map_screen") != null, "map_screen group present (touch top bar shows Map)")
	# a few discoveries in the home region so the map has known + unknown places
	var home := MapModel.place_by_id(MapModel.home_city_id())
	var near := WorldData.get_pois_in_radius(home["position"], 2400.0)
	var travel_to: Dictionary = {}
	for i in mini(5, near.size()):
		GameState.discover_poi(StringName(near[i]["id"]))
		var pl := MapModel.place_by_id(StringName(near[i]["id"]))
		if travel_to.is_empty() and MapModel.is_travel_point(pl) and w.player.global_position.distance_to(pl["position"]) > 200.0:
			travel_to = pl
	await p.wait_game(1.5)
	await p.tap(&"open_map")
	await p.wait(0.6)
	p.check(book.is_open and book.page == &"map", "open_map opens the book on the map")
	var page := book.current_page() as WorldMapPage
	await p.wait(1.0)
	await p.screenshot("map_%s_home" % ElementDefs.id_of(e))
	# zoom out with the wheel at the centre
	var c := page.canvas
	for i in 6:
		_wheel(c, false)
		await p.frames(2)
	await p.wait(0.8)
	p.check(c.zoom < 1.3, "wheel zooms out (zoom %.2f)" % c.zoom)
	await p.screenshot("map_%s_world" % ElementDefs.id_of(e))
	# controller-style reticle: pan with the move actions, then look at a discovered place
	if not travel_to.is_empty():
		c.focus_on(travel_to["position"], 3.0)
		await p.wait(0.8)
		p.hold(&"move_right", 0.25)
		await p.wait(0.15)
		p.release(&"move_right")
		await p.wait(0.4)
		c.focus_on(travel_to["position"], 3.0)
		await p.wait(0.8)
		p.check(c.cursor_mode, "stick / keys put the map in reticle mode")
		p.check(c.hover.get("id", &"") == travel_to["id"], "the reticle snaps onto %s" % travel_to["name"])
		await p.screenshot("map_%s_reticle_card" % ElementDefs.id_of(e))
		# combat guard
		MapModel.combat_override = 1
		p.check(MapModel.travel_block_reason(travel_to) != "", "fast travel refused in combat")
		MapModel.combat_override = -1
		p.check(MapModel.travel_block_reason(travel_to) == "", "fast travel allowed out of combat: '%s'" % MapModel.travel_block_reason(travel_to))
		if OS.get_environment("QUICK") != "1":
			await p.tap(&"ui_accept")
			await p.wait(0.5)
			await p.screenshot("map_%s_travel_confirm" % ElementDefs.id_of(e))
			await _key(KEY_ENTER)
			var arrived := await p.wait_until(func() -> bool: return not w.travel.busy and w.player.global_position.distance_to(travel_to["position"]) < 150.0, 120.0)
			p.check(arrived, "fast travel brought the player to %s" % travel_to["name"])
			p.check(not book.is_open and not p.get_tree().paused, "book closed and game running after travel")
			await p.wait_game(1.5)
			await p.screenshot("map_%s_arrived" % ElementDefs.id_of(e))
	if book.is_open:
		await _key(KEY_ESCAPE)
		await p.wait(0.3)
	p.check(not book.is_open, "Esc closes the map")


func _wheel(c: Control, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = c.get_global_rect().get_center()
	ev.global_position = ev.position
	ev.factor = 1.0
	c.get_viewport().push_input(ev, true)


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
