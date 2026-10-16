extends DefenseAbility
## Earth Shield: a stone slab rises from the ground in front while held. It is
## a real construct (projectiles smash into it) that follows the bender; melee
## hits from the front are reduced 90%. Sustained damage breaks it (guard_hp /
## slab HP). Parry: the slab slams forward and shoves the attacker away.

var _slab: BendingConstruct = null


func on_guard_up() -> void:
	var hp := float(param("guard_hp", 80.0))
	_slab = BendingConstruct.raise(ctx, ctx.ground_point(ctx.origin() + ctx.forward() * 0.95), ctx.forward(), {
		"kind": &"earth", "size": Vector3(1.7, 1.95, 0.5), "hp": hp, "rise_time": 0.16, "follow": ctx.caster,
		"follow_offset": Vector3(0, 0, 0.95)})
	_slab.broken.connect(_on_slab_broken)
	_slab.hit_filter = _slab_filter
	if ctx.is_player():
		BendingFeedback.shake(0.12, 0.1)


## Hits on the slab inside the parry window are parries (the slab is in front
## of the bender, so projectiles meet it before the body).
func _slab_filter(hit: HitInfo) -> int:
	if not is_defending() or not in_parry_window():
		return -1
	var r: Dictionary = guard(hit)
	return int(r["result"])


func _on_slab_broken(_c: BendingConstruct) -> void:
	_slab = null
	if is_defending():
		break_guard()


func on_block(hit: HitInfo) -> void:
	# Melee wears the guard (guard_hp, base class); projectiles wear the slab's own HP.
	FxDebris.spawn(ctx.caster, hit.position, {"count": 3, "size": 0.08, "up": 2.0, "out": 1.5, "ground_y": ctx.origin().y})


func counter(_hit: HitInfo, attacker: Node3D) -> void:
	if attacker != null and is_instance_valid(attacker):
		var h := ctx.make_hit({"damage": 8.0, "reaction": HitInfo.Reaction.KNOCKBACK, "force": 10.0, "poise": 45.0, "heavy": true},
				attacker.global_position - ctx.origin(), 0, def.id)
		BendingHits.deliver(ctx, attacker, h)
	EarthFx.quake(ctx.caster, ctx.ground_point(ctx.origin() + ctx.forward() * 1.2), 2.0, ctx.surface_at(ctx.origin()))


func on_guard_break() -> void:
	sound(&"wall_break", ctx.origin() + ctx.forward())


func on_guard_down() -> void:
	if _slab and is_instance_valid(_slab):
		_slab.follow = null
		_slab.crumble()
	_slab = null
