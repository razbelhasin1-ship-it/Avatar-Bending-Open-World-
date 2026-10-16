extends BendingAbility
## Earth Wall (starter technique): stomp, cracks race to the aim point, and on
## the clip's release a 6 x 3 x 1 m wall erupts from the terrain there, its
## broad side facing the bender. It blocks movement and projectiles for 12 s
## (BendingConstruct, Layers.CONSTRUCT) and launches anyone standing on it.

var _spot := Vector3.ZERO
var _facing := Vector3.FORWARD


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1080.0
	ctx.poise_armor = 25.0
	_pick_spot()
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})


func _pick_spot() -> void:
	var dist := float(param("distance", 4.5))
	var dir := ctx.aim_flat()
	var t := ctx.aim_target()
	if t != null:
		var to := t.global_position - ctx.origin()
		to.y = 0.0
		dir = to.normalized() if to.length() > 0.5 else dir
		# Between the bender and the target, never on top of either.
		dist = clampf(to.length() * 0.5, 2.6, 7.0)
	_facing = dir
	_spot = ctx.ground_point(ctx.origin() + dir * dist)


func on_event(event: StringName) -> void:
	if event == &"stomp":
		ctx.face_dir = Vector3.ZERO
		var g := ctx.ground_point(ctx.origin() + _facing * 0.6)
		EarthFx.quake(ctx.caster, g, 1.6, ctx.surface_at(g))
		FxDecal.spawn(ctx.caster, _spot, &"crack", 2.2)
		sound(&"stomp", g)
		if ctx.is_player():
			BendingFeedback.shake(0.18, 0.15)
	elif event == &"release":
		var size: Vector3 = param("size", Vector3(6, 3, 1))
		BendingConstruct.raise(ctx, _spot, -_facing, {"kind": &"earth", "size": size, "hp": float(param("hp", 180.0)),
				"lifetime": float(param("lifetime", 12.0)), "rise_time": float(param("rise_time", 0.3)),
				"launch": {"lift": float(param("lift", 7.5)), "damage": 8.0}})
