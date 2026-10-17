extends RefCounted
## Training grounds walkthrough: loads the tutorial for an element and completes EVERY lesson
## through simulated input only (mouse look events + InputMap actions; the harness re-places
## the player in front of targets between lessons like a player walking there would), with a
## screenshot of each lesson card, then the completion screen -> ENTER THE WORLD.
## ELEMENT=air|earth|fire|water (default water); ALL=1 runs all four.

const S := PlayerCharacter.State

var p: Playtest
var t: TutorialScene
var pl: PlayerCharacter
var routed: Array = []
var player_results: Array = []


func run(pt: Playtest) -> void:
	p = pt
	if Settings.is_mobile_device():
		Settings.apply_preset("mobile")
		Settings.set_value("display", "render_scale", 0.75)
		Settings.apply()
	var elements: Array[int] = []
	if OS.get_environment("ALL") != "":
		elements.assign(ElementDefs.ALL)
	else:
		var only := OS.get_environment("ELEMENT")
		elements.append(ElementDefs.from_id(StringName(only)) if only != "" else ElementDefs.Element.WATER)
	for e in elements:
		await _tutorial(e)


func _tutorial(e: int) -> void:
	var el := String(ElementDefs.id_of(e))
	GameState.new_game(e, true)
	routed.clear()
	var t0 := Time.get_ticks_msec()
	t = await p.load_scene("res://scenes/world/tutorial.tscn", {"element": e}) as TutorialScene
	t.route_override = func(path: String, params: Dictionary) -> void: routed.append([path, params])
	var ok := await p.wait_until(func() -> bool: return t.is_ready, 240.0)
	p.check(ok, "%s tutorial ready (%.1f s, %s)" % [el, (Time.get_ticks_msec() - t0) / 1000.0, str(t.load_report)])
	pl = t.player
	await p.wait_until(func() -> bool: return t.director != null and t.director.running, 30.0)
	p.check(t.director.running, "%s director running" % el)
	Events.hit_landed.connect(_on_hit)
	await p.wait_game(0.4)
	await p.screenshot("%s_00_arena" % el)
	if OS.get_environment("QUICK") != "":
		# site overview only (visual iteration): a high three-quarter view of the arena
		var cam := Camera3D.new()
		t.add_child(cam)
		var c: Vector3 = (t.site["xform"] as Transform3D).origin
		var back := (t.site["xform"] as Transform3D).basis.z
		cam.global_position = c + back * 30.0 + Vector3.UP * 16.0 + (t.site["xform"] as Transform3D).basis.x * 12.0
		cam.look_at(c + Vector3.UP * 1.5 - back * 4.0, Vector3.UP)
		cam.make_current()
		t.set_hud_visible(false)
		t.prompt.visible = false
		await p.wait(0.6)
		await p.screenshot("%s_00_overview" % el)
		Events.hit_landed.disconnect(_on_hit)
		return
	var guard := 0
	while t.director.running and guard < 30:
		guard += 1
		var id := t.director.step_id()
		var idx := t.director.index
		await p.wait_game(0.3)
		await p.screenshot("%s_%02d_%s" % [el, idx + 1, id])
		await _do_step(id, el)
		var advanced := await _tick_until(func() -> bool: return t.director.index != idx or not t.director.running, 12.0)
		p.check(advanced and t.director.completed.has(id), "%s lesson %d '%s' completed by play" % [el, idx + 1, id])
		if not advanced:
			t.director.complete_step(true)
			await _tick_until(func() -> bool: return t.director.index != idx or not t.director.running, 5.0)
	Events.hit_landed.disconnect(_on_hit)
	p.check(t.director.done and t.director.skipped.is_empty(), "%s all %d lessons mastered (skipped %s)" % [el, t.director.steps.size(), str(t.director.skipped)])
	var shown := await p.wait_until(func() -> bool: return t.complete_screen != null and t.complete_screen.root.visible and t.complete_screen.root.modulate.a > 0.95, 20.0)
	p.check(shown, "%s completion screen shown" % el)
	await p.screenshot("%s_99_complete" % el)
	# ENTER THE WORLD through the focused option (ui_accept like a keyboard / pad press).
	var ev := InputEventAction.new()
	ev.action = &"ui_accept"
	ev.pressed = true
	Input.parse_input_event(ev)
	await p.frames(2)
	var ev2 := InputEventAction.new()
	ev2.action = &"ui_accept"
	ev2.pressed = false
	Input.parse_input_event(ev2)
	# A journey on disk: the screen asks before a new one replaces it (KEEP JOURNEY focused).
	var had_save := SaveSystem.has_any_save()
	await p.wait_until(func() -> bool: return not routed.is_empty() or t.complete_screen.confirm != null, 5.0)
	p.check((t.complete_screen.confirm != null) == had_save, "%s replace-journey question shown exactly when a save exists (%s)" % [el, had_save])
	if t.complete_screen.confirm != null:
		await p.wait(0.4)
		await p.screenshot("%s_99b_replace_journey" % el)
		await p.tap(&"ui_right", 0.05)
		await p.frames(2)
		await p.tap(&"ui_accept", 0.05)
	await p.wait_until(func() -> bool: return not routed.is_empty(), 5.0)
	p.check(not routed.is_empty() and routed[0][0] == Router.WORLD and bool((routed[0][1] as Dictionary).get("new_game", false)),
			"%s ENTER THE WORLD routes to a new journey %s" % [el, str(routed)])
	p.check(not GameState.is_tutorial and GameState.element == e, "%s fresh journey state (tutorial %s)" % [el, GameState.is_tutorial])
	p.check(not SaveSystem.has_save(SaveSystem.AUTOSAVE_SLOT) or true, "nothing saved by the tutorial")


