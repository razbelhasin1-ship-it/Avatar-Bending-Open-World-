extends ComboAbility
## Water Whip: a lash of water extends from the hand, cracks at the clip's
## impact frame (capsule sweep along the whip) and recoils. The third lash is
## two-handed and yanks the target in (PULL). Water streams in from a nearby
## source on the first lash; without a source the whip is shorter.

var _stream: WaterStream = null
var _t0 := 0.0
var _t_hit := 0.1
var _reach := 5.0
var _side := 1.0
var _src: Dictionary = {}
var _tip := Vector3.ZERO


func on_step_begin(i: int, sd: Dictionary) -> void:
	_end_stream(0.05)
	_src = WaterSource.find(ctx)
	_reach = float(sd.get("reach", 5.0)) * (1.0 if bool(_src.get("found", false)) else 0.8)
	_t0 = time
	_t_hit = maxf(time_to_event(StringName(sd.get("event", &"impact"))), 0.05)
	_side = 1.0 if StringName(sd.get("hand", &"hand_r")) == &"hand_r" else -1.0
	if StringName(sd.get("hand", &"")) == &"hands":
		_side = 0.0
	_stream = WaterStream.spawn(ctx.caster)
	if i == first_step and bool(_src.get("found", false)) and float(_src.get("distance", 0.0)) > 1.5:
		WaterSource.draw(ctx, _src, _t_hit * 1.5, StringName(sd.get("hand", &"hand_r")) if _side != 0.0 else &"hand_r")
	_update_stream()


func update(delta: float) -> void:
	_update_stream()
	super.update(delta)


func _hand() -> Vector3:
	var h := StringName(_step_data.get("hand", &"hand_r"))
	return ctx.hands_pos() if h == &"hands" else ctx.socket_pos(h)


func _update_stream() -> void:
	if _stream == null or not is_instance_valid(_stream):
		return
	var hand := _hand()
	var dir := ctx.aim_dir_from(hand, 0.0)
	dir.y = clampf(dir.y, -0.25, 0.25)
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var e := 0.0
	var u := (time - _t0) / maxf(_t_hit, 0.01)
	if u <= 1.0:
		e = 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 2.2)
	else:
		e = clampf(1.0 - (time - _t0 - _t_hit) / maxf(clip_end - _t0 - _t_hit, 0.05), 0.0, 1.0)
		e = e * e * (3.0 - 2.0 * e)
	var length := _reach * maxf(e, 0.04)
	# The lash curls sideways while it travels and straightens at the crack.
	var bend := (1.0 - clampf(u, 0.0, 1.0)) * 0.9 + 0.12
	var pts := PackedVector3Array()
	for k in 6:
		var s := float(k) / 5.0
		var p := hand + dir * length * s
		p += right * _side * sin(PI * s) * bend * length * 0.22
		p += Vector3.UP * sin(PI * s * 1.3) * 0.25 * bend
		pts.append(p)
	_tip = pts[5]
	var r := float(param("whip_radius", 0.42)) * (1.0 if bool(_src.get("found", false)) else 0.8)
	_stream.set_points(pts, 0.075 * (r / 0.42), 0.055 * (r / 0.42))
	_stream.set_spray(e > 0.6 and u <= 1.2)


func strike(_i: int, sd: Dictionary) -> void:
	_update_stream()
	var hand := _hand()
	var h := step_hit()
	var push: StringName = &"pull" if bool(sd.get("pull", false)) else &"forward"
	var res := BendingHits.sweep(ctx, hand, _tip, float(param("whip_radius", 0.42)), h, attack_id, def.id, {"push": push})
	sound(&"cast_light", _tip, -1.0)
	if BendingHits.count_landed(res) == 0:
		var gy := ctx.ground_y(_tip, 1.0, 2.0)
		if _tip.y - gy < 0.8:
			IceFx.splash(ctx.caster, Vector3(_tip.x, gy, _tip.z), 0.5, Vector3.UP, gy)
		else:
			FxBurst.spawn(ctx.caster, &"droplets", _tip, {"count": 0.5})


func _end_stream(fade: float) -> void:
	if _stream and is_instance_valid(_stream):
		_stream.finish(fade)
	_stream = null


func on_cancel(_reason: StringName) -> void:
	_end_stream(0.15)


func on_finish() -> void:
	_end_stream(0.15)
