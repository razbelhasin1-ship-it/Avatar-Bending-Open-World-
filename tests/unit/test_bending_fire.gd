extends TestCase
## Fire bending (docs/modules/bending_fire.md): kit + technique tree + unlock rules,
## starters on a new game, every technique on rig-less casters and the simulated player
## (costs, cooldowns, one hit per attack id, hits when the fire arrives, AI casters),
## Blaze Charge stages, Jet Step flight, Lightning (charge / fizzle / backfire / chain),
## the burn status (damage over time, doused by water), the environment hooks (ignite,
## extinguish by water / air hits, grass fire budget, snow, ice melt, marks) and
## "a hit VFX is shown <=> damage was applied". Prints measured latencies.

const E := ElementDefs.Element
const DT := 1.0 / 60.0
const FIRE_IDS: Array[StringName] = [&"fire_combo", &"fire_blast", &"flame_guard", &"fire_step", &"fire_burst", &"flame_sweep",
		&"jet_step", &"fire_ring", &"fire_whip", &"inferno", &"lightning"]


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	GameState.reset()
	FireEnv.force_wet = false
	PlayerSim.ground(self)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	GameState.reset()
	FireEnv.force_wet = false
	var g := GrassFire.current()
	if g != null:
		g.clear()
	for w in FireRingWave.live.duplicate():
		(w as FireRingWave).queue_free()
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).queue_free()
	for p in BendingProjectile.live.duplicate():
		(p as BendingProjectile).destroy(false)
	for c in get_children():
		c.queue_free()
	await frames(2)


# --- helpers --------------------------------------------------------------------------------------

## Chi / focus pool for rig-less casters (same interface as PlayerResources).
class Pool extends RefCounted:
	var chi := 100.0
	var focus := 100.0
	var upkeep := 0.0

	func has_chi(a: float) -> bool:
		return chi >= a

	func spend_chi(a: float) -> bool:
		if chi < a:
			return false
		chi -= a
		return true

	func add_focus(a: float) -> void:
		focus = minf(100.0, focus + a)

	func spend_focus(a: float) -> bool:
		if focus + 0.001 < a:
			return false
		focus -= a
		return true


func _caster(team: int, pos: Vector3, face: Vector3 = Vector3.INF, pool: bool = false) -> BendingController:
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
	if face.is_finite():
		b.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP)
	var ctx := BendingContext.new(b, null, E.FIRE, team)
	if pool:
		ctx.resources = Pool.new()
	# Level aim along the facing (the context's default aims at a ground point 10 m ahead).
	ctx.aim_provider = func() -> Dictionary:
		var f := ctx.forward()
		return {"direction": f, "target": null, "point": ctx.origin() + Vector3.UP * 1.2 + f * 30.0}
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


## Fire nodes that tick on their own physics (stepped here so tests stay deterministic).
func _fire_nodes() -> Array:
	var out: Array = []
	out.append_array(FireRingWave.live)
	var g := GrassFire.current()
	if g != null:
		out.append(g)
	var m := FireStatus.manager()
	if m != null and m.is_inside_tree():
		out.append(m)
	return out


func _run(bcs: Array, frames_n: int, player: PlayerCharacter = null) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in frames_n:
		for bc: BendingController in bcs:
			if is_instance_valid(bc):
				bc.tick(DT)
		PlayerSim.step_once(player, _fire_nodes())


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


## Runs a controller until it is idle (max frames). Returns frames taken.
func _until_idle(bc: BendingController, max_frames: int = 400, player: PlayerCharacter = null) -> int:
	var f := 0
	while bc.is_busy() and f < max_frames:
		await _run([bc], 1, player)
		f += 1
	return f


func _hits_by(d: TrainingDummy, id: StringName) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	if d.has_meta(&"log"):
		for h: HitInfo in d.get_meta(&"log"):
			if h.ability_id == id:
				out.append(h)
	return out


func _log(d: TrainingDummy) -> void:
	d.set_meta(&"log", [])
	d.hit_received.connect(func(hit: HitInfo, result: int) -> void:
		if result == Combat.Result.HIT or result == Combat.Result.KILLED or result == Combat.Result.BLOCKED:
			(d.get_meta(&"log") as Array).append(hit))


# --- kit + tree ------------------------------------------------------------------------------------

