extends TestCase
## Player module: locomotion profiles and their measured speeds / turn rates /
## jump heights, coyote time + jump buffer, Air double jump + glide, deep snow,
## Water skating, step-up, swimming, input buffer, combo windows, cooldowns +
## chi, parry window, i-frames, poise armor, death / respawn, save state, HUD
## contract, targeting, interaction, hitstop, light-attack latency and a
## 3000-frame random-input fuzz per element (no stuck states).

const E := ElementDefs.Element
const S := PlayerCharacter.State

var _ground: StaticBody3D


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	_ground = PlayerSim.ground(self)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0


func _player(e: int, pos: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var p := PlayerSim.player(self, e, pos)
	await PlayerSim.step(p, 3)
	return p


func _hspeed(p: PlayerCharacter) -> float:
	return Vector2(p.velocity.x, p.velocity.z).length()


# --- profiles ------------------------------------------------------------------------------------

func test_profiles_match_design_table() -> void:
	var air := LocomotionProfile.for_element(E.AIR)
	var earth := LocomotionProfile.for_element(E.EARTH)
	var fire := LocomotionProfile.for_element(E.FIRE)
	var water := LocomotionProfile.for_element(E.WATER)
	expect_eq([air.walk_speed, air.run_speed, air.sprint_speed], [3.4, 7.6, 11.5], "air speeds")
	expect_eq([earth.walk_speed, earth.run_speed, earth.sprint_speed], [2.8, 5.6, 7.6], "earth speeds")
	expect_eq([fire.walk_speed, fire.run_speed, fire.sprint_speed], [3.1, 6.9, 9.6], "fire speeds")
	expect_eq([water.walk_speed, water.run_speed, water.sprint_speed, water.skate_speed], [3.0, 6.5, 9.2, 12.0], "water speeds")
	expect_eq([air.turn_rate, earth.turn_rate, fire.turn_rate, water.turn_rate], [900.0, 380.0, 650.0, 520.0], "turn rates")
	expect_eq([air.jump_velocity, earth.jump_velocity, fire.jump_velocity, water.jump_velocity], [7.4, 5.0, 6.3, 6.0], "jump velocity")
	expect_eq([air.knockback_mult, earth.knockback_mult, fire.knockback_mult, water.knockback_mult], [1.3, 0.4, 1.0, 0.9], "knockback")
	expect_near(air.jump_height(), 7.4 * 7.4 / (2.0 * 9.8 * 0.8), 0.001, "air jump height formula")
	expect(air.sprint_speed > fire.sprint_speed and fire.sprint_speed > water.sprint_speed and water.sprint_speed > earth.sprint_speed, "air fastest, earth slowest")
	expect(earth.jump_height() < water.jump_height() and water.jump_height() < fire.jump_height() and fire.jump_height() < air.jump_height(), "jump heights ordered")
	expect(air.can_glide() and air.air_jumps == 1 and not earth.can_glide(), "air only: glide + air jump")
	expect(water.can_skate() and not fire.can_skate(), "water only: skating")
	expect(air.dodge_in_air and not earth.dodge_in_air and earth.dodge_poise_armor and earth.dodge_iframes == 0.0, "dodge rules")


func test_run_and_sprint_speeds_measured() -> void:
	for e: int in ElementDefs.ALL:
		var p := await _player(e)
		var prof := p.profile
		p.input.press(&"move_forward")
		await PlayerSim.step(p, 120)
		expect_near(_hspeed(p), prof.run_speed, prof.run_speed * 0.03, "%s run speed" % ElementDefs.id_of(e))
		p.input.press(&"sprint")
		await PlayerSim.step(p, 120)
		expect_near(_hspeed(p), prof.sprint_speed, prof.sprint_speed * 0.03, "%s sprint speed" % ElementDefs.id_of(e))
		# Accelerating 0 -> run takes about run / accel seconds.
		p.input.release_all()
		await PlayerSim.step(p, 120)
		expect(_hspeed(p) < 0.05, "%s stops" % ElementDefs.id_of(e))
		p.input.press(&"move_forward")
		var frames := await PlayerSim.step_until(p, func() -> bool: return _hspeed(p) >= prof.run_speed * 0.95, 240)
		var expected := prof.run_speed * 0.95 / prof.accel * 60.0
		expect(frames > 0 and absf(frames - expected) <= expected * 0.35 + 3.0, "%s accel time %d frames (expected ~%d)" % [ElementDefs.id_of(e), frames, int(expected)])
		p.queue_free()


func test_walk_speed_with_analog_stick() -> void:
	var p := await _player(E.FIRE)
	p.input.press(&"move_forward", 0.5)
	await PlayerSim.step(p, 120)
	expect_near(_hspeed(p), p.profile.walk_speed, 0.15, "half stick = walk")


func test_turn_rates_differ() -> void:
	var times := {}
	for e: int in ElementDefs.ALL:
		var p := await _player(e)
		p.motor.face(Vector3.FORWARD)
		p.input.press(&"move_right")
		var f := await PlayerSim.step_until(p, func() -> bool: return absf(wrapf(p.motor.yaw - (-PI * 0.5), -PI, PI)) < 0.05, 240)
		times[e] = f
		var min_frames := 90.0 / p.profile.turn_rate * 60.0
		expect(f >= int(min_frames) - 1, "%s cannot turn faster than its rate (%d frames, min %.1f)" % [ElementDefs.id_of(e), f, min_frames])
		p.queue_free()
	expect(times[E.AIR] < times[E.FIRE] and times[E.FIRE] < times[E.WATER] and times[E.WATER] < times[E.EARTH], "turn order air < fire < water < earth: %s" % str(times))


func test_jump_heights_measured() -> void:
	for e: int in ElementDefs.ALL:
		var p := await _player(e)
		var y0 := p.global_position.y
		p.input.press(&"jump")
		var peak := y0
		for i in 120:
			await PlayerSim.step(p, 1)
			peak = maxf(peak, p.global_position.y)
		p.input.release(&"jump")
		expect_near(peak - y0, p.profile.jump_height(), p.profile.jump_height() * 0.06, "%s jump height" % ElementDefs.id_of(e))
		await PlayerSim.step(p, 120)
		expect(p.motor.on_floor, "%s lands" % ElementDefs.id_of(e))
		p.queue_free()


func test_variable_jump_height() -> void:
	var p := await _player(E.FIRE)
	await PlayerSim.tap(p, &"jump", 4)
	var peak := 0.0
	for i in 90:
		await PlayerSim.step(p, 1)
		peak = maxf(peak, p.global_position.y)
	expect(peak < p.profile.jump_height() * 0.8, "short tap jumps lower (%.2f < %.2f)" % [peak, p.profile.jump_height()])


func test_air_double_jump_and_glide() -> void:
	var p := await _player(E.AIR)
	await PlayerSim.tap(p, &"jump", 3)
	await PlayerSim.step_until(p, func() -> bool: return p.velocity.y <= 0.5, 120)
	var y_apex := p.global_position.y
	await PlayerSim.tap(p, &"jump", 2)
	expect(p.motor.air_jumps_used == 1, "air jump used")
	var peak := y_apex
	for i in 90:
		await PlayerSim.step(p, 1)
		peak = maxf(peak, p.global_position.y)
	expect(peak - y_apex > p.profile.air_jump_height() * 0.85, "air jump adds height (%.2f)" % (peak - y_apex))
	# Third press does nothing (one air jump; holding may start a glide).
	await PlayerSim.step_until(p, func() -> bool: return p.velocity.y < -1.0, 120)
	await PlayerSim.tap(p, &"jump", 2)
	expect(p.velocity.y < 0.0, "no third jump (vy %.2f)" % p.velocity.y)
	# Glide: hold jump while falling.
	p.input.press(&"jump")
	await PlayerSim.step(p, 40)
	expect(p.motor.gliding, "gliding while holding jump and falling")
	expect(p.velocity.y >= -p.profile.glide_fall_speed - 0.01, "glide caps fall speed (%.2f)" % p.velocity.y)
	p.input.release(&"jump")
	await PlayerSim.step(p, 5)
	expect(not p.motor.gliding, "releasing jump stops the glide")
	# Earth cannot double jump.
	var e := await _player(E.EARTH, Vector3(10, 0, 0))
	await PlayerSim.tap(e, &"jump", 3)
	await PlayerSim.step(e, 15)
	await PlayerSim.tap(e, &"jump", 2)
	expect(e.motor.air_jumps_used == 0, "earth has no air jump")


func test_coyote_time_and_jump_buffer() -> void:
	# Ledge: platform 2 m high, player runs off it.
	PlayerSim.box(self, Vector3(0, 1.0, 0), Vector3(4, 2, 4))
	var p := await _player(E.FIRE, Vector3(0, 2.05, 1.0))
	p.input.press(&"move_back")
	await PlayerSim.step_until(p, func() -> bool: return not p.motor.on_floor, 120)
	await PlayerSim.step(p, 3)
	p.input.release(&"move_back")
	await PlayerSim.tap(p, &"jump", 2)
	expect(p.velocity.y > 3.0, "coyote jump right after leaving the ledge (vy %.2f)" % p.velocity.y)
	# Buffer: press jump just before landing -> jumps on touchdown.
	await PlayerSim.step_until(p, func() -> bool: return p.velocity.y < 0.0 and p.global_position.y < 0.5, 240)
	p.input.press(&"jump")
	await PlayerSim.step(p, 1)
	p.input.release(&"jump")
	var jumped := await PlayerSim.step_until(p, func() -> bool: return p.velocity.y > 3.0, 20)
	expect(jumped >= 0, "buffered jump fires on landing")


func test_deep_snow_and_water_skating() -> void:
	GroundSampler.add_zone(&"t_snow", Rect2(-50, -50, 100, 100), &"snow", 0.5)
	var f := await _player(E.FIRE)
	f.input.press(&"move_forward")
	await PlayerSim.step(f, 120)
	expect_near(_hspeed(f), f.profile.run_speed * (1.0 - 0.3), 0.25, "deep snow slows walking ~30%")
	var w := await _player(E.WATER, Vector3(5, 0, 0))
	w.input.press(&"move_forward")
	w.input.press(&"sprint")
	await PlayerSim.step(w, 200)
	expect(w.motor.skating, "water skates when sprinting on snow")
	expect_near(_hspeed(w), w.profile.skate_speed, 0.4, "skating speed 12 m/s")
	GroundSampler.clear_zones()
	GroundSampler.add_zone(&"t_ice", Rect2(-50, -50, 100, 100), &"ice", 0.0)
	await PlayerSim.step(w, 60)
	expect(w.motor.skating, "skates on ice too")


func test_step_up_and_slopes() -> void:
	PlayerSim.box(self, Vector3(0, 0.15, -3), Vector3(4, 0.3, 1))
	var p := await _player(E.EARTH)
	p.input.press(&"move_forward")
	var top := 0.0
	for i in 60:
		await PlayerSim.step(p, 1)
		if absf(p.global_position.z + 3.0) < 0.4:
			top = maxf(top, p.global_position.y)
	expect(p.global_position.z < -3.6 and top > 0.25, "climbs over a 0.3 m step (z %.2f, top %.2f)" % [p.global_position.z, top])
	var q := await _player(E.EARTH, Vector3(10, 0, 0))
	PlayerSim.box(self, Vector3(10, 0.6, -3), Vector3(4, 1.2, 1))
	q.input.press(&"move_forward")
	await PlayerSim.step(q, 90)
	expect(q.global_position.z > -2.7, "blocked by a 1.2 m wall (z %.2f)" % q.global_position.z)
	# 55 degree ramp is not walkable.
	var r := await _player(E.EARTH, Vector3(-10, 0, 0))
	PlayerSim.box(self, Vector3(-10, 1.0, -4.5), Vector3(4, 0.4, 6), Vector3(55, 0, 0))
	r.input.press(&"move_forward")
	await PlayerSim.step(r, 180)
	expect(r.global_position.y < 1.5, "cannot walk up a 55 deg slope (y %.2f)" % r.global_position.y)


func test_swimming_never_drowns() -> void:
	WorldData.height_override = func(x: float, _z: float) -> float: return -3.0 if x > 4.0 else 0.0
	PlayerSim.box(self, Vector3(14, -3.5, 0), Vector3(20, 1, 20))
	# Dry ground only up to x = 4, then a 3 m deep pool.
	_ground.position.x = -196.0
	var p := await _player(E.EARTH, Vector3(2, 0, 0))
	p.input.press(&"move_right")
	await PlayerSim.step(p, 240)
	expect(p.motor.swimming, "swimming in deep water")
	expect(p.global_position.y > -1.8, "floats near the surface (y %.2f)" % p.global_position.y)
	p.input.release_all()
	await PlayerSim.step(p, 600)
	expect(p.motor.swimming and p.is_alive(), "still afloat and alive after 10 s")
	p.input.press(&"move_left")
	await PlayerSim.step(p, 400)
	var before := "x %.2f y %.2f yaw %.2f swim %s" % [p.global_position.x, p.global_position.y, p.motor.yaw, p.motor.swimming]
	p.input.press(&"jump")
	await PlayerSim.step(p, 6)
	p.input.release(&"jump")
	await PlayerSim.step(p, 120)
	expect(not p.motor.swimming and p.global_position.x < 4.0, "climbs back out (now x %.2f y %.2f; before jump %s)" % [p.global_position.x, p.global_position.y, before])


# --- combat ------------------------------------------------------------------------------------

func _dummy(pos: Vector3) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = &"post"
	d.position = pos
	add_child(d)
	d.home = d.global_transform
	return d


func _hit(p: PlayerCharacter, dmg: float, reaction: HitInfo.Reaction = HitInfo.Reaction.STAGGER, from: Vector3 = Vector3(0, 1, -3), source: Node = null) -> int:
	var h := HitInfo.make(dmg, source, ElementDefs.Element.NONE, reaction, p.global_position - from, 5.0)
	h.team = Combat.Team.ENEMY
	h.origin = from
	h.poise_damage = 15.0
	h.stun_time = 0.5
	h.attack_id = HitInfo.new_attack_id()
	return Combat.deal(p, h)


func test_input_buffer_fires_on_first_cancellable_frame() -> void:
	var p := await _player(E.FIRE)
	await PlayerSim.tap(p, &"attack_heavy", 2)
	expect(p.get_state() == S.ACTION, "heavy started")
	# A light press during the heavy's recovery is buffered (<= 0.2 s) and
	# fires once the heavy ends.
	await PlayerSim.step_until(p, func() -> bool: return p.controller.current != null and p.controller.current.time_to_event(&"release") == INF, 120)
	var started := false
	var left := p.controller.current.clip_end - p.controller.current.time
	if left < 0.18:
		await PlayerSim.tap(p, &"attack_light", 1)
		var f := await PlayerSim.step_until(p, func() -> bool: return p.controller.current is ComboAbility, 30)
		started = f >= 0
		expect(started, "buffered light fired when the heavy ended")
	# Too early presses (> 0.2 s before) are dropped.
	var q := await _player(E.EARTH, Vector3(6, 0, 0))
	await PlayerSim.tap(q, &"ability_1", 2)
	expect(q.get_state() == S.ACTION, "technique started")
	await PlayerSim.tap(q, &"attack_light", 1)
	await PlayerSim.step(q, 20)
	await PlayerSim.step_until(q, func() -> bool: return not q.controller.is_busy(), 120)
	await PlayerSim.step(q, 2)
	expect(not (q.controller.current is ComboAbility), "press made long before the end was not kept")


func test_combo_chain_windows() -> void:
	for e: int in ElementDefs.ALL:
		var p := await _player(e)
		var steps: Array[int] = []
		for i in 6:
			await PlayerSim.tap(p, &"attack_light", 1)
			await PlayerSim.step_until(p, func() -> bool: return p.controller.current is ComboAbility and (p.controller.current as ComboAbility).struck, 60)
			if p.controller.current is ComboAbility:
				steps.append((p.controller.current as ComboAbility).step)
			await PlayerSim.step_until(p, func() -> bool: return p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain() or not p.controller.is_busy(), 60)
		var n: int = (p.controller.get_slot_def(&"light").params["steps"] as Array).size()
		expect(str(steps.slice(0, n)) == str(range(n)), "%s chain steps %s" % [ElementDefs.id_of(e), str(steps)])
		# After the window closes the chain restarts.
		await PlayerSim.step(p, 90)
		await PlayerSim.tap(p, &"attack_light", 1)
		await PlayerSim.step(p, 2)
		expect(p.controller.current is ComboAbility and (p.controller.current as ComboAbility).step == 0, "%s chain resets after the window" % ElementDefs.id_of(e))
		p.queue_free()


func test_light_attack_latency() -> void:
	var report := []
	for e: int in ElementDefs.ALL:
		var p := await _player(e)
		var lat: Array[int] = []
		var n: int = (p.controller.get_slot_def(&"light").params["steps"] as Array).size()
		for i in n:
			await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy() or (p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain()), 90)
			p.input.press(&"attack_light")
			var frames := 0
			var before := p.controller.current
			var before_step := (before as ComboAbility).step if before is ComboAbility else -1
			for k in 30:
				await PlayerSim.step(p, 1)
				frames += 1
				var c := p.controller.current as ComboAbility
				if c != null and c.struck and (c != before or c.step != before_step):
					break
			p.input.release(&"attack_light")
			lat.append(frames)
		report.append("%s %s" % [ElementDefs.id_of(e), str(lat)])
		expect(lat[0] <= 6, "%s first light strike active within 6 frames (%d)" % [ElementDefs.id_of(e), lat[0]])
		for f in lat:
			expect(f <= 6, "%s every light strike <= 6 frames: %s" % [ElementDefs.id_of(e), str(lat)])
		p.queue_free()
	print("    light latency (frames @60Hz, press -> active): ", ", ".join(report))


