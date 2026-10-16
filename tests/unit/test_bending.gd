extends TestCase
## Bending framework: registry + element kits, starters / unlock rules,
## rig-less casters (virtual clip timelines, enemy team), controller flow
## (chi, cooldown, busy, failures), water sources, projectile continuous
## collision (no tunnelling at 150-200 m/s), pooling, deflect / redirect,
## one hit per attack_id, line of sight, constructs (launch, HP, blocking,
## crumble, lifetime) and "a hit VFX is shown <=> damage was applied".

const E := ElementDefs.Element
const DT := 1.0 / 60.0


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	PlayerSim.ground(self)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0


## A rig-less caster body (enemy / companion style) with its own controller.
func _caster(element: int, team: int, pos: Vector3, look_at_point: Vector3 = Vector3.INF) -> BendingController:
	var b := CharacterBody3D.new()
	b.name = "Caster"
	b.collision_layer = Layers.PLAYER if team == Combat.Team.PLAYER else Layers.ENEMY
	b.collision_mask = Layers.SOLID
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.74
	cs.shape = cap
	cs.position = Vector3(0, 0.87, 0)
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	if look_at_point.is_finite():
		b.look_at(Vector3(look_at_point.x, pos.y, look_at_point.z), Vector3.UP)
	var ctx := BendingContext.new(b, null, element, team)
	var bc := BendingController.new()
	b.add_child(bc)
	bc.setup(ctx)
	return bc


func _dummy(pos: Vector3, guarding: bool = false, face: Vector3 = Vector3.INF) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = &"post"
	d.guarding = guarding
	d.max_health = 5000.0
	add_child(d)
	d.global_position = pos
	if face.is_finite():
		d.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP)
	d.home = d.global_transform
	return d


## Steps controllers, projectiles and constructs by fixed 1/60 s ticks inside a physics frame.
func _run(bcs: Array, frames_n: int, player: PlayerCharacter = null) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in frames_n:
		for bc: BendingController in bcs:
			if is_instance_valid(bc):
				bc.tick(DT)
		PlayerSim.step_once(player)


func _settle() -> void:
	# New bodies become visible to physics queries after a physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	return PlayerSim.box(self, pos, size)


# --- registry -------------------------------------------------------------------------------------

func test_registry_kits_complete() -> void:
	BendingClips.ensure()
	var starters := {E.AIR: &"air_sweep", E.EARTH: &"earth_wall", E.FIRE: &"flame_sweep", E.WATER: &"ice_shards"}
	for e: int in ElementDefs.ALL:
		var kit := AbilityRegistry.core_kit(e)
		for slot_name: StringName in [&"light", &"heavy", &"defense", &"dodge"]:
			expect(kit.has(slot_name), "%s core kit has %s" % [ElementDefs.id_of(e), slot_name])
		expect(AbilityRegistry.starter_techniques(e).has(starters[e]), "%s starter" % ElementDefs.id_of(e))
		for d in AbilityRegistry.for_element(e):
			expect(d.display_name != "" and d.description != "", "%s has name + description" % d.id)
			if d.slot == AbilityDef.Slot.INNATE:
				continue
			var a := d.instantiate()
			expect(a is BendingAbility, "%s instantiates (%s)" % [d.id, d.script_path])
			if d.clip != &"":
				expect(AnimLibrary.get_clip(d.clip) != null, "%s clip %s exists" % [d.id, d.clip])
			for s: Dictionary in d.params.get("steps", []):
				expect(AnimLibrary.get_clip(StringName(s.get("clip", &""))) != null, "%s step clip %s exists" % [d.id, s.get("clip")])
			for k: String in ["hold_clip", "release_clip", "clip_tap", "clip_charged"]:
				if d.params.has(k) and StringName(d.params[k]) != &"":
					expect(AnimLibrary.get_clip(StringName(d.params[k])) != null, "%s %s %s exists" % [d.id, k, d.params[k]])
	# Light combos: 3-4 steps (GAME_DESIGN §4).
	for e: int in ElementDefs.ALL:
		var n: int = (AbilityRegistry.core_kit(e)[&"light"].params["steps"] as Array).size()
		expect(n >= 3 and n <= 4, "%s light chain has %d steps" % [ElementDefs.id_of(e), n])