func test_kit_tree_and_unlocks() -> void:
	BendingClips.ensure()
	for id in FIRE_IDS:
		var d := AbilityRegistry.get_def(id)
		if not expect(d != null, "%s registered" % id):
			continue
		expect(d.element == E.FIRE and d.display_name != "" and d.description != "", "%s data" % id)
		expect(ResourceLoader.exists(d.script_path) and load(d.script_path) != null, "%s script" % id)
		expect(d.icon == "" or ResourceLoader.exists(d.icon), "%s icon %s" % [id, d.icon])
		if d.clip != &"":
			expect(AnimLibrary.get_clip(d.clip) != null, "%s clip %s" % [id, d.clip])
		var hc: StringName = d.params.get("hold_clip", &"")
		if hc != &"":
			expect(AnimLibrary.get_clip(hc) != null, "%s hold clip %s" % [id, hc])
	for c: StringName in [&"fire_burst_blast", &"fire_ring_kick", &"jet_step_launch", &"jet_hover", &"fire_whip_lash", &"inferno_spin",
			&"lightning_charge", &"lightning_release", &"fire_blaze_hold", &"fire_blaze_release"]:
		expect(AnimLibrary.get_clip(c) != null, "clip %s" % c)
	expect(AnimLibrary.get_clip(&"inferno_spin").event_time(&"release") > AnimLibrary.get_clip(&"inferno_spin").event_time(&"spin"), "inferno spins before it releases")
	expect_eq(AbilityRegistry.starter_techniques(E.FIRE), [&"fire_burst", &"flame_sweep"] as Array[StringName], "fire starters (alphabetical)")
	var tree := FireKit.tree()
	var ids: Array = tree.map(func(n: Dictionary) -> StringName: return n["id"])
	for id: StringName in [&"fire_burst", &"flame_sweep", &"jet_step", &"fire_ring", &"fire_whip", &"inferno", &"lightning"]:
		expect(ids.has(id), "tree has %s" % id)
	for i in range(1, tree.size()):
		expect(int(tree[i]["tier"]) >= int(tree[i - 1]["tier"]), "tree sorted by tier")
	for n: Dictionary in tree:
		var req: StringName = n["requires"]
		if req != &"":
			expect(ids.has(req), "%s requires a tree node (%s)" % [n["id"], req])
			var tier_req: int = tree[ids.find(req)]["tier"]
			expect(tier_req < int(n["tier"]), "%s comes after %s" % [n["id"], req])
	var inferno: Dictionary = tree[ids.find(&"inferno")]
	expect(bool(inferno["signature"]) and inferno["trainer"] == &"fn_jinzo", "Inferno: signature taught by Master Jinzo")
	expect(int(tree[ids.find(&"lightning")]["tier"]) == 5 and int(tree[ids.find(&"lightning")]["level"]) >= 9, "Lightning is the late tier")
	expect(FireKit.TRAINERS.has(&"fn_jinzo"), "trainer id published")
	# New game: starters unlocked + equipped in slots 1-2.
	GameState.new_game(E.FIRE)
	var granted := AbilityRegistry.grant_starters(E.FIRE)
	expect_eq(granted.size(), 2, "two starters granted")
	expect_eq(GameState.equipped_abilities[0], &"fire_burst", "slot 1 Fire Burst")
	expect_eq(GameState.equipped_abilities[1], &"flame_sweep", "slot 2 Flame Sweep")
	# Jet Step: level -> practice -> skill point -> learnable.
	expect_eq(AbilityRegistry.can_unlock(&"jet_step"), &"level", "jet step needs level 3")
	GameState.level = 3
	expect_eq(AbilityRegistry.can_unlock(&"jet_step"), &"practice", "jet step needs Fire Burst practice")
	GameState.add_practice(&"fire_burst", 6)
	GameState.skill_points = 0
	expect_eq(AbilityRegistry.can_unlock(&"jet_step"), &"skill_points", "then a skill point")
	GameState.skill_points = 1
	expect_eq(AbilityRegistry.can_unlock(&"jet_step"), &"", "learnable")
	# Inferno: trainer-gated.
	GameState.level = 7
	GameState.skill_points = 2
	GameState.unlock_ability(&"fire_ring", false)
	GameState.unlock_ability(&"fire_whip", false)
	expect_eq(AbilityRegistry.can_unlock(&"inferno"), &"trainer", "inferno needs Master Jinzo")
	GameState.set_flag("trained_fn_jinzo_inferno", true)
	expect_eq(AbilityRegistry.can_unlock(&"inferno"), &"", "taught -> learnable")
	# Lightning: level 9, Jet Step practised, trainer.
	expect_eq(AbilityRegistry.can_unlock(&"lightning"), &"level", "lightning needs level 9")
	GameState.level = 9
	expect_eq(AbilityRegistry.can_unlock(&"lightning"), &"prerequisite", "lightning needs Jet Step")
	GameState.unlock_ability(&"jet_step", false)
	expect_eq(AbilityRegistry.can_unlock(&"lightning"), &"trainer", "then the master")
	GameState.set_flag("trained_fn_jinzo_lightning", true)
	expect_eq(AbilityRegistry.can_unlock(&"lightning"), &"practice", "then Jet Step practice")
	GameState.add_practice(&"jet_step", 8)
	expect_eq(AbilityRegistry.can_unlock(&"lightning"), &"", "learnable")
	# Enemy attack entries point at real clips and technique slots.
	for k: StringName in FireKit.enemy_attacks():
		var a: Dictionary = FireKit.enemy_attacks()[k]
		expect(AnimLibrary.get_clip(a["clip"]) != null and String((a["bending"] as Dictionary)["slot"]).begins_with("technique"), "enemy attack %s" % k)


