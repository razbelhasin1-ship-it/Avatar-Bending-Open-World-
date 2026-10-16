extends BendingAbility
## Fire Whip: the right hand circles back over the head (fire_whip_lash) and, from
## &"release", a lash of flame uncoils from the fist and sweeps a 110° arc in front -
## from high on the right down to the ground on the left, reaching 7.5 m - cracking at
## &"impact". Everything the lash passes through is hit once (STAGGER + burn); the last
## 1.6 m (the tip) hits harder (KNOCKBACK). The lash is a gameplay object: its hit
## capsules are the drawn curve (plus the space it swept since the last tick, so a fast
## tip never skips a target). Walls between the hand and a target stop it.

const SEGMENTS := 10

var _whip: FireWhipFx = null
var _sweep_t := -1.0
var _sweep_time := 0.16
var _cracked := false
var _prev_pts := PackedVector3Array()
var _yaw_basis := Basis.IDENTITY
var _origin := Vector3.ZERO


func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.BRAKE
	ctx.brake_rate = 30.0
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1440.0
	ctx.poise_armor = def.poise_armor
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.05})
	var tr := time_to_event(&"release")
	var ti := time_to_event(&"impact")
	if tr < INF and ti < INF:
		_sweep_time = maxf(0.08, ti - tr)


func on_event(event: StringName) -> void:
	match event:
		&"release":
			ctx.face_dir = Vector3.ZERO
			var f := ctx.aim_flat()
			_yaw_basis = Basis(Vector3.UP, atan2(-f.x, -f.z))
			_origin = ctx.origin()
			_sweep_t = 0.0
			_whip = FireWhipFx.spawn(ctx.caster)
			FireCommon.ignite_limb(ctx, &"hand_r", 1.0)
			sound(&"cast_light", ctx.socket_pos(&"hand_r"), 1.0)
			_step(0.0)
		&"impact":
			_crack()


## Whip curve at sweep progress u (0..1+): hand -> curved body -> tip.
func _curve(u: float) -> PackedVector3Array:
	var reach := float(param("reach", 7.5))
	var half := deg_to_rad(float(param("arc", 110.0)) * 0.5)
	var k := clampf(u, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 2.0)
	# Sweep from the right (+half) to the left (-half), high to the ground.
	var ang := lerpf(half, -half, e)
	var length := lerpf(2.6, reach, smoothstep(0.0, 0.55, k))
	var height := lerpf(2.5, 0.25, pow(k, 1.2))
	var hand := ctx.socket_pos(&"hand_r") if ctx.is_valid() else _origin + Vector3.UP * 1.4
	var local_tip := Vector3(sin(ang), 0.0, -cos(ang)) * length
	var tip := _origin + _yaw_basis * local_tip
	tip.y = _origin.y + height
	# The body lags behind the sweep (a whip, not a stick): bend the middle against
	# the direction the tip travels and lift it a little.
	var travel := _yaw_basis * Vector3(-cos(ang), 0.0, -sin(ang))
	var mid := hand.lerp(tip, 0.5) - travel * 0.9 * (1.0 - k * 0.6) + Vector3.UP * (0.6 * (1.0 - k))
	var pts := PackedVector3Array()
	for i in SEGMENTS + 1:
		var s := float(i) / SEGMENTS
		var a := hand.lerp(mid, s)
		var b := mid.lerp(tip, s)
		pts.append(a.lerp(b, s))
	return pts


func update(delta: float) -> void:
	if _sweep_t >= 0.0:
		_sweep_t += delta
		_step(delta)
	if time >= clip_end:
		finish()


func _step(_delta: float) -> void:
	var u := _sweep_t / _sweep_time
	var pts := _curve(u)
	if _whip != null and is_instance_valid(_whip):
		_whip.set_points(pts, 0.34)
	if u <= 1.05 and ctx.is_valid():
		_hits(pts)
	_prev_pts = pts
	if u >= 1.0 and not _cracked:
		_crack()
	if u >= 1.9 and _whip != null:
		_whip.finish(0.22)
		_whip = null


func _hits(pts: PackedVector3Array) -> void:
	var r := float(param("radius", 0.45))
	var tip_len := float(param("tip", 1.6))
	var tip_h := hit_data(param("tip_hit", {}))
	var body_h := hit_data()
	var n := pts.size()
	# Tip first (the strongest hit wins: one hit per target per lash).
	var tip_from := maxi(0, n - 1 - int(ceil(tip_len / maxf(pts[n - 2].distance_to(pts[n - 1]), 0.1))))
	BendingHits.sweep(ctx, pts[tip_from], pts[n - 1], r, tip_h, attack_id, def.id)
	if _prev_pts.size() == n:
		BendingHits.sweep(ctx, _prev_pts[n - 1], pts[n - 1], r, tip_h, attack_id, def.id)
		var m := n / 2
		BendingHits.sweep(ctx, _prev_pts[m], pts[m], r, body_h, attack_id, def.id)
	for i in range(0, tip_from, 2):
		BendingHits.sweep(ctx, pts[i], pts[mini(i + 2, tip_from)], r, body_h, attack_id, def.id)


func _crack() -> void:
	if _cracked:
		return
	_cracked = true
	var pts := _curve(1.0)
	var tip := pts[pts.size() - 1]
	FireFx.burst(ctx.caster, tip, 1.2, Vector3.UP)
	FxBurst.spawn(ctx.caster, &"sparks", tip, {"count": 1.0, "speed": 1.2, "spread": 160.0})
	FxFlash.spawn(ctx.caster, tip + Vector3.UP * 0.3, FireCommon.HOT, 3.0, 0.25, 6.0)
	sound(&"impact", tip, 2.0)
	FireEnv.heat(ctx, tip, 1.1, 0.8, {"mark": 0.8, "stretch": 2.2, "dir": tip - _origin})
	FireCommon.shake(ctx, 0.2, 0.15)
	FireCommon.practiced(ctx, def.id)


func on_cancel(_reason: StringName) -> void:
	_cleanup()


func on_finish() -> void:
	_cleanup()


func _cleanup() -> void:
	if _whip != null and is_instance_valid(_whip):
		_whip.finish(0.2)
	_whip = null
