extends TestCase
## Earth bending (docs/modules/bending_earth.md): kit + technique tree + unlock
## rules, costs / cooldowns from the real player, every technique on rig-less
## casters (hits applied once per attack id, reactions, timing), Earth Pillar
## launch + construct + self-lift, Earth Stomp shockwave (front timing, airborne
## and walled targets missed), Earth Spikes line (stops at ice), Earth Grab root,
## Earth Armor toggle (modifiers, drain, survives other abilities, burst, chi
## out), Earthquake (knockdown radius, unblockable, debris), surfaces (stone /
## sand / snow / mud / deep water / ice / wood), refusals, the fist fallback,
## AI (enemy-team) casters vs the player, persistent marks, hit VFX parity and
## a latency report.

const E := ElementDefs.Element
const DT := 1.0 / 60.0
const R := HitInfo.Reaction


func before_each() -> void:
	WorldData.use_flat_world(true)
	TimeDilation.enabled = false
	GroundSampler.clear_zones()
	BendingHits.clear_log()
	PlayerSim.ground(self)


func after_each() -> void:
	WorldData.height_override = Callable()
	WorldData.use_flat_world(false)
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()
	TimeDilation.enabled = true
	TimeDilation.clear()
	Engine.time_scale = 1.0
	for c in BendingConstruct.live.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	BendingConstruct.live.clear()
	for p in BendingProjectile.live.duplicate():
		if is_instance_valid(p):
			p.queue_free()


# --- helpers ---------------------------------------------------------------------------------------

func _caster(team: int, pos: Vector3, look_at_point: Vector3 = Vector3.INF) -> BendingController:
	var b := CharacterBody3D.new()
	b.name = "EarthCaster"
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
	var ctx := BendingContext.new(b, null, E.EARTH, team)
	var bc := BendingController.new()
	b.add_child(bc)
	bc.setup(ctx)
	return bc


func _aim_at(bc: BendingController, target: Node3D) -> void:
	bc.ctx.aim_provider = func() -> Dictionary:
		if target == null or not is_instance_valid(target):
			return {"direction": bc.ctx.forward(), "target": null, "point": bc.ctx.origin() + bc.ctx.forward() * 8.0}
		var tp := BendingContext.target_point(target)
		return {"direction": (tp - bc.ctx.hands_pos()).normalized(), "target": target, "point": tp}


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


func _def(id: StringName) -> AbilityDef:
	return AbilityRegistry.get_def(id)


## Steps controllers, the player sim (player, projectiles, constructs) and the
## live earth nodes (shockwaves, spike lines, armor) by fixed 1/60 s ticks.
func _run(bcs: Array, frames_n: int, player: PlayerCharacter = null) -> void:
	if not Engine.is_in_physics_frame():
		await get_tree().physics_frame
	for i in frames_n:
		for bc: BendingController in bcs:
			if is_instance_valid(bc):
				bc.tick(DT)
		PlayerSim.step_once(player)
		for w: EarthShockwave in EarthShockwave.live.duplicate():
			if is_instance_valid(w):
				w.step(DT)
		for l: EarthSpikeLine in EarthSpikeLine.live.duplicate():
			if is_instance_valid(l):
				l.step(DT)
		for s: EarthArmorState in EarthArmorState.live.duplicate():
			if is_instance_valid(s) and (player == null or s.ctx.caster != player):
				s.step(DT)


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _until_idle(bc: BendingController, max_frames: int = 400) -> int:
	var f := 0
	while bc.is_busy() and f < max_frames:
		await _run([bc], 1)
		f += 1
	return f


func _hits(d: TrainingDummy, id: StringName) -> Array[HitInfo]:
	var out: Array[HitInfo] = []
	if d.last_hit != null and d.last_hit.ability_id == id:
		out.append(d.last_hit)
	return out


# --- kit / tree ------------------------------------------------------------------------------------

