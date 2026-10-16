extends TestCase
## Water bending (docs/modules/bending_water.md): kit + technique tree + unlock
## rules, starters on a new game, every technique on rig-less casters and the
## simulated player (costs, cooldowns, hits once per attack, timing of hits vs
## the moving water, AI casters), the soaked status and its ice synergies, the
## environment hooks (extinguish, ice floes on water, water sources) and
## "a hit VFX is shown <=> damage was applied".

const E := ElementDefs.Element
const DT := 1.0 / 60.0
const POOL := Rect2(14.0, -6.0, 12.0, 12.0)
const WATER_IDS: Array[StringName] = [&"water_whip", &"water_blast", &"water_shield", &"flow_slide", &"ice_shards", &"water_surge",
		&"ice_wall", &"ice_trap", &"water_wave", &"water_jet", &"healing_waters", &"tidal_torrent"]


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	GameState.reset()


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	GameState.reset()
	for n in WaterWaveRunner.live.duplicate():
		n.queue_free()
	for n in IceTrapZone.live.duplicate():
		n.queue_free()
	for n in IceFloe.live.duplicate():
		n.queue_free()
	for c in BendingConstruct.live.duplicate():
		c.queue_free()
	for p in BendingProjectile.live.duplicate():
		p.destroy(false)
	for c in get_children():
		c.queue_free()


# --- helpers --------------------------------------------------------------------------------------

func _ground() -> void:
	PlayerSim.ground(self)


## Flat stone floor with an open pool (POOL, 2 m deep, water level 0).
func _pool_world() -> void:
	WorldData.height_override = func(x: float, z: float) -> float: return -2.0 if POOL.has_point(Vector2(x, z)) else 0.0
	var big := 200.0
	var x0 := POOL.position.x
	var x1 := POOL.end.x
	var z0 := POOL.position.y
	var z1 := POOL.end.y
	PlayerSim.box(self, Vector3((-big + x0) * 0.5, -0.5, 0), Vector3(x0 + big, 1.0, big * 2.0))
	PlayerSim.box(self, Vector3((x1 + big) * 0.5, -0.5, 0), Vector3(big - x1, 1.0, big * 2.0))
	PlayerSim.box(self, Vector3((x0 + x1) * 0.5, -0.5, (-big + z0) * 0.5), Vector3(x1 - x0, 1.0, z0 + big))
	PlayerSim.box(self, Vector3((x0 + x1) * 0.5, -0.5, (z1 + big) * 0.5), Vector3(x1 - x0, 1.0, big - z1))
	PlayerSim.box(self, Vector3((x0 + x1) * 0.5, -2.25, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.5, z1 - z0))


func _caster(element: int, team: int, pos: Vector3, look_at_point: Vector3 = Vector3.INF, with_resources: bool = false) -> BendingController:
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
	if with_resources:
		var res := PlayerResources.new()
		res.auto_tick = false
		b.add_child(res)
		ctx.resources = res
	return bc


func _aim_at(bc: BendingController, t: Node3D) -> void:
	var ctx := bc.ctx
	ctx.aim_provider = func() -> Dictionary:
		if t == null or not is_instance_valid(t):
			return {"direction": ctx.forward(), "target": null, "point": ctx.origin() + ctx.forward() * 10.0}
		var tp := BendingContext.target_point(t)
		return {"direction": (tp - ctx.hands_pos()).normalized(), "target": t, "point": tp}


func _aim_point(bc: BendingController, p: Vector3) -> void:
	var ctx := bc.ctx
	ctx.aim_provider = func() -> Dictionary:
		return {"direction": (p - ctx.hands_pos()).normalized(), "target": null, "point": p}


func _dummy(pos: Vector3, guarding: bool = false, face: Vector3 = Vector3.INF, look: StringName = &"post") -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = look
	d.guarding = guarding
	d.max_health = 5000.0
	add_child(d)
	d.global_position = pos
	if face.is_finite():
		d.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP)
	d.home = d.global_transform
	return d


## Fixed 1/60 s steps of controllers, projectiles, constructs and the water hazards.
func _run(bcs: Array, frames_n: int, player: PlayerCharacter = null) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in frames_n:
		for bc: BendingController in bcs:
			if is_instance_valid(bc):
				bc.tick(DT)
				var res := bc.ctx.resources as PlayerResources
				if res != null and bc.ctx.caster != player:
					res.tick(DT)
		PlayerSim.step_once(player, _hazards())


