extends BendingAbility
## Earthquake (signature, 100 Focus). Palms pressed to the ground - the earth
## trembles around the bender (shake, hopping stones, a ring marking the reach);
## rise on the toes with both fists overhead while boulders tear loose and
## hover; then drop onto one knee and drive a fist into the ground:
## * a fissure shockwave rolls out 11 m (EarthShockwave): everything on the
##   ground is knocked down (KNOCKDOWN, unblockable - only a jump or i-frames
##   avoid it), walls stop it;
## * fissures split the ground outward with broken slabs jutting along them, a
##   big cracked crater stays at the centre (EarthMarks / EarthRubble);
## * the hovering boulders are flung outward as debris (one more hit each
##   target the wave missed);
## * an aftershock rumbles 0.3 s later. Poise armor + 50 % damage reduction
##   while it runs.

var info: Dictionary = {}
var wave: EarthShockwave = null
var risers: Array = []
var debris_id := 0
var _ring_shown := false


func can_use() -> StringName:
	EarthCommon.prepare()
	if not EarthEnv.grounded(ctx):
		return &"airborne"
	info = EarthEnv.feet(ctx)
	if not bool(info["ok"]):
		return EarthEnv.refuse(ctx, def.id, info)
	return &""


func begin() -> void:
	ctx.move_mode = BendingContext.Move.HOLD
	ctx.face_dir = ctx.aim_flat()
	ctx.face_rate = 600.0
	ctx.poise_armor = maxf(ctx.base_poise_armor, def.poise_armor)
	ctx.damage_reduction = maxf(ctx.base_damage_reduction, float(param("damage_reduction", 0.5)))
	play_clip(def.clip, {"speed": def.clip_speed, "blend_in": 0.06})
	max_time = 4.0
	debris_id = HitInfo.new_attack_id()


func _radius() -> float:
	return float(param("radius", 11.0)) * lerpf(1.0, EarthEnv.power(info), 0.6)


func on_event(event: StringName) -> void:
	var g := EarthEnv.ground(ctx, ctx.origin())
	var gp: Vector3 = g["point"]
	var kind: StringName = info["kind"]
	match event:
		&"gather":
			_tremor(gp, kind)
		&"lift":
			_lift(gp, kind)
		&"impact":
			_slam(gp, kind)
		&"pulse":
			_aftershock(gp, kind)


func _tremor(gp: Vector3, kind: StringName) -> void:
	var r := _radius()
	FxRing.spawn(ctx.caster, gp, r, EarthPalette.color(kind, "dust"), 0.9, {"opacity": 0.35, "width": 0.06, "fill": 0.08})
	_ring_shown = true
	for i in 6:
		var a := randf() * TAU
		var p := gp + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.5, r * 0.7)
		p.y = EarthEnv.ground_y(ctx, p)
		FxDebris.spawn(ctx.caster, p, {"count": 3, "size": 0.08, "up": 1.6, "out": 0.4, "ground_y": p.y, "color": EarthPalette.color(kind, "debris")})
		if i % 2 == 0:
			FxBurst.spawn(ctx.caster, &"dust", p, {"color": EarthPalette.color(kind, "dust"), "count": 0.3, "size": 0.6, "speed": 0.5})
	sound(&"stomp", gp, -8.0)
	sound(&"debris", gp, -6.0)
	EarthEnv.shake(ctx, gp, 0.2, 0.7, 18.0)


func _lift(gp: Vector3, kind: StringName) -> void:
	var n := int(param("boulders", 6))
	var rise := maxf(time_to_event(&"impact"), 0.1)
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / n
		var out := Vector3(cos(a), 0.0, sin(a))
		var base := gp + out * randf_range(2.0, 3.0)
		base.y = EarthEnv.ground_y(ctx, base)
		var to := base + Vector3.UP * randf_range(1.4, 2.4)
		risers.append([EarthCommon.rise_rock(ctx, base, to, randf_range(0.26, 0.38), rise, kind), out])
	sound(&"cast_heavy", gp, 0.0)
	EarthEnv.shake(ctx, gp, 0.3, 0.3, 18.0)