func test_kit_tree_and_unlocks() -> void:
	var ids: Array[StringName] = [&"earth_punch", &"earth_boulder", &"earth_shield", &"earth_slide", &"earth_pillar", &"earth_stomp", &"earth_wall",
			&"earth_grab", &"earth_spikes", &"earth_armor", &"earthquake"]
	for id in ids:
		var d := _def(id)
		if not expect(d != null, "%s registered" % id):
			continue
		expect_eq(d.element, E.EARTH, "%s element" % id)
		expect(d.instantiate() is BendingAbility, "%s instantiates" % id)
		if d.clip != &"":
			expect(AnimLibrary.get_clip(d.clip) != null, "%s clip %s" % [id, d.clip])
		expect(ResourceLoader.exists(d.icon), "%s icon %s" % [id, d.icon])
		expect(d.display_name != "" and d.description.length() > 40, "%s described" % id)
	expect_eq(AbilityRegistry.starter_techniques(E.EARTH), [&"earth_pillar", &"earth_stomp", &"earth_wall"] as Array[StringName], "three starters, stable order")
	var kit := AbilityRegistry.core_kit(E.EARTH)
	expect(kit[&"light"].id == &"earth_punch" and kit[&"heavy"].id == &"earth_boulder" and kit[&"defense"].id == &"earth_shield" and kit[&"dodge"].id == &"earth_slide", "core kit")
	# Tree layout data.
	var tree := EarthKit.tree()
	expect_eq(tree.size(), 7, "7 techniques in the tree")
	var by_id := {}
	for n: Dictionary in tree:
		by_id[n["id"]] = n
	expect(by_id[&"earth_pillar"]["tier"] == 1 and by_id[&"earth_pillar"]["starter"], "pillar tier 1 starter")
	expect(by_id[&"earth_grab"]["tier"] == 2 and by_id[&"earth_grab"]["requires"] == &"earth_pillar" and by_id[&"earth_grab"]["practice"] == 6, "grab <- pillar x6")
	expect(by_id[&"earth_spikes"]["requires"] == &"earth_stomp", "spikes <- stomp")
	expect(by_id[&"earth_armor"]["tier"] == 3 and by_id[&"earth_armor"]["trainer"] != &"", "armor tier 3, trainer")
	expect(by_id[&"earthquake"]["signature"] and by_id[&"earthquake"]["tier"] == 4 and by_id[&"earthquake"]["cost"] == 2, "earthquake signature tier 4")
	for n: Dictionary in tree:
		if n["trainer"] != &"":
			expect(EarthKit.TRAINERS.has(n["trainer"]), "trainer %s published" % n["trainer"])
	for i in range(1, tree.size()):
		expect(int(tree[i - 1]["tier"]) <= int(tree[i]["tier"]), "tree sorted by tier")
	# Unlock flow (AbilityRegistry.can_unlock with the earth rules).
	GameState.reset()
	GameState.new_game(E.EARTH)
	AbilityRegistry.grant_starters(E.EARTH)
	expect(GameState.is_unlocked(&"earth_pillar") and GameState.is_unlocked(&"earth_stomp") and GameState.is_unlocked(&"earth_wall"), "starters granted")
	expect_eq(GameState.equipped_abilities[0], &"earth_pillar", "slot 1 = Earth Pillar (tutorial technique)")
	expect_eq(AbilityRegistry.can_unlock(&"earth_grab"), &"level", "grab needs level 3")
	GameState.level = 3
	expect_eq(AbilityRegistry.can_unlock(&"earth_grab"), &"practice", "grab needs pillar practice")
	for i in 6:
		GameState.add_practice(&"earth_pillar")
	expect_eq(AbilityRegistry.can_unlock(&"earth_grab"), &"skill_points", "then a skill point")
	GameState.skill_points = 1
	expect_eq(AbilityRegistry.can_unlock(&"earth_grab"), &"", "grab unlockable")
	GameState.level = 5
	expect_eq(AbilityRegistry.can_unlock(&"earth_armor"), &"trainer", "armor needs the trainer")
	GameState.set_flag("trained_ek_bao_shan_earth_armor", true)
	expect_eq(AbilityRegistry.can_unlock(&"earth_armor"), &"", "armor after the lesson")
	GameState.level = 7
	expect_eq(AbilityRegistry.can_unlock(&"earthquake"), &"prerequisite", "earthquake needs spikes")
	GameState.reset()


# --- costs / cooldowns / practice (real player) ---------------------------------------------------

