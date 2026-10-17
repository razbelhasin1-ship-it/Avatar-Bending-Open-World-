extends TestCase
## Air bending (docs/modules/bending_air.md): kit + technique tree + unlock rules,
## starters, every technique on rig-less casters and the simulated player (costs,
## cooldowns, one hit per attack id, hits when the wind arrives, AI casters), Air Push
## front timing / knockdown / projectile scatter / charge, Wind Blade pierce, Air
## Scooter ride (speed, carving, wall run, water, jump off, re-press, no attacks, chi),
## Air Tornado pull -> lift -> release, Vortex Ward catch + fling, aerial hang time,
## Gale Drop, air dash budget + perfect dodge counter, the environment hooks (wind
## impulses, extinguish, wind_reactive, physics props, landing cushion) and "a hit
## VFX is shown <=> damage was applied". Prints measured latencies.

const E := ElementDefs.Element
const R := HitInfo.Reaction
const DT := 1.0 / 60.0
var _ground: StaticBody3D

const AIR_IDS: Array[StringName] = [&"air_combo", &"air_blast", &"air_shield", &"air_dash", &"air_push", &"air_sweep",
		&"wind_blade", &"air_scooter", &"vortex_ward", &"air_tornado"]


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	GameState.reset()
	_ground = PlayerSim.ground(self)


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	GameState.reset()
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


## A fire the wind can blow out (the shared EXTINGUISH hook).
class Torch extends Node3D:
	var lit := true
	var extinguish_radius := 0.3

	func _ready() -> void:
		add_to_group(&"extinguishable")

	func extinguish(_by: Node, _at: Vector3) -> bool:
		if not lit:
			return false
		lit = false
		return true


## Anything that wants to feel the wind (the wind_reactive hook).
class Chime extends Node3D:
	var pushes: Array[Vector3] = []

	func _ready() -> void:
		add_to_group(&"wind_reactive")

	func wind(impulse: Vector3, _at: Vector3, _by: Node) -> void:
		pushes.append(impulse)


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
	var ctx := BendingContext.new(b, null, E.AIR, team)
	if pool:
		ctx.resources = Pool.new()
	ctx.aim_provider = func() -> Dictionary:
		var f := ctx.forward()
		return {"direction": f, "target": null, "point": ctx.origin() + Vector3.UP * 1.2 + f * 30.0}
	var bc := BendingController.new()
	b.add_child(bc)
	bc.setup(ctx)
	return bc


func _dummy(pos: Vector3, humanoid: bool = false, guarding: bool = false, face: Vector3 = Vector3.INF) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.look = &"humanoid" if humanoid else &"post"
	d.guarding = guarding
	d.max_health = 5000.0
	add_child(d)
	d.global_position = pos
	if face.is_finite():
		d.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP)
	d.home = d.global_transform
	d.set_meta(&"log", [])
	d.hit_received.connect(func(hit: HitInfo, result: int) -> void:
		(d.get_meta(&"log") as Array).append([hit, result]))
	return d


func _hits(d: TrainingDummy, id: StringName = &"") -> Array:
	var out: Array = []
	for e: Array in d.get_meta(&"log", []):
		var h: HitInfo = e[0]
		if id == &"" or h.ability_id == id:
			out.append(e)
	return out


## Steps controllers, the player, projectiles and `extra` nodes by fixed ticks.
func _run(bcs: Array, frames_n: int, player: PlayerCharacter = null, extra: Array = []) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in frames_n:
		for bc: BendingController in bcs:
			if is_instance_valid(bc):
				bc.tick(DT)
		PlayerSim.step_once(player, extra)


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _until_idle(bc: BendingController, max_frames: int = 400, player: PlayerCharacter = null, extra: Array = []) -> int:
	var f := 0
	while bc.is_busy() and f < max_frames:
		await _run([bc], 1, player, extra)
		f += 1
	return f