func test_cooldowns_and_chi() -> void:
	var p := await _player(E.EARTH)
	var failures: Array = []
	var cb := func(id: StringName, reason: StringName) -> void: failures.append([id, reason])
	Events.ability_failed.connect(cb)
	var chi0 := p.resources.chi
	await PlayerSim.tap(p, &"ability_1", 2)
	var d := p.controller.get_slot_def(&"technique_1")
	expect(d != null and d.id == &"earth_wall", "earth wall equipped")
	expect_near(p.resources.chi, chi0 - d.chi_cost, 0.5, "chi spent")
	expect(p.controller.cooldown_left(d.id) > d.cooldown - 0.2, "cooldown started")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	await PlayerSim.tap(p, &"ability_1", 2)
	expect(failures.size() > 0 and failures[failures.size() - 1][1] == &"cooldown", "second use fails: cooldown")
	var info := p.get_ability_slot_info(0)
	expect(info["cooldown_ratio"] > 0.0 and info["cooldown_ratio"] <= 1.0 and not info["available"], "HUD slot shows the cooldown")
	p.controller.reset_cooldowns()
	p.resources.set_chi(5.0)
	await PlayerSim.tap(p, &"ability_1", 2)
	expect(failures[failures.size() - 1][1] == &"chi", "fails without chi (failures %s, chi %.1f, state %s)" % [str(failures), p.resources.chi, p.get_state_name()])
	# Light strikes are free.
	await PlayerSim.tap(p, &"attack_light", 2)
	expect(p.controller.current is ComboAbility, "light works at 5 chi")
	# Chi regenerates after 0.6 s idle at 25/s.
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	var c1 := p.resources.chi
	await PlayerSim.step(p, 30)
	await PlayerSim.step(p, 60)
	expect(p.resources.chi > c1 + 15.0, "chi regenerates (%.1f -> %.1f)" % [c1, p.resources.chi])
	Events.ability_failed.disconnect(cb)