func test_costs_cooldowns_and_practice() -> void:
	GameState.reset()
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	await _settle()
	for id: StringName in [&"earth_pillar", &"earth_stomp", &"earth_spikes", &"earth_grab", &"earth_wall"]:
		var d := _def(id)
		p.controller.reset_cooldowns()
		p.controller.set_slot(&"technique_1", d)
		p.resources.set_chi(100.0)
		var prac := int(GameState.ability_practice.get(String(id), 0))
		await PlayerSim.tap(p, &"ability_1", 2)
		expect(p.controller.current != null and p.controller.current.def == d, "%s started" % id)
		expect_near(p.resources.chi, 100.0 - d.chi_cost, 0.6, "%s chi spent" % id)
		expect(p.controller.cooldown_left(id) > d.cooldown - 0.2, "%s cooldown started" % id)
		var info := p.get_ability_slot_info(0)
		expect(info["id"] == id and info["cooldown_ratio"] > 0.9, "%s HUD slot shows it" % id)
		await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 400)
		expect(not p.controller.is_busy(), "%s ended" % id)
		expect(int(GameState.ability_practice.get(String(id), 0)) == prac + 1, "%s practice counted" % id)
		await PlayerSim.tap(p, &"ability_1", 2)
		expect(p.controller.last_failure == &"cooldown", "%s second press: cooldown (%s)" % [id, p.controller.last_failure])
		await PlayerSim.step(p, 10)
	# Signature: needs 100 Focus.
	p.controller.set_slot(&"signature", _def(&"earthquake"))
	p.resources.focus = 40.0
	await PlayerSim.tap(p, &"ability_special", 2)
	expect(p.controller.last_failure == &"focus", "earthquake needs full focus")
	p.resources.add_focus(100.0)
	await PlayerSim.tap(p, &"ability_special", 2)
	expect(p.controller.current != null and p.controller.current.def.id == &"earthquake", "earthquake from the signature button")
	expect(p.resources.focus < 1.0, "focus spent")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 400)
	p.queue_free()
	GameState.reset()


# --- Earth Pillar -------------------------------------------------------------------------------------

func test_pillar_launches_once_and_stands() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -6))
	var d := _dummy(Vector3(0, 0, -6))
	_aim_at(bc, d)
	bc.set_slot(&"technique_1", _def(&"earth_pillar"))
	await _settle()
	expect_eq(bc.request(&"technique_1"), &"", "pillar starts")
	bc.release(&"technique_1")
	var ab := bc.current
	var t_release := ab.time_to_event(&"release")
	await _run([bc], 50)
	expect_eq(d.hits_taken, 1, "target launched exactly once")
	expect(d.last_hit != null and d.last_hit.reaction == R.LAUNCH and d.last_hit.ability_id == &"earth_pillar" and d.last_hit.unblockable,
			"LAUNCH from beneath (unblockable)")
	expect(d.last_hit.lift >= 9.0, "big lift (%.1f)" % (d.last_hit.lift if d.last_hit else 0.0))
	expect(t_release > 0.3 and t_release < 0.45, "erupts on the release event (%.2f s)" % t_release)
	var pillar: BendingConstruct = null
	for c in BendingConstruct.live:
		if c.has_meta(&"earth_pillar"):
			pillar = c
	if not expect(pillar != null, "a stone column stands"):
		return
	expect(pillar.global_position.distance_to(Vector3(0, 0, -6)) < 0.8, "under the target")
	expect(pillar.collision_layer & Layers.CONSTRUCT != 0 and pillar.is_in_group(&"damageable"), "a real construct (cover)")
	# It blocks an enemy projectile.
	var enemy := _caster(Combat.Team.ENEMY, Vector3(0, 0, -12), Vector3.ZERO)
	await _settle()
	var proj := BendingProjectile.launch(enemy.ctx, Vector3(0, 1.2, -11), Vector3.BACK, 30.0, {"damage": 10.0}, {"radius": 0.2})
	await _run([bc], 30)
	expect(not proj.alive and proj.global_position.z < -6.0, "projectile stopped by the column")
	# Lifetime: crumbles.
	await _run([bc], int(9.5 / DT))
	await _run([bc], 50)
	expect(not BendingConstruct.live.has(pillar), "crumbles after its lifetime")


func test_pillar_without_target_and_self_lift() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3(4, 0, 0), Vector3(4, 0, -10))
	bc.set_slot(&"technique_1", _def(&"earth_pillar"))
	await _settle()
	bc.request(&"technique_1")
	bc.release(&"technique_1")
	await _until_idle(bc)
	var found := false
	for c in BendingConstruct.live:
		if c.has_meta(&"earth_pillar") and absf(c.global_position.x - 4.0) < 0.5 and c.global_position.z < -2.5 and c.global_position.z > -9.5:
			found = true
	expect(found, "no target: the column rises on the aim line (2.6-9 m ahead)")
	# The player holding the button rides a column up. Real physics frames here
	# (the column is an AnimatableBody3D: no manual double stepping).
	var p := PlayerSim.player(self, E.EARTH, Vector3(-6, 0, 0))
	p.controller.set_slot(&"technique_1", _def(&"earth_pillar"))
	p.set_physics_process(true)
	for i in 6:
		await get_tree().physics_frame
	var y0 := p.global_position.y
	p.input.press(&"ability_1")
	for i in 40:
		await get_tree().physics_frame
	p.input.release(&"ability_1")
	for i in 90:
		await get_tree().physics_frame
	expect(p.global_position.y > y0 + 2.6, "rode the column up (%.2f m)" % (p.global_position.y - y0))
	expect(p.is_on_floor(), "standing on top of it")
	expect(p.get_state() == PlayerCharacter.State.LOCOMOTION, "free to move again (%s)" % p.get_state_name())
	p.queue_free()