func _player(pos: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var p := PlayerSim.player(self, E.AIR, pos)
	await PlayerSim.step(p, 3)
	return p


# --- kit + tree ------------------------------------------------------------------------------------

func test_kit_tree_and_unlocks() -> void:
	AirClips.ensure()
	for id in AIR_IDS:
		var d := AbilityRegistry.get_def(id)
		if not expect(d != null, "%s registered" % id):
			continue
		expect(d.element == E.AIR and d.display_name != "" and d.description.length() > 40, "%s has name + description" % id)
		expect(ResourceLoader.exists(d.script_path), "%s script exists" % id)
		expect(d.icon != "" and ResourceLoader.exists(d.icon), "%s icon exists (%s)" % [id, d.icon])
		if d.clip != &"":
			expect(AnimLibrary.get_clip(d.clip) != null, "%s clip %s registered" % [id, d.clip])
	for c: StringName in [&"air_push_gather", &"air_push_release", &"air_scooter_ride", &"air_combo_kick", &"wind_blade_kick", &"wind_blade_air",
			&"air_tornado_cast", &"air_dive", &"air_slam_land", &"vortex_ward_hold"]:
		var clip := AnimLibrary.get_clip(c)
		expect(clip != null, "clip %s" % c)
	expect(AnimLibrary.get_clip(&"air_push_release").event_time(&"release") > 0.0, "push release event")
	expect(AnimLibrary.get_clip(&"air_tornado_cast").event_time(&"impact") > AnimLibrary.get_clip(&"air_tornado_cast").event_time(&"release"), "tornado forms before it bursts")
	expect_eq(AbilityRegistry.starter_techniques(E.AIR), [&"air_push", &"air_sweep"] as Array[StringName], "two starters, alphabetical")
	# Tree data for the skill-tree UI.
	var tree := AirKit.tree()
	expect_eq(tree.size(), 6, "6 techniques in the tree")
	var by_id := {}
	for n: Dictionary in tree:
		by_id[n["id"]] = n
		for k: String in ["id", "tier", "branch", "column", "requires", "level", "practice", "trainer", "cost", "starter", "signature"]:
			expect(n.has(k), "tree node has %s" % k)
	for i in range(1, tree.size()):
		expect(int(tree[i]["tier"]) >= int(tree[i - 1]["tier"]), "tree sorted by tier")
	expect(bool(by_id[&"air_tornado"]["signature"]) and int(by_id[&"air_tornado"]["tier"]) == 4, "tornado is the tier-4 signature")
	expect_eq(by_id[&"wind_blade"]["requires"], &"air_push", "blade grows from push")
	expect_eq(by_id[&"air_scooter"]["requires"], &"air_sweep", "scooter grows from the sweep")
	expect_eq(by_id[&"vortex_ward"]["trainer"], &"at_tashi", "Master Tashi teaches the ward")
	expect(AirKit.TRAINERS.has(&"at_tashi"), "trainer published")
	# Unlock chain: level -> prerequisite -> practice -> trainer -> skill points.
	GameState.reset()
	GameState.element = E.AIR
	var granted := AbilityRegistry.grant_starters(E.AIR)
	expect(granted.has(&"air_push") and granted.has(&"air_sweep"), "new game grants push + sweep")
	expect_eq(GameState.equipped_abilities[0], &"air_push", "push in slot 1")
	expect_eq(GameState.equipped_abilities[1], &"air_sweep", "sweep in slot 2")
	expect_eq(AbilityRegistry.can_unlock(&"wind_blade"), &"level", "blade: level gate")
	GameState.level = 3
	expect_eq(AbilityRegistry.can_unlock(&"wind_blade"), &"practice", "blade: practice the push")
	GameState.add_practice(&"air_push", 6)
	expect_eq(AbilityRegistry.can_unlock(&"wind_blade"), &"skill_points", "blade: needs a point")
	GameState.skill_points = 1
	expect_eq(AbilityRegistry.can_unlock(&"wind_blade"), &"", "blade unlockable")
	GameState.level = 7
	GameState.skill_points = 5
	expect_eq(AbilityRegistry.can_unlock(&"air_tornado"), &"prerequisite", "tornado needs the blade")
	GameState.unlock_ability(&"wind_blade")
	expect_eq(AbilityRegistry.can_unlock(&"air_tornado"), &"trainer", "tornado needs Master Tashi")
	GameState.set_flag("trained_at_tashi_air_tornado", true)
	expect_eq(AbilityRegistry.can_unlock(&"air_tornado"), &"", "tornado unlockable after the lesson")
	GameState.reset()


func test_practice_counts_player_casts_only() -> void:
	var bc := _caster(Combat.Team.ENEMY, Vector3(0, 0, 0))
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"air_push"))
	await _settle()
	bc.request(&"technique_1")
	await _until_idle(bc)
	expect_eq(int(GameState.ability_practice.get("air_push", 0)), 0, "enemy casts never count as practice")
	var p := await _player(Vector3(20, 0, 0))
	await PlayerSim.tap(p, &"ability_1", 2)
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	expect_eq(int(GameState.ability_practice.get("air_push", 0)), 1, "the player's push counts once")


# --- techniques on rig-less casters -----------------------------------------------------------------