func _hazards() -> Array:
	var out: Array = []
	out.append_array(WaterWaveRunner.live)
	out.append_array(IceTrapZone.live)
	out.append_array(IceFloe.live)
	return out


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


## Runs the current ability of `bc` to its end (max frames).
func _finish(bcs: Array, bc: BendingController, max_frames: int = 400, player: PlayerCharacter = null) -> int:
	var f := 0
	while bc.is_busy() and f < max_frames:
		await _run(bcs, 1, player)
		f += 1
	return f


func _landed(d: TrainingDummy) -> int:
	var n := 0
	for r in d.results:
		if r == Combat.Result.HIT or r == Combat.Result.KILLED:
			n += 1
	return n


# --- kit, tree, unlocks ------------------------------------------------------------------------------

func test_kit_tree_and_unlock_rules() -> void:
	for id in WATER_IDS:
		var d := AbilityRegistry.get_def(id)
		if not expect(d != null, "%s registered" % id):
			continue
		expect_eq(d.element, E.WATER, "%s element" % id)
		expect(d.instantiate() is BendingAbility, "%s script" % id)
		expect(d.display_name != "" and d.description.length() > 20, "%s name + description" % id)
		expect(ResourceLoader.exists(d.icon), "%s icon %s" % [id, d.icon])
		if d.clip != &"":
			expect(AnimLibrary.get_clip(d.clip) != null, "%s clip %s" % [id, d.clip])
	for c: StringName in [&"water_wave_ride", &"water_wave_crash", &"water_torrent_hold"]:
		expect(AnimLibrary.get_clip(c) != null, "clip %s" % c)
	var starters := AbilityRegistry.starter_techniques(E.WATER)
	expect_eq(starters.size(), 3, "three starters %s" % str(starters))
	for s: StringName in [&"ice_shards", &"water_surge", &"ice_wall"]:
		expect(starters.has(s), "starter %s" % s)
	# Tree data for the skill-tree UI.
	var tree := WaterKit.tree()
	expect_eq(tree.size(), 8, "8 techniques in the tree")
	var tiers := {}
	for n: Dictionary in tree:
		tiers[n["tier"]] = true
		if StringName(n["requires"]) != &"":
			expect(AbilityRegistry.has(n["requires"]), "%s requires a real technique" % n["id"])
	expect(tiers.size() == 4, "4 tiers")
	expect(tree[tree.size() - 1]["signature"], "the signature crowns the tree")
	# Gates: level -> prerequisite -> practice -> skill point.
	GameState.level = 1
	expect_eq(AbilityRegistry.can_unlock(&"ice_trap"), &"level", "ice trap: level gate")
	GameState.level = 3
	expect_eq(AbilityRegistry.can_unlock(&"ice_trap"), &"prerequisite", "needs ice shards")
	GameState.unlock_ability(&"ice_shards", false)
	expect_eq(AbilityRegistry.can_unlock(&"ice_trap"), &"practice", "needs practice")
	GameState.add_practice(&"ice_shards", 8)
	expect_eq(AbilityRegistry.can_unlock(&"ice_trap"), &"skill_points", "needs a skill point")
	GameState.skill_points = 1
	expect_eq(AbilityRegistry.can_unlock(&"ice_trap"), &"", "ice trap learnable")
	GameState.level = 4
	expect_eq(AbilityRegistry.can_unlock(&"healing_waters"), &"trainer", "healing: trainer")
	GameState.set_flag("trained_yugoda_healing_waters", true)
	expect_eq(AbilityRegistry.can_unlock(&"healing_waters"), &"", "healing learnable after Yugoda")
	GameState.level = 7
	GameState.unlock_ability(&"water_jet", false)
	GameState.set_flag("trained_pakku_tidal_torrent", true)
	expect_eq(AbilityRegistry.can_unlock(&"tidal_torrent"), &"skill_points", "signature costs 2 points")
	GameState.skill_points = 2
	expect_eq(AbilityRegistry.can_unlock(&"tidal_torrent"), &"", "signature learnable")
	expect(WaterKit.TRAINERS.has(&"pakku") and WaterKit.TRAINERS.has(&"yugoda"), "trainers listed for the NPC module")


