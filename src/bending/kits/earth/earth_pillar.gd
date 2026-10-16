extends BendingAbility
## Earth Pillar (starter technique). Chamber the knee, stomp - cracks race over
## the ground to the target - and a double uppercut makes a stone column erupt
## beneath it: LAUNCH. The column stays as cover / a platform (BendingConstruct:
## blocks movement, projectiles and sight) and crumbles after its lifetime.
## * Target (lock / soft aim within range): erupts under the target (the player
##   tracks it until the release; enemy casters commit when the cast starts, with
##   the ground rumbling there: dodge it).
## * No target: erupts at the aim point (cover / a stepping block).
## * Player holding the button through the release: the column rises under the
##   bender and carries them up 3 m (high ground, ledges, traversal).
## Needs earth: refused on ice, wood or deep water (EarthEnv).

enum Mode { TARGET, SPOT, SELF }

var mode := Mode.SPOT
var target: Node3D = null
var spot := Vector3.ZERO
var info: Dictionary = {}
var pillar: BendingConstruct = null
var raised := false
## Tests / scripted casters: force the self-lift regardless of the button.
var self_lift := false
var _locked := false
var _lift := false
var _lift_from := 0.0
var _lift_to := 0.0
var _lift_t := 0.0
var _lift_dur := 0.3
var _rumble_t := 0.0


func can_use() -> StringName:
	EarthCommon.prepare()
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	_choose()
	info = EarthEnv.material_at(ctx, spot)
	if not bool(info["ok"]):
		# Nothing at the target: maybe under the bender (traversal) is still fine,
		# but the tap would do nothing visible - refuse with feedback.
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


func _choose() -> void:
	var rng := float(param("range", 16.0))
	var t := ctx.aim_target()
	if t != null:
		var d := t.global_position - ctx.origin()
		d.y = 0.0
		if d.length() <= rng and d.length() >= 1.2:
			mode = Mode.TARGET
			target = t
			spot = t.global_position
			return
	mode = Mode.SPOT
	target = null
	var a: Dictionary = ctx.aim()
	var pt: Vector3 = a.get("point", Vector3.INF)
	var dir := ctx.aim_flat()
	var dist := float(param("distance", 5.0))
	if pt.is_finite():
		var to := pt - ctx.origin()
		to.y = 0.0
		if to.length() > 0.1 and to.normalized().dot(dir) > 0.5:
			dist = clampf(to.length(), float(param("min_distance", 2.6)), rng)
	spot = ctx.origin() + dir * dist


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = _flat_to(spot)
	ctx.face_rate = 1080.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	max_time = 3.5
	if not ctx.is_player():
		# Enemy casters commit to the spot now and the ground rumbles there for the
		# whole wind-up: readable and dodgeable.
		_locked = true
		_rumble(spot, 1.0)


func _flat_to(p: Vector3) -> Vector3:
	var d := p - ctx.origin()
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.04 else ctx.aim_flat()


func _rumble(p: Vector3, size: float) -> void:
	var g := EarthEnv.ground(ctx, p)
	var gp: Vector3 = g["point"]
	FxRing.spawn(ctx.caster, gp, 1.25, EarthPalette.color(info.get("kind", &"dirt"), "dust"), 0.5, {"opacity": 0.45, "width": 0.18, "fill": 0.2})
	FxBurst.spawn(ctx.caster, &"dust", gp, {"color": EarthPalette.color(info.get("kind", &"dirt"), "dust"), "count": 0.45 * size, "size": 0.7, "speed": 0.6})
	FxDebris.spawn(ctx.caster, gp + Vector3.UP * 0.05, {"count": 4, "size": 0.07, "up": 2.2, "out": 0.8, "ground_y": gp.y,
			"color": EarthPalette.color(info.get("kind", &"dirt"), "debris")})


func on_event(event: StringName) -> void:
	match event:
		&"stomp":
			ctx.face_dir = Vector3.ZERO
			var feet := EarthEnv.ground(ctx, ctx.origin() + ctx.forward() * 0.35)
			var fp: Vector3 = feet["point"]
			var fk: StringName = EarthEnv.classify(fp, feet["collider"])
			EarthFx.quake(ctx.caster, fp, 1.3, fk if EarthEnv.KINDS.has(fk) else info["kind"])
			sound(&"stomp", fp, -2.0)
			if mode != Mode.SELF and not _wants_self():
				_track()
				var gs := EarthEnv.ground_y(ctx, spot)
				var to := Vector3(spot.x, gs, spot.z)
				if fp.distance_to(to) > 1.6:
					EarthEnv.fissure(ctx, fp + _flat_to(to) * 0.6, to, 0.45, info["kind"])
				_rumble(to, 1.0)
			EarthEnv.shake(ctx, fp, 0.16, 0.12)
		&"release":
			_raise()


