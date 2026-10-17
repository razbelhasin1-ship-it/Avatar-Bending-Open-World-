extends BendingAbility
## Earth Armor (toggle technique). First press: a double stomp tears stone
## plates out of the ground, the arms sweep them up and a cross-slam on the
## chest locks them onto the body (EarthArmorState): damage reduction, poise,
## slower movement, chi draining every second. Second press: the bender bursts
## out of the armor - plates fly outward and knock back everyone close; the
## technique's cooldown starts then. Chi running out breaks the armor.
## Donning needs earth under the feet; shedding works anywhere.

var info: Dictionary = {}
var state: EarthArmorState = null
var shedding := false
var _done := false


func can_use() -> StringName:
	EarthCommon.prepare()
	if EarthArmorState.of(ctx.caster) != null:
		return &""
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	info = EarthEnv.feet(ctx)
	if not bool(info["ok"]):
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


## Shedding is free; donning costs the def's chi.
func chi_cost() -> float:
	return 0.0 if EarthArmorState.of(ctx.caster) != null else def.chi_cost


func begin() -> void:
	state = EarthArmorState.of(ctx.caster)
	shedding = state != null
	if not shedding and controller != null:
		# The cooldown starts when the armor comes off, not when it goes on.
		controller.cooldowns.erase(def.id)
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	var c: StringName = param("shed_clip", &"earth_armor_shed") if shedding else def.clip
	play_clip(c, {"speed": float(param("shed_speed", 1.1)) if shedding else def.clip_speed, "blend_in": 0.05})
	max_time = 3.0


func on_event(event: StringName) -> void:
	if shedding:
		if event == &"release" and not _done:
			_done = true
			_shed()
		return
	match event:
		&"gather":
			var g := EarthEnv.ground(ctx, ctx.origin())
			var gp: Vector3 = g["point"]
			state = EarthArmorState.don(ctx, info["kind"], maxf(time_to_event(&"armor"), 0.1), {
				"reduction": float(param("reduction", 0.4)), "poise": float(param("poise", 40.0)), "speed_scale": float(param("speed_scale", 0.78)),
				"drain": float(param("drain", 5.0)), "max_time": float(param("max_time", INF)) if ctx.resources != null else float(param("ai_time", 25.0))})
			EarthFx.quake(ctx.caster, gp, 1.8, info["kind"])
			sound(&"stomp", gp, -2.0)
			sound(&"debris", gp, -3.0)
			EarthEnv.shake(ctx, gp, 0.2, 0.15)
		&"armor":
			if state != null and is_instance_valid(state):
				state.attach()
				_done = true
				EarthEnv.shake(ctx, ctx.origin(), 0.22, 0.15)
				EarthEnv.note_weak(ctx, info)
				EarthEnv.practiced(ctx, def.id)


func _shed() -> void:
	if state == null or not is_instance_valid(state):
		return
	var h := hit_data(param("burst_hit", {}) as Dictionary)
	state.shed(h, float(param("burst_radius", 3.0)), attack_id, def.id)
	sound(&"wall_break", ctx.origin() + Vector3.UP, 0.0)
	sound(&"impact", ctx.origin() + Vector3.UP, -3.0)
	EarthEnv.shake(ctx, ctx.origin(), 0.3, 0.2)
	BendingFeedback.impulse(-ctx.forward(), 0.2)


func on_cancel(_reason: StringName) -> void:
	# Interrupted before the plates locked on: they drop back to the ground.
	if not shedding and not _done and state != null and is_instance_valid(state):
		state.break_off(&"interrupted")
		state = null

