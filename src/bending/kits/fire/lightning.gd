class_name FireLightning
extends BendingAbility
## Lightning Generation - the cold-blooded fire, a separate discipline:
## * HOLD: rooted in a long stance, the arms trace slow opposed circles (lightning_charge)
##   while arcs crackle around the fingertips, brighter as the charge builds (1.6 s). A
##   flash and a crack mark the full charge.
## * RELEASE (let go): two fingers thrust forward (lightning_release) and on &"release" an
##   instant bolt jumps along the aim (38 m, aim assist): 55 dmg KNOCKDOWN, unblockable
##   (only i-frames avoid it), arcing on to one more target within 4 m (40 %). Striking
##   water electrifies everyone standing in it within 5 m - the bender included.
##   Released before 55 % it fizzles (chi and cooldown spent); 55-100 % is a weaker bolt.
## * RISK: held past 2.8 s the lightning turns on the bender (18 dmg KNOCKDOWN); struck
##   while charging past half way, it discharges into them (12 dmg).
## Non-player casters release on the full charge.

var charging := true
var charge := 0.0
var released := false
var _k := 0.0
var _ready_cued := false
var _arcs: Array = []
var _loop_id := 0
var _light: FxFlash = null
var _spark_t := 0.0
var _fizzled := false

## Bolts fired / backfires (tests).
static var bolts := 0
static var backfires := 0


func can_use() -> StringName:
	if not FireCommon.grounded(ctx):
		return &"airborne"
	return &""


func begin() -> void:
	FireCommon.begin()
	ctx.move_mode = BendingContext.Move.HOLD
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 240.0
	ctx.poise_armor = 0.0
	play_clip(param("hold_clip", &"lightning_charge"), {"blend_in": 0.12})
	clip_end = INF
	max_time = def.max_hold + 2.0
	for s: StringName in [&"hand_l", &"hand_r"]:
		var node := ctx.rig.get_socket(s) if ctx.rig != null and is_instance_valid(ctx.rig) else null
		_arcs.append(LightningFx.arcs(ctx.caster, node if node != null else ctx.caster, 0.32))
	_loop_id = Audio.play_loop(&"lightning_charge_loop", ctx.caster, -4.0, 0.2)
	_light = FxFlash.attach(ctx.caster, ctx.caster, LightningFx.COLOR, 0.6, 4.0)
	# ANY landed hit breaks the concentration (not only staggers).
	Events.hit_landed.connect(_on_hit_landed)


func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if not charging or finished or target != ctx.caster or hit.ability_id == &"lightning_backfire":
		return
	if (result == Combat.Result.HIT or result == Combat.Result.KILLED) and hit.damage > 0.0 and not hit.has_meta(&"dot"):
		if controller != null and controller.current == self:
			controller.cancel_current(&"hit")


func update(delta: float) -> void:
	if charging:
		charge += delta
		ctx.face_dir = ctx.aim_flat()
		_k = clampf(charge / maxf(def.charge_time, 0.05), 0.0, 1.0)
		for a: Variant in _arcs:
			if is_instance_valid(a):
				(a as LightningFx.LightningArcs).set_intensity(0.15 + _k * 1.1)
		if _light != null and is_instance_valid(_light):
			_light.set_energy(0.4 + _k * 1.6 + randf() * 0.4 * _k)
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = lerpf(0.3, 0.08, _k)
			FxBurst.spawn(ctx.caster, &"sparkle", ctx.socket_pos(&"hand_r" if randf() < 0.5 else &"hand_l"), {"count": 0.3 + _k * 0.5, "color": LightningFx.COLOR})
		if _k >= 1.0 and not _ready_cued:
			_ready_cued = true
			_ready_cue()
		if charge >= float(param("overcharge", def.max_hold)):
			_backfire(float(param("backfire_damage", 18.0)), HitInfo.Reaction.KNOCKDOWN)
			finish()
			return
		var want_release := (not input_held and charge >= 0.1) or (not ctx.is_player() and charge >= def.charge_time + 0.12)
		if want_release:
			_release()
		return
	if time >= clip_end:
		finish()


func _ready_cue() -> void:
	var p := ctx.socket_pos(&"hand_r")
	FxFlash.spawn(ctx.caster, p, LightningFx.COLOR, 3.0, 0.2, 5.0)
	FxBurst.spawn(ctx.caster, &"sparkle", p, {"count": 1.2, "color": LightningFx.COLOR, "speed": 1.6})
	Audio.play_sfx(&"lightning_crackle", p, -2.0)