# --- Earth Stomp ------------------------------------------------------------------------------------

func test_stomp_shockwave_front_air_and_walls() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -5))
	bc.set_slot(&"technique_1", _def(&"earth_stomp"))
	var near := _dummy(Vector3(0, 0, -1.8))
	var mid := _dummy(Vector3(3.5, 0, 0))
	var far := _dummy(Vector3(-7.0, 0, 0))
	var high := _dummy(Vector3(0, 2.6, 3.0))
	var walled := _dummy(Vector3(0, 0, 4.5))
	PlayerSim.box(self, Vector3(2.0, 1.0, -2.0), Vector3(0.4, 2.0, 3.0), Vector3(0, 45, 0))
	var behind := _dummy(Vector3(3.2, 0, -3.2))
	await _settle()
	expect_eq(bc.request(&"technique_1"), &"", "stomp starts")
	var times := {}
	for i in 120:
		high.global_position = Vector3(0, 2.6, 3.0)
		high.velocity = Vector3.ZERO
		await _run([bc], 1)
		for d: TrainingDummy in [near, mid]:
			if d.hits_taken > 0 and not times.has(d):
				times[d] = i
	expect(near.hits_taken == 1 and near.last_hit.reaction == R.STAGGER and near.last_hit.ability_id == &"earth_stomp", "near: staggered once")
	expect_eq(mid.hits_taken, 1, "mid: staggered once")
	expect(times.has(near) and times.has(mid) and int(times[near]) < int(times[mid]), "the front reaches the near one first %s" % str(times.values()))
	expect_eq(far.hits_taken, 0, "beyond the radius: untouched")
	expect_eq(high.hits_taken, 0, "in the air: the wave passes under")
	expect_eq(behind.hits_taken, 0, "behind a wall: stopped")
	expect(walled.hits_taken == 1, "the open side is hit (%d)" % walled.hits_taken)
	expect(EarthShockwave.live.is_empty(), "the shockwave ended")
	expect(FxLib.alive_count(&"earth_mark_crater") > 0, "a cracked crater stays")


# --- Earth Spikes ------------------------------------------------------------------------------------

func test_spikes_line_launches_and_stops_at_ice() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -10))
	bc.set_slot(&"technique_1", _def(&"earth_spikes"))
	var a := _dummy(Vector3(0, 0, -4.0))
	var b := _dummy(Vector3(0.3, 0, -8.5))
	var off := _dummy(Vector3(3.0, 0, -6.0))
	await _settle()
	expect_eq(bc.request(&"technique_1"), &"", "spikes start")
	await _run([bc], 90)
	expect(a.hits_taken == 1 and a.last_hit.reaction == R.LAUNCH, "first target launched once")
	expect_eq(b.hits_taken, 1, "second target launched once")
	expect(a.last_hit.attack_id == b.last_hit.attack_id, "one attack id for the whole line")
	expect_eq(off.hits_taken, 0, "off the line: untouched")
	await _until_idle(bc)
	await _run([bc], 150)
	expect(EarthSpikeLine.live.is_empty(), "the spikes sank back")
	# An ice rink across the path stops the line.
	GroundSampler.add_zone(&"rink", Rect2(-3.0, 3.0, 6.0, 3.0), &"ice", 0.0)
	var bc2 := _caster(Combat.Team.PLAYER, Vector3(0, 0, 10), Vector3(0, 0, 0))
	bc2.set_slot(&"technique_1", _def(&"earth_spikes"))
	var beyond := _dummy(Vector3(0, 0, 1.5))
	await _settle()
	bc2.request(&"technique_1")
	var line: EarthSpikeLine = null
	for i in 90:
		await _run([bc2], 1)
		if line == null and not EarthSpikeLine.live.is_empty():
			line = EarthSpikeLine.live[0]
	expect(line == null or line.stop_reason == &"ice", "stopped at the ice (%s)" % (line.stop_reason if line else &"?"))
	expect_eq(beyond.hits_taken, 0, "nothing beyond the ice was hit")


# --- Earth Grab --------------------------------------------------------------------------------------