func test_runtime_registration_and_unlocks() -> void:
	GameState.reset()
	var custom := AbilityDef.make({"id": &"test_gust", "element": E.AIR, "display_name": "Test Gust", "description": "test",
			"slot": AbilityDef.Slot.TECHNIQUE, "chi_cost": 10.0, "cooldown": 1.0,
			"script_path": "res://src/bending/kits/air/air_sweep.gd", "clip": &"air_sweep",
			"unlock": {"level": 3, "prerequisite": &"air_sweep", "cost": 1}})
	AbilityRegistry.register(custom)
	expect(AbilityRegistry.get_def(&"test_gust") == custom, "registered at runtime")
	expect_eq(AbilityRegistry.can_unlock(&"test_gust"), &"level", "level gate")
	GameState.level = 3
	expect_eq(AbilityRegistry.can_unlock(&"test_gust"), &"prerequisite", "prerequisite gate")
	var granted := AbilityRegistry.grant_starters(E.AIR)
	expect(granted.has(&"air_sweep"), "new game grants the starters %s" % [granted])
	expect(GameState.equipped_abilities.has(&"air_sweep"), "starter equipped")
	expect(AbilityRegistry.grant_starters(E.AIR).is_empty(), "granted only once")
	expect_eq(AbilityRegistry.can_unlock(&"test_gust"), &"skill_points", "needs a skill point")
	GameState.skill_points = 1
	expect_eq(AbilityRegistry.can_unlock(&"test_gust"), &"", "unlockable")
	expect_eq(AbilityRegistry.can_unlock(&"air_sweep"), &"unlocked", "already unlocked")
	expect_eq(AbilityRegistry.can_unlock(&"nope"), &"unknown", "unknown id")
	AbilityRegistry._defs.erase(&"test_gust")
	GameState.reset()


# --- casters ---------------------------------------------------------------------------------------

func test_rigless_caster_runs_light_chains() -> void:
	for e: int in ElementDefs.ALL:
		var bc := _caster(e, Combat.Team.PLAYER, Vector3(float(e) * 10.0 - 15.0, 0, 0))
		var d := _dummy(bc.ctx.origin() + Vector3(0, 0, -1.8))
		await _settle()
		var steps: Array[int] = []
		expect_eq(bc.request(&"light"), &"", "%s light starts" % ElementDefs.id_of(e))
		for i in 240:
			await _run([bc], 1)
			var c := bc.current as ComboAbility
			if c != null and c.struck and (steps.is_empty() or steps[steps.size() - 1] != c.step):
				steps.append(c.step)
			if c != null and c.can_chain():
				bc.request(&"light")
			if not bc.is_busy():
				break
		var n := (bc.get_slot_def(&"light").params["steps"] as Array).size()
		expect_eq(steps.size(), n, "%s rig-less chain struck every step %s" % [ElementDefs.id_of(e), str(steps)])
		expect(d.hits_taken >= n, "%s every step hit the dummy (%d)" % [ElementDefs.id_of(e), d.hits_taken])
		expect(not bc.is_busy(), "%s chain ended" % ElementDefs.id_of(e))
		# Heavy (tap) and the starter technique also run without a rig.
		bc.set_slot(&"technique_1", AbilityRegistry.get_def(AbilityRegistry.starter_techniques(e)[0]))
		for slot_name: StringName in [&"heavy", &"technique_1"]:
			expect_eq(bc.request(slot_name), &"", "%s %s starts" % [ElementDefs.id_of(e), slot_name])
			await _run([bc], 2)
			bc.release(slot_name)
			var f := 0
			while bc.is_busy() and f < 400:
				await _run([bc], 1)
				f += 1
			expect(not bc.is_busy(), "%s %s ends (%d frames)" % [ElementDefs.id_of(e), slot_name, f])
		d.queue_free()
		bc.ctx.caster.queue_free()


func test_virtual_events_follow_the_clip() -> void:
	var bc := _caster(E.FIRE, Combat.Team.PLAYER, Vector3.ZERO)
	await _settle()
	bc.request(&"light")
	var a := bc.current as ComboAbility
	var t_ev := a.time_to_event(&"impact")
	expect(t_ev > 0.0 and t_ev < 0.2, "impact scheduled from the clip data (%.3f s)" % t_ev)
	var frames_n := 0
	while not a.struck and frames_n < 60:
		await _run([bc], 1)
		frames_n += 1
	expect(absf(frames_n * DT - t_ev) <= DT * 1.01, "strike fires on the clip event (%d frames vs %.3f s)" % [frames_n, t_ev])