func test_new_game_starters_slots_and_practice() -> void:
	_ground()
	GameState.new_game(E.WATER, true)
	var granted := AbilityRegistry.grant_starters(E.WATER)
	expect_eq(granted.size(), 3, "three starters granted")
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	var ids: Array = []
	for i in 3:
		var info := p.get_ability_slot_info(i)
		expect(info.has("id") and info.has("icon") and info.has("cost") and info.has("cooldown_ratio"), "slot %d HUD/touch info %s" % [i, str(info)])
		ids.append(info.get("id"))
	for s: StringName in [&"ice_shards", &"water_surge", &"ice_wall"]:
		expect(ids.has(s), "%s on a technique slot %s" % [s, str(ids)])
	expect(p.get_ability_slot_info(4).is_empty(), "no signature on a new game")
	GameState.unlock_ability(&"tidal_torrent", false)
	p.controller.load_equipped()
	expect_eq(StringName(p.get_ability_slot_info(4).get("id", &"")), &"tidal_torrent", "signature slot after unlocking")
	expect_near(float(p.get_ability_slot_info(4).get("cost", 0.0)), 100.0, 0.01, "signature shows its Focus cost")
	# Practice: performing a technique counts toward the techniques that require it.
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_shards"))
	p.resources.infinite_chi = true
	await PlayerSim.tap(p, &"ability_1", 2)
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	expect_eq(int(GameState.ability_practice.get("ice_shards", 0)), 1, "practice counted")


# --- Water Surge -----------------------------------------------------------------------------------

func test_water_surge_rolls_hits_once_and_soaks() -> void:
	_ground()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO, Vector3.INF, true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_surge"))
	var near := _dummy(Vector3(0, 0, -4))
	var far := _dummy(Vector3(0.8, 0, -8.6))
	var side := _dummy(Vector3(5.5, 0, -5))
	await _settle()
	var res := bc.ctx.resources as PlayerResources
	var def := bc.get_slot_def(&"technique_1")
	expect_eq(bc.request(&"technique_1"), &"", "surge starts")
	expect_near(res.chi, 100.0 - def.chi_cost * WaterSource.NO_SOURCE_COST, 0.01, "no source: +30 % chi")
	var a = bc.current
	var f := 0
	while a.runner == null and f < 120:
		await _run([bc], 1)
		f += 1
	expect(a.runner != null, "wave thrown on the clip's release (%d frames)" % f)
	expect(f * DT > 0.45, "after a readable wind-up (%.2f s)" % (f * DT))
	expect_eq(far.hits_taken, 0, "the far dummy is not hit before the water reaches it")
	var t_far := -1
	for i in 120:
		await _run([bc], 1)
		if far.hits_taken > 0 and t_far < 0:
			t_far = i
	expect(t_far > 6, "far dummy hit when the wave arrives (%d frames after release)" % t_far)
	expect_eq(near.hits_taken, 1, "near dummy hit once")
	expect_eq(far.hits_taken, 1, "far dummy hit once")
	expect_eq(side.hits_taken, 0, "dummy off the wave's path untouched")
	expect(near.last_hit != null and near.last_hit.reaction == HitInfo.Reaction.KNOCKBACK and near.last_hit.is_heavy, "knockback heavy hit")
	expect(WaterStatus.is_soaked(near) and WaterStatus.is_soaked(far), "targets soaked")
	expect(not WaterWaveRunner.live.has(a.runner), "wave crashed and ended")
	expect(bc.cooldown_left(def.id) > 0.0, "cooldown running")
	# With a water source in range: full size, base chi.
	bc.reset_cooldowns()
	WorldData.register_water_source(Vector3(-3, 0, 0), 2.0, &"fountain")
	await get_tree().physics_frame
	res.set_chi(100.0)
	expect_eq(bc.request(&"technique_1"), &"", "surge again (source)")
	expect_near(res.chi, 100.0 - def.chi_cost, 0.01, "source: base chi")
	await _finish([bc], bc)