func test_parry_window_and_block() -> void:
	var bot := SparringBot.new()
	bot.active = false
	bot.position = Vector3(0, 0, -2.5)
	add_child(bot)
	var p := await _player(E.WATER)
	p.motor.face(Vector3.FORWARD)
	p.input.press(&"block")
	await PlayerSim.step(p, 2)
	expect(p.get_state() == S.DEFEND, "defending")
	var focus0 := p.resources.focus
	var r := _hit(p, 20.0, HitInfo.Reaction.STAGGER, Vector3(0, 1, -2.5), bot)
	expect_eq(r, Combat.Result.DEFLECTED, "parry inside the first 0.15 s")
	expect_near(p.resources.focus, focus0 + 15.0, 0.6, "+15 focus on parry")
	expect(bot.hits_taken >= 1, "attacker is countered")
	expect(p.health.health == p.health.max_health, "parry negates damage")
	await PlayerSim.step(p, 20)
	var hp := p.health.health
	r = _hit(p, 20.0, HitInfo.Reaction.STAGGER, Vector3(0, 1, -2.5), bot)
	expect_eq(r, Combat.Result.BLOCKED, "after the window: block")
	expect_near(hp - p.health.health, 20.0 * (1.0 - 0.8), 0.2, "water shield blocks 80%")
	expect(p.get_state() == S.DEFEND, "block does not stagger")
	# From behind the guard does not cover.
	r = _hit(p, 10.0, HitInfo.Reaction.FLINCH, Vector3(0, 1, 3.0), bot)
	expect_eq(r, Combat.Result.HIT, "hit from behind gets through")
	p.input.release(&"block")
	await PlayerSim.step(p, 30)
	expect(p.get_state() == S.LOCOMOTION, "guard lowered")


