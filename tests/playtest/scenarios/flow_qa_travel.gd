extends RefCounted
## flow_qa: the in-game flows a player uses between fights, in the REAL world scene with input
## through the InputMap (docs/qa/flow_qa.md):
##   1 Journey Book: K (skills) -> J (journal) -> M (map) -> Esc; the game pauses and resumes,
##     movement answers afterwards
##   2 pause -> SETTINGS -> Graphics preset Low: the WORLD's sun shadows, environment glow, terrain
##     clipmap and vegetation follow; CANCEL restores them -> RESUME
##   3 a ferry trip from the home port (dock prompt, number key, sail, destination quay)
##   4 fast travel back home from the map (place card, Enter, TRAVEL)
##   5 call the companion, mount it (F), take off (jump), fly, climb, descend, land, dismount
## ELEMENT=fire (default; the dragon) or air (the sky bison) - flying mounts only. PART=fly runs
## only step 5.

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var el := "fire"
var e := ElementDefs.Element.FIRE
var toasts: Array[String] = []

const HOME_PORT := {ElementDefs.Element.FIRE: &"port_crimson_harbor", ElementDefs.Element.AIR: &"port_foothill_landing"}


func run(pt: Playtest) -> void:
	p = pt
	if OS.get_environment("ELEMENT") != "":
		e = ElementDefs.from_id(StringName(OS.get_environment("ELEMENT")))
	if not HOME_PORT.has(e):
		e = ElementDefs.Element.FIRE
	el = String(ElementDefs.id_of(e))
	if Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.apply()
	GameState.new_game(e)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": e, "skip_intro": true, "time_of_day": 10.5}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 400.0)
	if not p.check(ok, "%s world ready %s" % [el, str(w.load_report)]):
		return
	pl = w.player
	pl.camera_rig.require_capture = false
	Events.notify.connect(func(t: String, _k: StringName) -> void: toasts.append(t))
	await p.wait_game(1.5)
	if OS.get_environment("PART") != "fly":      # PART=fly: only the mount / flight (quick reruns)
		await _journey_book()
		await _pause_settings()
		await _ferry()
		await _map_fast_travel()
	await _fly()


func _ui(action: StringName) -> void:
	await p.tap(action, 0.05)
	await p.frames(2)


func _focus_owner() -> Control:
	return p.get_tree().root.get_viewport().gui_get_focus_owner()


func _ticks_until(cond: Callable, t: float) -> bool:
	for i in int(t * Engine.physics_ticks_per_second):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _walks() -> float:
	var at := pl.global_position
	Input.action_press(&"move_forward")
	await p.wait_game(0.8)
	Input.action_release(&"move_forward")
	await p.wait_game(0.2)
	return Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length()


## A walkable, flat point between r0 and r1 m from `near`, outside settlements, on land.
func _find_open(near: Vector3, r0: float, r1: float) -> Vector3:
	for r in range(int(r0), int(r1), 10):
		var n := 12 + r / 12
		for k in n:
			var a := TAU * float(k) / n + float(r) * 0.37
			var q := near + Vector3(cos(a), 0, sin(a)) * float(r)
			var h := WorldData.get_height(q.x, q.z)
			if h < WorldData.SEA_LEVEL + 1.0:
				continue
			var g := Vector3(q.x, h, q.z)
			if Settlements.settlement_at(g) != &"" or WorldData.get_normal(q.x, q.z).y < 0.96:
				continue
			if WorldData.get_water_height(q.x, q.z) > -INF:      # lakes / canals / sea (a lake floor is "flat" too)
				continue
			var flat := true
			for j in 8:
				var b := TAU * float(j) / 8.0
				for rr: float in [8.0, 18.0]:
					var o := g + Vector3(cos(b), 0, sin(b)) * rr
					if absf(WorldData.get_height(o.x, o.z) - h) > 1.6 or WorldData.get_water_height(o.x, o.z) > -INF:
						flat = false
			if flat:
				return g
	return Vector3.INF


func _book() -> JourneyBook:
	return p.get_tree().get_first_node_in_group(&"journey_book") as JourneyBook


# --- 1 Journey Book --------------------------------------------------------------------------------------

