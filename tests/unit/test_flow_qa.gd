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