# --- techniques ------------------------------------------------------------------------------------

func test_every_technique_hits_once_and_ends() -> void:
	# [id, dummy distance, frames to hold the button]
	var cases := [[&"fire_burst", 2.6, 2], [&"fire_ring", 5.0, 2], [&"fire_whip", 5.5, 2], [&"jet_step", 1.6, 2], [&"lightning", 12.0, 110]]
	var x := -30.0
	for c: Array in cases:
		var id: StringName = c[0]
		var bc := _caster(Combat.Team.PLAYER, Vector3(x, 0, 0), Vector3(x, 0, -10), true)
		var d := _dummy(Vector3(x, 0, -float(c[1])))
		_log(d)
		await _settle()
		var def := AbilityRegistry.get_def(id)
		bc.set_slot(&"technique_1", def)
		var pool: Pool = bc.ctx.resources
		var chi0 := pool.chi
		expect_eq(bc.request(&"technique_1"), &"", "%s starts" % id)
		expect_near(pool.chi, chi0 - def.chi_cost, 0.01, "%s chi spent" % id)
		expect(bc.cooldown_left(id) > def.cooldown - 0.05, "%s cooldown started" % id)
		await _run([bc], int(c[2]))
		bc.release(&"technique_1")
		var f := await _until_idle(bc, 400)
		await _run([bc], 30)
		expect(not bc.is_busy(), "%s ended (%d frames)" % [id, f])
		var hits := _hits_by(d, id)
		expect_eq(hits.size(), 1, "%s hit the dummy exactly once" % id)
		if bc.request(&"technique_1") == &"":
			fail("%s should be on cooldown" % id)
		x += 15.0


func test_ring_hits_when_flames_arrive_and_can_be_jumped() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	var near := _dummy(Vector3(0, 0, -1.8))
	var far := _dummy(Vector3(0, 0, -6.0))
	var behind_wall := _dummy(Vector3(5.0, 0, 0))
	PlayerSim.box(self, Vector3(2.6, 1.5, 0), Vector3(0.4, 3.0, 3.0))
	var high := _dummy(Vector3(-4.0, 2.2, 0))
	PlayerSim.box(self, Vector3(-4.0, 1.0, 0), Vector3(1.6, 2.0, 1.6))
	for d in [near, far, behind_wall, high]:
		_log(d)
	await _settle()
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"fire_ring"))
	bc.request(&"technique_1")
	var wave: FireRingWave = null
	var near_at := -1.0
	var far_at := -1.0
	for i in 120:
		await _run([bc], 1)
		if wave == null and not FireRingWave.live.is_empty():
			wave = FireRingWave.live[0]
		if wave != null and near_at < 0.0 and not _hits_by(near, &"fire_ring").is_empty():
			near_at = wave.radius_at(wave.t)
		if wave != null and far_at < 0.0 and not _hits_by(far, &"fire_ring").is_empty():
			far_at = wave.radius_at(wave.t)
	expect(wave != null, "ring wave spawned")
	expect(near_at > 0.0 and far_at > 0.0, "both dummies in reach hit")
	expect(far_at > near_at + 2.5, "the far dummy is hit later, when the flames reach it (%.2f vs %.2f m)" % [far_at, near_at])
	expect(absf(far_at - 6.0) < 1.2, "hit radius matches the visual front (%.2f m at 6 m)" % far_at)
	expect(_hits_by(behind_wall, &"fire_ring").is_empty(), "a wall shields the dummy behind it")
	expect(_hits_by(high, &"fire_ring").is_empty(), "a target 2 m up clears the ring")
	expect_eq(_hits_by(near, &"fire_ring").size(), 1, "one hit per target")


func test_fire_burst_knocks_down_close_back_far_and_burns_projectiles() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	var close := _dummy(Vector3(0, 0, -1.4))
	var mid := _dummy(Vector3(2.6, 0, 1.2))
	var out := _dummy(Vector3(-6.0, 0, 0))
	for d in [close, mid, out]:
		_log(d)
	var enemy := _caster(Combat.Team.ENEMY, Vector3(0, 0, -14), Vector3.ZERO)
	await _settle()
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"fire_burst"))
	var proj := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -4.0), Vector3(0, 0, 1), 6.0, {"damage": 10.0}, {"radius": 0.25, "range": 30.0})
	bc.request(&"technique_1")
	await _until_idle(bc, 120)
	var hc := _hits_by(close, &"fire_burst")
	var hm := _hits_by(mid, &"fire_burst")
	expect(hc.size() == 1 and hc[0].reaction == HitInfo.Reaction.KNOCKDOWN, "close: knocked down")
	expect(hm.size() == 1 and hm[0].reaction == HitInfo.Reaction.KNOCKBACK, "mid: knocked back")
	expect(_hits_by(out, &"fire_burst").is_empty(), "out of reach: untouched")
	expect(not proj.alive, "the incoming projectile was burnt away")