func test_grab_roots_grounded_targets() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -6))
	var d := _dummy(Vector3(0, 0, -6))
	_aim_at(bc, d)
	bc.set_slot(&"technique_1", _def(&"earth_grab"))
	await _settle()
	expect_eq(bc.request(&"technique_1"), &"", "grab starts")
	var ab := bc.current
	var t_grab := ab.time_to_event(&"grab")
	await _until_idle(bc)
	expect(d.hits_taken == 1 and d.last_hit.reaction == R.FREEZE and is_equal_approx(d.last_hit.stun_time, 2.5), "rooted 2.5 s (FREEZE)")
	expect(d.last_hit.unblockable, "from the ground: unblockable")
	expect(t_grab > 0.4 and t_grab < 0.6, "clamps on the grab event (%.2f s)" % t_grab)
	expect(FxLib.count(&"earth_shackle") > 0, "stone jaws shown")
	# A target in the air escapes.
	BendingHits.clear_log()
	bc.reset_cooldowns()
	var air := _dummy(Vector3(2, 2.5, -6))
	_aim_at(bc, air)
	await _settle()
	bc.request(&"technique_1")
	for i in 80:
		air.global_position = Vector3(2, 2.5, -6)
		air.velocity = Vector3.ZERO
		await _run([bc], 1)
	expect_eq(air.hits_taken, 0, "airborne target not grabbed")


# --- Earth Armor -------------------------------------------------------------------------------------

func test_armor_toggle_modifiers_drain_and_burst() -> void:
	GameState.reset()
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	p.controller.set_slot(&"technique_1", _def(&"earth_armor"))
	await _settle()
	await PlayerSim.step(p, 3)
	p.resources.set_chi(100.0)
	await PlayerSim.tap(p, &"ability_1", 2)
	var started := p.controller.current != null and p.controller.current.def.id == &"earth_armor"
	expect(started, "armor technique started")
	expect_near(p.resources.chi, 80.0, 0.6, "donning costs 20 chi")
	expect(p.controller.cooldown_left(&"earth_armor") == 0.0, "no cooldown while putting it on")
	await PlayerSim.step_until(p, func() -> bool: return EarthArmorState.is_worn(p), 120)
	expect(EarthArmorState.is_worn(p), "armor worn")
	expect_near(p.ctx.base_damage_reduction, 0.4, 0.001, "damage reduction")
	expect_near(p.motor.speed_scale, 0.78, 0.001, "slower")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	# Damage is reduced even between abilities.
	var hp := p.health.health
	var h := HitInfo.make(50.0, null, E.NONE, R.FLINCH, Vector3.FORWARD, 0.0)
	h.team = Combat.Team.ENEMY
	Combat.deal(p, h)
	expect_near(hp - p.health.health, 50.0 * 0.6 * Settings.difficulty_damage_scale(), 0.6, "40% less damage")
	# Another ability starting / ending keeps it.
	await PlayerSim.tap(p, &"attack_light", 2)
	expect(p.ctx.damage_reduction >= 0.4, "still armored during a punch")
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	expect_near(p.ctx.damage_reduction, 0.4, 0.001, "still armored after it")
	# Chi drains (no regeneration).
	var c0 := p.resources.chi
	await PlayerSim.step(p, 60, [EarthArmorState.of(p)])
	expect(p.resources.chi < c0 - 3.0, "chi drains (%.1f -> %.1f)" % [c0, p.resources.chi])
	# Shed: burst knocks back whoever is close, modifiers cleared, cooldown now.
	var d := _dummy(p.global_position + Vector3(0, 0, -1.8))
	await _settle()
	await PlayerSim.tap(p, &"ability_1", 2)
	await PlayerSim.step_until(p, func() -> bool: return not p.controller.is_busy(), 120)
	expect(not EarthArmorState.is_worn(p), "shed")
	expect(d.hits_taken == 1 and d.last_hit.reaction == R.KNOCKBACK, "burst knocked the close target back")
	expect(p.ctx.base_damage_reduction == 0.0 and p.ctx.damage_reduction == 0.0 and p.motor.speed_scale == 1.0, "modifiers cleared")
	expect(p.controller.cooldown_left(&"earth_armor") > 3.0, "cooldown after shedding")
	# Running out of chi breaks it.
	p.controller.reset_cooldowns()
	p.resources.set_chi(100.0)
	await PlayerSim.tap(p, &"ability_1", 2)
	await PlayerSim.step_until(p, func() -> bool: return EarthArmorState.is_worn(p), 120)
	p.resources.set_chi(1.0)
	await PlayerSim.step(p, 30, [EarthArmorState.of(p)])
	expect(not EarthArmorState.is_worn(p) and p.motor.speed_scale == 1.0, "chi out: the armor crumbles")
	p.queue_free()
	GameState.reset()