func test_enemy_team_caster_hits_the_player() -> void:
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	var bc := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -7), Vector3.ZERO)
	await _settle()
	var hp0 := p.health.health
	expect_eq(bc.request(&"heavy"), &"", "enemy fire blast")
	await _run([bc], 1, p)
	bc.release(&"heavy")
	var f := 0
	while p.health.health >= hp0 and f < 120:
		await _run([bc], 1, p)
		f += 1
	expect(p.health.health < hp0, "player damaged by an enemy-team ability (%d frames)" % f)
	expect(p.resources.focus <= 0.01, "enemy hits never grant the player Focus")


func test_controller_chi_cooldown_busy_and_water_sources() -> void:
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO)
	var res := PlayerResources.new()
	res.auto_tick = false
	bc.ctx.caster.add_child(res)
	bc.ctx.resources = res
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_shards"))
	await _settle()
	var def := bc.get_slot_def(&"technique_1")
	var fails: Array = []
	bc.ability_failed.connect(func(id: StringName, why: StringName) -> void: fails.append([id, why]))
	# No water nearby: +30% chi, smaller shards.
	var probe := def.instantiate()
	probe.ctx = bc.ctx
	expect_near(bc.ability_chi_cost(probe), def.chi_cost * WaterSource.NO_SOURCE_COST, 0.01, "no source: +30% chi")
	expect_near(WaterSource.size_mult(bc.ctx), WaterSource.NO_SOURCE_SIZE, 0.001, "no source: smaller")
	res.set_chi(5.0)
	expect_eq(bc.request(&"technique_1"), &"chi", "not enough chi")
	res.set_chi(100.0)
	expect_eq(bc.request(&"technique_1"), &"", "starts")
	expect_near(res.chi, 100.0 - def.chi_cost * WaterSource.NO_SOURCE_COST, 0.01, "charged the canteen price")
	expect_eq(bc.request(&"heavy"), &"busy", "busy while casting (kept buffered)")
	await _run([bc], 2)
	bc.release(&"technique_1")
	var f := 0
	while bc.is_busy() and f < 300:
		await _run([bc], 1)
		f += 1
	expect_eq(bc.request(&"technique_1"), &"cooldown", "cooldown")
	expect(fails.size() == 2 and fails[1][1] == &"cooldown", "failures reported %s" % str(fails))
	expect(bc.cooldown_ratio(def.id) > 0.0 and bc.get_slot_info(0)["available"] == false, "HUD shows the cooldown")
	await _run([bc], int(def.cooldown * 60.0) + 2)
	expect(bc.cooldown_left(def.id) == 0.0, "cooldown elapsed")
	# Standing on snow: snow is a source -> normal price.
	GroundSampler.add_zone(&"snow", Rect2(20, -5, 10, 10), &"snow", 0.3)
	bc.ctx.caster.global_position = Vector3(25, 0, 0)
	await get_tree().physics_frame
	expect(WaterSource.has_source(bc.ctx), "snow counts as a water source")
	expect_near(bc.ability_chi_cost(probe), def.chi_cost, 0.01, "source: base chi cost")
	# A registered lake / fountain also counts.
	bc.ctx.caster.global_position = Vector3(-40, 0, 0)
	WorldData.register_water_source(Vector3(-44, 0, 0), 2.0, &"fountain")
	await get_tree().physics_frame
	expect(WaterSource.has_source(bc.ctx), "fountain in range")


# --- projectiles -------------------------------------------------------------------------------------

func test_projectiles_never_tunnel() -> void:
	var bc := _caster(E.FIRE, Combat.Team.PLAYER, Vector3.ZERO)
	_wall(Vector3(0, 1.5, -10), Vector3(4, 3, 0.05))
	var d := _dummy(Vector3(3, 0, -20))
	await _settle()
	# 150 m/s = 2.5 m per tick against a 5 cm wall.
	var p := BendingProjectile.launch(bc.ctx, Vector3(0, 1.2, -0.6), Vector3.FORWARD, 150.0, {"damage": 10.0}, {"radius": 0.08, "range": 60.0})
	var f := 0
	while p.alive and f < 60:
		await _run([], 1)
		f += 1
	expect(not p.alive and p.global_position.z > -10.2, "stopped at the thin wall (z %.2f)" % p.global_position.z)
	# 200 m/s against a 0.72 m wide dummy (3.3 m per tick).
	var q := BendingProjectile.launch(bc.ctx, Vector3(3, 1.2, -0.6), Vector3.FORWARD, 200.0, {"damage": 10.0}, {"radius": 0.05, "range": 60.0})
	expect(q == p, "projectiles are pooled")
	f = 0
	while q.alive and f < 60:
		await _run([], 1)
		f += 1
	expect_eq(d.hits_taken, 1, "fast bolt hit the dummy once")
	expect(q.global_position.z > -20.5, "and stopped on it (z %.2f)" % q.global_position.z)