func test_fire_whip_tip_hits_harder_and_never_skips() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	# One target near the hand side of the arc, one at the tip's reach.
	var body := _dummy(Vector3(-1.2, 0, -2.6))
	var tip := _dummy(Vector3(-4.6, 0, -5.4))
	var outside := _dummy(Vector3(0, 0, 9.0))
	for d in [body, tip, outside]:
		_log(d)
	await _settle()
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"fire_whip"))
	bc.request(&"technique_1")
	await _until_idle(bc, 150)
	var hb := _hits_by(body, &"fire_whip")
	var ht := _hits_by(tip, &"fire_whip")
	expect_eq(hb.size(), 1, "the lash hit the near target once")
	expect_eq(ht.size(), 1, "the lash hit the far target once")
	if hb.size() == 1 and ht.size() == 1:
		expect(ht[0].damage > hb[0].damage, "the tip cracks harder (%.0f vs %.0f)" % [ht[0].damage, hb[0].damage])
	expect(_hits_by(outside, &"fire_whip").is_empty(), "behind the bender: untouched")


func test_blaze_charge_stages_and_explosion() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	var target := _dummy(Vector3(0, 0, -9.0))
	var side := _dummy(Vector3(2.6, 0, -9.5))
	for d in [target, side]:
		_log(d)
	await _settle()
	var pool: Pool = bc.ctx.resources
	expect_eq(bc.request(&"heavy"), &"", "charge starts")
	await _run([bc], 30)
	var a := bc.current as ChargeAbility
	var c_half := a.charge if a else 0.0
	await _run([bc], 60)
	var c_full := a.charge if a else 0.0
	expect(c_half > 0.2 and c_half < 0.9 and c_full >= 0.99, "charge builds (%.2f -> %.2f)" % [c_half, c_full])
	expect(pool.chi < 100.0 - 10.0 - 10.0, "charging spends extra chi (%.1f)" % pool.chi)
	bc.release(&"heavy")
	for i in 120:
		await _run([bc], 1)
		if not _hits_by(side, &"fire_blast").is_empty():
			break
	expect(_hits_by(target, &"fire_blast").size() >= 1, "the blast hit the target")
	expect(_hits_by(side, &"fire_blast").size() == 1, "the explosion caught the one beside it")


func test_jet_step_launch_hover_and_air_use() -> void:
	var p := PlayerSim.player(self, E.FIRE, Vector3(0, 0, 0))
	await PlayerSim.step(p, 10)
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"jet_step"))
	var y0 := p.global_position.y
	# Tap: a leap up and forward.
	await PlayerSim.tap(p, &"ability_1", 2)
	var peak := y0
	var z_end := 0.0
	for i in 240:
		await PlayerSim.step(p, 1)
		peak = maxf(peak, p.global_position.y)
		z_end = p.global_position.z
		if i > 30 and p.motor.on_floor:
			break
	await PlayerSim.step(p, 20)
	expect(peak - y0 > 2.0, "jet step leaps (%.2f m)" % (peak - y0))
	expect(absf(z_end) > 2.0, "and travels forward (%.2f m)" % absf(z_end))
	expect(p.motor.on_floor, "lands again")
	# Hold: hover.
	p.controller.reset_cooldowns()
	var chi0 := p.resources.chi
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 50)
	var y_a := p.global_position.y
	await PlayerSim.step(p, 25)
	var y_b := p.global_position.y
	var hovering := p.controller.current != null and p.controller.current.def.id == &"jet_step"
	expect(hovering, "still on the jets while held")
	expect(absf(y_b - y_a) < 0.6 and y_a > 1.5, "hovering at height (%.2f -> %.2f)" % [y_a, y_b])
	expect(p.resources.chi < chi0 - 14.0, "hover drains chi (%.1f)" % p.resources.chi)
	p.input.release(&"ability_1")
	await PlayerSim.step(p, 4)
	# Released mid-air: one more jet in the air is allowed, then refused until landing.
	p.controller.reset_cooldowns()
	expect(p.can_bend_airborne(&"technique_1"), "jet step usable in the air (params.in_air)")
	var why := p.controller.request(&"technique_1")
	expect_eq(why, &"", "air jet")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	p.controller.reset_cooldowns()
	if not p.motor.on_floor:
		expect_eq(p.controller.request(&"technique_1"), &"airborne", "only once per airtime")
	await PlayerSim.step_until(p, func() -> bool: return p.motor.on_floor, 300)
	await PlayerSim.step(p, 10)
	p.controller.reset_cooldowns()
	expect_eq(p.controller.request(&"technique_1"), &"", "recharged on landing")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 200)