func test_dodge_iframes_and_earth_armor() -> void:
	var p := await _player(E.FIRE)
	p.input.press(&"move_left")
	await PlayerSim.tap(p, &"dodge", 1)
	expect(p.get_state() == S.DODGE, "dodging")
	expect_eq(_hit(p, 30.0), Combat.Result.DODGED, "i-frames dodge the hit")
	expect(p.health.health == p.health.max_health, "no damage while dodging")
	await PlayerSim.step(p, 20)
	expect_eq(_hit(p, 10.0, HitInfo.Reaction.FLINCH), Combat.Result.HIT, "after the i-frames hits land")
	p.input.release_all()
	var e := await _player(E.EARTH, Vector3(8, 0, 0))
	await PlayerSim.tap(e, &"dodge", 1)
	expect(e.get_state() == S.DODGE, "earth slide")
	expect_eq(_hit(e, 10.0, HitInfo.Reaction.STAGGER), Combat.Result.HIT, "earth slide has no i-frames")
	expect(e.get_state() == S.DODGE, "but poise armor keeps the slide going")
	# Fire step cancels into strikes.
	var f := await _player(E.FIRE, Vector3(-8, 0, 0))
	await PlayerSim.tap(f, &"dodge", 1)
	await PlayerSim.step(f, 9)
	await PlayerSim.tap(f, &"attack_light", 1)
	expect(f.controller.current is ComboAbility, "fire step cancels into a strike")