func test_every_technique_hits_once_and_ends() -> void:
	var cases := [[&"air_push", Vector3(0, 0, -1.8)], [&"air_sweep", Vector3(0, 0, -2.0)], [&"wind_blade", Vector3(0, 0, -8.0)],
		[&"vortex_ward", Vector3(0, 0, -1.6)], [&"air_tornado", Vector3(0, 0, -6.0)]]
	var x := -40.0
	for c: Array in cases:
		var id: StringName = c[0]
		x += 16.0
		var bc := _caster(Combat.Team.PLAYER, Vector3(x, 0, 0), Vector3(x, 0, -10), true)
		var d := _dummy(Vector3(x, 0, 0) + (c[1] as Vector3))
		var slot := &"signature" if id == &"air_tornado" else &"technique_1"
		bc.set_slot(slot, AbilityRegistry.get_def(id))
		await _settle()
		var pool: Pool = bc.ctx.resources
		var chi0 := pool.chi
		expect_eq(bc.request(slot), &"", "%s starts" % id)
		await _run([bc], 2)
		bc.release(slot)
		var f := await _until_idle(bc, 400)
		expect(not bc.is_busy(), "%s ends (%d frames)" % [id, f])
		var hits := _hits(d, id)
		expect(hits.size() >= 1, "%s hit the dummy (%d)" % [id, hits.size()])
		var ids := {}
		for e: Array in hits:
			var h: HitInfo = e[0]
			expect(not ids.has(h.attack_id), "%s: one hit per attack id" % id)
			ids[h.attack_id] = true
		var d_def := AbilityRegistry.get_def(id)
		if d_def.chi_cost > 0.0:
			expect(pool.chi <= chi0 - d_def.chi_cost + 0.01, "%s spent its chi (%.1f -> %.1f)" % [id, chi0, pool.chi])
		if d_def.cooldown > 0.0:
			expect(bc.cooldown_left(id) > 0.0, "%s cooling down" % id)
			expect_eq(bc.request(slot), &"cooldown", "%s refused on cooldown" % id)
		if d_def.focus_cost > 0.0:
			expect(pool.focus < 1.0, "%s spent the focus" % id)


func test_air_push_front_close_knockdown_far_knockback_and_scatters_projectiles() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"air_push"))
	var close := _dummy(Vector3(0, 0, -1.5))
	var far := _dummy(Vector3(3.6, 0, 1.0))
	var beyond := _dummy(Vector3(0, 0, 7.0))
	await _settle()
	# An enemy bolt flying in from the side.
	var ectx := BendingContext.new(beyond, null, E.FIRE, Combat.Team.ENEMY)
	var bolt := BendingProjectile.launch(ectx, Vector3(-3.0, 1.0, 0.0), Vector3.RIGHT, 6.0, {"damage": 10.0, "projectile": true}, {"radius": 0.2})
	bc.request(&"technique_1")
	bc.release(&"technique_1")
	var f_close := -1
	var f_far := -1
	for i in 120:
		await _run([bc], 1)
		if f_close < 0 and not _hits(close).is_empty():
			f_close = i
		if f_far < 0 and not _hits(far).is_empty():
			f_far = i
	expect(f_close >= 0 and f_far >= 0, "both in reach were hit (%d / %d)" % [f_close, f_far])
	expect(f_far > f_close, "the far one is hit later: when the front reaches it (%d > %d)" % [f_far, f_close])
	expect(_hits(beyond).is_empty(), "beyond the ring: untouched")
	if not _hits(close).is_empty() and not _hits(far).is_empty():
		expect_eq(int((_hits(close)[0][0] as HitInfo).reaction), R.KNOCKDOWN, "close: knocked down")
		expect_eq(int((_hits(far)[0][0] as HitInfo).reaction), R.KNOCKBACK, "far: blown back")
		expect(((_hits(far)[0][0] as HitInfo).direction).dot(Vector3(3.6, 0, 1.0).normalized()) > 0.9, "pushed radially away")
	expect(not bolt.alive or bolt.team == Combat.Team.PLAYER, "the enemy bolt was scattered (now the bender's)")


func test_air_push_charge_widens_the_ring() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	# Non-player casters push after params.ai_hold: a long one lets the test hold the charge.
	var def := AbilityRegistry.get_def(&"air_push").duplicate() as AbilityDef
	def.params = def.params.duplicate(true)
	def.params["ai_hold"] = 3.0
	bc.set_slot(&"technique_1", def)
	var d := _dummy(Vector3(0, 0, -6.0))
	await _settle()
	bc.request(&"technique_1")
	await _run([bc], 2)
	bc.release(&"technique_1")
	await _until_idle(bc)
	expect(_hits(d).is_empty(), "a tapped push does not reach 6 m")
	bc.reset_cooldowns()
	BendingHits.clear_log()
	bc.request(&"technique_1")
	await _run([bc], 70)
	var pool: Pool = bc.ctx.resources
	bc.release(&"technique_1")
	await _until_idle(bc)
	expect(_hits(d).size() == 1, "a charged push reaches 6 m (%d)" % _hits(d).size())
	if not _hits(d).is_empty():
		expect((_hits(d)[0][0] as HitInfo).damage > 8.0, "charged: more damage")
	expect(pool.chi < 100.0 - 16.0 - 5.0, "the charge spent extra chi (%.1f)" % pool.chi)


