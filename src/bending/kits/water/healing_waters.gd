extends BendingAbility
## Healing Waters (unlock): hold - rooted, head bowed, the bender draws water
## into both hands (from the source, or the canteen) where it glows, and
## presses it to the body: heals params.rate HP/s (allies within
## params.ally_radius get half) up to params.max_heal per use. Balanced by an
## up-front chi cost, chi upkeep while channelling, a long cooldown and the
## vulnerability of standing still (any staggering hit interrupts it).
## Clip: water_heal_channel (hold), glow starts on &"gather".

var _src: Dictionary = {}
var _size := 1.0
var healed := 0.0
var channel := 0.0
var glowing := false
var _orbs: Array[WaterStream] = []
var _light: FxFlash = null
var _loop_id := 0
var _sparkle := 0.0
var _stopped := false
var _ally_healed: Dictionary = {}


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func can_use() -> StringName:
	var h := WaterCommon.health_of(ctx.caster)
	if h != null and h.health >= h.max_health - 0.5 and not _ally_needs_healing():
		return &"full_health"
	return &""


func _ally_needs_healing() -> bool:
	for n in ctx.tree().get_nodes_in_group(&"damageable"):
		if n == ctx.caster or not (n is Node3D) or not ("team" in n) or int(n.get("team")) != ctx.team:
			continue
		if (n as Node3D).global_position.distance_to(ctx.origin()) > float(param("ally_radius", 3.5)):
			continue
		var h := WaterCommon.health_of(n)
		if h != null and h.health < h.max_health - 0.5:
			return true
	return false


func begin() -> void:
	WaterCommon.prepare()
	_src = WaterSource.find(ctx)
	_size = WaterSource.size_mult(ctx)
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.1})
	clip_end = INF
	max_time = float(param("max_hold", 4.0)) + 2.0
	var c := ctx
	WaterCommon.pull(ctx, _src, func() -> Vector3: return c.hands_pos() if c.is_valid() else Vector3.ZERO, maxf(time_to_event(&"gather"), 0.15), 0.1, 2)


func on_event(event: StringName) -> void:
	if event == &"gather" and not glowing and not _stopped:
		glowing = true
		ctx.set_upkeep(float(param("upkeep", 6.0)))
		var c := ctx
		for sock: StringName in [&"hand_l", &"hand_r"]:
			var s := sock
			_orbs.append(WaterFx.orb(ctx.caster, func() -> Vector3: return c.socket_pos(s) if c.is_valid() else Vector3.ZERO, 0.16, 1.4))
		if FxLib.tier() > 0:
			_light = FxFlash.attach(ctx.caster, ctx.caster, Color(0.45, 0.85, 1.0), 1.6, 3.5)
		_loop_id = Audio.start_bending_loop(ctx.element, &"heal_loop", ctx.caster, -4.0)
		FxBurst.spawn(ctx.caster, &"sparkle", ctx.hands_pos(), {"count": 1.2, "color": Color(0.6, 0.95, 1.0)})


func update(delta: float) -> void:
	if _stopped:
		if time >= clip_end:
			finish()
		return
	if glowing:
		channel += delta
		var rate := float(param("rate", 10.0)) * lerpf(0.75, 1.0, _size)
		var cap := float(param("max_heal", 35.0))
		var amount := minf(rate * delta, cap - healed)
		var h := WaterCommon.health_of(ctx.caster)
		if h != null and amount > 0.0 and h.health < h.max_health:
			var before := h.health
			h.heal(amount)
			healed += h.health - before
		_heal_allies(amount * 0.5)
		_sparkle -= delta
		if _sparkle <= 0.0:
			_sparkle = 0.25
			FxBurst.spawn(ctx.caster, &"sparkle", ctx.origin() + Vector3.UP * 1.1, {"count": 0.6, "color": Color(0.6, 0.95, 1.0), "radius": 1.4})
		var full := h == null or h.health >= h.max_health - 0.01
		var done := healed >= cap - 0.01 or (full and not _ally_needs_healing())
		if (not input_held and channel >= float(param("min_hold", 0.5))) or channel >= float(param("max_hold", 4.0)) or done or ctx.chi() <= 0.5:
			_stop()
	# Released before the water reached the hands: the gather still completes
	# (no free cancel), then min_hold applies.


func _heal_allies(amount: float) -> void:
	if amount <= 0.0:
		return
	var r := float(param("ally_radius", 3.5))
	for n in ctx.tree().get_nodes_in_group(&"damageable"):
		if n == ctx.caster or not (n is Node3D) or not ("team" in n) or int(n.get("team")) != ctx.team:
			continue
		if (n as Node3D).global_position.distance_to(ctx.origin()) > r:
			continue
		var h := WaterCommon.health_of(n)
		if h == null or h.is_dead():
			continue
		var got := float(_ally_healed.get(n.get_instance_id(), 0.0))
		var a := minf(amount, float(param("max_heal", 35.0)) * 0.5 - got)
		if a > 0.0:
			h.heal(a)
			_ally_healed[n.get_instance_id()] = got + a


func _stop() -> void:
	if _stopped:
		return
	_stopped = true
	ctx.set_upkeep(0.0)
	_end_visuals()
	if healed > 0.0:
		FxBurst.spawn(ctx.caster, &"sparkle", ctx.origin() + Vector3.UP * 1.2, {"count": 1.5, "color": Color(0.6, 0.95, 1.0), "spread": 180.0})
		WaterCommon.practiced(ctx, def)
	if ctx.rig and ctx.rig.current_action() == def.clip:
		ctx.rig.stop_action(0.25)
	clip_end = time + 0.25


func _end_visuals() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.3)
		_loop_id = 0
	for o in _orbs:
		if is_instance_valid(o):
			o.finish(0.3)
	_orbs.clear()
	if _light != null and is_instance_valid(_light):
		_light.fade_out(0.3)
	_light = null


func on_cancel(_reason: StringName) -> void:
	_end_visuals()
	ctx.set_upkeep(0.0)


func on_finish() -> void:
	_end_visuals()
	ctx.set_upkeep(0.0)
	if ctx.rig and ctx.rig.current_action() == def.clip:
		ctx.rig.stop_action(0.25)
