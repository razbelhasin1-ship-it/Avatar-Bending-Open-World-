class_name FireCommon
extends RefCounted
## Helpers shared by the Fire abilities (docs/modules/bending_fire.md):
##
##   FireCommon.begin()                                  # clips + burn status ready (every fire ability)
##   FireCommon.practiced(ctx, &"fire_ring")             # skill practice (player casts only)
##   FireCommon.ignite_limb(ctx, &"hand_r", 1.0)         # a fist / foot flares up
##   FireCommon.burst(ctx, center, 3.8, hit, aid, &"fire_burst", {...})   # point-blank explosion
##   FireCommon.burn_projectiles(ctx, center, 3.0)       # incoming projectiles burnt away

const HOT := Color(1.0, 0.58, 0.22)


static func begin() -> void:
	FireClips.ensure()
	FireStatus.ensure()


## A technique performed by the player counts as practice (unlock rules); enemy casts never do.
static func practiced(ctx: BendingContext, id: StringName) -> void:
	if ctx != null and ctx.is_player():
		GameState.add_practice(id)


static func shake(ctx: BendingContext, strength: float, duration: float) -> void:
	if ctx != null and ctx.is_player():
		BendingFeedback.shake(strength, duration)


## The striking limb flares (fists / feet igniting on a strike).
static func ignite_limb(ctx: BendingContext, socket: StringName, strength: float = 1.0) -> void:
	var p := ctx.socket_pos(socket)
	FxBurst.spawn(ctx.caster, &"flame", p, {"size": 0.3 + 0.2 * strength, "count": 0.3 + 0.25 * strength, "speed": 0.6})


## Destroys enemy projectiles within `radius` (fire burns them away; rocks are knocked
## aside). Returns how many.
static func burn_projectiles(ctx: BendingContext, center: Vector3, radius: float) -> int:
	var n := 0
	for p: BendingProjectile in BendingProjectile.live.duplicate():
		if not is_instance_valid(p) or not p.alive or p.team == ctx.team:
			continue
		if p.global_position.distance_to(center) > radius + p.radius:
			continue
		if p.element == ElementDefs.Element.EARTH:
			var away := p.global_position - center
			away.y = 0.0
			p.redirect((away.normalized() + Vector3.UP * 0.6).normalized(), ctx.team, ctx.caster, 0.6)
		else:
			if p.element == ElementDefs.Element.WATER:
				FireEnv.steam(ctx.caster, p.global_position, 0.6)
			p.destroy(true)
		n += 1
	return n


## Point-blank explosion around the bender (Fire Burst, the Flame Guard parry counter,
## a hard Jet Step landing). Inside `opts.inner` (m) targets are knocked DOWN, out to
## `radius` knocked BACK; incoming projectiles are burnt away; the ground is scorched and
## grass catches. opts: inner, inner_hit (overrides), power (VFX / env), projectiles (bool).
static func burst(ctx: BendingContext, center: Vector3, radius: float, h: Dictionary, attack_id: int, ability_id: StringName,
		opts: Dictionary = {}) -> Array[Dictionary]:
	var power := float(opts.get("power", 1.0))
	var g := ctx.ground_y(center, 1.5, 3.0)
	var ground := Vector3(center.x, g, center.z)
	_burst_fx(ctx, center, ground, radius, power)
	if bool(opts.get("projectiles", true)):
		burn_projectiles(ctx, center, radius * 0.85)
	var out: Array[Dictionary] = []
	var inner := float(opts.get("inner", radius * 0.5))
	if inner > 0.0:
		var ih := h.duplicate()
		for k: String in (opts.get("inner_hit", {}) as Dictionary):
			ih[k] = opts["inner_hit"][k]
		out.append_array(BendingHits.sphere(ctx, center, inner, ih, attack_id, ability_id, {"push": &"radial"}))
	out.append_array(BendingHits.sphere(ctx, center, radius, h, attack_id, ability_id, {"push": &"radial"}))
	FireEnv.heat(ctx, ground + Vector3.UP * 0.2, radius * 0.7, power, {"mark": radius * 0.55})
	return out


static func _burst_fx(ctx: BendingContext, center: Vector3, ground: Vector3, radius: float, power: float) -> void:
	var from: Node = ctx.caster
	# A fast ring of flame racing out along the ground marks the reach exactly.
	FireRingWave.visual(ctx, ground, radius, 0.16, {"height": 0.9 * power, "r0": 0.5, "hold": 0.12, "lean": 0.45})
	FxBurst.spawn(from, &"flame", center, {"size": 1.1 * power, "count": 1.4, "speed": 2.6 * radius / 3.8, "radius": 0.8, "spread": 180.0})
	FxBurst.spawn(from, &"embers", center, {"count": 1.6, "speed": 2.4, "spread": 180.0})
	FxBurst.spawn(from, &"smoke", ground + Vector3.UP * 0.6, {"size": 1.1, "count": 0.9, "radius": radius * 0.4})
	FxBurst.spawn(from, &"sparks", center, {"count": 1.0, "speed": 1.4, "spread": 180.0})
	FxFlash.spawn(from, center + Vector3.UP * 0.3, HOT, 5.5 * power, 0.3, radius * 2.6)
	HeatShimmer.spawn(from, ground, radius * 1.1, 2.4, 0.7, 0.9)
	BendingFeedback.sound(ElementDefs.Element.FIRE, &"explosion", center, 1.0)
	shake(ctx, 0.3 * power, 0.25)
