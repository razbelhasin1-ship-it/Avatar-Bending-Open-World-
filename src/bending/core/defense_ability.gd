class_name DefenseAbility
extends BendingAbility
## Element defense held on the block button (docs/GAME_DESIGN.md §5):
## * frontal arc (params.arc half-angle, deg) blocks params.reduction of damage;
## * the first PARRY_WINDOW s is a parry: the hit is negated, the element's
##   counter fires (counter()), +15 Focus, the attacker is staggered;
## * chi upkeep (params.upkeep chi/s) while held; at 0 chi the guard breaks;
## * params.guard_hp (Earth Shield): sustained damage breaks the guard;
## * deflectable projectiles may be deflected (params.deflect) and redirected
##   back on a parry (params.redirect).
## The caster's receive_hit() asks the running defense via guard(hit).

const PARRY_WINDOW := 0.15

var guard_time := 0.0
var guard_hp := 0.0
var broken := false
var lowering := false
var _lower_t := 0.0
var _loop_id := 0


func begin() -> void:
	ctx.move_mode = BendingContext.Move.FREE
	ctx.move_speed_scale = float(param("walk_scale", 0.4))
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 720.0
	ctx.set_upkeep(float(param("upkeep", 5.0)))
	guard_hp = float(param("guard_hp", 0.0))
	if def.clip != &"":
		play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	if ctx.rig:
		ctx.rig.set_pose_state(&"blocking", 0.08)
	clip_end = INF
	max_time = 120.0
	_loop_id = Audio.start_bending_loop(ctx.element, &"shield_loop", ctx.caster, -6.0)
	BendingFeedback.sound(ctx.element, &"shield_up", ctx.hands_pos())
	on_guard_up()


func update(delta: float) -> void:
	if lowering:
		_lower_t += delta
		if _lower_t >= 0.12:
			finish()
		return
	guard_time += delta
	if ctx.aim_target() != null:
		ctx.face_dir = ctx.aim_flat()
	var min_hold := float(param("min_hold", 0.18))
	if not input_held and guard_time >= min_hold:
		lower()
		return
	if ctx.chi() <= 0.01 and float(param("upkeep", 5.0)) > 0.0:
		break_guard()
		return
	on_guard(delta)


func is_defending() -> bool:
	return not lowering and not broken


func in_parry_window() -> bool:
	return guard_time <= PARRY_WINDOW


## Is `hit` coming from inside the guarded arc?
func covers(hit: HitInfo) -> bool:
	if hit.unblockable:
		return false
	var arc := float(param("arc", 75.0))
	if arc >= 180.0:
		return true
	var from := hit.origin
	var to_attacker := from - ctx.origin()
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.04:
		to_attacker = -hit.direction
	return ctx.forward().dot(to_attacker.normalized()) >= cos(deg_to_rad(arc))


## Resolves a hit against the guard. Returns {"result": Combat.Result, "damage": float}.
func guard(hit: HitInfo) -> Dictionary:
	if not is_defending() or not covers(hit):
		return {"result": -1, "damage": hit.damage}
	var proj: Variant = hit.get_meta(&"projectile", null) if hit.has_meta(&"projectile") else null
	if in_parry_window():
		var attacker := hit.source as Node3D
		counter(hit, attacker)
		ctx.add_focus(15.0)
		if attacker != null and is_instance_valid(attacker) and not hit.is_projectile:
			var sh := ctx.make_hit({"damage": float(param("counter_damage", 6.0)), "reaction": HitInfo.Reaction.STAGGER, "force": 4.0,
					"stun": 0.6, "poise": 40.0}, attacker.global_position - ctx.origin(), 0, def.id)
			sh.position = BendingContext.target_point(attacker)
			BendingHits.deliver(ctx, attacker, sh)
		if proj is BendingProjectile and is_instance_valid(proj):
			if bool(param("redirect", false)) and hit.deflectable:
				var back := (BendingContext.target_point(attacker) - ctx.hands_pos()) if attacker != null and is_instance_valid(attacker) else -hit.direction
				(proj as BendingProjectile).redirect(back, ctx.team, ctx.caster)
			else:
				(proj as BendingProjectile).destroy(true)
		ImpactFx.parry(ctx.caster, ctx.element, ctx.hands_pos())
		BendingFeedback.sound(ctx.element, &"parry", ctx.hands_pos())
		BendingFeedback.impulse(-hit.direction, 0.25)
		if ctx.rig:
			ctx.rig.play_action(&"parry_r" if randf() < 0.5 else &"parry_l", {"blend_in": 0.03})
		on_parry(hit)
		return {"result": Combat.Result.DEFLECTED, "damage": 0.0}
	var reduction := clampf(float(param("reduction", 0.7)), 0.0, 1.0)
	var dmg := hit.damage * (1.0 - reduction)
	if guard_hp > 0.0:
		guard_hp -= hit.damage * (1.5 if hit.is_heavy else 1.0)
		if guard_hp <= 0.0:
			break_guard()
	if proj is BendingProjectile and is_instance_valid(proj) and bool(param("deflect", false)) and hit.deflectable:
		var side := ctx.right() * (1.0 if randf() < 0.5 else -1.0)
		(proj as BendingProjectile).redirect((side + Vector3.UP * 0.3 - hit.direction * 0.3).normalized(), ctx.team, ctx.caster, 0.8)
		dmg = 0.0
	elif proj is BendingProjectile and is_instance_valid(proj) and bool(param("burn_projectiles", false)):
		(proj as BendingProjectile).destroy(true)
	if ctx.rig and not broken:
		ctx.rig.play_action(&"block_impact", {"blend_in": 0.02})
	ctx.spend_chi(float(param("chi_per_block", 3.0)))
	on_block(hit)
	return {"result": Combat.Result.BLOCKED, "damage": dmg}


func lower() -> void:
	if lowering:
		return
	lowering = true
	_lower_t = 0.0
	ctx.set_upkeep(0.0)
	_end_visuals()


func break_guard() -> void:
	if broken:
		return
	broken = true
	ctx.set_upkeep(0.0)
	on_guard_break()
	_end_visuals()
	if controller and controller.has_signal(&"ability_failed"):
		controller.emit_signal(&"ability_failed", def.id, &"guard_broken")
	finish()


func _end_visuals() -> void:
	if ctx.rig and ctx.rig.get_pose_state() == &"blocking":
		ctx.rig.set_pose_state(&"normal", 0.12)
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.15)
		_loop_id = 0
	on_guard_down()


func on_cancel(_reason: StringName) -> void:
	_end_visuals()


func on_finish() -> void:
	if not lowering and not broken:
		_end_visuals()


# --- overridables ----------------------------------------------------------------------------

func on_guard_up() -> void:
	pass


func on_guard(_delta: float) -> void:
	pass


func on_guard_down() -> void:
	pass


func on_guard_break() -> void:
	pass


func on_block(_hit: HitInfo) -> void:
	pass


func on_parry(_hit: HitInfo) -> void:
	pass


## Element-specific parry counter (default: none beyond the stagger).
func counter(_hit: HitInfo, _attacker: Node3D) -> void:
	pass