func test_damage_reactions_and_knockback_by_element() -> void:
	var pushes := {}
	for e: int in ElementDefs.ALL:
		var p := await _player(e, Vector3(float(e) * 6.0, 0, 0))
		var h := HitInfo.make(5.0, null, ElementDefs.Element.NONE, HitInfo.Reaction.KNOCKBACK, Vector3.BACK, 8.0)
		h.team = Combat.Team.ENEMY
		h.poise_damage = 50.0
		Combat.deal(p, h)
		pushes[e] = _hspeed(p)
		expect(p.get_state() == S.HITSTUN, "%s knocked back into hitstun" % ElementDefs.id_of(e))
		await PlayerSim.step(p, 120)
		expect(p.get_state() == S.LOCOMOTION, "%s recovers" % ElementDefs.id_of(e))
	expect(pushes[E.AIR] > pushes[E.FIRE] and pushes[E.FIRE] > pushes[E.WATER] and pushes[E.WATER] > pushes[E.EARTH], "knockback x1.3 / x1.0 / x0.9 / x0.4: %s" % str(pushes))
	expect_near(pushes[E.EARTH] / pushes[E.FIRE], 0.4, 0.05, "earth x0.4")
	# Knockdown -> get up (with i-frames) -> locomotion.
	var p2 := await _player(E.FIRE, Vector3(0, 0, 10))
	_hit(p2, 5.0, HitInfo.Reaction.KNOCKDOWN)
	expect(p2.get_state() == S.KNOCKED_DOWN, "knocked down")
	await PlayerSim.step_until(p2, func() -> bool: return p2.get_state() == S.GETUP, 200)
	expect_eq(_hit(p2, 5.0), Combat.Result.DODGED, "get-up i-frames")
	await PlayerSim.step(p2, 120)
	expect(p2.get_state() == S.LOCOMOTION, "back to locomotion")