func _slam(gp: Vector3, kind: StringName) -> void:
	var r := _radius()
	var dur := float(param("wave_time", 0.6))
	var pw := EarthEnv.power(info)
	wave = EarthShockwave.start(ctx, gp, r, dur, EarthEnv.scaled_hit(hit_data(), info), attack_id, def.id, {"clearance": 1.5, "inner": 0.6})
	EarthWaveFx.spawn(ctx.caster, gp, r, dur, kind, EarthEnv.ground_fn(ctx), {"rings": 4, "per_ring": 12, "height": 1.25 * pw, "inner": 0.22, "keep": 0.2})
	FxRing.spawn(ctx.caster, gp, r, EarthPalette.color(kind, "dust"), dur + 0.3, {"opacity": 0.75, "width": 0.12, "fill": 0.3,
			"inner": EarthPalette.color(kind, "rock")})
	# Fissures splitting the ground outward, broken slabs along them.
	var n := clampi(int(round(float(param("fissures", 7)) * clampf(FxLib.scale(), 0.6, 1.2))), 4, 9)
	var a0 := randf() * TAU
	for i in n:
		var a := a0 + TAU * float(i) / n + randf_range(-0.2, 0.2)
		var d := Vector3(cos(a), 0.0, sin(a))
		var p0 := gp + d * 1.2
		var p1 := gp + d * r * randf_range(0.6, 0.9)
		p0.y = EarthEnv.ground_y(ctx, p0)
		p1.y = EarthEnv.ground_y(ctx, p1)
		EarthEnv.fissure(ctx, p0, p1, randf_range(0.7, 1.0), kind, 6 if i % 2 == 0 else 0)
	EarthEnv.crater(ctx, gp, 2.6, kind)
	FxBurst.spawn(ctx.caster, &"dust_ring", gp, {"color": EarthPalette.color(kind, "dust"), "radius": 2.0, "count": 2.2, "size": 1.4})
	for i in 4:
		var a := randf() * TAU
		var p := gp + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 5.0)
		p.y = EarthEnv.ground_y(ctx, p)
		FxBurst.spawn(ctx.caster, &"dust", p, {"color": EarthPalette.color(kind, "dust"), "count": 0.8, "size": 1.3, "speed": 1.0})
	FxDebris.spawn(ctx.caster, gp, {"count": 12, "size": 0.18, "up": 6.0, "out": 4.0, "ground_y": gp.y, "color": EarthPalette.color(kind, "debris")})
	_fling(gp)
	sound(&"special", gp, 3.0)
	sound(&"stomp", gp, 2.0)
	EarthEnv.shake(ctx, gp, EarthEnv.MAX_SHAKE, 0.6, r + 8.0)
	BendingFeedback.impulse(Vector3.DOWN, 0.35)
	EarthEnv.note_weak(ctx, info)
	EarthEnv.practiced(ctx, def.id)


## The hovering boulders are flung outward as debris.
func _fling(gp: Vector3) -> void:
	var main := attack_id
	attack_id = debris_id
	for e: Array in risers:
		var rr: EarthCommon.RockRiser = e[0]
		if rr == null or not is_instance_valid(rr) or rr.released:
			continue
		var rock := rr.take()
		var out: Vector3 = e[1]
		var from := rock.global_position
		var dir := (out + Vector3.UP * 0.35).normalized()
		EarthCommon.launch(self, rock, from, dir, float(param("debris_speed", 15.0)), rock.scale.x * 0.5, hit_data(param("debris_hit", {}) as Dictionary),
				{"range": 14.0, "gravity": 9.0, "kind": info["kind"]})
	risers.clear()
	attack_id = main


func _aftershock(gp: Vector3, kind: StringName) -> void:
	var r := _radius() * 0.6
	EarthWaveFx.spawn(ctx.caster, gp, r, 0.35, kind, EarthEnv.ground_fn(ctx), {"rings": 2, "per_ring": 8, "height": 0.5, "inner": 0.4})
	sound(&"debris", gp, -2.0)
	EarthEnv.shake(ctx, gp, 0.3, 0.3, r + 10.0)


func _drop_risers() -> void:
	for e: Array in risers:
		var rr: EarthCommon.RockRiser = e[0]
		if rr != null and is_instance_valid(rr):
			rr.drop()
	risers.clear()


func on_cancel(_reason: StringName) -> void:
	_drop_risers()


func on_finish() -> void:
	_drop_risers()