func _journey_book() -> void:
	var book := _book()
	if not p.check(book != null, "journey book present in the world"):
		return
	await _ui(&"open_skills")
	await p.wait_until(func() -> bool: return book.is_open, 5.0)
	p.check(book.is_open and book.page == &"skills" and p.get_tree().paused, "K opens the skills page and pauses (page %s)" % book.page)
	await p.wait(0.4)
	await p.screenshot("travel_01_book_skills")
	await _ui(&"open_journal")
	p.check(book.is_open and book.page == &"journal", "J switches to the journal (%s)" % book.page)
	await p.wait(0.3)
	await p.screenshot("travel_02_book_journal")
	await _ui(&"open_map")
	p.check(book.is_open and book.page == &"map", "M switches to the map (%s)" % book.page)
	await p.wait(0.5)
	await p.screenshot("travel_03_book_map")
	await _ui(&"ui_cancel")
	await p.wait_until(func() -> bool: return not book.is_open, 3.0)
	p.check(not book.is_open and not p.get_tree().paused, "Esc closes the book and resumes")
	var d := await _walks()
	p.check(d > 1.0, "movement answers after the book (%.1f m)" % d)


# --- 2 pause -> settings -> back: the world follows the graphics options ---------------------------------

func _world_render_state() -> Dictionary:
	var sky := w.renderer.sky
	var env: Environment = sky.environment if sky else null
	var sun: DirectionalLight3D = sky.sun if sky else null
	return {"sun_shadow": sun.shadow_enabled if sun else null, "shadow_dist": sun.directional_shadow_max_distance if sun else 0.0,
			"glow": env.glow_enabled if env else null, "terrain": w.renderer._config_key,
			"veg": Settings.vegetation_density(), "msaa": w.get_viewport().msaa_3d, "lod": w.get_viewport().mesh_lod_threshold}


func _pause_settings() -> void:
	await _ui(&"pause")
	await p.wait_until(func() -> bool: return w.pause_menu.is_open, 5.0)
	if not p.check(w.pause_menu.is_open, "pause menu open"):
		return
	await _ui(&"ui_down")
	await _ui(&"ui_down")
	p.check(_focus_owner() == w.pause_menu.options[2], "SETTINGS focused")
	await _ui(&"ui_accept")
	await p.wait_until(func() -> bool: return w.pause_menu.settings_menu != null and w.pause_menu.settings_menu.is_open, 5.0)
	var sm := w.pause_menu.settings_menu
	if not p.check(sm != null and sm.is_open, "settings open over the pause menu"):
		return
	sm.persist = false
	sm.show_tab("graphics")
	await p.wait(0.3)
	var before := _world_render_state()
	var was_low := String(Settings.get_value("graphics", "preset")) == "low"
	sm.set_option("graphics", "preset", "medium" if was_low else "low", "preset")
	await p.frames(3)
	var low := _world_render_state()
	p.note("world render state %s -> %s" % [str(before), str(low)])
	p.check(low["shadow_dist"] != before["shadow_dist"] and low["glow"] != before["glow"] and low["terrain"] != before["terrain"] and low["veg"] != before["veg"],
			"the world's sun shadows, glow, terrain clipmap and vegetation follow the preset")
	await p.screenshot("travel_04_settings_low")
	await _ui(&"ui_cancel")      # Back with changes -> "Keep the changes?" dialog
	await p.wait(0.3)
	if p.check(sm.confirm != null and sm.confirm.is_open, "Back with unsaved changes asks to keep them"):
		await p.screenshot("travel_05_settings_confirm")
		await _ui(&"ui_right")     # APPLY -> DISCARD
		var f := _focus_owner()
		p.check(f is Button and (f as Button).text == "DISCARD", "DISCARD focused (%s)" % (f as Button).text if f is Button else str(f))
		await _ui(&"ui_accept")
		await p.wait(0.3)
	if not p.check(not sm.is_open, "DISCARD closes the settings"):
		sm.cancel()
	await p.wait(0.3)
	var after := _world_render_state()
	p.check(str(after) == str(before), "discarding restores the world (%s)" % str(after))
	p.check(w.pause_menu.is_open and _focus_owner() == w.pause_menu.options[2], "back on the pause menu, SETTINGS focused")
	await _ui(&"ui_up")
	await _ui(&"ui_up")
	await _ui(&"ui_accept")       # RESUME
	await p.wait_until(func() -> bool: return not w.pause_menu.is_open, 3.0)
	p.check(not p.get_tree().paused, "RESUME unpauses")
	var d := await _walks()
	p.check(d > 1.0, "movement answers after pause -> settings -> resume (%.1f m)" % d)


# --- 3 ferry -----------------------------------------------------------------------------------------------