func test_death_and_respawn_hook() -> void:
	var p := await _player(E.AIR)
	var died := [0]
	var back := [0]
	var c1 := func() -> void: died[0] += 1
	var c2 := func() -> void: back[0] += 1
	Events.player_died.connect(c1)
	Events.player_respawned.connect(c2)
	expect_eq(_hit(p, 9999.0), Combat.Result.KILLED, "lethal hit")
	expect(p.get_state() == S.DEAD and died[0] == 1, "dead + Events.player_died")
	expect_eq(_hit(p, 10.0), Combat.Result.IGNORED, "no hits while dead")
	await PlayerSim.step(p, 30)
	p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(5, 0, 5)))
	expect(p.get_state() == S.LOCOMOTION and back[0] == 1, "respawned")
	expect_near(p.health.ratio(), 0.5, 0.01, "50% health")
	expect(p.global_position.distance_to(Vector3(5, 0, 5)) < 0.1, "at the respawn point")
	# Without the world scene: auto respawn after the timeout.
	_hit(p, 9999.0)
	await PlayerSim.step(p, int(p.auto_respawn_time * 60.0) + 10)
	expect(p.get_state() == S.LOCOMOTION and p.is_alive(), "auto respawn when nobody calls respawn_at")
	Events.player_died.disconnect(c1)
	Events.player_respawned.disconnect(c2)


