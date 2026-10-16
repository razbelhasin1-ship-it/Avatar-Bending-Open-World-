extends DefenseAbility
## Water Shield: a rotating barrier of water circling the bender (80% frontal
## block, deflects projectiles). Perfect timing redirects projectiles back and
## freezes melee attackers solid.

var _ring: WaterStream = null
var _phase := 0.0


func on_guard_up() -> void:
	var src := WaterSource.find(ctx)
	if bool(src.get("found", false)) and float(src.get("distance", 0.0)) > 1.5:
		WaterSource.draw(ctx, src, 0.25, &"hand_l")
	_ring = WaterStream.spawn(ctx.caster)
	_update(0.0)


func on_guard(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	if _ring == null or not is_instance_valid(_ring):
		return
	_phase += delta * 6.5
	var c := ctx.origin() + Vector3.UP * 1.0
	var grow := clampf(guard_time / 0.18, 0.0, 1.0)
	var arc := lerpf(1.2, 5.6, grow)
	var pts := PackedVector3Array()
	for k in 11:
		var a := _phase - arc * (1.0 - float(k) / 10.0)
		var r := 0.95 + 0.06 * sin(a * 3.0)
		pts.append(c + Vector3(cos(a) * r, 0.35 * sin(a * 1.5 + _phase * 0.5), sin(a) * r))
	var size := WaterSource.size_mult(ctx)
	_ring.set_points(pts, 0.12 * size, 0.07 * size)
	_ring.set_spray(true)


func on_block(hit: HitInfo) -> void:
	IceFx.splash(ctx.caster, hit.position, 0.6, -hit.direction)


func counter(hit: HitInfo, attacker: Node3D) -> void:
	if attacker != null and is_instance_valid(attacker) and not hit.is_projectile:
		var h := ctx.make_hit({"damage": 4.0, "reaction": HitInfo.Reaction.FREEZE, "stun": 1.6, "poise": 50.0, "status": {"frozen": 1.6}},
				attacker.global_position - ctx.origin(), 0, def.id)
		h.position = BendingContext.target_point(attacker)
		BendingHits.deliver(ctx, attacker, h)
		IceFx.shatter(ctx.caster, BendingContext.target_point(attacker), Vector3.ZERO, 0.6, attacker.global_position.y)
		BendingFeedback.sound(ElementDefs.Element.WATER, &"freeze", attacker.global_position)


func on_guard_down() -> void:
	if _ring and is_instance_valid(_ring):
		_ring.finish(0.2)
	_ring = null
