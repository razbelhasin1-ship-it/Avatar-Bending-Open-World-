class_name PlayerDamage
extends RefCounted
## PlayerCharacter.receive_hit() (docs/GAME_DESIGN.md §5):
## 1. dead / cinematic -> IGNORED;
## 2. dodge i-frames (and get-up i-frames) -> DODGED (perfect dodge hook);
## 3. a held defense covering the hit: parry window -> DEFLECTED (counter,
##    +15 Focus, attacker staggered), else BLOCKED with the element's reduction;
## 4. damage (difficulty, element matchup, action damage reduction) -> health;
## 5. reaction: poise armor of the current action swallows reactions whose
##    poise damage is below it unless poise breaks; knockback scaled by the
##    element (air x1.3, earth x0.4 ...); hit flash, status tint, shake;
## 6. death -> die() (Events.player_died; the world drives respawn_at()).

const S := PlayerCharacter.State
const R := HitInfo.Reaction


static func receive(p: PlayerCharacter, hit: HitInfo) -> int:
	if p.health == null or p.health.is_dead() or p.states.state == S.DEAD or p.states.state == S.CINEMATIC:
		return Combat.Result.IGNORED
	if p.states.state == S.MOUNTED:
		return Combat.Result.IGNORED
	var ab := p.controller.current
	# I-frames.
	if (ab != null and ab.has_iframes()) or (p.states.state == S.GETUP and p.states.getup_iframes > 0.0):
		if ab is DodgeAbility:
			(ab as DodgeAbility).notify_dodged(hit)
		hit.damage = 0.0
		return Combat.Result.DODGED
	# Defense.
	if ab is DefenseAbility and (ab as DefenseAbility).is_defending():
		var g: Dictionary = (ab as DefenseAbility).guard(hit)
		var res := int(g["result"])
		if res == Combat.Result.DEFLECTED:
			hit.damage = 0.0
			p.resources.mark_combat()
			return res
		if res == Combat.Result.BLOCKED:
			var chip := float(g["damage"]) * Settings.difficulty_damage_scale()
			hit.damage = chip
			if chip > 0.0:
				p.health.apply_damage(chip, null)
				p.resources.since_damaged = 0.0
				Events.player_damaged.emit(chip, hit)
			p.resources.mark_combat()
			p.visual.enter_combat(8.0)
			if hit.force > 0.0:
				var push := hit.direction * hit.force * p.profile.knockback_mult * 0.25
				p.velocity.x += push.x
				p.velocity.z += push.z
			if p.health.is_dead():
				p.die(hit)
				return Combat.Result.KILLED
			return res
	var dmg := hit.damage * Settings.difficulty_damage_scale() * Combat.element_multiplier(hit.element, p.element)
	dmg *= 1.0 - clampf(p.ctx.damage_reduction, 0.0, 0.95)
	hit.damage = dmg
	var broke := p.health.apply_damage(dmg, hit)
	p.resources.mark_combat()
	p.resources.since_damaged = 0.0
	p.visual.enter_combat(8.0)
	var tick := is_tick(hit)
	p.visual.flash(Color(1, 1, 1), 0.08 if tick else 0.16)
	_status(p, hit)
	Events.player_damaged.emit(dmg, hit)
	# Damage-over-time ticks (burn) and sustained multi-hit pulses never shake the camera:
	# only real blows do (a burning player would otherwise shake once a second).
	if not tick:
		BendingFeedback.shake(0.3 if hit.is_heavy else 0.16, 0.15)
	if p.health.is_dead():
		p.die(hit)
		return Combat.Result.KILLED
	var reaction := int(hit.reaction)
	if broke and reaction < R.STAGGER:
		reaction = R.STAGGER
	var armor := p.ctx.poise_armor if ab != null else 0.0
	if armor > 0.0 and not broke and hit.poise_damage < armor and reaction != R.FREEZE:
		reaction = R.FLINCH
	react(p, hit, reaction)
	return Combat.Result.HIT