func test_lightning_release_fizzle_and_backfire() -> void:
	# Full charge: a big unblockable bolt that arcs to a second target.
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	var guard := _dummy(Vector3(0, 0, -14.0), true, Vector3.ZERO)
	var second := _dummy(Vector3(2.5, 0, -14.5))
	for d in [guard, second]:
		_log(d)
	await _settle()
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"lightning"))
	var bolts0 := FireLightning.bolts
	bc.request(&"technique_1")
	await _run([bc], 100)
	bc.release(&"technique_1")
	await _until_idle(bc, 120)
	var hg := _hits_by(guard, &"lightning")
	expect(hg.size() == 1 and hg[0].damage >= 50.0, "full bolt: %s dmg" % (str(hg[0].damage) if hg.size() > 0 else "none"))
	expect(guard.results.has(Combat.Result.HIT) and not guard.results.has(Combat.Result.BLOCKED), "unblockable: the guard does not stop it")
	expect_eq(_hits_by(second, &"lightning").size(), 1, "it arcs on to the target beside")
	expect_eq(FireLightning.bolts, bolts0 + 1, "one bolt")
	# Early release fizzles: nothing fired.
	bc.reset_cooldowns()
	var hits0 := guard.hits_taken
	bc.request(&"technique_1")
	await _run([bc], 30)
	bc.release(&"technique_1")
	await _until_idle(bc, 60)
	expect_eq(FireLightning.bolts, bolts0 + 1, "released at 30 % it fizzles")
	expect_eq(guard.hits_taken, hits0, "nothing hit")
	# Overcharge: the lightning turns on the bender (a player).
	var p := PlayerSim.player(self, E.FIRE, Vector3(20, 0, 0))
	await PlayerSim.step(p, 5)
	p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(&"lightning"))
	var hp0 := p.health.health
	var bf0 := FireLightning.backfires
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 200)
	p.input.release(&"ability_1")
	await seconds(0.15)
	await PlayerSim.step(p, 30)
	expect_eq(FireLightning.backfires, bf0 + 1, "held too long: backfire")
	expect(p.health.health < hp0 - 10.0, "the bender is hurt (%.0f -> %.0f)" % [hp0, p.health.health])
	await PlayerSim.step_until(p, func() -> bool: return p.get_state() == PlayerCharacter.State.LOCOMOTION, 400)
	# Interrupted by any hit past half charge: it discharges into the bender.
	p.controller.reset_cooldowns()
	p.health.revive(1.0)
	await PlayerSim.step(p, 5)
	p.input.press(&"ability_1")
	await PlayerSim.step(p, 60)
	var enemy := _caster(Combat.Team.ENEMY, Vector3(20, 0, -3), Vector3(20, 0, 0))
	await _settle()
	var jab := enemy.ctx.make_hit({"damage": 3.0, "reaction": HitInfo.Reaction.FLINCH}, Vector3(0, 0, 1))
	Combat.deal(p, jab)
	await PlayerSim.step(p, 2)
	expect(p.controller.current == null or p.controller.current.def.id != &"lightning", "a jab breaks the charge")
	await seconds(0.15)
	expect_eq(FireLightning.backfires, bf0 + 2, "and the lightning discharges into the bender")
	p.input.release(&"ability_1")


func test_inferno_vortex_pulses_and_launching_ring() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	var inside := _dummy(Vector3(0, 0, -2.2))
	var ring := _dummy(Vector3(8.0, 0, 0))
	for d in [inside, ring]:
		_log(d)
	await _settle()
	bc.set_slot(&"signature", AbilityRegistry.get_def(&"inferno"))
	var pool: Pool = bc.ctx.resources
	pool.focus = 40.0
	expect_eq(bc.request(&"signature"), &"focus", "needs full Focus")
	pool.focus = 100.0
	expect_eq(bc.request(&"signature"), &"", "Inferno starts")
	expect_near(pool.focus, 0.0, 0.01, "Focus spent")
	await _run([bc], 50)
	expect_near(bc.ctx.damage_reduction, 0.5, 0.01, "damage reduction while it runs")
	expect(bc.ctx.poise_armor >= 900.0, "hyper armor while it runs")
	await _until_idle(bc, 300)
	await _run([bc], 30)
	var pulses := _hits_by(inside, &"inferno").filter(func(h: HitInfo) -> bool: return h.reaction != HitInfo.Reaction.LAUNCH)
	expect(pulses.size() >= 3, "the vortex scorched the close target on several pulses (%d)" % pulses.size())
	var launches := _hits_by(ring, &"inferno").filter(func(h: HitInfo) -> bool: return h.reaction == HitInfo.Reaction.LAUNCH)
	expect_eq(launches.size(), 1, "the ring launched the far target once")