func test_wind_blade_pierces_every_target_once() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"wind_blade"))
	var line: Array[TrainingDummy] = [_dummy(Vector3(0, 0, -5)), _dummy(Vector3(0.9, 0, -9)), _dummy(Vector3(-0.9, 0, -13))]
	var aside := _dummy(Vector3(4.5, 0, -8))
	await _settle()
	bc.request(&"technique_1")
	await _until_idle(bc)
	await _run([bc], 50)
	for d in line:
		expect_eq(_hits(d, &"wind_blade").size(), 1, "blade hit %s exactly once" % d.name)
	expect(_hits(aside).is_empty(), "outside the blade's width: untouched")
	var h: HitInfo = _hits(line[0])[0][0] if not _hits(line[0]).is_empty() else null
	expect(h != null and h.is_projectile and h.deflectable, "the blade is a (deflectable) projectile hit")


func test_tornado_pulls_lifts_and_flings() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	bc.set_slot(&"signature", AbilityRegistry.get_def(&"air_tornado"))
	var near := _dummy(Vector3(0.6, 0, -6.4), true)
	var mid := _dummy(Vector3(3.5, 0, -7.5), true)
	await _settle()
	var x0 := mid.global_position
	expect_eq(bc.request(&"signature"), &"", "tornado cast")
	var top := 0.0
	var pulled := false
	var cur := bc.current
	for i in 220:
		await _run([bc], 1, null, [near, mid])
		top = maxf(top, near.global_position.y)
		var flat := mid.global_position - Vector3(0, 0, -6.0)
		flat.y = 0.0
		if flat.length() < (x0 - Vector3(0, 0, -6.0)).length() - 0.6:
			pulled = true
		if not bc.is_busy():
			break
	var tor = cur
	expect(top > 2.5, "the close dummy was lifted up the column (%.2f m)" % top)
	expect(pulled or _hits(mid).size() >= 2, "the outer dummy was dragged in (pulses %d)" % _hits(mid).size())
	var flung := false
	for e: Array in _hits(near, &"air_tornado"):
		var h: HitInfo = e[0]
		if h.reaction == R.LAUNCH and h.damage >= 20.0:
			flung = true
	expect(flung, "released: flung out (LAUNCH, heavy damage)")
	expect(tor != null and (tor.get("blown") == true), "the tornado burst on its impact event")
	var ids := {}
	for e: Array in _hits(near):
		var h2: HitInfo = e[0]
		expect(not ids.has(h2.attack_id), "one hit per pulse id")
		ids[h2.attack_id] = true


func test_vortex_ward_catches_projectiles_and_flings_them_back() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"vortex_ward"))
	var foe := _dummy(Vector3(0, 0, -9))
	await _settle()
	bc.request(&"technique_1")
	await _run([bc], 10)
	# A bolt from BEHIND the bender (any side is covered).
	var ectx := BendingContext.new(foe, null, E.FIRE, Combat.Team.ENEMY)
	var bolt := BendingProjectile.launch(ectx, Vector3(0, 1.0, 6.0), Vector3(0, 0, -1), 14.0, {"damage": 12.0, "projectile": true}, {"radius": 0.2})
	for i in 40:
		await _run([bc], 1)
	expect(bolt.alive and bolt.team == Combat.Team.PLAYER, "caught: the bolt now belongs to the ward")
	expect(bolt.global_position.distance_to(Vector3(0, 0.95, 0)) < 3.0, "it whirls around the bender")
	var ward = bc.current
	expect(ward != null and (ward.get("held") as Array).size() == 1, "held by the ward")
	# Re-press bursts the ward early: the bolt is flung at the foe.
	bc.request(&"technique_1")
	for i in 60:
		await _run([bc], 1)
	expect(not _hits(foe).is_empty(), "the flung bolt hit the foe")
	expect(not bc.is_busy(), "ward over")


# --- the simulated player ----------------------------------------------------------------------------

