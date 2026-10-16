class_name EnemyDamage
extends RefCounted
## EnemyBase.receive_hit (same rules as the player, GAME_DESIGN §5):
## 1. dead / surrendered / vanished -> IGNORED; i-frames (dodges, get-up) -> DODGED;
## 2. guards: a bending defense (DefenseAbility.guard) or a physical shield covering
##    the hit -> BLOCKED with chip damage (projectiles of every element stop on a
##    shield: defenders block water / fire / rock alike); heavy hits wear the guard
##    down and break it (stagger);
## 3. damage x element matchup x armor; poise; aggro + alert;
## 4. reaction by attack type and weight class: poise_resist turns staggers into
##    flinches for heavy fighters (a heavy earth hit still staggers a light one),
##    mass scales knockback (archers fly, brutes barely move), attack armor
##    (hyper armor) swallows reactions below its poise; captains change phase;
## 5. low health: some bandits flee or surrender; death -> loot / XP / events.

const R := HitInfo.Reaction
## force x mass of a heavy knockback that knocks an enemy down instead.
const TOPPLE_IMPACT := 11.5


static func receive(e: EnemyBase, hit: HitInfo) -> int:
	if not e.is_alive() or e.surrendered or e.dormant or not e.visible:
		return Combat.Result.IGNORED
	if e.iframes_t > 0.0 or e.state == EnemyBase.State.GETUP or (e.controller and e.controller.current and e.controller.current.has_iframes()):
		hit.damage = 0.0
		return Combat.Result.DODGED
	var aggressor := hit.source as Node3D if hit.source is Node3D else null
	# --- guards -----------------------------------------------------------------------------
	var g := _guard(e, hit)
	if g >= 0:
		if aggressor:
			e.brain.on_damaged(hit, aggressor)
		return g
	# --- damage -------------------------------------------------------------------------------
	var dmg := hit.damage * Combat.element_multiplier(hit.element, e.element)
	dmg *= 1.0 - clampf(float(e.archetype.get("armor", 0.0)), 0.0, 0.8)
	if e.controller and e.ctx.damage_reduction > 0.0:
		dmg *= 1.0 - clampf(e.ctx.damage_reduction, 0.0, 0.9)
	hit.damage = dmg
	var broke := e.health.apply_damage(dmg, hit)
	e.recent_hits += 1
	e.recent_hits_t = 1.8
	e.visual.flash()
	e.visual.status_from(hit)
	e.bar.on_damaged()
	if aggressor:
		e.brain.on_damaged(hit, aggressor)
	if e.health.is_dead():
		die(e, hit)
		e.damaged.emit(e, hit, Combat.Result.KILLED)
		return Combat.Result.KILLED
	var reaction := reaction_for(e, hit, broke)
	apply_reaction(e, hit, reaction)
	e.damaged.emit(e, hit, Combat.Result.HIT)
	e.brain.after_hit(hit, reaction)
	return Combat.Result.HIT


## Resolves guards. Returns a Combat.Result or -1 when no guard applies.
static func _guard(e: EnemyBase, hit: HitInfo) -> int:
	if hit.unblockable:
		return -1
	# Bending defense running through the controller (earth slab, water shield, flame guard).
	if e.controller and e.controller.current is DefenseAbility:
		var da := e.controller.current as DefenseAbility
		if da.is_defending():
			var res: Dictionary = da.guard(hit)
			var r := int(res["result"])
			if r == Combat.Result.BLOCKED or r == Combat.Result.DEFLECTED:
				var chip := float(res["damage"])
				hit.damage = chip
				if chip > 0.0:
					e.health.apply_damage(chip, null)
					e.bar.on_damaged()
				if e.health.is_dead():
					die(e, hit)
					return Combat.Result.KILLED
				return r
	# Physical shield (defenders).
	if not e.shield_up():
		return -1
	var block: Dictionary = e.archetype["block"]
	if not _covers(e, hit, float(block.get("arc", 75.0))):
		return -1
	if hit.is_projectile and not bool(block.get("projectiles", true)):
		return -1
	var heavy_mult := 2.0 if hit.is_heavy else 1.0
	if hit.element == ElementDefs.Element.EARTH and hit.is_heavy:
		heavy_mult = 2.6
	e.guard_hp -= hit.poise_damage * heavy_mult
	var chip := 0.0 if hit.is_projectile else hit.damage * (1.0 - float(block.get("reduction", 0.85)))
	hit.damage = chip
	if chip > 0.0:
		e.health.apply_damage(chip, null)
		e.bar.on_damaged()
	if e.health.is_dead():
		die(e, hit)
		return Combat.Result.KILLED
	if e.guard_hp <= 0.0:
		# Guard broken: shield arm thrown wide, a real punish window.
		e.guard_hp = 0.0
		e.guard_broken_t = 4.0
		e.actions.cancel(&"hit")
		e.stun_t = 1.0
		e.visual.reaction(R.STAGGER, hit.direction, 1.3)
		e.restart_state(EnemyBase.State.STAGGER)
		Audio.play_sfx(&"block_impact", e.global_position + Vector3.UP * 1.2, 2.0)
		e.bark("Agh! My guard!" if e.rng.randf() < 0.5 else "")
		return Combat.Result.HIT
	if e.visual.rig and not e.actions.is_busy():
		e.visual.play(&"block_impact", {"blend_in": 0.02, "mask": &"arm_l"})
	var push := hit.direction * hit.force * 0.25 * float(e.archetype["mass"])
	e.velocity.x += push.x
	e.velocity.z += push.z
	return Combat.Result.BLOCKED