func test_ai_casters_use_the_techniques_on_the_player() -> void:
	var p := PlayerSim.player(self, E.WATER, Vector3(0, 0, 0))
	await PlayerSim.step(p, 5)
	var cases := [[&"fire_burst", 2.0], [&"fire_ring", 4.0], [&"fire_whip", 5.0], [&"lightning", 10.0], [&"inferno", 3.0]]
	for c: Array in cases:
		var id: StringName = c[0]
		var e := _caster(Combat.Team.ENEMY, Vector3(0, 0, -float(c[1])), Vector3.ZERO)
		e.ctx.aim_provider = func() -> Dictionary: return {"direction": (BendingContext.target_point(p) - e.ctx.hands_pos()).normalized(), "target": p, "point": BendingContext.target_point(p)}
		await _settle()
		var slot := &"signature" if id == &"inferno" else &"technique_1"
		e.set_slot(slot, AbilityRegistry.get_def(id))
		p.health.revive(1.0)
		await PlayerSim.step_until(p, func() -> bool: return p.get_state() == PlayerCharacter.State.LOCOMOTION, 300)
		p.teleport(Transform3D(Basis.IDENTITY, Vector3.ZERO))
		# Real physics frames: the broadphase must see the teleported body.
		await _settle()
		var hp0 := p.health.health
		var landed := [false]
		var seen: Array = []
		var cb := func(hit: HitInfo, t: Node, r: int) -> void:
			if t == p:
				seen.append("%s:%d" % [hit.ability_id, r])
			if t == p and hit.ability_id == id and (r == Combat.Result.HIT or r == Combat.Result.KILLED):
				landed[0] = true
		Events.hit_landed.connect(cb)
		expect_eq(e.request(slot), &"", "enemy %s starts" % id)
		var f := 0
		while e.is_busy() and f < 400:
			await _run([e], 1, p)
			f += 1
		Events.hit_landed.disconnect(cb)
		print("    AI %s vs player (state %s, at %s): %s" % [id, p.get_state_name(), str(p.global_position), str(seen)])
		expect(not e.is_busy(), "enemy %s ends without input release (%d frames)" % [id, f])
		expect(landed[0] and p.health.health < hp0, "enemy %s hit the player" % id)
		e.ctx.caster.queue_free()
		await PlayerSim.step(p, 90)
	# The enemies module's tuned copies work with the new techniques too.
	var v := EnemyAbilities.variant(&"fire_burst")
	expect(v != null and v.id == &"enemy_fire_burst" and v.script_path != "", "EnemyAbilities.variant(fire_burst)")


# --- burn ------------------------------------------------------------------------------------------

func test_burn_damage_over_time_and_water_douses() -> void:
	FireStatus.ensure()
	await frames(2)
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	var d := _dummy(Vector3(0, 0, -2.0))
	await _settle()
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var r := BendingHits.sphere(bc.ctx, Vector3(0, 1, -2), 1.0, {"damage": 10.0, "status": {"burn": 3.0}}, HitInfo.new_attack_id(), &"test_fire")
	expect_eq(BendingHits.count_landed(r), 1, "the fire hit landed")
	expect(FireStatus.is_burning(d), "the target is alight")
	var dmg0 := d.damage_taken
	var ticks0 := FireStatus.ticks_applied
	await _run([bc], 120)
	expect(FireStatus.ticks_applied - ticks0 >= 2, "burn ticks applied (%d)" % (FireStatus.ticks_applied - ticks0))
	expect(d.damage_taken > dmg0 + 3.0, "burn damage over time (%.1f)" % (d.damage_taken - dmg0))
	expect_eq(ImpactFx.hits_shown - shown0, BendingHits.applied_hits - applied0, "every applied burn tick shows a flare (and only those)")
	# Water puts it out.
	var water := BendingContext.new(bc.ctx.caster, null, E.WATER, Combat.Team.PLAYER)
	BendingHits.sphere(water, Vector3(0, 1, -2), 1.0, {"damage": 1.0, "status": {"soaked": 2.0}}, HitInfo.new_attack_id(), &"test_water")
	expect(not FireStatus.is_burning(d), "a water hit douses the flames")
	# Light jabs only scorch (no burn below MIN_BURN).
	BendingHits.sphere(bc.ctx, Vector3(0, 1, -2), 1.0, {"damage": 2.0, "status": {"burn": 1.5}}, HitInfo.new_attack_id(), &"test_jab")
	expect(not FireStatus.is_burning(d), "a jab does not set it alight")


# --- environment -----------------------------------------------------------------------------------