func _ferry() -> void:
	var from: StringName = HOME_PORT[e]
	var port := TravelSystem.port_by_id(from)
	var routes := TravelSystem.routes_from(from)
	if not p.check(not port.is_empty() and not routes.is_empty(), "home port %s has ferry lines" % from):
		return
	var dock: FerryDock = w.travel.docks.get(from)
	if not p.check(dock != null, "dock built at %s" % from):
		return
	var post := dock.interactable.global_position
	var quay: Vector3 = port["quay"]
	var stand := quay + (post - quay) * 0.2
	var ok: bool = await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-(post - stand).x, -(post - stand).z)), stand + Vector3.UP * 0.2), {"text": "Walking to the harbour", "autosave": false})
	p.check(ok, "at the %s ferry landing" % from)
	await p.wait_game(1.0)
	ok = await p.wait_until(func() -> bool: return pl.interaction.current == dock.interactable, 8.0)
	p.check(ok and w.hud.prompt_panel.visible, "ferry prompt shown")
	await p.screenshot("travel_06_ferry_prompt")
	await p.tap(&"interact", 0.08)
	ok = await p.wait_until(func() -> bool: return w.is_dialogue_open() and w.dialogue.choices.size() > 0, 10.0)
	if not p.check(ok, "ferry master offers destinations"):
		return
	var to: StringName = routes[0]["to"]
	var key := InputEventKey.new()
	key.physical_keycode = KEY_1
	key.keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await p.frames(2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	ok = await p.wait_until(func() -> bool: return w.travel.phase == &"depart" and w.fader.amount() < 0.3, 30.0)
	p.check(ok, "the ferry casts off")
	await p.wait(0.5)
	await p.screenshot("travel_07_ferry_sailing")
	ok = await p.wait_until(func() -> bool: return not w.travel.busy, 120.0)
	p.check(ok, "trip finished")
	await p.wait_game(0.6)
	var dest := TravelSystem.quay_transform(TravelSystem.port_by_id(to))
	p.check(pl.global_position.distance_to(dest.origin) < 3.0 and pl.get_state() == PlayerCharacter.State.LOCOMOTION, "on the %s quay in control (%.1f m, %s)" % [to, pl.global_position.distance_to(dest.origin), pl.get_state_name()])
	await p.screenshot("travel_08_ferry_arrived")


# --- 4 map fast travel home ---------------------------------------------------------------------------------

func _map_fast_travel() -> void:
	var book := _book()
	var home := MapModel.home_city_id()
	var place := MapModel.place_by_id(home)
	if not p.check(not place.is_empty(), "home city %s on the map" % home):
		return
	p.check(MapModel.travel_block_reason(place) == "", "home city is a fast-travel point (%s)" % MapModel.travel_block_reason(place))
	await _ui(&"open_map")
	await p.wait_until(func() -> bool: return book.is_open and book.page == &"map", 5.0)
	# pad / keys: the move actions put the map in reticle mode; the reticle rests on the city
	var c := (book.get_page(&"map") as WorldMapPage).canvas
	c.focus_on(place["position"], 3.0)
	await p.wait(0.6)
	p.hold(&"move_right", 0.25)
	await p.wait(0.15)
	p.release(&"move_right")
	await p.wait(0.3)
	c.focus_on(place["position"], 3.0)
	await p.wait(0.6)
	p.check(c.cursor_mode and c.hover.get("id", &"") == home, "the reticle rests on %s" % place["name"])
	await p.screenshot("travel_09_map_card")
	await _ui(&"ui_accept")
	var asked := await p.wait_until(func() -> bool: return not book.root.find_children("*", "ConfirmDialog", true, false).is_empty(), 5.0)
	p.check(asked, "fast travel asks for confirmation")
	await p.wait(0.3)
	await p.screenshot("travel_10_map_confirm")
	await _ui(&"ui_accept")       # TRAVEL (first choice, focused)
	var ok := await p.wait_until(func() -> bool: return w.travel.busy, 5.0)
	p.check(ok and not book.is_open, "the book closes and the journey starts")
	ok = await p.wait_until(func() -> bool: return not w.travel.busy, 120.0)
	await p.wait_game(0.6)
	var target: Vector3 = MapModel.travel_transform(place).origin
	p.check(ok and pl.global_position.distance_to(target) < 6.0, "arrived home by fast travel (%.1f m from the point)" % pl.global_position.distance_to(target))
	p.check(toasts.any(func(t: String) -> bool: return t.begins_with("Arrived at")), "arrival toast")
	await p.screenshot("travel_11_home_again")


# --- 5 mount and fly ----------------------------------------------------------------------------------------

func _fly() -> void:
	# open ground outside the city for a clean landing and takeoff (harness trip)
	var spot := _find_open(pl.global_position, 120.0, 1500.0)
	if spot.is_finite():
		await w.travel.travel_to(Transform3D(Basis(), spot + Vector3.UP * 0.1), {"fade": 0.1, "autosave": false})
		await p.wait_game(2.0)
	var c := pl.get_companion() as Companion
	if not p.check(c != null and c.prof.can_fly, "%s flying companion present" % el):
		return
	await p.tap(&"companion_call")
	# a called flyer arrives by air and lands beside the player
	var landed := await p.wait_until(func() -> bool: return c.global_position.distance_to(pl.global_position) < 16.0 and not c.is_airborne() and c.mode != Companion.Mode.CALLED, 45.0)
	p.check(landed, "G calls the %s: it lands beside the player (%s, %.1f m)" % [c.species, c.get_mode_name(), c.global_position.distance_to(pl.global_position)])
	var side := Vector3(-CompanionNav.dir_of(c.motor.yaw).z, 0.0, CompanionNav.dir_of(c.motor.yaw).x)
	var stand := c.global_position - side * (c.prof.radius() + 1.3)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(c.global_position - stand))), stand))
	await p.wait_game(0.5)
	p.check(c.can_mount(pl), "%s in mount range (prompt)" % el)
	await p.tap(&"mount")
	var ok := await _ticks_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN and pl.get_state() == PlayerCharacter.State.MOUNTED, 5.0)
	p.check(ok, "F mounts the %s (%s)" % [c.species, c.get_mode_name()])
	await p.tap(&"jump")
	ok = await _ticks_until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 8.0)
	p.check(ok, "jump takes off (%s)" % c.flight.phase_name())
	var y0 := c.global_position.y
	var take_off := c.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	await p.wait_game(1.2)
	# A short hop forward, then climb and come back down over the open ground the flight left
	# from (forward from the Air Temple's terraces is the cloud sea: nowhere to land for 300 m).
	Input.action_release(&"move_forward")
	await p.wait_game(1.3)
	Input.action_release(&"jump")
	await p.wait_game(1.0)
	await p.screenshot("travel_12_flying")
	var climbed := c.global_position.y - y0
	p.check(climbed > 3.0, "climbs while holding jump (+%.1f m)" % climbed)
	p.note("%s flight: %.0f m from the take-off point, %.0f m above the ground" % [c.species,
			Vector2(c.global_position.x - take_off.x, c.global_position.z - take_off.z).length(),
			c.global_position.y - WorldData.get_height(c.global_position.x, c.global_position.z)])
	# Descend and steer back over the flat take-off ground (a flyer refuses to land on a steep
	# slope: "Can't land here"); the camera yaw steers like on foot.
	Input.action_press(&"descend")
	var t := 0.0
	while t < 40.0 and c.flight.phase == CompanionFlight.Phase.FLY:
		var to := Vector2(take_off.x - c.global_position.x, take_off.z - c.global_position.z)
		if to.length() > 6.0:
			# Turn like a rider: at most ~70 degrees off the current heading (input pointing
			# behind the flyer brakes instead of turning).
			var want := atan2(-to.x, -to.y)
			var turn := clampf(wrapf(want - c.flight.heading, -PI, PI), -1.2, 1.2)
			pl.camera_rig.set_yaw(c.flight.heading + turn)
			Input.action_press(&"move_forward")
		else:
			Input.action_release(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
	Input.action_release(&"move_forward")
	Input.action_release(&"descend")
	p.note("%s descent: %.1f s, %.0f m from the take-off point" % [c.species, t,
			Vector2(c.global_position.x - take_off.x, c.global_position.z - take_off.z).length()])
	ok = await _ticks_until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.NONE and not c.is_flying(), 12.0)
	p.check(ok, "descend lands (%s)" % c.flight.phase_name())
	await p.wait_game(0.5)
	await p.tap(&"mount")
	ok = await _ticks_until(func() -> bool: return pl.get_state() == PlayerCharacter.State.LOCOMOTION, 6.0)
	p.check(ok, "F dismounts, back on foot (%s)" % pl.get_state_name())
	var d := await _walks()
	p.check(d > 1.0, "walks after the flight (%.1f m)" % d)
	await p.screenshot("travel_13_landed")