func _wants_self() -> bool:
	return self_lift or (ctx.is_player() and input_held and bool(param("self_lift", true)))


func _track() -> void:
	if mode == Mode.TARGET and not _locked and target != null and is_instance_valid(target):
		spot = target.global_position


func _raise() -> void:
	if raised:
		return
	raised = true
	if _wants_self():
		var feet := EarthEnv.feet(ctx)
		var terrain := WorldData.get_height(ctx.origin().x, ctx.origin().z)
		if bool(feet["ok"]) and ctx.origin().y - terrain < float(param("max_stack", 6.0)):
			mode = Mode.SELF
			info = feet
			spot = ctx.origin()
	_track()
	if mode != Mode.SELF:
		var m := EarthEnv.material_at(ctx, spot)
		if not bool(m["ok"]):
			# The target stepped onto ice / into deep water: nothing rises.
			EarthEnv.refuse(ctx, def.id, m)
			return
		info = m
	var gp: Vector3 = info["ground"]
	var kind: StringName = info["kind"]
	var pw := EarthEnv.power(info)
	var self_mode := mode == Mode.SELF
	var height := float(param("self_height", 3.0)) if self_mode else float(param("height", 2.8)) * lerpf(1.0, pw, 0.5)
	var rise := float(param("self_rise_time", 0.32)) if self_mode else float(param("rise_time", 0.16))
	var facing := ctx.forward() if self_mode else -_flat_to(gp)
	pillar = EarthEnv.raise_pillar(ctx, gp, facing, {"radius": float(param("radius", 0.75)) * lerpf(1.0, pw, 0.4), "height": height,
			"hp": float(param("hp", 120.0)) * pw, "lifetime": float(param("lifetime", 9.0)), "rise_time": rise, "kind": kind})
	EarthEnv.crater(ctx, gp, 1.25, kind)
	FxBurst.spawn(ctx.caster, &"dust_ring", gp, {"color": EarthPalette.color(kind, "dust"), "radius": 0.9, "count": 1.1})
	sound(&"launch", gp)
	EarthEnv.shake(ctx, gp, 0.3, 0.22)
	EarthEnv.note_weak(ctx, info)
	EarthEnv.practiced(ctx, def.id)
	if self_mode:
		_start_lift(gp.y + height, rise)
	else:
		# Whoever stands where it erupts is launched (from beneath: unblockable).
		BendingHits.sphere(ctx, gp + Vector3.UP * 0.7, float(param("launch_radius", 1.15)), EarthEnv.scaled_hit(hit_data(), info), attack_id, def.id,
				{"push": &"radial", "los": false})


func _start_lift(top_y: float, rise: float) -> void:
	_lift = true
	_lift_from = ctx.origin().y
	_lift_to = top_y + 0.02
	_lift_t = 0.0
	_lift_dur = maxf(rise, 0.05)
	ctx.move_mode = BendingContext.Move.HOLD
	ctx.gravity_scale = 0.0
	ctx.poise_armor = 999.0
	clip_end = maxf(clip_end, time + _lift_dur + 0.15)


func update(delta: float) -> void:
	if not raised and mode == Mode.TARGET and ctx.is_player():
		_track()
		ctx.face_dir = _flat_to(spot)
	if _lift:
		_lift_t += delta
		var u := clampf(_lift_t / _lift_dur, 0.0, 1.0)
		# Same ease-out-back as the column (BendingConstruct), never below the start.
		var e := 1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0)
		var p := ctx.caster.global_position
		p.y = maxf(_lift_from, lerpf(_lift_from, _lift_to, minf(e, 1.0)))
		ctx.caster.global_position = p
		if ctx.body:
			ctx.body.velocity = Vector3.ZERO
		if u >= 1.0:
			_end_lift()
	if time >= clip_end:
		finish()


## The bender now stands on top: collide with the column again.
func _end_lift() -> void:
	if not _lift:
		return
	_lift = false
	ctx.gravity_scale = 1.0
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	if pillar != null and is_instance_valid(pillar) and ctx.caster is PhysicsBody3D:
		var p := ctx.caster.global_position
		ctx.caster.global_position = Vector3(p.x, maxf(p.y, _lift_to), p.z)
		pillar.remove_collision_exception_with(ctx.caster as PhysicsBody3D)


func on_cancel(_reason: StringName) -> void:
	_end_lift()


func on_finish() -> void:
	_end_lift()