func test_scooter_rides_fast_wall_runs_and_jumps_off() -> void:
	var p := await _player(Vector3(0, 0, 40))
	p.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"air_scooter"))
	var wall := PlayerSim.box(self, Vector3(0, 6, -10), Vector3(20, 12, 1))
	await _settle()
	p.input.press(&"move_forward")
	await PlayerSim.tap(p, &"ability_3", 2)
	expect(p.controller.current != null and p.controller.current.def.id == &"air_scooter", "riding")
	var top := 0.0
	for i in 70:
		await PlayerSim.step(p, 1)
		top = maxf(top, Vector2(p.velocity.x, p.velocity.z).length())
	expect(top > 15.0, "scooter speed > 15 m/s (%.1f; sprint is 11.5)" % top)
	# Attacks are refused while riding.
	await PlayerSim.tap(p, &"attack_light", 2)
	expect(p.controller.current != null and p.controller.current.def.id == &"air_scooter", "no attacks while riding")
	# Ride into the wall: it runs up it.
	var y0 := p.global_position.y
	var max_y := y0
	var walled := false
	for i in 160:
		await PlayerSim.step(p, 1)
		max_y = maxf(max_y, p.global_position.y)
		var sc = p.controller.current
		if sc != null and sc.def.id == &"air_scooter" and int(sc.get("phase")) == 1:
			walled = true
		if not p.controller.is_busy():
			break
	expect(walled, "wall run started")
	expect(max_y - y0 > 3.0, "ran up the wall (%.2f m)" % (max_y - y0))
	p.input.release(&"move_forward")
	wall.queue_free()
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor() and not p.controller.is_busy(), 300)
	# Ride again, then jump off with the momentum.
	p.controller.reset_cooldowns()
	p.input.press(&"move_back")
	await PlayerSim.tap(p, &"ability_3", 2)
	await PlayerSim.step(p, 50)
	var ride = p.controller.current
	await PlayerSim.tap(p, &"jump", 2)
	expect(ride != null and ride.get("end_reason") == &"jump", "jumped off")
	expect(p.velocity.y > 5.0 and Vector2(p.velocity.x, p.velocity.z).length() > 8.0, "launch keeps the ride's momentum (vy %.1f)" % p.velocity.y)
	p.input.release(&"move_back")
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor(), 300)
	# Press again to hop down.
	p.controller.reset_cooldowns()
	await PlayerSim.tap(p, &"ability_3", 2)
	await PlayerSim.step(p, 30)
	await PlayerSim.tap(p, &"ability_3", 2)
	await PlayerSim.step(p, 20)
	expect(not p.controller.is_busy(), "re-press hops down")
	expect(p.visual.rig.position.y < 0.05, "rig back on its feet")


func test_scooter_skims_water_and_drains_chi() -> void:
	# Dry ground up to z = -6, then a 3 m deep pool (sea level water over it).
	WorldData.height_override = func(_x: float, z: float) -> float: return -3.0 if z < -6.0 else 0.0
	_ground.position.z = 194.0
	PlayerSim.box(self, Vector3(0, -3.5, -40), Vector3(40, 1, 68))
	var p := await _player(Vector3(0, 0, 0))
	p.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"air_scooter"))
	await _settle()
	var chi0 := p.resources.chi
	p.input.press(&"move_forward")
	await PlayerSim.tap(p, &"ability_3", 2)
	var over_water := 0
	var lowest := 0.0
	for i in 120:
		await PlayerSim.step(p, 1)
		if p.global_position.z < -8.0:
			over_water += 1
			lowest = minf(lowest, p.global_position.y)
	expect(over_water > 30, "rode out over the water (%d frames)" % over_water)
	expect(lowest > -0.3 and not p.motor.swimming, "skims the surface, never sinks (lowest y %.2f)" % lowest)
	expect(p.resources.chi < chi0 - p.controller.get_slot_def(&"technique_3").chi_cost - 4.0, "chi drains while riding (%.1f)" % p.resources.chi)
	p.input.release(&"move_forward")
	p.resources.set_chi(0.0)
	await PlayerSim.step(p, 20)
	expect(not p.controller.is_busy(), "out of chi: the ball bursts")
	await PlayerSim.step(p, 120)
	expect(p.motor.swimming, "and the bender drops into the water")


func test_aerial_hang_time_and_gale_drop() -> void:
	var p := await _player(Vector3(0, 0, 0))
	await PlayerSim.tap(p, &"jump", 3)
	await PlayerSim.step_until(p, func() -> bool: return p.velocity.y <= 1.0, 120)
	var y_top := p.global_position.y
	# Three aerial strikes: the bender hangs.
	for i in 3:
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy() or (p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain()), 60)
		await PlayerSim.tap(p, &"attack_light", 2)
	await PlayerSim.step(p, 12)
	expect(p.global_position.y > y_top - 0.6, "aerial strikes hang in the air (dropped %.2f m)" % (y_top - p.global_position.y))
	# Free fall for comparison: after the budget the bender drops.
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor(), 300)
	# Gale Drop from height.
	var d := _dummy(Vector3(1.5, 0, -2.5))
	var d2 := _dummy(Vector3(0, 0, 9))
	await _settle()
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 7, 0)))
	await PlayerSim.step(p, 2)
	await PlayerSim.tap(p, &"attack_heavy", 2)
	var a = p.controller.current
	expect(a != null and bool(a.get("_dive")), "high in the air: heavy = Gale Drop")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 200)
	expect(p.is_on_floor(), "landed")
	var hits := _hits(d, &"air_blast")
	expect(hits.size() == 1 and int((hits[0][0] as HitInfo).reaction) == R.KNOCKDOWN, "the slam knocked down the dummy below (%d)" % hits.size())
	expect(_hits(d2).is_empty(), "out of the slam ring: untouched")


