extends DefenseAbility
## Earth Shield: a stone slab rises from the ground in front while held. It is
## a real construct (projectiles smash into it) that follows the bender; melee
## hits from the front are reduced 90%. Sustained damage breaks it (guard_hp /
## slab HP). Parry: the slab slams forward and shoves the attacker away, the
## ground cracking under it. The slab is the ground it came from (granite,
## turf-capped earth, sandstone, basalt ...). No earth underfoot (ice, wood,
## deep water): the bender guards with bare forearms (params.bare_reduction).

var _slab: BendingConstruct = null
var _info: Dictionary = {}
var _bare := false


func begin() -> void:
	EarthCommon.prepare()
	_info = EarthEnv.material_at(ctx, ctx.origin() + ctx.forward() * 0.95)
	_bare = not bool(_info["ok"])
	super.begin()


## Forearms only (no earth): the guard's reduction drops to the bare guard's.
func param(key: String, fallback: Variant = null) -> Variant:
	if _bare and key == "reduction":
		return def.params.get("bare_reduction", 0.5)
	return super.param(key, fallback)


func on_guard_up() -> void:
	if _bare:
		EarthEnv.refuse(ctx, def.id, _info)
		return
	var hp := float(param("guard_hp", 80.0)) * lerpf(1.0, EarthEnv.power(_info), 0.6)
	var size := Vector3(1.7, 1.95, 0.5)
	_slab = BendingConstruct.raise(ctx, ctx.ground_point(ctx.origin() + ctx.forward() * 0.95), ctx.forward(), {
		"kind": &"earth", "size": size, "hp": hp, "rise_time": 0.16, "follow": ctx.caster,
		"follow_offset": Vector3(0, 0, 0.95)})
	EarthEnv.dress(_slab, EarthMeshes.slab(size, randi() % 4, _info["kind"]))
	_slab.broken.connect(_on_slab_broken)
	_slab.hit_filter = _slab_filter
	EarthEnv.shake(ctx, ctx.origin(), 0.12, 0.1)


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
	FxDebris.spawn(ctx.caster, hit.position, {"count": 3, "size": 0.08, "up": 2.0, "out": 1.5, "ground_y": ctx.origin().y,
			"color": EarthPalette.color(_info.get("kind", &"stone"), "debris")})


func counter(_hit: HitInfo, attacker: Node3D) -> void:
	if attacker != null and is_instance_valid(attacker):
		var h := ctx.make_hit({"damage": float(param("counter_damage", 8.0)), "reaction": HitInfo.Reaction.KNOCKBACK, "force": 10.0, "poise": 45.0, "heavy": true},
				attacker.global_position - ctx.origin(), 0, def.id)
		BendingHits.deliver(ctx, attacker, h)
	var g := ctx.ground_point(ctx.origin() + ctx.forward() * 1.2)
	var kind: StringName = _info.get("kind", &"stone") if bool(_info.get("ok", false)) else &"stone"
	EarthFx.quake(ctx.caster, g, 2.0, kind)
	if not _bare:
		EarthEnv.fissure(ctx, ctx.ground_point(ctx.origin() + ctx.forward() * 0.6), ctx.ground_point(ctx.origin() + ctx.forward() * 3.0), 0.4, kind)
	EarthEnv.shake(ctx, g, 0.25, 0.15)


func on_guard_break() -> void:
	sound(&"wall_break", ctx.origin() + ctx.forward())


func on_guard_down() -> void:
	if _slab and is_instance_valid(_slab):
		_slab.follow = null
		_slab.crumble()
	_slab = null