func test_projectile_redirect_and_attack_id() -> void:
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -14), Vector3.ZERO)
	var defender := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -14))
	var d := _dummy(Vector3(0, 0, -10))
	await _settle()
	var p := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -13), Vector3.BACK, 20.0, {"damage": 10.0}, {"radius": 0.2, "range": 40.0})
	await _run([], 24)
	expect(p.alive and d.hits_taken == 0, "enemy projectile passes enemy-team dummies")
	var old_id := p.attack_id
	p.redirect(Vector3.FORWARD, Combat.Team.PLAYER, defender.ctx.caster)
	expect(p.team == Combat.Team.PLAYER and p.attack_id != old_id, "redirect changes team + attack id")
	expect_near(p.velocity.length(), 23.0, 0.01, "redirect speeds it up (x1.15)")
	var f := 0
	while p.alive and f < 90:
		await _run([], 1)
		f += 1
	expect_eq(d.hits_taken, 1, "redirected projectile hits the enemy side")
	expect(d.last_hit != null and d.last_hit.source == defender.ctx.caster, "credited to the defender")
	expect_near(d.last_hit.damage, 12.5, 0.01, "redirected damage x1.25")
	# Incoming scan (defenses / AI).
	var r := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -6), Vector3.BACK, 10.0, {"damage": 1.0}, {"radius": 0.1})
	expect(BendingProjectile.incoming(Vector3(0, 1.2, 0), 8.0, Combat.Team.PLAYER).has(r), "incoming() lists it")
	r.destroy(false)
	expect(not r.alive and not BendingProjectile.live.has(r), "destroy() ends it")


func test_one_hit_per_attack_id_and_line_of_sight() -> void:
	var bc := _caster(E.AIR, Combat.Team.PLAYER, Vector3.ZERO)
	var d := _dummy(Vector3(0, 0, -2))
	var hidden := _dummy(Vector3(6, 0, -2))
	_wall(Vector3(4.2, 1.5, -2), Vector3(0.3, 3, 4))
	await _settle()
	var h := {"damage": 5.0}
	var aid := HitInfo.new_attack_id()
	var r1 := BendingHits.sphere(bc.ctx, Vector3(0, 1, -2), 1.5, h, aid, &"t")
	expect_eq(BendingHits.count_landed(r1), 1, "first hit lands")
	expect_eq(BendingHits.count_landed(BendingHits.sphere(bc.ctx, Vector3(0, 1, -2), 1.5, h, aid, &"t")), 0, "same attack id: no second hit")
	expect_eq(BendingHits.count_landed(BendingHits.cone(bc.ctx, Vector3(0, 1, 0), Vector3.FORWARD, 4.0, 40.0, h, aid, &"t")), 0, "cone, same id")
	expect_eq(BendingHits.count_landed(BendingHits.sweep(bc.ctx, Vector3(-1, 1, -2), Vector3(1, 1, -2), 0.5, h, aid, &"t")), 0, "sweep, same id")
	var p := BendingProjectile.launch(bc.ctx, Vector3(0, 1.2, -0.5), Vector3.FORWARD, 30.0, h, {"radius": 0.2, "attack_id": aid, "range": 6.0})
	await _run([], 20)
	expect_eq(d.hits_taken, 1, "projectile with the same id flies through")
	expect(not p.alive, "and expires")
	expect_eq(BendingHits.count_landed(BendingHits.sphere(bc.ctx, Vector3(0, 1, -2), 1.5, h, HitInfo.new_attack_id(), &"t")), 1, "new id hits again")
	# Walls block area hits.
	BendingHits.sphere(bc.ctx, Vector3(2.5, 1, -2), 5.0, h, HitInfo.new_attack_id(), &"t")
	expect_eq(hidden.hits_taken, 0, "no hits through walls")
	expect_eq(d.hits_taken, 3, "the visible dummy is hit")


# --- constructs ---------------------------------------------------------------------------------------