func _release() -> void:
	charging = false
	var min_k := float(param("min_charge", 0.55))
	if _k < min_k:
		_fizzled = true
		var p := ctx.socket_pos(&"hand_r")
		FxBurst.spawn(ctx.caster, &"sparkle", p, {"count": 0.6, "color": LightningFx.COLOR})
		FxBurst.spawn(ctx.caster, &"smoke", p, {"count": 0.3, "size": 0.4})
		Audio.play_sfx(&"lightning_crackle", p, -10.0)
		_cleanup()
		finish()
		return
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.04})
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 1440.0
	if time_to_event(&"release") == INF:
		on_event(&"release")


func on_event(event: StringName) -> void:
	if event == &"release" and not charging and not released:
		released = true
		_fire()


## Damage scale for the charge reached (min_charge..1 -> weak_scale..1).
func power() -> float:
	var min_k := float(param("min_charge", 0.55))
	var u := clampf((_k - min_k) / maxf(1.0 - min_k, 0.01), 0.0, 1.0)
	return lerpf(float(param("weak_scale", 0.55)), 1.0, u)


func _fire() -> void:
	var from := ctx.socket_pos(&"hand_r")
	var dir := ctx.aim_dir_from(from, 0.0, 0.0)
	from += dir * 0.2
	var range_m := float(param("range", 38.0))
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * range_m, ctx.hit_mask() | Layers.SOLID)
	q.exclude = ctx.exclude()
	q.collide_with_areas = true
	var end := from + dir * range_m
	var target: Node = null
	var hit_world := false
	var normal := Vector3.UP
	var guard := 0
	while guard < 6:
		guard += 1
		var r := ctx.space().intersect_ray(q)
		if r.is_empty():
			break
		var col: Node = r["collider"] as Node
		var d := Combat.find_damageable(col) if col != null else null
		if d is FireHitProxy:
			# Fire objects do not stop lightning (but they hear it: it is fire).
			(d as FireHitProxy).receive_hit(ctx.make_hit(hit_data(), dir, attack_id, def.id))
			var ex := q.exclude
			ex.append((col as CollisionObject3D).get_rid())
			q.exclude = ex
			continue
		end = r["position"]
		normal = r.get("normal", Vector3.UP)
		if d != null:
			target = d
		else:
			hit_world = true
		break
	var k := power()
	var h := hit_data({"damage": float(def.hit.get("damage", 55.0)) * k, "poise": float(def.hit.get("poise", 120.0)) * k})
	LightningFx.bolt(ctx.caster, from, end, {"width": 0.24 + 0.2 * k, "branches": 4 if k > 0.8 else 2, "duration": 0.45})
	FxFlash.spawn(ctx.caster, from, LightningFx.COLOR, 4.0 * k, 0.18, 8.0)
	FxFlash.spawn(ctx.caster, end, LightningFx.COLOR, 6.0 * k, 0.25, 12.0)
	Audio.play_sfx(&"lightning_strike", from.lerp(end, 0.3), 2.0)
	bolts += 1
	if target != null:
		var hit := ctx.make_hit(h, dir, attack_id, def.id)
		hit.position = end
		hit.origin = from
		BendingHits.deliver(ctx, target, hit)
		_chain(target, end, h)
	FxBurst.spawn(ctx.caster, &"sparks", end, {"count": 1.4, "speed": 1.6, "spread": 160.0, "color": LightningFx.COLOR})
	FxBurst.spawn(ctx.caster, &"smoke", end, {"count": 0.5, "size": 0.6})
	if hit_world or target == null:
		var gy := ctx.ground_y(end, 0.6, 2.0)
		if absf(end.y - gy) < 0.8:
			FireMarks.burn(ctx.caster, Vector3(end.x, gy, end.z), 0.7 + 0.4 * k, {"glow": 0.8})
	FireEnv.heat(ctx, end, 0.9, 0.8, {"mark": 0.0})
	_conduct(end, h)
	BendingFeedback.impulse(-dir, 0.3)
	FireCommon.shake(ctx, 0.25 + 0.2 * k, 0.2)
	FireCommon.practiced(ctx, def.id)
	_cleanup()


