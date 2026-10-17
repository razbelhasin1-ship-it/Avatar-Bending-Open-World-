extends ComboAbility
## Water Whip: a lash of water extends from the hand, cracks at the clip's
## impact frame (capsule sweep along the whip) and recoils. The third lash is
## two-handed and yanks the target in (PULL). Water streams in from a nearby
## source on the first lash and stays the same body of water through the whole
## chain (passed from hand to hand); when the chain ends it falls and splashes.
## Without a source the whip is shorter and thinner.

var _stream: WaterStream = null
var _t0 := 0.0
var _t_hit := 0.1
var _reach := 5.0
var _side := 1.0
var _src: Dictionary = {}
var _tip := Vector3.ZERO


func on_step_begin(i: int, sd: Dictionary) -> void:
	if i == first_step:
		WaterCommon.prepare()
	_src = WaterSource.find(ctx)
	_reach = float(sd.get("reach", 5.0)) * (1.0 if bool(_src.get("found", false)) else 0.8)
	_t0 = time
	_t_hit = maxf(time_to_event(StringName(sd.get("event", &"impact"))), 0.05)
	_side = 1.0 if StringName(sd.get("hand", &"hand_r")) == &"hand_r" else -1.0
	if StringName(sd.get("hand", &"")) == &"hands":
		_side = 0.0
	# The same water carries over between lashes.
	if _stream == null or not is_instance_valid(_stream):
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
		# Recoil: the lash stays out a moment after the crack, then retracts.
		var hold := 0.06
		e = clampf(1.0 - (time - _t0 - _t_hit - hold) / maxf(clip_end - _t0 - _t_hit - hold, 0.08), 0.0, 1.0)
		e = e * e * (3.0 - 2.0 * e)
	var length := _reach * maxf(e, 0.04)
	# The lash swings in from the side (its tip sweeping across toward the
	# target) and keeps a visible arc at the crack: seen from behind the
	# bender, a straight lash pointing away would vanish.
	var sweep := 1.0 - clampf(u, 0.0, 1.0)
	var side := _side if _side != 0.0 else 0.6
	var tip_dir := dir.rotated(Vector3.UP, -deg_to_rad(80.0) * side * sweep)
	var bend := sweep * 0.6 + 0.4
	var p2 := hand + tip_dir * length
	var p1 := hand + dir * length * 0.55 + right * side * bend * length * 0.36 + Vector3.UP * (0.45 + 0.45 * bend) * minf(length, 3.0) / 3.0
	var pts := PackedVector3Array()
	for k in 9:
		var s := float(k) / 8.0
		pts.append(hand.lerp(p1, s).lerp(p1.lerp(p2, s), s))
	_tip = pts[8]
	var r := float(param("whip_radius", 0.42)) * (1.0 if bool(_src.get("found", false)) else 0.8)
	_stream.set_points(pts, 0.13 * (r / 0.42), 0.075 * (r / 0.42))
	_stream.set_spray(e > 0.6 and u <= 1.2)


func strike(_i: int, sd: Dictionary) -> void:
	_update_stream()
	var hand := _hand()
	var h := step_hit()
	var push: StringName = &"pull" if bool(sd.get("pull", false)) else &"forward"
	var res := BendingHits.sweep(ctx, hand, _tip, float(param("whip_radius", 0.42)), h, attack_id, def.id, {"push": push})
	sound(&"cast_light", _tip, -1.0)
	# The crack: a spray burst at the tip, hit or miss.
	FxBurst.spawn(ctx.caster, &"droplets", _tip, {"count": 0.6, "size": 0.8})
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
	# Interrupted (hit, dodge): the water falls.
	_drop_water()


func on_finish() -> void:
	_drop_water()


## The lash water falls to the ground when the chain ends.
func _drop_water() -> void:
	if _stream != null and is_instance_valid(_stream):
		var g := ctx.ground_point(_tip) if ctx.is_valid() else _tip
		if ctx.is_valid() and _tip != Vector3.ZERO:
			WaterEnv.splash_ground(ctx.caster, g, 0.45)
	_end_stream(0.15)