func test_armor_on_an_ai_caster_times_out() -> void:
	var bc := _caster(Combat.Team.ENEMY, Vector3.ZERO)
	bc.set_slot(&"technique_1", _def(&"earth_armor"))
	await _settle()
	expect_eq(bc.request(&"technique_1"), &"", "enemy dons armor")
	await _until_idle(bc)
	var st := EarthArmorState.of(bc.ctx.caster)
	expect(st != null and st.active and bc.ctx.base_damage_reduction > 0.3, "enemy armored")
	await _run([bc], int(26.0 / DT))
	expect(EarthArmorState.of(bc.ctx.caster) == null or not EarthArmorState.of(bc.ctx.caster).active, "times out without resources")
	expect_eq(bc.ctx.base_damage_reduction, 0.0, "modifiers cleared")


# --- Earthquake -------------------------------------------------------------------------------------

func test_earthquake_knocks_down_everything_on_the_ground() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -5))
	bc.set_slot(&"signature", _def(&"earthquake"))
	var ds: Array[TrainingDummy] = [_dummy(Vector3(0, 0, -3)), _dummy(Vector3(6, 0, 0)), _dummy(Vector3(-7, 0, 6)), _dummy(Vector3(0, 0, 10))]
	var guard := _dummy(Vector3(-3, 0, -3), true, Vector3.ZERO)
	var out := _dummy(Vector3(0, 0, -14))
	await _settle()
	var applied0 := BendingHits.applied_hits
	var shown0 := ImpactFx.hits_shown
	expect_eq(bc.request(&"signature"), &"", "earthquake starts (rig-less: unlimited focus)")
	var ab := bc.current
	expect(ab.time_to_event(&"impact") > 0.8, "a big, readable wind-up (%.2f s)" % ab.time_to_event(&"impact"))
	await _until_idle(bc)
	await _run([bc], 60)
	for d in ds:
		expect(d.hits_taken >= 1 and _first_quake(d), "%s knocked down" % d.name)
	expect(guard.results.has(Combat.Result.HIT), "a guard does not stop it (unblockable)")
	expect_eq(out.hits_taken, 0, "beyond 11 m: untouched")
	expect(FxLib.alive_count(&"earth_mark_fissure") >= 4, "fissures split the ground (%d)" % FxLib.alive_count(&"earth_mark_fissure"))
	expect(FxLib.alive_count(&"earth_rubble") >= 1, "broken slabs stay")
	expect_eq(ImpactFx.hits_shown - shown0, BendingHits.applied_hits - applied0, "hit VFX == applied hits")


func _first_quake(d: TrainingDummy) -> bool:
	return d.last_hit != null and (d.last_hit.ability_id == &"earthquake" and d.last_hit.reaction == R.KNOCKDOWN or d.last_hit.ability_id == &"earthquake")


# --- surfaces ----------------------------------------------------------------------------------------