func test_water_surge_douses_fire_and_fire_projectiles() -> void:
	_ground()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO)
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -16), Vector3.ZERO)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_surge"))
	var fire := ExtinguishableFire.new()
	fire.relight_time = 0.0
	add_child(fire)
	fire.global_position = Vector3(1.0, 0.6, -7)
	await _settle()
	expect(fire.is_burning(), "fire burns")
	var n0 := WaterEnv.extinguished
	bc.request(&"technique_1")
	var a = bc.current
	while a.runner == null and bc.is_busy():
		await _run([bc], 1)
	# An enemy fire bolt flying into the wave is doused in flight.
	var bolt := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.0, -12), Vector3.BACK, 12.0, {"damage": 10.0}, {"radius": 0.25, "range": 30.0})
	await _run([bc], 90)
	expect(not fire.is_burning(), "the wave put the fire out")
	expect(not bolt.alive, "the fire bolt was doused")
	expect(WaterEnv.extinguished >= n0 + 2, "extinguish count (%d)" % (WaterEnv.extinguished - n0))
	expect_near(bc.ctx.caster.global_position.z, 0.0, 0.01, "caster untouched")


# --- Ice Wall --------------------------------------------------------------------------------------

func test_ice_wall_blocks_melts_and_shatters_when_broken() -> void:
	_ground()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO)
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -14), Vector3.ZERO)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_wall"))
	var front := _dummy(Vector3(0.5, 0, -6.5))
	await _settle()
	bc.request(&"technique_1")
	var a = bc.current
	await _finish([bc], bc)
	var w: BendingConstruct = a.wall
	expect(w != null and w.kind == &"ice", "ice wall raised")
	await _run([bc], 20)
	expect(not BendingHits.line_of_sight(enemy.ctx, Vector3(0, 1.2, -13), Vector3(0, 1.2, 0)), "blocks line of sight")
	# Fire melts ice fast (x1.8).
	var hp0 := w.hp
	var bolt := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -12), Vector3.BACK, 30.0, {"damage": 10.0}, {"radius": 0.2})
	await _run([bc], 30)
	expect(not bolt.alive, "projectile stopped on the wall")
	expect_near(hp0 - w.hp, 18.0, 0.01, "fire x1.8 against ice")
	expect_eq(front.hits_taken, 0, "nothing hit yet")
	# Broken by the enemy: ice shards burst toward its side.
	var shards0 := BendingProjectile.live.size()
	var h := enemy.ctx.make_hit({"damage": 400.0, "heavy": true}, Vector3.BACK, HitInfo.new_attack_id(), &"test")
	Combat.deal(w, h)
	expect(not w.is_alive(), "wall broken")
	expect(BendingProjectile.live.size() >= shards0 + 5, "shards launched (%d)" % (BendingProjectile.live.size() - shards0))
	await _run([bc], 40)
	expect(front.hits_taken >= 1, "shards hit the enemy side (%d)" % front.hits_taken)
	# Expiring walls melt harmlessly.
	bc.reset_cooldowns()
	front.clear_stats()
	bc.request(&"technique_1")
	a = bc.current
	await _finish([bc], bc)
	var shards1 := BendingProjectile.live.size()
	(a.wall as BendingConstruct).crumble()
	expect_eq(BendingProjectile.live.size(), shards1, "an expiring wall throws no shards")


# --- Ice Trap ---------------------------------------------------------------------------------------

func test_ice_trap_freezes_longer_when_soaked_and_arms_when_missed() -> void:
	_ground()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO)
	WorldData.register_water_source(Vector3(-3, 0, 0), 2.0, &"fountain")
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_trap"))
	var d := _dummy(Vector3(0, 0, -7))
	_aim_at(bc, d)
	await _settle()
	var prisons0 := FxLib.count(&"ice_prison")
	expect_eq(bc.request(&"technique_1"), &"", "ice trap starts")
	var a = bc.current
	var f := 0
	while d.hits_taken == 0 and f < 120:
		await _run([bc], 1)
		f += 1
	expect(d.hits_taken == 1 and d.last_hit.reaction == HitInfo.Reaction.FREEZE, "target frozen")
	expect(f >= 25, "freezes on the clip's freeze event, after the water travels (%d frames)" % f)
	expect_near(d.last_hit.stun_time, 2.0, 0.01, "2 s freeze")
	expect(FxLib.count(&"ice_prison") == prisons0 + 1, "ice prison shown on the frozen target")
	await _finish([bc], bc)
	# Soaked targets stay frozen longer.
	bc.reset_cooldowns()
	WaterStatus.soak(d, 30.0)
	bc.request(&"technique_1")
	await _finish([bc], bc)
	expect_near(d.last_hit.stun_time, 2.0 * WaterStatus.FREEZE_MULT, 0.01, "soaked: x1.5 freeze")
	# Missed: the frozen patch stays armed and catches the next enemy stepping in.
	bc.reset_cooldowns()
	_aim_point(bc, Vector3(4, 0.5, -6))
	bc.request(&"technique_1")
	a = bc.current
	await _finish([bc], bc)
	expect(a.frozen.is_empty() and a.trap != null and IceTrapZone.live.has(a.trap), "nobody caught: trap armed")
	var walker := _dummy(Vector3(4, 0, -6))
	await _settle()
	await _run([bc], 12)
	expect(walker.hits_taken == 1 and walker.last_hit.reaction == HitInfo.Reaction.FREEZE, "the armed trap froze the enemy stepping in")
	expect(not IceTrapZone.live.has(a.trap), "trap spent")