func test_constructs_launch_block_and_crumble() -> void:
	var bc := _caster(E.EARTH, Combat.Team.PLAYER, Vector3.ZERO)
	var on_spot := _dummy(Vector3(0, 0, -3))
	var behind := _dummy(Vector3(0, 0, -6))
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -12), Vector3.ZERO)
	await _settle()
	var w := BendingConstruct.raise(bc.ctx, Vector3(0, 0, -3), Vector3.FORWARD, {"size": Vector3(4, 3, 0.8), "hp": 60.0,
			"lifetime": 3.0, "rise_time": 0.2, "launch": {"lift": 7.0, "damage": 8.0}})
	expect(w.get_collision_exceptions().has(bc.ctx.caster), "the caster never collides with its own wall")
	await _run([], 30)
	expect(on_spot.hits_taken == 1 and on_spot.last_hit.reaction == HitInfo.Reaction.LAUNCH, "standing on the spot: launched once")
	on_spot.queue_free()
	await _settle()
	# Enemy projectiles stop on it and wear it down.
	var p := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -11), Vector3.BACK, 30.0, {"damage": 20.0}, {"radius": 0.2})
	await _run([], 30)
	expect(not p.alive and p.global_position.z < -3.0, "projectile stopped by the wall (z %.2f)" % p.global_position.z)
	expect_near(w.hp, 40.0, 0.01, "wall took the damage")
	expect_eq(behind.hits_taken, 0, "nothing behind it was hit")
	expect(not BendingHits.line_of_sight(enemy.ctx, Vector3(0, 1.2, -11), Vector3(0, 1.2, 0)), "blocks line of sight")
	var q := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -11), Vector3.BACK, 30.0, {"damage": 30.0, "heavy": true}, {"radius": 0.2})
	await _run([], 30)
	expect(not w.is_alive(), "heavy hit breaks it (x1.6)")
	await _run([], 40)
	expect(not BendingConstruct.live.has(w), "crumbled away")
	expect(not q.alive, "heavy projectile spent")
	# Lifetime.
	var w2 := BendingConstruct.raise(bc.ctx, Vector3(5, 0, -3), Vector3.FORWARD, {"size": Vector3(2, 2, 0.6), "lifetime": 0.5, "rise_time": 0.1})
	await _run([], 12 + 30 + 40)
	expect(not BendingConstruct.live.has(w2), "expires after its lifetime")


# --- feedback ------------------------------------------------------------------------------------------

func test_hit_vfx_only_when_damage_applied() -> void:
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var dummies: Array[TrainingDummy] = []
	for e: int in ElementDefs.ALL:
		var x := float(e) * 12.0 - 18.0
		var bc := _caster(e, Combat.Team.PLAYER, Vector3(x, 0, 0))
		bc.set_slot(&"technique_1", AbilityRegistry.get_def(AbilityRegistry.starter_techniques(e)[0]))
		var open := _dummy(Vector3(x, 0, -2.2))
		var guard := _dummy(Vector3(x + 1.3, 0, -2.6), true, Vector3(x, 0, 0))
		dummies.append(open)
		dummies.append(guard)
		await _settle()
		for slot_name: StringName in [&"light", &"light", &"light", &"heavy", &"technique_1"]:
			var f := 0
			while bc.is_busy() and not (bc.current is ComboAbility and (bc.current as ComboAbility).can_chain()) and f < 300:
				await _run([bc], 1)
				f += 1
			bc.request(slot_name)
			await _run([bc], 3)
			bc.release(slot_name)
		await _run([bc], 180)
	var landed := 0
	var blocked := 0
	for d in dummies:
		for r in d.results:
			if r == Combat.Result.HIT or r == Combat.Result.KILLED:
				landed += 1
			elif r == Combat.Result.BLOCKED:
				blocked += 1
		if d.hits_taken > 0:
			expect(d.damage_taken > 0.0, "damage applied to %s" % d.name)
	var shown := ImpactFx.hits_shown - shown0
	var applied := BendingHits.applied_hits - applied0
	print("    hits: %d landed, %d blocked, %d hit VFX shown" % [landed, blocked, shown])
	expect(landed >= 8, "the attacks landed (%d)" % landed)
	expect(blocked >= 1, "the guarding dummy blocked some (%d)" % blocked)
	expect_eq(applied, landed, "every landed hit was applied")
	expect_eq(shown, applied, "hit VFX shown exactly for applied hits")


func test_lead_point_intercepts() -> void:
	var from := Vector3.ZERO
	var target := Vector3(10, 0, 0)
	var v := Vector3(0, 0, 5)
	var speed := 20.0
	var aim := BendingContext.lead_point(from, target, v, speed, 1.0)
	var t := (aim - target).length() / v.length()
	expect(absf((aim - from).length() / speed - t) < 0.01, "projectile and target arrive together (t %.3f)" % t)
	expect_eq(BendingContext.lead_point(from, target, Vector3.ZERO, speed), target, "static target: no lead")
	expect_eq(BendingContext.lead_point(from, target, Vector3(0, 0, 50), speed), target, "unreachable: aim at it")