func test_braziers_ignite_and_any_water_or_wind_hit_puts_them_out() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	var b := FireBrazier.new()
	add_child(b)
	b.global_position = Vector3(0, 0, -6)
	var torch := FireBrazier.new()
	torch.kind = &"torch"
	add_child(torch)
	torch.global_position = Vector3(0, 0, -12)
	await _settle()
	var lit := [0]
	b.ignited.connect(func(_by: Node) -> void: lit[0] += 1)
	expect(not b.is_burning(), "starts unlit")
	FireEnv.heat(bc.ctx, b.flame_point(), 1.0, 1.0, {"ground": false})
	expect(b.is_burning() and lit[0] == 1, "fire reaching it lights it (ignite hook)")
	# Any element's hits through the proxy: water douses, a gust blows it out, fire relights.
	var water := BendingContext.new(bc.ctx.caster, null, E.WATER, Combat.Team.PLAYER)
	BendingHits.sphere(water, b.flame_point(), 0.8, {"damage": 5.0}, HitInfo.new_attack_id(), &"test_water")
	expect(not b.is_burning(), "a water hit puts it out")
	BendingHits.sphere(bc.ctx, b.flame_point(), 0.8, {"damage": 5.0}, HitInfo.new_attack_id(), &"test_fire")
	expect(b.is_burning(), "a fire hit lights it")
	var air := BendingContext.new(bc.ctx.caster, null, E.AIR, Combat.Team.PLAYER)
	BendingHits.sphere(air, b.flame_point(), 0.8, {"damage": 5.0, "force": 1.0}, HitInfo.new_attack_id(), &"test_breeze")
	expect(b.is_burning(), "a light breeze does not")
	BendingHits.sphere(air, b.flame_point(), 0.8, {"damage": 5.0, "force": 8.0}, HitInfo.new_attack_id(), &"test_gust")
	expect(not b.is_burning(), "a strong gust blows it out")
	# Fire bolts through the proxy light it and fly on (the proxy is not a target).
	var p := BendingProjectile.launch(bc.ctx, Vector3(0, torch.flame_point().y, -2), Vector3(0, 0, -1), 30.0, {"damage": 5.0}, {"radius": 0.25, "range": 30.0})
	for i in 40:
		await _run([bc], 1)
	expect(torch.is_burning(), "a fire bolt through the torch lit it")
	expect(p.traveled > 11.0, "and flew on (%.1f m)" % p.traveled)
	# Shared extinguish contract (WaterEnv / FireEnv.extinguish).
	expect_eq(FireEnv.extinguish(self, torch.flame_point(), 1.0), 1, "FireEnv.extinguish puts it out")
	expect(torch.hook.is_in_group(&"extinguishable") and torch.hook.is_in_group(&"ignitable"), "hook groups (on the flame)")
	# Hits on the proxy never count as hits.
	expect(b.proxy.receive_hit(bc.ctx.make_hit({"damage": 9.0}, Vector3.FORWARD)) == Combat.Result.IGNORED, "proxy ignores damage")


func test_grass_fire_spreads_within_budget_and_burns_out() -> void:
	GroundSampler.add_zone(&"field", Rect2(-20, -20, 40, 40), &"grass", 0.0)
	var bc := _caster(Combat.Team.PLAYER, Vector3(-18, 0, -18), Vector3.ZERO)
	await _settle()
	var lit0 := GrassFire.cells_lit
	var res := FireEnv.heat(bc.ctx, Vector3(0, 0.3, 0), 1.0, 1.0)
	expect_eq(res["ground"], &"grass", "dry grass caught")
	expect(GrassFire.burning_count() >= 1, "a cell burns")
	var peak := 0
	for i in 60 * 12:
		await _run([bc], 1)
		peak = maxi(peak, GrassFire.burning_count())
		if i % 60 == 0 and peak > GrassFire.max_cells():
			break
	var lit := GrassFire.cells_lit - lit0
	expect(lit > 1, "it spread (%d cells)" % lit)
	expect(lit <= GrassFire.PER_FIRE, "one fire never exceeds its budget (%d <= %d)" % [lit, GrassFire.PER_FIRE])
	expect(peak <= GrassFire.max_cells(), "never more than %d cells at once (%d)" % [GrassFire.max_cells(), peak])
	expect_eq(GrassFire.burning_count(), 0, "it burns out")
	# Burnt ground does not catch again right away.
	FireEnv.heat(bc.ctx, Vector3(0, 0.3, 0), 1.0, 1.0)
	expect_eq(GrassFire.burning_count(), 0, "burnt ground does not re-ignite")
	# Elsewhere: water / wind put cells out; rain stops fires starting.
	FireEnv.heat(bc.ctx, Vector3(10, 0.3, 10), 1.0, 1.0)
	expect(GrassFire.burning_count() >= 1, "a new fire")
	var out := FireEnv.extinguish(self, Vector3(10, 0, 10), 4.0)
	expect(out >= 1 and GrassFire.burning_count() == 0, "extinguished (%d)" % out)
	FireEnv.force_wet = true
	FireEnv.heat(bc.ctx, Vector3(-10, 0.3, 10), 1.0, 1.0)
	expect_eq(GrassFire.burning_count(), 0, "nothing catches in the rain")
	FireEnv.force_wet = false
	# Off the grass (the arena's stone courtyard: no zone, flat world) nothing burns.
	GroundSampler.clear_zones()
	var marks0 := FireMarks.spawned
	FireEnv.heat(bc.ctx, Vector3(30, 0.3, 30), 1.0, 1.0)
	expect_eq(GrassFire.burning_count(), 0, "no grass, no fire")
	expect(FireMarks.spawned > marks0, "but a burn mark")


