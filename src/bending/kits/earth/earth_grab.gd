extends BendingAbility
## Earth Grab (technique). Reach out with an open claw - a ripple runs under the
## ground to the target's feet - then clench and yank: stone jaws burst out and
## clamp the target's legs (FREEZE: rooted 2.5 s, EarthShackleFx), the earth
## piled around them. Only grounded targets are caught (a jump in time escapes);
## from the ground, it cannot be blocked. Missed, the jaws snap shut on empty
## ground. The player's grab tracks the target until the clench; enemy casters
## commit when the ripple starts (dodge out of the ring).

const STONE_TINT := Color(0.62, 0.55, 0.47)

var info: Dictionary = {}
var target: Node3D = null
var spot := Vector3.ZERO
var grabbed: Array[Node] = []
var shackle: EarthShackleFx = null
var _locked := false
var _done := false


func can_use() -> StringName:
	EarthCommon.prepare()
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	_choose()
	info = EarthEnv.material_at(ctx, spot)
	if not bool(info["ok"]):
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


func _choose() -> void:
	var rng := float(param("range", 14.0))
	var t := ctx.aim_target()
	if t != null:
		var d := t.global_position - ctx.origin()
		d.y = 0.0
		if d.length() <= rng:
			target = t
			spot = t.global_position
			return
	target = null
	var dist := float(param("distance", 7.0))
	var a: Dictionary = ctx.aim()
	var pt: Vector3 = a.get("point", Vector3.INF)
	if pt.is_finite():
		var to := pt - ctx.origin()
		to.y = 0.0
		if to.length() > 1.0 and to.normalized().dot(ctx.aim_flat()) > 0.5:
			dist = clampf(to.length(), 2.0, rng)
	spot = ctx.origin() + ctx.aim_flat() * dist


func begin() -> void:
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = _flat_to(spot)
	ctx.face_rate = 1080.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	max_time = 3.0


func _flat_to(p: Vector3) -> Vector3:
	var d := p - ctx.origin()
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.04 else ctx.aim_flat()


func _track() -> void:
	if not _locked and target != null and is_instance_valid(target):
		spot = target.global_position


func update(delta: float) -> void:
	if not _done and ctx.is_player():
		_track()
		ctx.face_dir = _flat_to(spot)
	super.update(delta)


func on_event(event: StringName) -> void:
	match event:
		&"release":
			_track()
			if not ctx.is_player():
				_locked = true
			var from := ctx.ground_point(ctx.origin() + _flat_to(spot) * 0.8)
			var to := Vector3(spot.x, EarthEnv.ground_y(ctx, spot), spot.z)
			var dur := maxf(time_to_event(&"grab"), 0.12)
			EarthBurrowFx.spawn(ctx.caster, from, to, dur, info["kind"], EarthEnv.ground_fn(ctx))
			sound(&"debris", from, -2.0)
			if not ctx.is_player():
				FxRing.spawn(ctx.caster, to, float(param("radius", 1.25)), EarthPalette.color(info["kind"], "dust"), dur + 0.1,
						{"opacity": 0.5, "width": 0.18, "fill": 0.25})
		&"grab":
			_grab()


func _grab() -> void:
	if _done:
		return
	_done = true
	ctx.face_dir = Vector3.ZERO
	_track()
	var m := EarthEnv.material_at(ctx, spot)
	if not bool(m["ok"]):
		EarthEnv.refuse(ctx, def.id, m)
		return
	info = m
	var gp: Vector3 = m["ground"]
	var radius := float(param("radius", 1.25))
	var hold := float(param("hold", 2.5))
	var h := EarthEnv.scaled_hit(hit_data(), m)
	h["stun"] = hold
	var results := BendingHits.sphere(ctx, gp + Vector3.UP * 0.5, radius, h, attack_id, def.id, {"push": &"pull", "los": false})
	var caught: Node3D = null
	for r: Dictionary in results:
		var res := int(r["result"])
		if res == Combat.Result.HIT or res == Combat.Result.KILLED:
			grabbed.append(r["target"])
			stone_tint(r["target"])
			if caught == null:
				caught = r["target"] as Node3D
	var at := gp
	if caught != null:
		at = Vector3(caught.global_position.x, EarthEnv.ground_y(ctx, caught.global_position + Vector3.UP * 0.5), caught.global_position.z)
	shackle = EarthShackleFx.spawn(ctx.caster, at, m["kind"], caught, hold if caught != null else 0.45)
	sound(&"wall", at, -2.0)
	sound(&"impact", at, -4.0)
	EarthEnv.shake(ctx, at, 0.22, 0.15)
	EarthEnv.note_weak(ctx, m)
	EarthEnv.practiced(ctx, def.id)


## Gripped by rock, not frozen: a dusty stone tint over the FREEZE reaction's ice tint.
static func stone_tint(t: Node) -> void:
	if t == null or not is_instance_valid(t):
		return
	var vis: Variant = t.get("visual") if "visual" in t else null
	if vis is Object and (vis as Object).has_method("tint"):
		(vis as Object).call("tint", STONE_TINT, 0.35)
	var rig: Variant = t.get("rig") if "rig" in t else null
	if rig is HumanoidRig:
		(rig as HumanoidRig).set_status_tint(STONE_TINT, 0.4)