func test_save_state() -> void:
	var p := await _player(E.FIRE, Vector3(3, 0, -4))
	p.motor.face(Vector3.RIGHT)
	p.health.apply_damage(30.0)
	p.write_save_state()
	expect(GameState.player_position.distance_to(p.global_position) < 0.01, "position saved")
	expect_near(GameState.player_yaw, p.motor.yaw, 0.001, "yaw saved")
	expect_near(GameState.player_health_ratio, p.health.ratio(), 0.001, "health saved")
	var q := await _player(E.FIRE, Vector3.ZERO)
	expect(q.apply_saved_state(), "restore from GameState")
	expect(q.global_position.distance_to(GameState.player_position) < 0.01, "restored position")
	GameState.reset()


func test_hud_contract() -> void:
	var p := await _player(E.WATER)
	var got := []
	p.resource_changed.connect(func(r: StringName, v: float, m: float) -> void: got.append([r, v, m]))
	expect(p.health is HealthComponent, "health property")
	expect(p.get_resource(&"chi") == Vector2(100, 100), "chi via get_resource")
	expect(p.get_resource(&"focus").y == 100.0, "focus max")
	var info := p.get_ability_slot_info(0)
	expect(info.get("id") == &"ice_shards" and info.has("icon") and info.has("cooldown_ratio") and info.has("available") and info.has("cost"), "slot 0 info %s" % str(info))
	expect(p.get_ability_slot_info(3).is_empty(), "empty slot -> {}")
	expect(p.get_ability_slot_info(4).is_empty(), "no signature yet -> {}")
	expect(p.get_lock_target() == null and p.get_companion() == null, "no lock / companion")
	await PlayerSim.tap(p, &"ability_1", 2)
	await PlayerSim.step(p, 5)
	expect(got.any(func(g: Array) -> bool: return g[0] == &"chi"), "resource_changed emits chi")


func test_targeting_soft_aim_and_lock_on() -> void:
	var p := await _player(E.AIR)
	var a := _dummy(Vector3(0, 0, -6))
	var b := _dummy(Vector3(5, 0, -6))
	var far := _dummy(Vector3(0, 0, -60))
	await PlayerSim.step(p, 10)
	expect(p.targeting.soft_target == a, "soft aim picks the dummy in the cone")
	var locked: Array = []
	var cb := func(t: Node3D) -> void: locked.append(t)
	Events.target_locked.connect(cb)
	await PlayerSim.tap(p, &"lock_on", 1)
	expect(p.get_lock_target() == a and locked.size() == 1, "lock-on")
	p.targeting.camera = null
	p.targeting.lock(b)
	expect(p.get_lock_target() == b, "switch target")
	var unl := [0]
	var cb2 := func() -> void: unl[0] += 1
	Events.target_unlocked.connect(cb2)
	b.health.apply_damage(9999.0)
	await PlayerSim.step(p, 2)
	expect(p.get_lock_target() == null and unl[0] == 1, "auto release when the target dies")
	expect(not p.targeting.candidates(30.0).has(far), "out of range targets are ignored")
	Events.target_locked.disconnect(cb)
	Events.target_unlocked.disconnect(cb2)


func test_interaction_contract() -> void:
	var p := await _player(E.EARTH)
	var it := Interactable.new()
	it.prompt = "Open the gate"
	it.position = Vector3(0, 0, -1.2)
	add_child(it)
	var prompts: Array = []
	var cb := func(t: String, v: bool) -> void: prompts.append([t, v])
	Events.interaction_prompt.connect(cb)
	var used := [0]
	it.interacted.connect(func(_pl: Node3D) -> void: used[0] += 1)
	await PlayerSim.step(p, 10)
	expect(prompts.size() > 0 and prompts[prompts.size() - 1][1] and String(prompts[prompts.size() - 1][0]).contains("Open the gate"), "prompt shown %s" % str(prompts))
	await PlayerSim.tap(p, &"interact", 1)
	expect(used[0] == 1 and p.get_state() == S.INTERACTING, "interacted")
	await PlayerSim.step(p, int(it.lock_time * 60.0) + 5)
	expect(p.get_state() == S.LOCOMOTION, "interaction lock times out")
	it.enabled = false
	await PlayerSim.step(p, 10)
	expect(not prompts[prompts.size() - 1][1], "prompt hidden when disabled")
	Events.interaction_prompt.disconnect(cb)