static func _covers(e: EnemyBase, hit: HitInfo, arc_deg: float) -> bool:
	var to := hit.origin - e.global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		to = -hit.direction
	if to.length_squared() < 1e-6:
		return false
	return e.forward().dot(to.normalized()) >= cos(deg_to_rad(arc_deg))


## Final reaction for this enemy (weight class, attack armor, poise break).
static func reaction_for(e: EnemyBase, hit: HitInfo, broke: bool) -> int:
	var r := int(hit.reaction)
	if broke and r < R.STAGGER:
		r = R.STAGGER
	# Heavy blasts topple light and medium fighters off their feet (impact = force x mass):
	# a full charge floors a bandit, an archer goes down to half a charge, brutes stand.
	if r == R.KNOCKBACK and hit.is_heavy and hit.force * float(e.archetype.get("mass", 1.0)) >= TOPPLE_IMPACT:
		r = R.KNOCKDOWN
	var resist := float(e.archetype.get("poise_resist", 0.0))
	if not broke and resist > 0.0:
		if (r == R.STAGGER or r == R.KNOCKBACK or r == R.PULL) and hit.poise_damage < resist:
			r = R.FLINCH
		elif (r == R.KNOCKDOWN or r == R.LAUNCH) and hit.poise_damage < resist * 1.5:
			r = R.STAGGER
	var armor := e.current_armor()
	if armor > 0.0 and not broke and hit.poise_damage < armor and r != R.FREEZE:
		r = R.FLINCH
	return r


static func apply_reaction(e: EnemyBase, hit: HitInfo, reaction: int) -> void:
	var dir := hit.direction
	var mass := float(e.archetype.get("mass", 1.0))
	var light := mass >= 1.1
	# Already on the ground: hits never turn a knockdown into a stagger (the strongest
	# reaction of a combined hit wins); heavier ones keep it down a little longer, a
	# launch juggles. The knockdown state timeout still bounds the time on the floor.
	if e.state == EnemyBase.State.KNOCKDOWN and reaction != R.LAUNCH:
		if reaction >= R.STAGGER and e.state_time < 1.6:
			e.down_t = minf(e.down_t + 0.2, 2.0)
		return
	if reaction >= R.STAGGER:
		e.actions.cancel(&"hit")
		if e.controller and e.controller.is_busy():
			e.controller.cancel_current(&"hit")
	match reaction:
		R.NONE:
			pass
		R.FLINCH:
			e.visual.reaction(R.FLINCH, dir, 1.0)
			if not e.actions.is_busy() and hit.force > 0.0:
				var p := dir * hit.force * 0.3 * mass
				e.velocity.x += p.x
				e.velocity.z += p.z
		R.STAGGER, R.PULL:
			var d := e.visual.reaction(R.STAGGER if reaction == R.STAGGER else &"pull", dir, 1.0)
			var v := dir * hit.force * 0.6 * mass
			if reaction == R.PULL:
				var to := hit.origin - e.global_position
				to.y = 0.0
				v = to.normalized() * maxf(hit.force, 4.0) * mass if to.length() > 0.6 else Vector3.ZERO
			e.velocity.x = v.x
			e.velocity.z = v.z
			e.stun_t = maxf(hit.stun_time, clampf(d * 0.7, 0.35, 0.8)) + (0.12 if light else 0.0)
			e.restart_state(EnemyBase.State.STAGGER)
		R.KNOCKBACK:
			e.visual.reaction(R.KNOCKBACK, dir, 1.0)
			var v2 := dir * maxf(hit.force, 4.0) * mass
			e.velocity.x = v2.x
			e.velocity.z = v2.z
			e.velocity.y = maxf(e.velocity.y, hit.lift * mass * 0.6)
			e.stun_t = clampf(0.4 + hit.force * 0.04 * mass, 0.45, 1.1)
			e.restart_state(EnemyBase.State.STAGGER)
		R.KNOCKDOWN:
			e.visual.reaction(R.KNOCKDOWN, dir, 1.0)
			var v3 := dir * hit.force * 0.7 * mass
			e.velocity.x = v3.x
			e.velocity.z = v3.z
			e.velocity.y = maxf(e.velocity.y, hit.lift * 0.5 * mass)
			e.down_t = clampf(maxf(hit.stun_time, 1.1), 0.9, 2.2)
			e.restart_state(EnemyBase.State.KNOCKDOWN)
		R.LAUNCH:
			e.visual.reaction(R.LAUNCH, dir, 1.0)
			var v4 := dir * hit.force * mass
			e.velocity = Vector3(v4.x, maxf(hit.lift, 5.0) * clampf(mass, 0.5, 1.3), v4.z)
			e.airborne_reaction = true
			e.down_t = 1.0
			e.restart_state(EnemyBase.State.KNOCKDOWN)
		R.FREEZE:
			var t := clampf(maxf(hit.stun_time, 0.6), 0.5, 2.5)
			e.velocity = Vector3(0, minf(e.velocity.y, 0.0), 0)
			e.visual.reaction(R.FREEZE, dir, t)
			e.visual.tint(Color(0.7, 0.9, 1.0), 0.9)
			e.stun_t = t
			e.restart_state(EnemyBase.State.STAGGER)
	# Element touches: water douses firebenders (longer recovery), fire vs beasts burns.
	if hit.element == ElementDefs.Element.WATER and e.element == ElementDefs.Element.FIRE and reaction >= R.STAGGER:
		e.stun_t *= 1.35
		FxBurst.spawn(e, &"steam", e.global_position + Vector3.UP * 1.2, {"count": 0.8})
		Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", e.global_position, -4.0)
		for id: StringName in [&"enemy_fire_combo", &"enemy_fire_blast", &"enemy_flame_sweep"]:
			if e.controller:
				e.controller.cooldowns[id] = maxf(e.controller.cooldown_left(id), 1.5)


