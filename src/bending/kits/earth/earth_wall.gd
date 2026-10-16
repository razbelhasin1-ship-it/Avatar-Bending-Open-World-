extends BendingAbility
## Earth Wall (starter technique): stomp, cracks race to the aim point, and on
## the clip's release a 6 x 3 x 1 m wall erupts from the terrain there, its
## broad side facing the bender. It blocks movement and projectiles for 12 s
## (BendingConstruct, Layers.CONSTRUCT) and launches anyone standing on it.
## The wall is the ground it came from (granite, turf-capped earth, sandstone,
## basalt ...) and leaves broken ground along its base. Refused when the spot
## is ice, wood or deep water.

var _spot := Vector3.ZERO
var _facing := Vector3.FORWARD
var _info: Dictionary = {}


func can_use() -> StringName:
	EarthCommon.prepare()
	_pick_spot()
	_info = EarthEnv.material_at(ctx, _spot)
	if not bool(_info["ok"]):
		return EarthEnv.refuse(ctx, def.id, _info)
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1080.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, 25.0)
	if _info.is_empty():
		_pick_spot()
		_info = EarthEnv.material_at(ctx, _spot)
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
	var kind: StringName = _info.get("kind", &"dirt")
	if event == &"stomp":
		ctx.face_dir = Vector3.ZERO
		var g := ctx.ground_point(ctx.origin() + _facing * 0.6)
		EarthFx.quake(ctx.caster, g, 1.6, kind)
		EarthEnv.fissure(ctx, g + _facing * 0.4, _spot - _facing * 0.6, 0.45, kind)
		sound(&"stomp", g)
		EarthEnv.shake(ctx, g, 0.18, 0.15)
	elif event == &"release":
		var size: Vector3 = param("size", Vector3(6, 3, 1))
		var w := BendingConstruct.raise(ctx, _spot, -_facing, {"kind": &"earth", "size": size, "hp": float(param("hp", 180.0)) * EarthEnv.power(_info),
				"lifetime": float(param("lifetime", 12.0)), "rise_time": float(param("rise_time", 0.3)),
				"launch": {"lift": float(param("lift", 7.5)), "damage": 8.0}})
		EarthEnv.dress(w, EarthMeshes.slab(size, randi() % 4, kind))
		w.set_meta(&"surface", &"stone")
		# Broken ground along both faces of the wall.
		var side := Vector3(-_facing.z, 0.0, _facing.x)
		var a := _spot - side * size.x * 0.5
		var b := _spot + side * size.x * 0.5
		EarthRubble.spawn(ctx.caster, EarthRubble.line_xforms(a, b, 8, EarthEnv.ground_fn(ctx), 0.36, size.z * 0.9), kind, &"chunk",
				float(param("lifetime", 12.0)))
		EarthEnv.note_weak(ctx, _info)
		EarthEnv.practiced(ctx, def.id)