func test_hitstop_never_sticks() -> void:
	TimeDilation.enabled = true
	Events.hitstop.emit(0.05)
	var cam := PlayerCamera.new()
	add_child(cam)
	Events.hitstop.emit(0.08)
	await frames(2)
	expect(Engine.time_scale < 0.5, "time dips during hitstop (%.2f)" % Engine.time_scale)
	await get_tree().create_timer(0.25, true, false, true).timeout
	await frames(2)
	expect_eq(Engine.time_scale, 1.0, "time scale restored")
	TimeDilation.request(0.3, 5.0)
	cam.queue_free()
	TimeDilation.clear()
	await frames(2)
	expect_eq(Engine.time_scale, 1.0, "clear() restores")


func test_camera_modes_and_collision() -> void:
	var p := PlayerSim.player(self, E.FIRE, Vector3.ZERO, true)
	await PlayerSim.step(p, 2)
	var cam := p.camera_rig
	await frames(3)
	var d := cam.global_position.distance_to(p.global_position + Vector3.UP * 1.55)
	expect(d > 3.0 and d < 6.5, "orbit distance %.2f" % d)
	# A wall right behind the player pulls the camera in.
	PlayerSim.box(self, Vector3(0, 1.5, 2.0), Vector3(6, 3, 0.4))
	await frames(4)
	expect(cam.global_position.z < 1.8, "camera stays in front of the wall (z %.2f)" % cam.global_position.z)
	cam.set_mode(&"cinematic", {"transform": Transform3D(Basis.IDENTITY, Vector3(0, 10, 10)), "blend": 0.01})
	await frames(4)
	expect(cam.global_position.distance_to(Vector3(0, 10, 10)) < 0.2, "cinematic transform")
	cam.set_mode(&"default")
	cam.add_trauma(0.8)
	await frames(2)
	expect(cam.camera.current, "camera is current")


func test_mount_hook() -> void:
	var p := await _player(E.WATER)
	var mount := Node3D.new()
	add_child(mount)
	var seat := Node3D.new()
	mount.add_child(seat)
	seat.position = Vector3(3, 2, 0)
	p.mount_on(mount, seat)
	await PlayerSim.step(p, 5)
	expect(p.get_state() == S.MOUNTED and p.global_position.distance_to(seat.global_position) < 0.01, "follows the seat")
	expect_eq(_hit(p, 10.0), Combat.Result.IGNORED, "mounted player is not hit directly")
	mount.queue_free()
	await frames(1)
	await PlayerSim.step(p, 3)
	expect(p.get_state() == S.LOCOMOTION, "freed mount auto-dismounts")


func test_fuzz_never_stuck() -> void:
	var actions: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"dodge",
			&"attack_light", &"attack_heavy", &"block", &"ability_1", &"ability_2", &"lock_on", &"interact"]
	var rng := RandomNumberGenerator.new()
	for e: int in ElementDefs.ALL:
		rng.seed = 1000 + e
		var p := await _player(e, Vector3(float(e) * 12.0 - 18.0, 0, 0))
		p.resources.infinite_chi = e % 2 == 0
		var d := _dummy(p.global_position + Vector3(0, 0, -4))
		var states_seen := {}
		for f in 3000:
			if f % 6 == 0:
				for a in actions:
					if rng.randf() < 0.12:
						if p.input.virtual.has(a):
							p.input.release(a)
						else:
							p.input.press(a)
			if f % 400 == 0 and rng.randf() < 0.3:
				_hit(p, 8.0, [HitInfo.Reaction.FLINCH, HitInfo.Reaction.STAGGER, HitInfo.Reaction.KNOCKDOWN, HitInfo.Reaction.LAUNCH, HitInfo.Reaction.FREEZE][rng.randi() % 5])
			await PlayerSim.step(p, 1)
			states_seen[p.get_state_name()] = true
			if absf(p.global_position.y) > 50.0:
				fail("%s fell out of the world" % ElementDefs.id_of(e))
				break
		p.input.release_all()
		var back := await PlayerSim.step_until(p, func() -> bool: return p.get_state() == S.LOCOMOTION, 60 * 12)
		expect(back >= 0, "%s returns to Locomotion after the fuzz (stuck in %s)" % [ElementDefs.id_of(e), p.get_state_name()])
		expect(p.is_alive(), "%s alive" % ElementDefs.id_of(e))
		expect(not p.controller.is_busy(), "%s no ability left running" % ElementDefs.id_of(e))
		expect(Engine.time_scale == 1.0, "time scale untouched")
		print("    fuzz %s states: %s" % [ElementDefs.id_of(e), ", ".join(states_seen.keys())])
		d.queue_free()
		p.queue_free()