# --- Water: floes, ride --------------------------------------------------------------------------

func test_floes_freeze_water_into_walkable_ice() -> void:
	_pool_world()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3(10, 0, 0), Vector3(20, 0, 0))
	await _settle()
	var c := POOL.get_center()
	var on_water := Vector3(c.x, 0, c.y)
	expect(WaterEnv.is_over_water(bc.ctx, on_water), "pool is open water")
	expect(not WaterEnv.is_over_water(bc.ctx, Vector3(0, 0, 0)), "floor is not")
	expect(WaterEnv.freeze_floe(bc.ctx, Vector3(0, 0, 0)) == null, "no floe on dry land")
	var floe := WaterEnv.freeze_floe(bc.ctx, on_water, 2.6, 3.0)
	expect(floe != null and floe.collision_layer == Layers.CONSTRUCT, "floe frozen on the water")
	await _run([bc], 20)
	await _settle()
	# A player dropped on it stands on the ice, not in the water.
	var p := PlayerSim.player(self, E.WATER, on_water + Vector3.UP * 1.0)
	for i in 60:
		await get_tree().physics_frame
		PlayerSim.step_once(p, _hazards())
	expect(p.motor.on_floor and not p.motor.swimming, "player stands on the floe (y %.2f, swim %s)" % [p.global_position.y, p.motor.swimming])
	expect(IceFloe.supports(p.global_position), "floe supports the player")
	await PlayerSim.step(p, 180, _hazards())
	expect(not IceFloe.live.has(floe), "floe melted after its lifetime")
	# Ice trap aimed at open water freezes a floe instead.
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_trap"))
	_aim_point(bc, on_water + Vector3(2, 0, 0))
	bc.request(&"technique_1")
	var a = bc.current
	await _finish([bc], bc)
	expect(a.floe != null, "ice trap on water: floe")


func test_water_wave_ride_over_ground_and_water() -> void:
	_pool_world()
	var p := PlayerSim.player(self, E.WATER, Vector3(0, 0, 0))
	await PlayerSim.step(p, 3)
	p.motor.face(Vector3.RIGHT)
	p.resources.infinite_chi = true
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_wave"))
	var bowled := _dummy(Vector3(5.5, 0, 1.0), false, Vector3.INF, &"humanoid")
	await _settle()
	var x0 := p.global_position.x
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 30, _hazards())
	var a = p.controller.current
	expect(a != null and a.def.id == &"water_wave" and a.riding, "riding the wave")
	expect(p.global_position.y > 0.4, "carried on top of the water (%.2f m up)" % p.global_position.y)
	await PlayerSim.step(p, 60, _hazards())
	var x1 := p.global_position.x
	expect(x1 - x0 > 9.0, "rode %.1f m in 1.5 s" % (x1 - x0))
	expect(bowled.hits_taken == 1 and bowled.last_hit.reaction == HitInfo.Reaction.KNOCKBACK, "enemy in the way bowled aside once")
	# Now over the pool: release -> crash, a floe freezes under the rider.
	var over_water := WaterEnv.is_over_water(p.get_bending_context(), p.global_position)
	p.input.release(&"ability_1")
	# Real physics frames: the new floe must enter the physics space.
	for i in 150:
		await get_tree().physics_frame
		PlayerSim.step_once(p, _hazards())
	expect(not p.controller.is_busy(), "ride over")
	expect(over_water, "the ride reached the water (x %.1f)" % x1)
	expect(a._released, "crash wave thrown on release")
	expect(a.floe != null, "landed on a frozen floe")
	expect(not p.motor.swimming, "not swimming after the ride (y %.2f)" % p.global_position.y)
	expect(p.get_state() == PlayerCharacter.State.LOCOMOTION, "back to locomotion (%s)" % p.get_state_name())


