extends TestCase
## Wave-4 end-to-end flow QA (flow_qa, docs/qa/flow_qa.md): regressions for the bugs found while
## playing the real scenes through the brief's testing checklist.

const WORLD := "res://scenes/world/world.tscn"
const TUTORIAL := "res://scenes/world/tutorial.tscn"

var _slots: Dictionary = {}


func before_each() -> void:
	WorldData.load_world()
	GameState.reset()
	_slots.clear()
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			_slots[i] = FileAccess.get_file_as_string(SaveSystem.slot_path(i))
			SaveSystem.delete_save(i)


func after_each() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		if _slots.has(i):
			var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.WRITE)
			f.store_string(String(_slots[i]))
			f.close()
	_release_all()
	GameState.reset()
	Engine.time_scale = 1.0
	get_tree().paused = false


func _release_all() -> void:
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _load(path: String, opts: Dictionary, timeout: float = 90.0) -> PlayableScene:
	var w := (load(path) as PackedScene).instantiate() as PlayableScene
	w.options = opts
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.is_ready and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await get_tree().process_frame
	return w


func _free(w: Node) -> void:
	if is_instance_valid(w):
		w.queue_free()
	await frames(3)


func _wait_until(cond: Callable, timeout: float = 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


## Physics ticks until `cond` (game time, independent of the frame rate).
func _ticks_until(cond: Callable, seconds_max: float) -> bool:
	for i in int(seconds_max * Engine.physics_ticks_per_second):
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _hold_for(action: StringName, t: float) -> void:
	Input.action_press(action)
	await physics_frames(maxi(1, int(t * Engine.physics_ticks_per_second)))
	Input.action_release(action)
	await physics_frames(1)


## Skips lessons (as holding interact would) until `id` is the current one.
func _skip_to(d: TutorialDirector, id: StringName) -> bool:
	var guard := 0
	while d.running and d.step_id() != id and guard < 30:
		guard += 1
		if not d._advancing:
			d.complete_step(true)
		await _wait_until(func() -> bool: return not d._advancing, 5.0)
	return d.running and d.step_id() == id


func _place(t: TutorialScene, local: Vector3, facing: Vector3 = Vector3.FORWARD) -> void:
	_release_all()
	var x := t.ground.local_xform(local, facing)
	t.player.teleport(Transform3D(x.basis, x.origin + Vector3.UP * 0.05))
	await physics_frames(3)
	t.player.camera_rig.snap_behind(t.player)
	await physics_frames(12)


# --- 14: the training grounds are playable for every element ------------------------------------------

## The heavy and charged-heavy lessons count the element's real heavy strike: Earth Boulder is
## not a ChargeAbility, so Earth's lessons 'heavy' and 'charge' never completed by play.
## Sprint is measured above run speed for every element (Earth: slowest acceleration).
## The light chain lands every strike on the dummy: Air's hook-kick gust (low and wide) died
## on the floor half a metre out, so an airbender could never chain 3 strikes into a dummy.
func test_tutorial_light_heavy_charge_sprint_lessons_complete_for_every_element() -> void:
	for e in ElementDefs.ALL:
		var el := String(ElementDefs.id_of(e))
		GameState.new_game(e, true)
		var t := await _load(TUTORIAL, {"element": e, "no_content": true}) as TutorialScene
		if not expect(t.is_ready, "%s tutorial ready" % el):
			await _free(t)
			continue
		await _wait_until(func() -> bool: return t.director != null and t.director.running, 20.0)
		var d := t.director
		var pl := t.player
		# sprint: hold sprint + a direction, in the open lane right of the start
		expect(await _skip_to(d, &"sprint"), "%s reached the sprint lesson" % el)
		await _place(t, Vector3(-9.0, 0, 6.0), Vector3.RIGHT)
		Input.action_press(&"sprint")
		Input.action_press(&"move_forward")
		var ok := await _ticks_until(func() -> bool: return d.completed.has(&"sprint"), 3.0)
		_release_all()
		expect(ok, "%s sprint lesson completes by sprinting (progress %.2f s, speed %.1f)" % [el, d.progress, Vector2(pl.velocity.x, pl.velocity.z).length()])
		# light: one chain, each press as the previous strike lands (the dummy 2.6 m ahead)
		expect(await _skip_to(d, &"light"), "%s reached the light lesson" % el)
		await _place(t, Vector3(0, 0, 0.2))
		var n := int(d.target())
		for k in n:
			await _hold_for(&"attack_light", 0.05)
			await _ticks_until(func() -> bool:
				var c := pl.controller.current as ComboAbility
				return c == null or (c.struck and c.step >= k and (c.can_chain() or c.is_last_step())), 1.5)
		ok = await _ticks_until(func() -> bool: return d.completed.has(&"light"), 1.5)
		expect(ok, "%s light lesson: %d strikes of one chain land on the dummy (%.0f / %d)" % [el, n, d.progress, n])
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
		# heavy: a tapped heavy strike
		expect(await _skip_to(d, &"heavy"), "%s reached the heavy lesson" % el)
		await _place(t, Vector3(0, 0, 1.0))
		pl.resources.set_chi(PlayerResources.CHI_MAX)
		await _hold_for(&"attack_heavy", 0.06)
		ok = await _ticks_until(func() -> bool: return d.completed.has(&"heavy"), 4.0)
		expect(ok, "%s heavy lesson completes from a tapped heavy (%s)" % [el, pl.controller.get_slot_def(&"heavy").id])
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		# charge: hold the heavy past 70 % and release
		expect(await _skip_to(d, &"charge"), "%s reached the charge lesson" % el)
		await _place(t, Vector3(0, 0, 1.5))
		pl.resources.set_chi(PlayerResources.CHI_MAX)
		await _hold_for(&"attack_heavy", 2.2)
		ok = await _ticks_until(func() -> bool: return d.completed.has(&"charge"), 4.0)
		expect(ok, "%s charge lesson completes from a charged heavy" % el)
		await _ticks_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		await _free(t)
		GameState.reset()


## The release contract every heavy follows (read by the tutorial): tap vs charged, nothing
## before the release.
func test_heavy_strike_report_for_charge_abilities_and_earth_boulder() -> void:
	expect(TutorialDirector.heavy_strike_of(null).is_empty(), "null")
	for e in ElementDefs.ALL:
		var def := AbilityRegistry.core_kit(e).get(&"heavy") as AbilityDef
		if not expect(def != null, "%d has a heavy" % e):
			continue
		var heavy_id := def.id
		var a := def.instantiate()
		expect(TutorialDirector.heavy_strike_of(a).is_empty(), "%s: no strike before the release" % heavy_id)
		a.set(&"released", true)
		a.set(&"tapped", false)
		a.set(&"charge", 0.9)
		var r := TutorialDirector.heavy_strike_of(a)
		expect(not r.is_empty() and not bool(r["tapped"]) and float(r["charge"]) > 0.8, "%s: charged release reported %s" % [heavy_id, str(r)])


# --- 16: menu <-> game transitions keep input working ---------------------------------------------------------

func _press_ui(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await frames(1)


## Runs `body` with the Router free to change scenes (the test runner is kept aside as the
## current scene), then frees whatever scene the Router left and restores the runner.
func _with_router(body: Callable) -> void:
	var prev := get_tree().current_scene
	var holder := Node.new()
	holder.name = "FlowQaHolder"
	get_tree().root.add_child(holder)
	get_tree().current_scene = holder
	await body.call()
	await _wait_until(func() -> bool: return not Router.is_transitioning, 30.0)
	var cur := get_tree().current_scene
	get_tree().current_scene = prev
	if is_instance_valid(cur) and cur != prev:
		cur.queue_free()
	if is_instance_valid(holder):
		holder.queue_free()
	get_tree().paused = false
	await frames(3)


## Back / Esc pressed while the element select is still fading in (keyboard and pad input are
## not blocked by the fade, only the mouse is): the request used to be dropped by the Router
## while the screen's own `_busy` flag stayed set, so the screen ignored every later input.
func test_router_request_during_fade_in_is_not_lost() -> void:
	await _with_router(func() -> void:
		Router.goto(Router.ELEMENT_SELECT, {"tutorial": false}, 0.4)
		var ok := await _wait_until(func() -> bool: return get_tree().current_scene is ElementSelect, 30.0)
		expect(ok and Router.is_transitioning, "element select swapped in and still fading in (%s)" % Router.is_transitioning)
		await _press_ui(&"ui_cancel")
		ok = await _wait_until(func() -> bool: return get_tree().current_scene is MainMenu and not Router.is_transitioning, 30.0)
		expect(ok, "Back during the fade-in reaches the main menu (scene %s)" % get_tree().current_scene)
		# A request issued by the outgoing scene before the swap is still ignored.
		Router.goto(Router.ELEMENT_SELECT, {}, 0.3)
		Router.goto(Router.TUTORIAL, {}, 0.3)
		ok = await _wait_until(func() -> bool: return get_tree().current_scene is ElementSelect and not Router.is_transitioning, 30.0)
		await frames(10)
		expect(ok and get_tree().current_scene is ElementSelect, "a second request during the fade-out is dropped (scene %s)" % get_tree().current_scene))


## The training grounds are reachable with a journey on disk (main menu -> TUTORIAL). Their
## ENTER THE WORLD started a new journey whose arrival autosave replaced the saved one without a
## word; now it asks first (KEEP JOURNEY focused), like the main menu's NEW JOURNEY.
func test_tutorial_enter_world_asks_before_replacing_a_saved_journey() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	GameState.level = 7
	expect(SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT), "a journey on disk")
	GameState.new_game(ElementDefs.Element.FIRE, true)
	var screen := TutorialCompleteScreen.new()
	add_child(screen)
	screen.show_summary(ElementDefs.Element.FIRE, {"total": 14, "completed": [], "skipped": []})
	var entered := [0]
	screen.enter_world.connect(func() -> void: entered[0] += 1)
	screen.options[0].pressed.emit()
	await frames(2)
	expect(screen.confirm != null and screen.confirm.is_open, "ENTER THE WORLD asks first")
	if screen.confirm:
		expect(screen.confirm.buttons[&"keep"].has_focus(), "KEEP JOURNEY focused")
		expect(screen.confirm._text.text.contains("Earthbender · Level 7"), "names the saved journey: %s" % screen.confirm._text.text)
		screen.confirm.buttons[&"keep"].pressed.emit()
	await frames(2)
	expect(entered[0] == 0 and screen.confirm == null, "KEEP JOURNEY stays on the screen")
	expect(int(SaveSystem.get_save_info(SaveSystem.AUTOSAVE_SLOT).get("level", 0)) == 7, "the saved journey is untouched")
	screen.options[0].pressed.emit()
	await frames(2)
	if expect(screen.confirm != null, "asks again"):
		screen.confirm.buttons[&"new"].pressed.emit()
	await frames(2)
	expect(entered[0] == 1, "BEGIN ANEW enters the world")
	screen.queue_free()
	# No journey on disk: straight in.
	SaveSystem.delete_save(SaveSystem.AUTOSAVE_SLOT)
	var s2 := TutorialCompleteScreen.new()
	add_child(s2)
	s2.show_summary(ElementDefs.Element.FIRE, {"total": 14})
	var n := [0]
	s2.enter_world.connect(func() -> void: n[0] += 1)
	s2.options[0].pressed.emit()
	await frames(1)
	expect(n[0] == 1 and s2.confirm == null, "no question without a save")
	s2.queue_free()
	await frames(2)


# --- keyboard / pad answers to in-game confirmations ------------------------------------------------------------

func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


## A ConfirmDialog keeps keyboard / pad focus on its answers: on a real 960x540 window the
## nearest control right of APPLY was a settings toggle BEHIND the dim (focus escaped, Enter then
## flipped an invisible setting). Left / right cycle the answers, up / down / Tab stay in the row.
func test_confirm_dialog_traps_focus_on_its_answers() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	var behind := Button.new()
	holder.add_child(behind)
	var d := ConfirmDialog.new()
	holder.add_child(d)
	d.ask("UNSAVED CHANGES", "Keep the changes you made?", [[&"apply", "APPLY"], [&"discard", "DISCARD"], [&"cancel", "KEEP EDITING"]])
	await frames(2)
	var a: Button = d.buttons[&"apply"]
	var b: Button = d.buttons[&"discard"]
	var c: Button = d.buttons[&"cancel"]
	expect(a.has_focus(), "first answer focused")
	expect(a.get_node_or_null(a.focus_neighbor_right) == b and b.get_node_or_null(b.focus_neighbor_right) == c and c.get_node_or_null(c.focus_neighbor_right) == a, "right cycles the answers")
	expect(a.get_node_or_null(a.focus_neighbor_left) == c, "left wraps")
	expect(a.get_node_or_null(a.focus_neighbor_top) == a and a.get_node_or_null(a.focus_neighbor_bottom) == a, "up / down stay")
	expect(a.get_node_or_null(a.focus_next) == b and a.get_node_or_null(a.focus_previous) == c, "Tab / Shift+Tab stay in the row")
	# asked again with other answers: the neighbours follow the new row
	d.ask("FAST TRAVEL", "Travel?", [[&"go", "TRAVEL"], [&"stay", "STAY"]])
	await frames(2)
	var go: Button = d.buttons[&"go"]
	expect(go.get_node_or_null(go.focus_neighbor_right) == d.buttons[&"stay"], "rebuilt row keeps the trap")
	holder.queue_free()
	await frames(1)


## A wide, growing gust skims the floor: bodies meet its full radius, terrain only its core
## (`world_radius`). Air Combo's hook-kick gust (0.75 m growing to 3.15 m, launched 0.5 m
## above the floor) used to stop on the ground after half a metre.
func test_wide_gust_skims_the_floor_and_reaches_its_target() -> void:
	var ground := PlayerSim.ground(self)
	var pl := PlayerSim.player(self, ElementDefs.Element.AIR, Vector3.ZERO)
	var d := TrainingDummy.new()
	d.max_health = 5000.0
	add_child(d)
	d.global_position = Vector3(0, 0, -4.5)
	await physics_frames(3)
	var travel := 6.5 / 32.0
	var g := BendingProjectile.launch(pl.controller.ctx, Vector3(0, 0.48, -0.6), Vector3.FORWARD, 32.0, {"damage": 8.0},
			{"radius": 0.75, "radius_growth": 2.4 / travel, "max_radius": 3.15, "range": 6.5, "pierce": true, "world_radius": 0.25})
	var f := 0
	while g.alive and f < 90:
		await physics_frames(1)
		f += 1
	expect(g.traveled > 6.0, "the gust flew its range over the floor (%.2f m)" % g.traveled)
	expect(d.hits_taken == 1, "and hit the dummy 3.9 m out (%d hits)" % d.hits_taken)
	# a core still stops on a wall
	var wall := PlayerSim.box(self, Vector3(0, 1.5, -12.0), Vector3(6, 3, 0.3))
	await physics_frames(2)
	var w := BendingProjectile.launch(pl.controller.ctx, Vector3(0, 1.2, -8.0), Vector3.FORWARD, 32.0, {"damage": 1.0},
			{"radius": 0.6, "radius_growth": 8.0, "max_radius": 2.5, "range": 9.0, "pierce": true, "world_radius": 0.25})
	f = 0
	while w.alive and f < 90:
		await physics_frames(1)
		f += 1
	expect(not w.alive and w.global_position.z > -12.0 and w.global_position.z < -11.0, "the gust flies on to the wall and its core stops there (z %.2f)" % w.global_position.z)
	for n: Node in [d, pl, wall, ground]:
		n.queue_free()
	await frames(2)


## A projectile whose caster is freed mid-flight (a despawned enemy, a scene torn down while a
## gust still flies) ends quietly: its hits are built from the caster, and a freed one raised
## script errors in BendingContext.make_hit.
func test_projectile_outliving_its_caster_ends_quietly() -> void:
	var ground := PlayerSim.ground(self)
	var pl := PlayerSim.player(self, ElementDefs.Element.AIR, Vector3.ZERO)
	var d := TrainingDummy.new()
	add_child(d)
	d.global_position = Vector3(0, 0, -8.0)
	await physics_frames(3)
	var g := BendingProjectile.launch(pl.controller.ctx, Vector3(0, 1.2, -1.0), Vector3.FORWARD, 10.0, {"damage": 5.0}, {"radius": 0.3, "range": 12.0})
	await physics_frames(2)
	expect(g.alive, "in flight")
	pl.queue_free()
	await physics_frames(60)
	expect(not g.alive and d.hits_taken == 0, "ended with its caster, no hit built from a freed caster (alive %s, hits %d)" % [g.alive, d.hits_taken])
	d.queue_free()
	ground.queue_free()
	await frames(2)


## The training grounds' dummies named the reaction of a damage-only hit: "2  None".
func test_training_dummy_readout_names_only_real_reactions() -> void:
	var d := TrainingDummy.new()
	add_child(d)
	await frames(1)
	var chip := HitInfo.new()
	chip.damage = 2.0
	chip.reaction = HitInfo.Reaction.NONE
	d.receive_hit(chip)
	expect(d._label.text == "2", "damage-only hit: just the damage ('%s')" % d._label.text)
	var push := HitInfo.new()
	push.damage = 9.0
	push.reaction = HitInfo.Reaction.KNOCKBACK
	d.receive_hit(push)
	expect(d._label.text.begins_with("9  Knockback") and d._label.text.contains("x2 combo"), "a real reaction is named ('%s')" % d._label.text.replace("\n", " / "))
	d.queue_free()
	await frames(1)


## Enemy AI reads the same release contract as the tutorial: a player charging Earth Boulder
## never made a rogue earthbender raise its cover wall (the brain only knew ChargeAbility),
## while a charging Fire Blast did.
func test_enemies_see_every_element_charge_a_heavy() -> void:
	var ground := PlayerSim.ground(self)
	EnemySim.begin()
	for el: int in [ElementDefs.Element.EARTH, ElementDefs.Element.FIRE]:
		var tag := String(ElementDefs.id_of(el))
		var pl := PlayerSim.player(self, el, Vector3(0, 0, -8))
		pl.health.invulnerable = true
		var en := EnemySim.enemy(self, &"earth_rogue", Vector3.ZERO, pl)
		await EnemySim.settle(self)
		en.perception.alert_to(pl)
		en.perception.engaged = true
		en.brain.target = pl
		expect(pl.controller.request(&"heavy") == &"", "%s: the heavy starts" % tag)
		await PlayerSim.step(pl, 6)
		var cur := pl.controller.current
		expect(cur != null and cur.get(&"charging") == true, "%s: charging (%s)" % [tag, cur])
		var acted := en.brain._threats()
		expect(acted and en.actions.is_busy() and en.actions.attack.get("tag", &"") == &"cover",
				"%s: the rogue raises its earth wall against the charge (%s)" % [tag, en.actions.attack.get("id", &"none")])
		pl.controller.release(&"heavy")
		en.queue_free()
		pl.queue_free()
		await frames(2)
	EnemySim.end()
	ground.queue_free()
	await frames(1)


## Phone run (flow_qa_mobile): the first quest slid in while the arrival still hid the HUD
## (touch overlay off, tracker on the right); the overlay then moved the tracker under the
## vitals and the running slide tweened it back to the right, under the touch buttons, for good.
func test_quest_tracker_takes_the_touch_layout_during_its_slide_in() -> void:
	var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	await frames(2)
	var q := hud.quest
	q.show_quest({"title": "Born of the Tide", "objectives": [{"text": "Speak with Elder Anaaya"}]})
	await frames(2)
	hud.apply_touch_layout(true)
	await get_tree().create_timer(0.6).timeout
	expect(q.position.is_equal_approx(Vector2(40, 190)), "touch layout: under the vitals, clear of the buttons (%s)" % q.position)
	expect(is_equal_approx(q.modulate.a, 1.0), "fully shown")
	# a second quest while the first one still slides ends on its layout spot, not 40 px off
	hud.apply_touch_layout(false)
	await frames(2)
	var home := q.position
	q.show_quest({"title": "The First Breath", "objectives": [{"text": "Climb to the sanctum"}]})
	await frames(3)
	q.show_quest({"title": "Fire and Ash", "objectives": [{"text": "Meet Kaida"}]})
	await get_tree().create_timer(0.6).timeout
	expect(q.position.is_equal_approx(home), "back on its spot after two slides (%s vs %s)" % [q.position, home])
	hud.queue_free()
	await frames(1)


## Map fast travel and the settings' unsaved-changes question, answered with ui_* actions only
## (Enter / A), as a keyboard or pad player would.
func test_confirm_dialogs_answer_to_keyboard_and_pad() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	GameState.intro_done = true
	var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
	if not expect(w.is_ready, "world ready"):
		await _free(w)
		return
	await frames(5)
	var book := get_tree().get_first_node_in_group(&"journey_book") as JourneyBook
	var home := MapModel.place_by_id(MapModel.home_city_id())
	if not expect(book != null and not home.is_empty(), "book + home city"):
		await _free(w)
		return
	# visited (a fast-travel point), then stand away from it so it is a valid destination
	MapModel.note_position(home["position"])
	w.player.teleport(Transform3D(Basis(), (home["position"] as Vector3) + Vector3(400, 0, 0)))
	await physics_frames(5)
	var trips: Array = []
	MapModel.travel_override = func(xf: Transform3D, _o: Dictionary) -> bool:
		trips.append(xf)
		return true
	expect(book.open(&"map", {"place": home["id"]}), "book opens on the map")
	await frames(4)
	expect(MapModel.travel_block_reason(home) == "", "home is a destination (%s)" % MapModel.travel_block_reason(home))
	await _press_ui(&"ui_accept")
	await frames(3)
	var dlg := book.root.find_children("*", "ConfirmDialog", true, false)
	expect(dlg.size() == 1, "Enter on the selected city asks FAST TRAVEL (%d dialogs)" % dlg.size())
	if dlg.size() >= 1:
		var d := dlg[0] as ConfirmDialog
		expect(_focus() == d.buttons.get(&"go"), "TRAVEL focused (%s)" % _focus())
	await _press_ui(&"ui_accept")
	await frames(6)
	expect(trips.size() == 1, "Enter on TRAVEL travels (%d trips, %d dialogs open)" % [trips.size(), book.root.find_children("*", "ConfirmDialog", true, false).size()])
	expect(not book.is_open, "the book closed for the trip")
	MapModel.travel_override = Callable()
	if book.is_open:
		book.close()
	await frames(3)
	# Settings: change an option, Back -> "keep the changes?" -> ui_right -> DISCARD -> Enter
	w.pause_menu.open()
	await frames(2)
	var sm := w.pause_menu.open_settings()
	sm.persist = false
	await frames(3)
	var before := Settings.snapshot()
	sm.set_option("graphics", "glow", not bool(Settings.get_value("graphics", "glow")), "graphics")
	await frames(2)
	await _press_ui(&"ui_cancel")
	await frames(3)
	expect(sm.confirm != null and sm.confirm.is_open, "Back with changes asks")
	expect(_focus() == sm.confirm.buttons.get(&"apply"), "APPLY focused first (%s)" % _focus())
	await _press_ui(&"ui_right")
	await frames(2)
	expect(_focus() == sm.confirm.buttons.get(&"discard"), "ui_right -> DISCARD (%s %s)" % [_focus(), (_focus() as Button).text if _focus() is Button else ""])
	await _press_ui(&"ui_accept")
	await frames(4)
	expect(not sm.is_open and str(Settings.snapshot()) == str(before), "DISCARD closes and restores")
	expect(w.pause_menu.is_open, "back on the pause menu")
	w.pause_menu.resume()
	await _free(w)

## A save is JSON (one number type): counts came back as floats, so `log.has(1)` (the quest
## journal's "stage reached") was false for [0.0, 1.0] and records printed "2.0".
func test_save_round_trip_keeps_integer_records() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	GameState.add_item(&"ginseng_tea", 3)
	GameState.incr_stat("enemies_defeated", 4)
	GameState.add_practice(&"earth_pillar", 2)
	GameState.quests["ek_stone_beneath_the_sky"] = {"state": "failed", "stage": 1, "objectives": {"meet_lin": 1}, "log": [0, 1], "started": 12.5}
	GameState.discover_poi(&"poi_test")
	GameState.player_position = Vector3(10, 20, 30)
	GameState.time_of_day = 17.25
	var want := GameState.to_dict()
	expect(SaveSystem.save_game(SaveSystem.MAX_SLOTS - 1), "saved")
	GameState.reset()
	expect(SaveSystem.load_game(SaveSystem.MAX_SLOTS - 1), "loaded")
	expect(GameState.inventory["ginseng_tea"] is int and GameState.item_count(&"ginseng_tea") == 3, "inventory count is an int (%s)" % type_string(typeof(GameState.inventory["ginseng_tea"])))
	expect(GameState.stats["enemies_defeated"] is int and GameState.ability_practice["earth_pillar"] is int, "stats / practice are ints")
	var rec: Dictionary = GameState.quests["ek_stone_beneath_the_sky"]
	expect((rec["log"] as Array).has(1) and rec["stage"] is int and rec["objectives"]["meet_lin"] is int, "quest log / stage / progress are ints %s" % str(rec))
	expect(is_equal_approx(float(rec["started"]), 12.5), "times stay floats")
	var info := Quests.journal_entry(&"ek_stone_beneath_the_sky")
	if not info.is_empty():
		expect((info["stages"] as Array).size() == 2, "a failed quest's journal shows the stages it reached (%d)" % (info["stages"] as Array).size())
	expect(GameState.player_position.is_equal_approx(Vector3(10, 20, 30)) and is_equal_approx(GameState.time_of_day, 17.25), "position / hour")
	expect(str(JSON.parse_string(JSON.stringify(GameState.to_dict())).get("quests")) == str(JSON.parse_string(JSON.stringify(want)).get("quests")), "quests identical by value")
	SaveSystem.delete_save(SaveSystem.MAX_SLOTS - 1)


# --- 11: no permanent stuck states (input fuzz) --------------------------------------------------------------

const FUZZ_ACTIONS: Array[StringName] = [&"attack_light", &"attack_light", &"attack_light", &"attack_heavy", &"attack_heavy", &"block",
		&"dodge", &"dodge", &"jump", &"jump", &"sprint", &"ability_1", &"ability_2", &"ability_3", &"ability_4", &"ability_special",
		&"lock_on", &"interact", &"companion_call", &"mount", &"descend"]
const MOVES: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## States that may legitimately last (riding is ended by the player).
const FREE_STATES := [PlayerCharacter.State.LOCOMOTION, PlayerCharacter.State.AIRBORNE, PlayerCharacter.State.MOUNTED]


## Seeded random play next to an attacking bandit, for every element: every state the player
## enters ends by itself, the controller never stays busy, and once the input stops the player is
## back in control and walks. A conversation or shop the random `interact` opened holds the
## player until answered (by design); it is timed apart and answered like a player would.
func test_input_fuzz_never_leaves_the_player_stuck() -> void:
	for e in ElementDefs.ALL:
		var el := String(ElementDefs.id_of(e))
		GameState.new_game(e)
		GameState.intro_done = true
		var w := await _load(WORLD, {"new_game": true, "skip_intro": true, "no_content": true}) as WorldScene
		if not expect(w.is_ready, "%s world ready" % el):
			await _free(w)
			continue
		var pl := w.player
		await physics_frames(10)
		var fwd := -pl.global_basis.z
		var foe := EnemyBase.create(&"bandit_brawler", {"home": Transform3D(Basis(), pl.global_position + fwd * 6.0), "level": 1, "seed": 3})
		w.add_child(foe)
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242 + e
		var state_t := 0.0
		var last_state := pl.get_state()
		var worst := {"state": "", "t": 0.0}
		var busy_t := 0.0
		var worst_busy := 0.0
		var held: Array[StringName] = []
		# A conversation / shop the fuzz opened (interact next to an NPC) holds the player in
		# CINEMATIC on purpose until it is answered: player-driven, timed apart, closed after.
		var talk := [0]
		var on_talk := func(_n: Node) -> void: talk[0] += 1
		var on_done := func(_n: Node) -> void: talk[0] = maxi(0, int(talk[0]) - 1)
		Events.dialogue_started.connect(on_talk)
		Events.dialogue_ended.connect(on_done)
		var ui_t := 0.0
		for tick in 60 * 45:
			if tick % 6 == 0:
				for a in held.duplicate():
					if rng.randf() < 0.45:
						Input.action_release(a)
						held.erase(a)
				var act: StringName = FUZZ_ACTIONS[rng.randi() % FUZZ_ACTIONS.size()] if rng.randf() < 0.7 else MOVES[rng.randi() % MOVES.size()]
				if not held.has(act):
					Input.action_press(act)
					held.append(act)
				if rng.randf() < 0.3:
					pl.camera_rig.set_yaw(pl.camera_rig.yaw + rng.randf_range(-0.6, 0.6))
			if pl.health.ratio() < 0.3 and pl.is_alive():
				pl.health.health = pl.health.max_health
			await get_tree().physics_frame
			var st := pl.get_state()
			var in_ui := int(talk[0]) > 0 or get_tree().get_first_node_in_group(&"shop_panel") != null
			if in_ui:
				ui_t += 1.0 / 60.0
			if st != last_state or (in_ui and st == PlayerCharacter.State.CINEMATIC):
				state_t = 0.0
				last_state = st
			else:
				state_t += 1.0 / 60.0
			if not FREE_STATES.has(st) and st != PlayerCharacter.State.DEAD and state_t > float(worst["t"]):
				worst = {"state": pl.get_state_name(), "t": state_t}
			busy_t = busy_t + 1.0 / 60.0 if pl.controller.is_busy() else 0.0
			worst_busy = maxf(worst_busy, busy_t)
			if not pl.global_position.is_finite() or not pl.velocity.is_finite():
				fail("%s non-finite player position / velocity" % el)
				break
		_release_all()
		# Answer / close what the fuzz opened, the way a player would.
		var guard := 0
		while guard < 60 and (int(talk[0]) > 0 or get_tree().get_first_node_in_group(&"shop_panel") != null):
			guard += 1
			await _press_ui(&"ui_cancel" if get_tree().get_first_node_in_group(&"shop_panel") != null or guard % 3 == 0 else &"interact")
			await physics_frames(8)
		Events.dialogue_started.disconnect(on_talk)
		Events.dialogue_ended.disconnect(on_done)
		# Leave a mount (if the fuzz ended on one) the way a player would.
		if pl.get_state() == PlayerCharacter.State.MOUNTED:
			await _hold_for(&"mount", 0.05)
		var back := await _ticks_until(func() -> bool: return pl.get_state() == PlayerCharacter.State.LOCOMOTION and not pl.controller.is_busy(), 12.0)
		expect(back, "%s back in control after the fuzz (state %s, busy %s, ability %s)" % [el, pl.get_state_name(), pl.controller.is_busy(),
				pl.controller.current.def.id if pl.controller.current else &""])
		print("    fuzz %s: 45 s of random input, longest locking state %s %.2f s, longest busy %.2f s, %.1f s in conversations / shops it opened, back in control: %s" % [el, worst["state"], worst["t"], worst_busy, ui_t, back])
		expect(float(worst["t"]) < 8.0, "%s no locking state lasted long: worst %s %.1f s" % [el, worst["state"], worst["t"]])
		expect(worst_busy < 12.0, "%s controller never busy for long (%.1f s)" % [el, worst_busy])
		var at := pl.global_position
		Input.action_press(&"move_forward")
		await physics_frames(50)
		Input.action_release(&"move_forward")
		expect(Vector2(pl.global_position.x - at.x, pl.global_position.z - at.z).length() > 1.0 or pl.motor.swimming, "%s walks after the fuzz" % el)
		if is_instance_valid(foe):
			foe.queue_free()
		await _free(w)
		GameState.reset()