func test_air_dash_budget_and_perfect_dodge_counter() -> void:
	var p := await _player(Vector3(0, 0, 0))
	await PlayerSim.tap(p, &"jump", 3)
	await PlayerSim.step(p, 8)
	var dashes := 0
	for i in 3:
		p.input.press(&"move_forward")
		await PlayerSim.tap(p, &"dodge", 2)
		if p.controller.current != null and p.controller.current.def.id == &"air_dash":
			dashes += 1
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 60)
		p.input.release(&"move_forward")
	expect_eq(dashes, 2, "two air dashes per jump")
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor(), 300)
	await PlayerSim.step(p, 3)
	await PlayerSim.tap(p, &"jump", 3)
	await PlayerSim.step(p, 8)
	await PlayerSim.tap(p, &"dodge", 2)
	expect(p.controller.current != null and p.controller.current.def.id == &"air_dash", "landing refilled the air dashes")
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor() and not p.controller.is_busy(), 300)
	# Perfect dodge: an enemy strike inside the first 0.2 s is dodged and answered by a gust.
	var foe := _dummy(p.global_position + Vector3(0, 0, -1.6))
	await _settle()
	await PlayerSim.tap(p, &"dodge", 2)
	var h := HitInfo.make(10.0, foe, E.EARTH, R.STAGGER, Vector3(0, 0, 1), 4.0)
	h.team = Combat.Team.ENEMY
	h.origin = foe.global_position
	var res := Combat.deal(p, h)
	expect_eq(res, Combat.Result.DODGED, "i-frames")
	expect(not _hits(foe, &"air_dash").is_empty(), "perfect dodge: the gust knocked the attacker back")


func test_ai_casters_use_air_techniques_on_the_player() -> void:
	var p := await _player(Vector3(0, 0, -3))
	var hp0 := p.health.health
	for id: StringName in [&"air_push", &"wind_blade", &"air_tornado"]:
		var bc := _caster(Combat.Team.ENEMY, Vector3(0, 0, 3), Vector3(0, 0, -3))
		bc.ctx.aim_provider = func() -> Dictionary:
			return {"direction": (BendingContext.target_point(p) - bc.ctx.hands_pos()).normalized(), "target": p, "point": BendingContext.target_point(p)}
		var slot := &"signature" if id == &"air_tornado" else &"technique_1"
		bc.set_slot(slot, AbilityRegistry.get_def(id))
		await _settle()
		expect_eq(bc.request(slot), &"", "enemy %s starts (no player input needed)" % id)
		await _until_idle(bc, 400, p)
		expect(not bc.is_busy(), "enemy %s ends" % id)
		await PlayerSim.step_until(p, func() -> bool: return p.get_state() == PlayerCharacter.State.LOCOMOTION, 400)
		p.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0, -3)))
		await PlayerSim.step(p, 2)
		bc.ctx.caster.queue_free()
	expect(p.health.health < hp0, "the player took air damage (%.0f -> %.0f)" % [hp0, p.health.health])
	expect(AirKit.enemy_attacks().has(&"air_push") and AirKit.enemy_attacks()[&"air_push"]["kind"] == &"bending", "EnemyActions entries published")
	# AI scooter: follows its move intent, ends by itself.
	var bc2 := _caster(Combat.Team.ENEMY, Vector3(10, 0, 0))
	bc2.set_slot(&"technique_2", AbilityRegistry.get_def(&"air_scooter"))
	await _settle()
	bc2.ctx.move_input = Vector3(0, 0, -1)
	expect_eq(bc2.request(&"technique_2"), &"", "AI rides")
	var f := await _until_idle(bc2, 600)
	expect(not bc2.is_busy() and f < 60.0 * 6.5, "AI ride ends after ai_time (%d frames)" % f)


# --- environment ---------------------------------------------------------------------------------------