# --- Water Jet ----------------------------------------------------------------------------------------

func test_water_jet_pulses_pushes_and_stops_at_walls() -> void:
	_ground()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO, Vector3.INF, true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"water_jet"))
	var d := _dummy(Vector3(0, 0, -6))
	var hidden := _dummy(Vector3(4, 0, -6))
	PlayerSim.box(self, Vector3(2.4, 1.5, -3.5), Vector3(1.6, 3, 0.3))
	_aim_at(bc, d)
	await _settle()
	var res := bc.ctx.resources as PlayerResources
	bc.request(&"technique_1")
	var a = bc.current
	await _run([bc], 75)
	expect(a.jetting, "jetting while held")
	var chi_mid := res.chi
	bc.release(&"technique_1")
	await _finish([bc], bc)
	expect(a.pulses >= 5, "pulsed %d times in ~1 s" % a.pulses)
	expect_eq(d.hits_taken, a.landed, "every landed pulse hit the dummy (%d)" % d.hits_taken)
	expect(d.hits_taken >= 4, "jet hits repeatedly (%d)" % d.hits_taken)
	expect(chi_mid < 100.0 - a.def.chi_cost * WaterSource.NO_SOURCE_COST - 5.0, "upkeep drains chi (%.1f)" % chi_mid)
	expect(WaterStatus.is_soaked(d), "jet soaks")
	# Swept onto a target behind a wall: blocked.
	bc.reset_cooldowns()
	_aim_at(bc, hidden)
	bc.request(&"technique_1")
	await _run([bc], 50)
	bc.release(&"technique_1")
	await _finish([bc], bc)
	expect_eq(hidden.hits_taken, 0, "the jet does not pass through walls")


# --- Healing Waters -----------------------------------------------------------------------------------

func test_healing_waters_heals_limited_and_is_interruptible() -> void:
	_ground()
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	p.resources.infinite_chi = true
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"healing_waters"))
	expect_eq(p.controller.request(&"technique_1"), &"full_health", "nothing to heal at full health")
	p.health.apply_damage(70.0)
	var h0 := p.health.health
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 240)
	p.input.release(&"ability_1")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	var gained := p.health.health - h0
	expect(gained > 25.0 and gained <= 35.01, "healed %.1f (cap 35)" % gained)
	var d := AbilityRegistry.get_def(&"healing_waters")
	expect(p.controller.cooldown_left(d.id) > 10.0, "long cooldown")
	# A staggering hit interrupts the channel.
	p.controller.reset_cooldowns()
	p.health.apply_damage(40.0)
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 40)
	var mid := p.health.health
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -3), Vector3.ZERO)
	var hit := enemy.ctx.make_hit({"damage": 5.0, "reaction": HitInfo.Reaction.STAGGER, "stun": 0.5, "poise": 50.0}, Vector3.BACK)
	Combat.deal(p, hit)
	await PlayerSim.step(p, 60)
	p.input.release(&"ability_1")
	expect(p.health.health <= mid, "no more healing after the stagger (%.1f -> %.1f)" % [mid, p.health.health])


# --- Tidal Torrent --------------------------------------------------------------------------------------