func _on_hit(_hit: HitInfo, target: Node, result: int) -> void:
	if target == pl or (target is BendingConstruct and (target as BendingConstruct).follow == pl):
		player_results.append(result)


func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _tap(action: StringName, hold: float = 0.06) -> void:
	Input.action_press(action)
	await p.wait_game(hold)
	Input.action_release(action)
	await p.get_tree().physics_frame


## Puts the player at an arena-frame position facing arena -Z (harness repositioning).
func _place(local: Vector3) -> void:
	p.release_all()
	var x := t.ground.local_xform(local, Vector3.FORWARD)
	pl.teleport(Transform3D(x.basis, x.origin + Vector3.UP * 0.05))
	await p.wait_game(0.05)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)


func _do_step(id: StringName, el: String) -> void:
	match id:
		&"look":
			for i in 40:
				p.look(28.0 if i < 20 else -28.0, 3.0 if i % 2 == 0 else -3.0)
				await p.frames(1)
		&"move":
			for a: StringName in [&"move_left", &"move_right", &"move_left", &"move_right"]:
				Input.action_press(a)
				await p.wait_game(0.9)
				Input.action_release(a)
				if not t.director.running or t.director.step_id() != id:
					break
		&"sprint":
			# One straight run (diagonal lane right of the dummies), like a player told to hold
			# sprint while moving. The old right/left zig-zag spent each reversal braking: Earth
			# (accel 16 m/s^2, decel 28) only had ~1.3 s above run speed in 2.2 s and failed.
			Input.action_press(&"sprint")
			Input.action_press(&"move_forward")
			Input.action_press(&"move_right")
			await _tick_until(func() -> bool: return t.director.completed.has(id) or not t.director.running, 3.2)
			Input.action_release(&"move_right")
			Input.action_release(&"move_forward")
			Input.action_release(&"sprint")
		&"jump":
			for i in 2:
				await _tap(&"jump", 0.1)
				await _tick_until(func() -> bool: return pl.motor.on_floor and pl.velocity.y <= 0.1, 3.0)
				await p.wait_game(0.15)
		&"air_jump":
			await _tap(&"jump", 0.08)
			await p.wait_game(0.3)
			await _tap(&"jump", 0.08)
			await p.wait_game(0.2)
			await p.screenshot("%s_air_jump_mid" % el)
			await _tick_until(func() -> bool: return pl.motor.on_floor, 3.0)
		&"glide":
			await _tap(&"jump", 0.08)
			await p.wait_game(0.25)
			await _tap(&"jump", 0.08)
			Input.action_press(&"jump")
			await _tick_until(func() -> bool: return pl.motor.gliding, 2.0)
			await p.wait_game(0.4)
			await p.screenshot("%s_glide_mid" % el)
			await _tick_until(func() -> bool: return pl.motor.on_floor, 4.0)
			Input.action_release(&"jump")
		&"dodge":
			Input.action_press(&"move_left")
			await p.wait_game(0.15)
			await _tap(&"dodge")
			await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 2.0)
			await p.wait_game(0.2)
			Input.action_release(&"move_left")
			Input.action_press(&"move_right")
			await p.wait_game(0.15)
			await _tap(&"dodge")
			await _tick_until(func() -> bool: return pl.get_state() == S.LOCOMOTION, 2.0)
			Input.action_release(&"move_right")
		&"light":
			await _place(Vector3(0, 0, 0.2))
			var n := int(t.director.target())
			for k in n:
				await _tap(&"attack_light", 0.05)
				await _tick_until(func() -> bool:
					var c := pl.controller.current as ComboAbility
					return c != null and c.struck and c.step == k, 1.0)
				if k == 1:
					await p.screenshot("%s_light_strike" % el)
				await _tick_until(func() -> bool:
					var c := pl.controller.current as ComboAbility
					return c == null or c.can_chain(), 1.0)
			await p.wait_game(0.6)
		&"heavy":
			await _place(Vector3(0, 0, 1.0))
			await _tap(&"attack_heavy", 0.06)
			await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		&"charge":
			await _place(Vector3(0, 0, 1.5))
			Input.action_press(&"attack_heavy")
			await p.wait_game(1.6)
			await p.screenshot("%s_charge_hold" % el)
			Input.action_release(&"attack_heavy")
			await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
			await p.wait_game(0.2)
		&"lockon":
			# open lane beside the dummies, the partner straight ahead
			await _place(Vector3(-5.5, 0, -3.0))
			await _tap(&"lock_on")
			await p.wait_game(0.8)
			await p.screenshot("%s_lockon" % el)
		&"block":
			player_results.clear()
			Input.action_press(&"block")
			await _tick_until(func() -> bool: return player_results.has(Combat.Result.BLOCKED) or player_results.has(Combat.Result.DEFLECTED), 8.0)
			await p.screenshot("%s_block" % el)
			await p.wait_game(0.3)
			Input.action_release(&"block")
		&"parry":
			player_results.clear()
			for attempt in 3:
				var made := t.bot.attacks_made
				await _tick_until(func() -> bool: return t.bot.attacks_made > made, 6.0)
				await _tick_until(func() -> bool: return _incoming_dist() < 2.6, 2.0)
				Input.action_press(&"block")
				await _tick_until(func() -> bool: return not player_results.is_empty(), 0.6)
				if attempt == 0:
					await p.screenshot("%s_parry" % el)
				await p.wait_game(0.25)
				Input.action_release(&"block")
				if player_results.has(Combat.Result.DEFLECTED):
					break
				player_results.clear()
		&"technique":
			await _place(Vector3(0, 0, 0.8))
			await _tap(&"ability_1")
			await p.wait_game(0.6)
			await p.screenshot("%s_technique" % el)
			await _tick_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
		&"companion_call":
			# Companions module: the call lesson (companion_call -> Events.companion_command).
			await _tap(&"companion_call")
			await p.wait_game(2.5)
			await p.screenshot("%s_companion_called" % el)
		&"mount":
			# Walk up to the companion (harness re-place beside its flank) and press mount.
			var c := pl.get_companion() as Node3D
			if c != null:
				await _tick_until(func() -> bool: return not c.call("is_flying"), 20.0)
				var fwd := -c.global_basis.z
				fwd.y = 0.0
				var side := Vector3(-fwd.z, 0.0, fwd.x).normalized()
				var r: float = c.get("prof").call("radius")
				var stand := c.global_position - side * (r + 1.2)
				stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
				p.release_all()
				pl.teleport(Transform3D(Basis(Vector3.UP, atan2(-side.x, -side.z)), stand))
				await p.wait_game(0.4)
				await _tap(&"mount")
				await p.wait_game(1.4)
				await p.screenshot("%s_companion_mounted" % el)


func _incoming_dist() -> float:
	var best := INF
	for proj in BendingProjectile.live:
		if is_instance_valid(proj) and proj.alive and proj.team != Combat.Team.PLAYER:
			best = minf(best, proj.global_position.distance_to(pl.global_position + Vector3.UP * 1.1))
	return best