func test_snow_steams_and_ice_melts() -> void:
	GroundSampler.add_zone(&"snowfield", Rect2(-6, -6, 12, 12), &"snow", 0.4)
	var bc := _caster(Combat.Team.PLAYER, Vector3(0, 0, 3), Vector3(0, 0, -10))
	var water := _caster(Combat.Team.ENEMY, Vector3(0, 0, -12), Vector3.ZERO)
	await _settle()
	var steam0 := FireEnv.steamed
	var res := FireEnv.heat(bc.ctx, Vector3(0, 0.3, 0), 1.2, 1.0)
	expect_eq(res["ground"], &"snow", "snow underfoot")
	expect(FireEnv.steamed > steam0, "the snow steams")
	var wall := BendingConstruct.raise(water.ctx, Vector3(0, 0, -8), Vector3(0, 0, 1), {"kind": &"ice", "size": Vector3(3, 2.4, 0.8), "hp": 300.0, "lifetime": 30.0, "rise_time": 0.05})
	await _run([], 10)
	var hp0 := wall.hp
	FireEnv.heat(bc.ctx, Vector3(0, 1.2, -7.4), 1.0, 1.0)
	expect(wall.hp < hp0, "fire melts the ice wall (%.0f -> %.0f)" % [hp0, wall.hp])
	expect(wall.mesh_i.scale.y < 1.0, "it sags as it melts")


# --- parity + latency ------------------------------------------------------------------------------

func test_hit_vfx_parity_and_latency_report() -> void:
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var dummies: Array[TrainingDummy] = []
	var x := -40.0
	for id: StringName in [&"fire_burst", &"fire_ring", &"fire_whip", &"jet_step", &"lightning", &"flame_sweep"]:
		var bc := _caster(Combat.Team.PLAYER, Vector3(x, 0, 0), Vector3(x, 0, -10))
		dummies.append(_dummy(Vector3(x, 0, -2.4)))
		dummies.append(_dummy(Vector3(x + 1.0, 0, -4.5), true, Vector3(x, 0, 0)))
		await _settle()
		bc.set_slot(&"technique_1", AbilityRegistry.get_def(id))
		bc.request(&"technique_1")
		await _run([bc], 100 if id == &"lightning" else 3)
		bc.release(&"technique_1")
		await _until_idle(bc, 300)
		x += 16.0
	await _run([], 240)
	var landed := 0
	for d in dummies:
		for r in d.results:
			if r == Combat.Result.HIT or r == Combat.Result.KILLED:
				landed += 1
	var shown := ImpactFx.hits_shown - shown0
	var applied := BendingHits.applied_hits - applied0
	print("    fire hits: %d landed (incl. burn ticks), %d hit VFX shown" % [landed, shown])
	expect(landed >= 8, "the techniques landed (%d)" % landed)
	expect_eq(applied, landed, "every landed hit was applied")
	expect_eq(shown, applied, "hit VFX shown exactly for applied hits")
	# Press -> active latency with the simulated player.
	var p := PlayerSim.player(self, E.FIRE, Vector3(60, 0, 0))
	await PlayerSim.step(p, 5)
	var report := []
	var n: int = (p.controller.get_slot_def(&"light").params["steps"] as Array).size()
	var lat: Array[int] = []
	for i in n:
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy() or (p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain()), 90)
		p.input.press(&"attack_light")
		var before := p.controller.current
		var before_step := (before as ComboAbility).step if before is ComboAbility else -1
		var frames_n := 0
		for k in 30:
			await PlayerSim.step(p, 1)
			frames_n += 1
			var cur := p.controller.current as ComboAbility
			if cur != null and cur.struck and (cur != before or cur.step != before_step):
				break
		p.input.release(&"attack_light")
		lat.append(frames_n)
	report.append("light %s" % str(lat))
	for f in lat:
		expect(f <= 6, "every light strike <= 6 frames: %s" % str(lat))
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	for id: StringName in [&"fire_burst", &"fire_ring", &"fire_whip", &"jet_step", &"lightning"]:
		p.controller.set_slot(&"technique_1", AbilityRegistry.get_def(id))
		p.controller.reset_cooldowns()
		p.resources.chi = 100.0
		var fr := await _press_to_active(p, id)
		report.append("%s %d" % [id, fr])
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 400)
		await PlayerSim.step_until(p, func() -> bool: return p.motor.on_floor, 300)
		await PlayerSim.step(p, 20)
	print("    fire latency (frames @60Hz, press -> active): ", ", ".join(report))


## Frames from pressing a technique to its gameplay moment (release / impact / takeoff event).
func _press_to_active(p: PlayerCharacter, id: StringName) -> int:
	p.input.press(&"ability_1")
	var f := 0
	var fired := [false]
	var cb := func(_c: StringName, ev: StringName) -> void:
		if ev in [&"release", &"impact", &"takeoff"]:
			fired[0] = true
	p.visual.rig.action_event.connect(cb)
	for i in 200:
		await PlayerSim.step(p, 1)
		f += 1
		if id != &"lightning" and i == 3:
			p.input.release(&"ability_1")
		if id == &"lightning" and f >= 100:
			p.input.release(&"ability_1")
		if fired[0]:
			break
	p.visual.rig.action_event.disconnect(cb)
	p.input.release(&"ability_1")
	return f