func test_tidal_torrent_vortex_pulls_swallows_and_crashes() -> void:
	_ground()
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	p.controller.set_slot(&"signature", AbilityRegistry.get_def(&"tidal_torrent"))
	expect_eq(p.controller.request(&"signature"), &"focus", "needs 100 Focus")
	var close := _dummy(Vector3(2.0, 0, -1.5))
	var mid := _dummy(Vector3(-5.5, 0, -2))
	var ahead := _dummy(Vector3(0.5, 0, -12))
	var enemy := _caster(E.FIRE, Combat.Team.ENEMY, Vector3(0, 0, -18), Vector3.ZERO)
	await _settle()
	p.resources.mark_combat()
	p.resources.set_focus(100.0)
	await PlayerSim.tap(p, &"ability_special", 2)
	var a = p.controller.current
	expect(a != null and a.def.id == &"tidal_torrent", "signature started")
	expect(p.resources.focus < 1.0, "Focus spent")
	await PlayerSim.step_until(p, func() -> bool: return a.phase == 1, 120)
	await PlayerSim.step(p, 40, _hazards())
	expect(p.global_position.y > 0.8, "risen on the water column (%.2f m)" % p.global_position.y)
	expect(a.pulled.has(mid), "the vortex pulls enemies in")
	expect(a.launched.has(close), "the closest are swept up (launched)")
	# A rock (fire would simply be doused by the vortex) flying at the bender.
	var bolt := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.5, -8), Vector3.BACK, 14.0, {"damage": 10.0}, {"radius": 0.25, "element": E.EARTH})
	await PlayerSim.step(p, 30, _hazards())
	expect(not bolt.alive and a.swallowed >= 1, "incoming projectile swallowed by the vortex (alive %s at %s, phase %d, swallowed %d)" % [bolt.alive, bolt.global_position, a.phase, a.swallowed])
	await PlayerSim.step_until(p, func() -> bool: return a.phase == 2, 120)
	await PlayerSim.step(p, 70, _hazards())
	expect(mid.last_hit != null and mid.last_hit.ability_id == &"tidal_torrent", "ring wave reached the mid dummy")
	expect(ahead.hits_taken >= 1, "the forward wave reached 12 m ahead")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 200)
	await PlayerSim.step(p, 40)
	expect(p.global_position.y < 0.2, "back on the ground (%.2f)" % p.global_position.y)


# --- soaked ------------------------------------------------------------------------------------------------

func test_soaked_status_and_flash_freeze() -> void:
	_ground()
	WaterStatus.ensure()
	var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3.ZERO)
	var d := _dummy(Vector3(0, 0, -6))
	_aim_at(bc, d)
	await _settle()
	var h := bc.ctx.make_hit({"damage": 2.0, "status": {"soaked": 0.4}}, Vector3.FORWARD)
	BendingHits.deliver(bc.ctx, d, h)
	expect(WaterStatus.is_soaked(d), "soaked by a water hit")
	expect(WaterStatus.time_left(d) > 0.3, "for the hit's duration")
	await physics_frames(40)
	expect(not WaterStatus.is_soaked(d), "dries off")
	# Ice shards on a soaked target flash-freeze it.
	var reactions: Array = []
	d.hit_received.connect(func(hit: HitInfo, _r: int) -> void: reactions.append(hit.reaction))
	WaterStatus.soak(d, 30.0)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"ice_shards"))
	bc.request(&"technique_1")
	await _finish([bc], bc)
	await _run([bc], 30)
	expect(reactions.has(HitInfo.Reaction.FREEZE), "flash-frozen by the ice shards %s" % str(reactions))
	expect(not WaterStatus.is_soaked(d), "the water froze (no longer soaked)")


# --- AI casters ----------------------------------------------------------------------------------------------