## True for damage-over-time ticks (FireStatus burn: meta &"dot") and sustained multi-hit
## pulses (meta &"no_hitstop"): they hurt, flash softly, but add no camera shake.
static func is_tick(hit: HitInfo) -> bool:
	return hit != null and (hit.has_meta(&"dot") or hit.has_meta(&"no_hitstop"))


static func react(p: PlayerCharacter, hit: HitInfo, reaction: int) -> void:
	var kb := p.profile.knockback_mult
	var dir := hit.direction
	match reaction:
		R.NONE:
			pass
		R.FLINCH:
			p.visual.reaction(R.FLINCH, dir, 1.0)
			if hit.force > 0.0 and p.controller.current == null:
				var push := dir * hit.force * kb * 0.35
				p.velocity.x += push.x
				p.velocity.z += push.z
		R.STAGGER:
			p.controller.cancel_current(&"hit")
			var d := p.visual.reaction(R.STAGGER, dir, 1.0)
			var v := dir * hit.force * kb * 0.6
			p.velocity.x = v.x
			p.velocity.z = v.z
			p.states.enter_hitstun(maxf(hit.stun_time, clampf(d * 0.7, 0.3, 0.9)))
		R.KNOCKBACK:
			p.controller.cancel_current(&"hit")
			p.visual.reaction(R.KNOCKBACK, dir, 1.0)
			var v := dir * maxf(hit.force, 4.0) * kb
			p.velocity.x = v.x
			p.velocity.z = v.z
			p.velocity.y = maxf(p.velocity.y, hit.lift * kb)
			p.states.enter_hitstun(clampf(0.35 + hit.force * 0.035 * kb, 0.4, 1.0))
		R.KNOCKDOWN:
			p.controller.cancel_current(&"hit")
			p.visual.reaction(R.KNOCKDOWN, dir, 1.0)
			var v := dir * hit.force * kb * 0.7
			p.velocity.x = v.x
			p.velocity.z = v.z
			p.velocity.y = maxf(p.velocity.y, hit.lift * kb * 0.5)
			p.states.enter_knockdown(false, clampf(maxf(hit.stun_time, 0.8), 0.6, 1.6))
		R.LAUNCH:
			p.controller.cancel_current(&"hit")
			p.visual.reaction(R.LAUNCH, dir, 1.0)
			var v := dir * hit.force * kb
			p.velocity = Vector3(v.x, maxf(hit.lift, 5.0) * clampf(kb, 0.6, 1.3), v.z)
			p.motor.on_floor = false
			p.states.enter_knockdown(true, 0.8)
		R.PULL:
			p.controller.cancel_current(&"hit")
			p.visual.reaction(&"pull", -dir, 1.0)
			var to := hit.origin - p.global_position
			to.y = 0.0
			var v := to.normalized() * maxf(hit.force, 4.0) * kb if to.length() > 0.5 else Vector3.ZERO
			p.velocity.x = v.x
			p.velocity.z = v.z
			p.states.enter_hitstun(clampf(maxf(hit.stun_time, 0.4), 0.3, 0.9))
		R.FREEZE:
			p.controller.cancel_current(&"hit")
			p.velocity = Vector3(0, minf(p.velocity.y, 0.0), 0)
			var t := clampf(maxf(hit.stun_time, 0.5), 0.3, 2.0)
			p.visual.reaction(R.FREEZE, dir, t)
			p.visual.tint(Color(0.7, 0.9, 1.0), 0.9)
			p.states.enter_hitstun(t)


static func _status(p: PlayerCharacter, hit: HitInfo) -> void:
	if hit.status.has("burn"):
		p.visual.tint(Color(1.0, 0.45, 0.2), 0.45)
	elif hit.status.has("soaked"):
		p.visual.tint(Color(0.45, 0.7, 1.0), 0.5)
	elif hit.status.has("chill") or hit.status.has("frozen"):
		p.visual.tint(Color(0.75, 0.92, 1.0), 0.55)