## The bolt arcs on to the nearest other target within chain_radius.
func _chain(first: Node, at: Vector3, h: Dictionary) -> void:
	var best: Node3D = null
	var best_d := float(param("chain_radius", 4.0))
	for t in BendingHits.targets_in_sphere(ctx, at, best_d, [first]):
		if not (t is Node3D) or t is FireHitProxy or t is BendingConstruct:
			continue
		var dd := (t as Node3D).global_position.distance_to(at)
		if dd < best_d:
			best_d = dd
			best = t
	if best == null:
		return
	var p := BendingContext.target_point(best)
	if not BendingHits.line_of_sight(ctx, at, p, best):
		return
	var ch := h.duplicate()
	ch["damage"] = float(h["damage"]) * float(param("chain_scale", 0.4))
	ch["reaction"] = HitInfo.Reaction.STAGGER
	ch["poise"] = float(h["poise"]) * 0.4
	var hit := ctx.make_hit(ch, p - at, attack_id, def.id)
	hit.position = p
	hit.origin = at
	LightningFx.bolt(ctx.caster, at, p, {"width": 0.1, "branches": 1, "duration": 0.32})
	BendingHits.deliver(ctx, best, hit)


## Lightning striking water electrifies everyone standing in it nearby (the bender too).
func _conduct(at: Vector3, h: Dictionary) -> void:
	var w := GroundSampler.water_height(at)
	if w == -INF or w < at.y - 0.6:
		return
	var radius := float(param("water_radius", 5.0))
	var ch := h.duplicate()
	ch["damage"] = float(h["damage"]) * 0.35
	ch["reaction"] = HitInfo.Reaction.STAGGER
	var center := Vector3(at.x, w, at.z)
	for t in BendingHits.targets_in_sphere(ctx, center, radius):
		if not (t is Node3D) or t is FireHitProxy:
			continue
		var tn := t as Node3D
		if GroundSampler.water_height(tn.global_position) < tn.global_position.y + 0.1:
			continue
		var hit := ctx.make_hit(ch, tn.global_position - center, attack_id, def.id)
		hit.position = BendingContext.target_point(tn)
		LightningFx.bolt(ctx.caster, center + Vector3.UP * 0.05, hit.position, {"width": 0.08, "branches": 1, "duration": 0.3})
		BendingHits.deliver(ctx, t, hit)
	if ctx.origin().distance_to(center) <= radius and GroundSampler.water_height(ctx.origin()) > ctx.origin().y + 0.1:
		_backfire(float(param("backfire_hit_damage", 12.0)), HitInfo.Reaction.STAGGER)


## The lightning turns on the bender (overcharged, interrupted, own bolt in the water).
## Deferred: never re-enters the hit reaction that cancelled the charge.
func _backfire(damage: float, reaction: HitInfo.Reaction) -> void:
	backfires += 1
	var caster := ctx.caster
	var chest := ctx.socket_pos(&"chest")
	for i in 3:
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		LightningFx.bolt(caster, chest, chest + d * randf_range(1.2, 2.4), {"width": 0.1, "branches": 1, "duration": 0.3})
	FxFlash.spawn(caster, chest, LightningFx.COLOR, 5.0, 0.25, 8.0)
	Audio.play_sfx(&"lightning_strike", chest, 0.0)
	var dir := -ctx.forward()
	caster.get_tree().create_timer(0.05, false, true).timeout.connect(func() -> void:
		if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
			return
		var hit := HitInfo.make(damage, null, ElementDefs.Element.FIRE, reaction, dir, 5.0)
		hit.team = Combat.Team.NEUTRAL
		hit.unblockable = true
		hit.poise_damage = 60.0
		hit.stun_time = 1.0
		hit.ability_id = &"lightning_backfire"
		hit.position = chest
		hit.set_meta(&"no_focus", true)
		Combat.deal(caster, hit))
	_cleanup()


func on_cancel(reason: StringName) -> void:
	if charging and reason == &"hit" and _k >= 0.5:
		_backfire(float(param("backfire_hit_damage", 12.0)), HitInfo.Reaction.STAGGER)
	_cleanup()


func on_finish() -> void:
	_cleanup()


func _cleanup() -> void:
	if Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.disconnect(_on_hit_landed)
	for a: Variant in _arcs:
		if is_instance_valid(a):
			(a as LightningFx.LightningArcs).stop()
	_arcs.clear()
	if _loop_id != 0:
		Audio.stop_loop(_loop_id, 0.1)
		_loop_id = 0
	if _light != null and is_instance_valid(_light):
		_light.fade_out(0.15)
	_light = null
