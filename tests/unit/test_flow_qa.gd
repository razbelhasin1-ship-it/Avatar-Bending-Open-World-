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
func test_tutorial_heavy_charge_sprint_lessons_complete_for_every_element() -> void:
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


# --- 11: no permanent stuck states (input fuzz) --------------------------------------------------------------

const FUZZ_ACTIONS: Array[StringName] = [&"attack_light", &"attack_light", &"attack_light", &"attack_heavy", &"attack_heavy", &"block",
		&"dodge", &"dodge", &"jump", &"jump", &"sprint", &"ability_1", &"ability_2", &"ability_3", &"ability_4", &"ability_special",
		&"lock_on", &"interact", &"companion_call", &"mount", &"descend"]
const MOVES: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## States that may legitimately last (riding is ended by the player).
const FREE_STATES := [PlayerCharacter.State.LOCOMOTION, PlayerCharacter.State.AIRBORNE, PlayerCharacter.State.MOUNTED]


## Seeded random play next to an attacking bandit, for every element: every state the player
## enters ends by itself, the controller never stays busy, and once the input stops the player is
## back in control and walks.
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
			if st != last_state:
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
		# Leave a mount (if the fuzz ended on one) the way a player would.
		if pl.get_state() == PlayerCharacter.State.MOUNTED:
			await _hold_for(&"mount", 0.05)
		var back := await _ticks_until(func() -> bool: return pl.get_state() == PlayerCharacter.State.LOCOMOTION and not pl.controller.is_busy(), 12.0)
		expect(back, "%s back in control after the fuzz (state %s, busy %s, ability %s)" % [el, pl.get_state_name(), pl.controller.is_busy(),
				pl.controller.current.def.id if pl.controller.current else &""])
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