## A launched enemy touched the ground: lie there, then get up.
static func on_landed_knockdown(e: EnemyBase) -> void:
	if e.state == EnemyBase.State.KNOCKDOWN:
		e.down_t = maxf(e.down_t, 0.8)
		FxBurst.spawn(e, &"dust", e.global_position, {"color": FxLib.surface_color(GroundSampler.surface(e.global_position)), "count": 0.7})


static func die(e: EnemyBase, hit: HitInfo) -> void:
	if e.state == EnemyBase.State.DEAD:
		return
	e.killer = hit.source if hit != null and is_instance_valid(hit.source) else null
	e.kill_hit = hit
	e.actions.cancel(&"death")
	if e.controller and e.controller.is_busy():
		e.controller.cancel_current(&"death")
	AttackTokens.release_all(e)
	e.set_state(EnemyBase.State.DEAD)
	e.collision_layer = 0
	e.collision_mask = Layers.WORLD
	var dir := hit.direction if hit != null else -e.forward()
	e.visual.die(dir)
	if hit != null and hit.force > 0.0:
		var v := dir * hit.force * 0.6 * float(e.archetype.get("mass", 1.0))
		e.velocity.x = v.x
		e.velocity.z = v.z
	e.bar.hide_now()
	e.perception.forget()
	e.begin_death_fade()
	GameState.incr_stat("enemies_defeated")
	if e.rewards and e.killer != null and e.killer.is_in_group(&"player"):
		EnemyRewards.grant(e, &"killed")
	e.died.emit(e, e.killer)
	e.defeated.emit(e, &"killed")
	Events.enemy_killed.emit(e, e.killer)


## Low health: bandits may give up (rolled once per enemy).
static func surrender(e: EnemyBase) -> void:
	if e.surrendered or not e.is_alive():
		return
	e.surrendered = true
	e.actions.cancel(&"surrender")
	if e.controller and e.controller.is_busy():
		e.controller.cancel_current(&"surrender")
	AttackTokens.release_all(e)
	e.set_state(EnemyBase.State.SURRENDER)
	e.set_meta(&"no_lock", true)
	e.visual.play(&"enemy_surrender", {"blend_in": 0.15})
	e.visual.drop_weapons()
	e.bark(["I yield! I yield!", "Mercy! Take it, take it all!", "Enough! I give up!"][e.rng.randi() % 3], 2.5)
	e.bar.hide_now()
	GameState.incr_stat("enemies_defeated")
	if e.rewards:
		EnemyRewards.grant(e, &"surrendered")
	e.defeated.emit(e, &"surrendered")