func test_environment_wind_fires_props_and_reactive_nodes() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"air_push"))
	var torch := Torch.new()
	add_child(torch)
	torch.global_position = Vector3(2.0, 1.0, -1.0)
	var far_torch := Torch.new()
	add_child(far_torch)
	far_torch.global_position = Vector3(20.0, 1.0, 0.0)
	var chime := Chime.new()
	add_child(chime)
	chime.global_position = Vector3(-2.0, 1.5, 1.0)
	var pot := AirProp.spawn(self, &"pot", Vector3(0, 0, 2.5))
	var crate := AirProp.spawn(self, &"crate", Vector3(-2.5, 0, -1.0))
	await physics_frames(20)
	var started := AirWindField.started
	bc.request(&"technique_1")
	bc.release(&"technique_1")
	await _until_idle(bc)
	expect(not torch.lit, "the push blew the torch out")
	expect(far_torch.lit, "out of reach: still lit")
	expect(not chime.pushes.is_empty() and chime.pushes[0].x < 0.0, "wind_reactive nodes feel the wind (pushed away)")
	expect(AirWindField.started > started, "a wind impulse went to the vegetation shaders")
	expect(AirWindField.live_count() >= 1, "impulse live in a shader slot")
	await physics_frames(6)
	var pv := pot.linear_velocity if is_instance_valid(pot) else Vector3(0, 0, 9)
	expect(not is_instance_valid(pot) or pv.z > 1.0 or pot.global_position.z > 2.7, "the pot was blown away from the push")
	expect(is_instance_valid(crate) and (crate.linear_velocity.length() > 0.5 or crate.global_position.x < -2.6), "the crate was shoved")
	# A gust passing a torch blows it out too (the travelling volume reaches the world).
	var torch2 := Torch.new()
	add_child(torch2)
	torch2.global_position = Vector3(0.0, 1.2, -6.0)
	var bc2 := _caster(Combat.Team.PLAYER, Vector3(0, 0, 0), Vector3(0, 0, -10), true)
	bc2.request(&"heavy")
	bc2.release(&"heavy")
	await _until_idle(bc2)
	await _run([bc2], 30)
	expect(not torch2.lit, "the air blast's gust blew out the torch in its path")
	# Pots shatter when blasted hard; AirEnv.blow returns what reacted.
	var pot2 := AirProp.spawn(self, &"pot", Vector3(8, 0, 0))
	await physics_frames(3)
	var broke := [false]
	pot2.shattered.connect(func(_p: AirProp) -> void: broke[0] = true)
	pot2.wind(Vector3(30, 4, 0), pot2.global_position, null)
	expect(broke[0], "a hard blast shatters a clay pot")
	var r := AirEnv.blow(bc.ctx, Vector3(-2.5, 0.5, -1.0), 2.0, 1.0)
	expect(int(r["pushed"]) >= 1, "AirEnv.blow reports pushed props")


func test_wind_field_slots_envelope_and_release() -> void:
	var n := Node3D.new()
	add_child(n)
	await frames(1)
	var id := AirWindField.add(n, Vector3.ZERO, 3.0, 20.0, AirWindField.RADIAL, Vector3.ZERO, 0.1)
	expect(id != 0, "impulse id")
	await frames(3)
	var f := AirWindField.instance(n)
	expect(f != null and f.slots.size() == AirWindField.SLOTS, "4 shader slots")
	var ids: Array[int] = [id]
	var held := AirWindField.add(n, Vector3(5, 0, 0), 2.0, 15.0, AirWindField.DIRECTIONAL, Vector3(1, 0, 0), INF)
	ids.append(held)
	for i in 6:
		ids.append(AirWindField.add(n, Vector3(i, 0, 9), 2.0, 5.0, AirWindField.RADIAL, Vector3.ZERO, 0.05))
	expect(AirWindField.live_count() <= AirWindField.SLOTS, "never more than 4 live")
	AirWindField.move(held, Vector3(6, 0, 0))
	AirWindField.release(held)
	# A held impulse whose owner is freed lets go by itself.
	var owner_node := Node3D.new()
	add_child(owner_node)
	var orphan := AirWindField.add(owner_node, Vector3(0, 0, -9), 2.0, 15.0, AirWindField.RADIAL, Vector3.ZERO, INF)
	ids.append(orphan)
	owner_node.queue_free()
	await seconds(2.4)
	var left := 0
	for i2 in ids:
		if AirWindField.strength_of(i2) != 0.0:
			left += 1
	expect_eq(left, 0, "every impulse springs back and frees its slot (owner-freed ones too)")


