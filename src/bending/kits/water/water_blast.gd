extends ChargeAbility
## Water Blast / Torrent. Tap: a concentrated water bolt (knockback, soaks).
## Hold: water is drawn from the nearest source and coils around the body,
## thickening with the charge; release drives it forward as a crushing torrent
## (a piercing stream that keeps flowing from the hands to its head).

var _ring: WaterStream = null
var _ring_phase := 0.0
var _src: Dictionary = {}


func chi_cost() -> float:
	return WaterSource.chi_cost(ctx, def.chi_cost)


func on_windup() -> void:
	_src = WaterSource.find(ctx)
	if bool(_src.get("found", false)) and float(_src.get("distance", 0.0)) > 1.5:
		WaterSource.draw(ctx, _src, 0.35, &"hand_r")
	_ring = WaterStream.spawn(ctx.caster)
	_loop_id = Audio.start_bending_loop(ctx.element, &"charge_loop", ctx.caster, -8.0)
	_update_ring(0.0, 0.0)


func update(delta: float) -> void:
	super.update(delta)
	if charging:
		_update_ring(charge, delta)


func _update_ring(c: float, delta: float) -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_ring_phase += delta * (5.0 + c * 4.0)
	var center := ctx.origin() + Vector3.UP * 1.05
	var grow := clampf(hold_time / 0.35, 0.0, 1.0)
	var arc := lerpf(0.6, 5.2, grow)
	var radius := 0.75 + c * 0.2
	var pts := PackedVector3Array()
	for k in 9:
		var a := _ring_phase - arc * (1.0 - float(k) / 8.0)
		pts.append(center + Vector3(cos(a) * radius, sin(a * 2.0 + _ring_phase) * 0.12, sin(a) * radius))
	var size := WaterSource.size_mult(ctx)
	_ring.set_points(pts, (0.07 + c * 0.07) * size, 0.04 * size)
	_ring.set_spray(c > 0.5)
	if _loop_id != 0:
		Audio.set_loop_pitch(_loop_id, 1.0 + c * 0.3)


func release_attack(c: float, was_tap: bool) -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.1)
		_loop_id = 0
	var size := WaterSource.size_mult(ctx)
	var from := ctx.hands_pos() if not was_tap else ctx.socket_pos(&"hand_r")
	var speed := float(param("speed", 30.0)) * (1.0 if was_tap else 0.85)
	var dir := ctx.aim_dir_from(from, speed, 0.6)
	from += dir * 0.3
	var h := hit_data()
	if was_tap:
		_end_ring(0.1)
		_bolt(from, dir, speed, h, size)
	else:
		h["damage"] = 20.0 + 16.0 * c
		h["force"] = 10.0 + 5.0 * c
		h["lift"] = 1.0 + 2.0 * c
		h["poise"] = 32.0 + 25.0 * c
		_torrent(from, dir, speed, h, c, size)
	sound(&"cast_heavy", from, 0.0 if was_tap else 2.0)
	BendingFeedback.impulse(dir, 0.1 + c * 0.2)
	if ctx.is_player() and not was_tap:
		BendingFeedback.shake(0.2 + c * 0.2, 0.2)


func _bolt(from: Vector3, dir: Vector3, speed: float, h: Dictionary, size: float) -> void:
	var trail := WaterTrail.new()
	trail.stream = WaterStream.spawn(ctx.caster)
	trail.radius = 0.16 * size
	trail.ctx = ctx
	var p := BendingProjectile.launch(ctx, from, dir, speed, h, {"radius": 0.28 * size, "range": 26.0, "gravity": 1.5,
			"attack_id": attack_id, "ability_id": def.id, "homing": 20.0, "impact_size": 0.9 * size,
			"on_step": trail.step, "on_finish": trail.finish})
	p.set_meta(&"trail", trail)
	trail.step(p, 0.0)


func _torrent(from: Vector3, dir: Vector3, speed: float, h: Dictionary, c: float, size: float) -> void:
	var trail := WaterTrail.new()
	trail.stream = _ring if _ring and is_instance_valid(_ring) else WaterStream.spawn(ctx.caster)
	_ring = null
	trail.radius = (0.24 + 0.2 * c) * size
	trail.ctx = ctx
	trail.anchor_hands = true
	trail.max_points = 7
	var p := BendingProjectile.launch(ctx, from, dir, speed, h, {"radius": (0.7 + 0.45 * c) * size, "range": 15.0 + 4.0 * c, "pierce": true,
			"attack_id": attack_id, "ability_id": def.id, "impact_size": 1.4 * size, "deflectable": false,
			"on_step": trail.step, "on_finish": trail.finish})
	p.set_meta(&"trail", trail)
	trail.step(p, 0.0)


func _end_ring(fade: float) -> void:
	if _ring and is_instance_valid(_ring):
		_ring.finish(fade)
	_ring = null


func on_cleanup() -> void:
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.1)
		_loop_id = 0
	_end_ring(0.2)


## A water stream that follows a projectile (bolt tail / torrent from the hands).
class WaterTrail extends RefCounted:
	var stream: WaterStream
	var ctx: BendingContext
	var radius := 0.16
	var history := PackedVector3Array()
	var anchor_hands := false
	var max_points := 5
	var _spacing := 0.0

	func step(proj: BendingProjectile, _dt: float) -> void:
		if stream == null or not is_instance_valid(stream):
			return
		var p := proj.global_position
		if history.is_empty() or history[history.size() - 1].distance_to(p) > 0.35:
			history.append(p)
			if history.size() > max_points and not anchor_hands:
				history.remove_at(0)
		var pts := PackedVector3Array()
		if anchor_hands and ctx != null and ctx.is_valid():
			pts.append(ctx.hands_pos())
			# Keep a few evenly spread points from the hands to the head.
			var n := mini(history.size(), max_points)
			for k in n:
				pts.append(history[int(float(k) / maxf(n - 1, 1) * (history.size() - 1))])
		else:
			pts = history.duplicate()
			pts.append(p)
		if pts.size() < 2:
			pts.insert(0, p - proj.velocity.normalized() * 0.4)
		stream.set_points(pts, radius, radius * (0.8 if anchor_hands else 0.35))
		stream.set_spray(true)

	func finish(_v: Node3D) -> void:
		if stream and is_instance_valid(stream):
			stream.finish(0.2)
		stream = null