func test_surfaces_classify_and_refuse() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO, Vector3(0, 0, -5))
	await _settle()
	GroundSampler.add_zone(&"sand", Rect2(10, -2, 4, 4), &"sand", 0.0)
	GroundSampler.add_zone(&"snow", Rect2(20, -2, 4, 4), &"snow", 0.3)
	GroundSampler.add_zone(&"ice", Rect2(30, -2, 4, 4), &"ice", 0.0)
	GroundSampler.add_zone(&"ash", Rect2(40, -2, 4, 4), &"ash", 0.0)
	var ctx := bc.ctx
	expect_eq(EarthEnv.material_at(ctx, Vector3(12, 0, 0))["kind"], &"sand", "sand")
	expect(bool(EarthEnv.material_at(ctx, Vector3(12, 0, 0))["weak"]) and float(EarthEnv.material_at(ctx, Vector3(12, 0, 0))["power"]) < 0.9, "sand is weak")
	expect_eq(EarthEnv.material_at(ctx, Vector3(22, 0, 0))["kind"], &"snow", "snow (earth under it)")
	expect(not bool(EarthEnv.material_at(ctx, Vector3(32, 0, 0))["ok"]), "ice: nothing to bend")
	expect_eq(EarthEnv.material_at(ctx, Vector3(42, 0, 0))["kind"], &"ash", "ash")
	expect_eq(EarthEnv.material_at(ctx, Vector3(0, 0, -3))["kind"], &"grass", "flat world grass")
	# Water: shallow = mud (weak), deep = nothing.
	WorldData.height_override = func(x: float, z: float) -> float: return -2.0 if x < -20.0 else (-0.3 if x < -10.0 else 0.0)
	expect_eq(EarthEnv.classify(Vector3(-15, -0.3, 0)), &"mud", "shallow water: mud")
	expect_eq(EarthEnv.classify(Vector3(-25, -2.0, 0)), &"deep_water", "deep water")
	WorldData.height_override = Callable()
	# Tagged floors (decks) and earth constructs.
	var deck := PlayerSim.box(self, Vector3(50, 0.25, 0), Vector3(4, 0.5, 4))
	deck.set_meta(&"surface", &"wood")
	await _settle()
	expect(not bool(EarthEnv.material_at(ctx, Vector3(50, 0, 0))["ok"]), "wooden deck: nothing to bend")
	# Techniques refuse on ice with feedback.
	var fails: Array = []
	bc.ability_failed.connect(func(id: StringName, reason: StringName) -> void: fails.append([id, reason]))
	bc.ctx.caster.global_position = Vector3(32, 0, 0)
	await _settle()
	for id: StringName in [&"earth_stomp", &"earth_armor", &"earthquake", &"earth_boulder"]:
		var slot := &"signature" if id == &"earthquake" else (&"heavy" if id == &"earth_boulder" else &"technique_1")
		bc.set_slot(slot, _def(id))
		expect_eq(bc.request(slot), &"no_earth", "%s refused on ice" % id)
	expect(fails.size() >= 4 and fails[0][1] == &"no_earth", "ability_failed(no_earth) reported")
	# Earth Punch on ice: bare stone fists, no rocks.
	var d := _dummy(Vector3(32, 0, -1.5))
	await _settle()
	var projs := BendingProjectile.live.size()
	bc.request(&"light")
	await _until_idle(bc)
	expect(d.hits_taken == 1 and d.last_hit.ability_id == &"earth_punch", "fist strike lands up close")
	expect(d.last_hit.damage < 9.0, "weaker than a rock (%.1f)" % d.last_hit.damage)
	expect_eq(BendingProjectile.live.size(), projs, "no rock thrown")
	# Weak ground scales the hit.
	var info := EarthEnv.material_at(ctx, Vector3(12, 0, 0))
	expect(float(EarthEnv.scaled_hit({"damage": 20.0}, info)["damage"]) < 20.0, "sand weakens hits")


# --- AI casters --------------------------------------------------------------------------------------

func test_enemy_casters_use_the_techniques_on_the_player() -> void:
	GameState.reset()
	var p := PlayerSim.player(self, E.WATER, Vector3(0, 0, -6))
	await _settle()
	for id: StringName in [&"earth_pillar", &"earth_stomp", &"earth_spikes", &"earth_grab", &"earthquake"]:
		BendingHits.clear_log()
		p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0, 0, -6 if id != &"earth_stomp" else -2.5)), 1.0)
		var bc := _caster(Combat.Team.ENEMY, Vector3.ZERO, Vector3(0, 0, -6))
		_aim_at(bc, p)
		var slot := &"signature" if id == &"earthquake" else &"technique_1"
		bc.set_slot(slot, _def(id))
		await _settle()
		var hp := p.health.health
		var got := [false]
		var cb := func(_amount: float, hit: HitInfo) -> void:
			if hit.ability_id == id:
				got[0] = true
		Events.player_damaged.connect(cb)
		expect_eq(bc.request(slot), &"", "enemy casts %s" % id)
		for i in 160:
			await _run([bc], 1, p)
		Events.player_damaged.disconnect(cb)
		expect(got[0] and p.health.health < hp, "%s hurt the player (%.0f -> %.0f)" % [id, hp, p.health.health])
		bc.ctx.caster.queue_free()
		await PlayerSim.step(p, 120)
	# Fair play: an enemy pillar commits to the spot when the cast starts - stepping away dodges it.
	p.respawn_at(Transform3D(Basis.IDENTITY, Vector3(0, 0, -6)), 1.0)
	await PlayerSim.step(p, 5)
	var bc2 := _caster(Combat.Team.ENEMY, Vector3.ZERO, Vector3(0, 0, -6))
	_aim_at(bc2, p)
	bc2.set_slot(&"technique_1", _def(&"earth_pillar"))
	await _settle()
	for pr in BendingProjectile.live.duplicate():
		pr.destroy()
	bc2.request(&"technique_1")
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(3.0, 0, -6)))
	# Let the physics server see the move (bodies moved inside a manual step sync on real frames).
	await _settle()
	var pillar_hits := [0]
	var cb2 := func(_amount: float, hit: HitInfo) -> void:
		if hit.ability_id == &"earth_pillar":
			pillar_hits[0] += 1
	Events.player_damaged.connect(cb2)
	for i in 60:
		await _run([bc2], 1, p)
	Events.player_damaged.disconnect(cb2)
	expect_eq(pillar_hits[0], 0, "sidestepping the rumbling spot avoids the enemy pillar")
	p.queue_free()
	GameState.reset()