func test_landing_cushion_and_air_jump_press_the_grass() -> void:
	var p := await _player(Vector3(0, 0, 0))
	expect(p.get_node_or_null("AirTraversal") != null, "airbenders carry the traversal hook")
	var l0 := AirTraversal.landings
	var j0 := AirTraversal.jump_bursts
	await PlayerSim.tap(p, &"jump", 3)
	await PlayerSim.step_until(p, func() -> bool: return p.velocity.y <= 0.5, 120)
	await PlayerSim.tap(p, &"jump", 2)
	expect(AirTraversal.jump_bursts > j0, "the air jump pressed the ground cover down")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 9, 0)))
	await PlayerSim.step_until(p, func() -> bool: return p.is_on_floor(), 300)
	await PlayerSim.step(p, 2)
	expect(AirTraversal.landings > l0, "a high landing was cushioned (ring of wind)")


# --- parity + latency ------------------------------------------------------------------------------------

func test_hit_vfx_parity_and_latency_report() -> void:
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10), true)
	var ds: Array[TrainingDummy] = [_dummy(Vector3(0, 0, -2.0)), _dummy(Vector3(1.6, 0, -3.0), false, true, Vector3.ZERO), _dummy(Vector3(-1.2, 0, -6.5), true)]
	await _settle()
	for pair: Array in [[&"technique_1", &"air_push"], [&"technique_2", &"wind_blade"], [&"technique_3", &"air_sweep"], [&"signature", &"air_tornado"]]:
		bc.set_slot(pair[0], AbilityRegistry.get_def(pair[1]))
	for slot: StringName in [&"light", &"light", &"light", &"heavy", &"technique_1", &"technique_2", &"technique_3", &"signature"]:
		var f := 0
		while bc.is_busy() and not (bc.current is ComboAbility and (bc.current as ComboAbility).can_chain()) and f < 300:
			await _run([bc], 1, null, ds)
			f += 1
		bc.request(slot)
		await _run([bc], 2, null, ds)
		bc.release(slot)
	await _until_idle(bc, 400, null, ds)
	await _run([bc], 60, null, ds)
	var landed := 0
	for d in ds:
		for r in d.results:
			if r == Combat.Result.HIT or r == Combat.Result.KILLED:
				landed += 1
	var shown := ImpactFx.hits_shown - shown0
	var applied := BendingHits.applied_hits - applied0
	print("    air hits: %d landed, %d hit VFX shown" % [landed, shown])
	expect(landed >= 8, "the air attacks landed (%d)" % landed)
	expect_eq(applied, landed, "every landed hit was applied")
	expect_eq(shown, applied, "hit VFX shown exactly for applied hits")
	# Press -> active latency with the simulated player.
	var p := await _player(Vector3(30, 0, 0))
	p.controller.set_slot(&"technique_2", AbilityRegistry.get_def(&"wind_blade"))
	p.controller.set_slot(&"technique_3", AbilityRegistry.get_def(&"air_scooter"))
	var report: Array[String] = []
	var lat: Array[int] = []
	for i in 3:
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy() or (p.controller.current is ComboAbility and (p.controller.current as ComboAbility).can_chain()), 90)
		p.input.press(&"attack_light")
		var before := p.controller.current
		var before_step := (before as ComboAbility).step if before is ComboAbility else -1
		var frames_n := 0
		for k in 30:
			await PlayerSim.step(p, 1)
			frames_n += 1
			var c := p.controller.current as ComboAbility
			if c != null and c.struck and (c != before or c.step != before_step):
				break
		p.input.release(&"attack_light")
		lat.append(frames_n)
	report.append("combo %s" % str(lat))
	for f2 in lat:
		expect(f2 <= 6, "every light strike active within 6 frames: %s" % str(lat))
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	report.append("push %d" % await _press_to(p, &"ability_1", func(a: BendingAbility) -> bool: return a is ChargeAbility and (a as ChargeAbility).released))
	report.append("blade %d" % await _press_to(p, &"ability_2", func(a: BendingAbility) -> bool: return bool(a.get("_fired"))))
	report.append("scooter %d" % await _press_to(p, &"ability_3", func(a: BendingAbility) -> bool: return Vector2(p.velocity.x, p.velocity.z).length() > 5.0, true))
	print("    air latency (frames @60Hz, press -> active): ", ", ".join(report))


func _press_to(p: PlayerCharacter, action: StringName, cond: Callable, tap: bool = true) -> int:
	p.controller.reset_cooldowns()
	p.resources.set_chi(100.0)
	p.input.press(action)
	var n := 0
	var seen := false
	for k in 90:
		await PlayerSim.step(p, 1)
		n += 1
		if tap and k == 1:
			p.input.release(action)
		var a := p.controller.current
		if a != null and cond.call(a):
			seen = true
			break
	p.input.release(action)
	expect(seen, "%s reached its active moment" % action)
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 200)
	if p.controller.is_busy():
		p.controller.cancel_current(&"test")
	return n