func test_enemy_casters_use_water_techniques() -> void:
	_ground()
	var p := PlayerSim.player(self, E.FIRE, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	for id: StringName in [&"water_surge", &"ice_trap", &"water_jet", &"ice_wall", &"water_wave"]:
		BendingHits.clear_log()
		p.teleport(Transform3D.IDENTITY)
		var bc := _caster(E.WATER, Combat.Team.ENEMY, Vector3(0, 0, -7), Vector3.ZERO)
		bc.set_slot(&"technique_1", EnemyAbilities.variant(id))
		_aim_at(bc, p)
		await _settle()
		var hp0 := p.health.health
		var got: Array = []
		var cb := func(hit: HitInfo, target: Node, result: int) -> void:
			if target == p:
				got.append([hit.reaction, result])
		Events.hit_landed.connect(cb)
		expect_eq(bc.request(&"technique_1"), &"", "enemy %s starts" % id)
		await _run([bc], 50, p)
		bc.release(&"technique_1")
		await _finish([bc], bc, 300, p)
		await _run([bc], 60, p)
		Events.hit_landed.disconnect(cb)
		if id == &"ice_wall":
			expect(got.is_empty(), "ice wall raised between them, no hit")
		else:
			expect(p.health.health < hp0, "enemy %s hurt the player (%s)" % [id, str(got)])
		if id == &"ice_trap":
			expect(got.any(func(g: Array) -> bool: return g[0] == HitInfo.Reaction.FREEZE), "player frozen by the enemy trap")
		expect(p.resources.focus < 0.01, "enemy hits never give the player Focus")
		expect(not GameState.ability_practice.has(String(id)), "enemy casts do not count as practice")
		bc.ctx.caster.queue_free()
		for c in BendingConstruct.live.duplicate():
			c.crumble()
		await PlayerSim.step(p, 80, _hazards())
		p.health.revive(1.0)


# --- feedback -------------------------------------------------------------------------------------------------

func test_hit_vfx_only_for_applied_hits() -> void:
	_ground()
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var dummies: Array[TrainingDummy] = []
	var x := -20.0
	for id: StringName in [&"water_surge", &"ice_trap", &"water_jet", &"ice_shards"]:
		var bc := _caster(E.WATER, Combat.Team.PLAYER, Vector3(x, 0, 0), Vector3.INF, false)
		bc.set_slot(&"technique_1", AbilityRegistry.get_def(id))
		var open := _dummy(Vector3(x, 0, -5))
		var guard := _dummy(Vector3(x + 1.2, 0, -5.5), true, Vector3(x, 0, 0))
		dummies.append(open)
		dummies.append(guard)
		_aim_at(bc, open)
		await _settle()
		bc.request(&"technique_1")
		await _run([bc], 40)
		bc.release(&"technique_1")
		await _finish([bc], bc)
		await _run([bc], 60)
		x += 12.0
	var landed := 0
	var blocked := 0
	for d in dummies:
		landed += _landed(d)
		for r in d.results:
			if r == Combat.Result.BLOCKED:
				blocked += 1
	var shown := ImpactFx.hits_shown - shown0
	var applied := BendingHits.applied_hits - applied0
	print("    water hits: %d landed, %d blocked, %d hit VFX shown" % [landed, blocked, shown])
	expect(landed >= 6, "techniques landed (%d)" % landed)
	expect(blocked >= 1, "guards blocked some (%d)" % blocked)
	expect_eq(applied, landed, "every landed hit applied")
	expect_eq(shown, applied, "hit VFX exactly for applied hits")


# --- latency -------------------------------------------------------------------------------------------------

func test_water_latency_report() -> void:
	_ground()
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO)
	await PlayerSim.step(p, 3)
	p.resources.infinite_chi = true
	var lat: Array[int] = []
	for i in 3:
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy() or (p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain()), 90)
		var before := p.controller.current
		var before_step := (before as ComboAbility).step if before is ComboAbility else -1
		p.input.press(&"attack_light")
		var frames := 0
		for k in 30:
			await PlayerSim.step(p, 1)
			frames += 1
			var c := p.controller.current as ComboAbility
			if c != null and c.struck and (c != before or c.step != before_step):
				break
		p.input.release(&"attack_light")
		lat.append(frames)
	for f in lat:
		expect(f <= 6, "water light strike active within 6 frames: %s" % str(lat))
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	# Techniques: press -> the gameplay event (frames @60 Hz).
	var report: Array[String] = ["whip %s" % str(lat)]
	var probes := {&"water_surge": func(a) -> bool: return a.runner != null, &"ice_wall": func(a) -> bool: return a.wall != null,
			&"ice_trap": func(a) -> bool: return a._released, &"water_jet": func(a) -> bool: return a.jetting,
			&"water_wave": func(a) -> bool: return a.ride_time > 0.0}
	for id: StringName in probes:
		p.controller.reset_cooldowns()
		p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(id))
		p.input.press(&"ability_1")
		var frames := 0
		var a = null
		for k in 90:
			await PlayerSim.step(p, 1, _hazards())
			frames += 1
			a = p.controller.current
			if a != null and a.def.id == id and (probes[id] as Callable).call(a):
				break
		p.input.release(&"ability_1")
		report.append("%s %d" % [id, frames])
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 300)
		await PlayerSim.step(p, 30, _hazards())
	print("    water latency (frames @60Hz, press -> active): ", ", ".join(report))