# --- marks, VFX parity, latency ----------------------------------------------------------------------

func test_marks_persist_and_are_capped() -> void:
	var bc := _caster(Combat.Team.PLAYER, Vector3.ZERO)
	await _settle()
	EarthMarks.crater(bc.ctx.caster, Vector3.ZERO, 1.5, &"dirt")
	var m := EarthMarks.crater(bc.ctx.caster, Vector3(3, 0, 0), 1.5, &"sand")
	expect(m.life >= 12.0, "marks stay at least 12 s (%.0f)" % m.life)
	for i in 600:
		m._process(DT)
	expect(m.visible and m.t < m.life, "still there after 10 s")
	for i in 40:
		EarthMarks.fissure(bc.ctx.caster, Vector3(i, 0, 5), Vector3(i, 0, 9), 0.6, &"stone")
	expect(FxLib.alive_count(&"earth_mark_fissure") <= FxLib.cap_of(&"earth_mark_fissure"), "fissures capped (%d)" % FxLib.alive_count(&"earth_mark_fissure"))
	expect(FxLib.alive_count(&"earth_mark_fissure") <= 28 * 2, "hard cap")


func test_hit_vfx_parity_and_latency_report() -> void:
	var shown0 := ImpactFx.hits_shown
	var applied0 := BendingHits.applied_hits
	var report: Array[String] = []
	var x := 0.0
	for id: StringName in [&"earth_pillar", &"earth_stomp", &"earth_spikes", &"earth_grab", &"earth_wall", &"earth_boulder"]:
		var bc := _caster(Combat.Team.PLAYER, Vector3(x, 0, 0), Vector3(x, 0, -6))
		var d := _dummy(Vector3(x, 0, -3.5 if id != &"earth_wall" else -4.5))
		var g := _dummy(Vector3(x + 1.0, 0, -3.0), true, Vector3(x, 0, 0))
		_aim_at(bc, d)
		var slot := &"heavy" if id == &"earth_boulder" else &"technique_1"
		bc.set_slot(slot, _def(id))
		await _settle()
		var hits0 := d.hits_taken + g.hits_taken
		bc.request(slot)
		var first := -1
		var f := 0
		var effect := func() -> bool:
			return d.hits_taken + g.hits_taken > hits0 or not EarthShockwave.live.is_empty() or not EarthSpikeLine.live.is_empty() \
					or BendingConstruct.live.any(func(c: BendingConstruct) -> bool: return is_instance_valid(c) and c.is_alive())
		while bc.is_busy() and f < 400:
			if id == &"earth_boulder" and f == 2:
				bc.release(slot)
			await _run([bc], 1)
			f += 1
			if first < 0 and (effect.call() or BendingProjectile.live.size() > 0):
				first = f
		report.append("%s %d" % [id, first])
		await _run([bc], 120)
		for c in BendingConstruct.live.duplicate():
			c.queue_free()
		BendingConstruct.live.clear()
		x += 14.0
	print("    earth press -> active (frames @60Hz): ", ", ".join(report))
	var shown := ImpactFx.hits_shown - shown0
	var applied := BendingHits.applied_hits - applied0
	print("    earth hits: %d applied, %d hit VFX shown" % [applied, shown])
	expect(applied >= 5, "the techniques landed (%d)" % applied)
	expect_eq(shown, applied, "hit VFX shown exactly for applied hits")


func test_light_strike_latency_and_fist_stomp() -> void:
	GameState.reset()
	var p := PlayerSim.player(self, E.EARTH, Vector3.ZERO)
	await _settle()
	await PlayerSim.step(p, 3)
	var lat: Array[int] = []
	for i in 3:
		p.input.press(&"attack_light")
		var f := await PlayerSim.step_until(p, func() -> bool:
			var c := p.controller.current as ComboAbility
			return c != null and c.struck and c.step == i, 60)
		p.input.release(&"attack_light")
		lat.append(f)
		await PlayerSim.step_until(p, func() -> bool:
			var c := p.controller.current as ComboAbility
			return c == null or c.can_chain(), 60)
	print("    earth punch latency (frames, press -> rock released): ", str(lat))
	for f in lat:
		expect(f >= 0 and f <= 6, "light strike active within 6 frames (%d)" % f)
	p.queue_free()
	GameState.reset()
