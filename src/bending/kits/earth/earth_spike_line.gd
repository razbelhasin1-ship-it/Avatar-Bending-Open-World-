class_name EarthSpikeLine
extends Node3D
## A line of stone spikes erupting one after another along the ground (Earth
## Spikes): every `spacing` m a spike bursts up (taller as the line runs on,
## alternating sides, leaning forward), launching what it hits (one attack id:
## each target once). The line follows the ground, stops at ground that cannot
## be bent (ice, wood, deep water), at walls and at steep steps, and leaves a
## fissure. Spikes stand ~1.4 s, then sink back. One MultiMesh for all spikes.
## Outlives the ability (lives under FxRoot).
##
##   EarthSpikeLine.start(ctx, ground_from, dir, {"length": 12, "speed": 24, "hit": h, "attack_id": id, "ability_id": &"earth_spikes"})

const MAX := 28

var ctx: BendingContext
var dir := Vector3.FORWARD
var origin := Vector3.ZERO
var length := 12.0
var speed := 24.0
var spacing := 0.6
var radius := 0.85
var hit: Dictionary = {}
var attack_id := 0
var ability_id: StringName = &"earth_spikes"
var kind: StringName = &"dirt"
var power := 1.0
var hold := 1.4
var traveled := 0.0
var stopped := false
var stop_reason: StringName = &""
var hit_log: Array = []
## [age, base Transform3D, height]
var spikes: Array = []
var mmi: MultiMeshInstance3D
var _next := 0.0
var _last := Vector3.ZERO
var _last_y := 0.0
var _t := 0.0
var _done := false

static var live: Array[EarthSpikeLine] = []


static func start(p_ctx: BendingContext, from: Vector3, p_dir: Vector3, opts: Dictionary = {}) -> EarthSpikeLine:
	var l := EarthSpikeLine.new()
	l.name = "EarthSpikeLine"
	l.ctx = p_ctx
	var d := Vector3(p_dir.x, 0.0, p_dir.z)
	l.dir = d.normalized() if d.length_squared() > 1e-4 else p_ctx.forward()
	l.origin = from
	l.length = float(opts.get("length", 12.0))
	l.speed = float(opts.get("speed", 24.0))
	l.spacing = float(opts.get("spacing", 0.6))
	l.radius = float(opts.get("radius", 0.85))
	l.hit = opts.get("hit", {})
	l.attack_id = int(opts.get("attack_id", HitInfo.new_attack_id()))
	l.ability_id = opts.get("ability_id", &"earth_spikes")
	l.kind = opts.get("kind", &"dirt")
	l.power = float(opts.get("power", 1.0))
	l.hold = float(opts.get("hold", 1.4))
	l._last = from
	l._last_y = from.y
	FxLib.root(p_ctx.caster).add_child(l)
	l.global_position = from
	l.mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	mm.mesh = EarthMeshes.spike(1.0, 0.3, randi() % 4, l.kind, 0.3)
	l.mmi.multimesh = mm
	l.mmi.material_override = EarthMeshes.material()
	l.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if FxLib.tier() >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.mmi.top_level = true
	l.add_child(l.mmi)
	l.mmi.global_transform = Transform3D.IDENTITY
	live.append(l)
	return l


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if _done:
		return
	_t += delta
	if not stopped:
		if ctx == null or not ctx.is_valid():
			_stop(&"caster")
		else:
			traveled += speed * delta
			while not stopped and _next <= minf(traveled, length) and spikes.size() < MAX:
				_erupt(_next)
				_next += spacing
			if _next > length and not stopped:
				_stop(&"end")
	_animate(delta)


func _erupt(at: float) -> void:
	var i := spikes.size()
	var side := Vector3(-dir.z, 0.0, dir.x) * (0.28 if i % 2 == 0 else -0.28) * randf_range(0.6, 1.2)
	var p := origin + dir * at + side
	var m := EarthEnv.material_at(ctx, p + Vector3.UP * maxf(0.0, _last_y - origin.y))
	var gp: Vector3 = m["ground"]
	if not bool(m["ok"]):
		if i == 0 and ctx.is_player():
			EarthEnv.refuse(ctx, ability_id, m)
		else:
			_puff(gp, m["kind"])
		_stop(m["kind"])
		return
	if absf(gp.y - _last_y) > 1.1:
		_stop(&"step")
		return
	var from_p := _last + Vector3.UP * 0.6
	var to_p := gp + Vector3.UP * 0.6
	if from_p.distance_to(to_p) > 0.05:
		var q := PhysicsRayQueryParameters3D.create(from_p, to_p, Layers.SOLID)
		q.exclude = ctx.exclude()
		if not ctx.space().intersect_ray(q).is_empty():
			_stop(&"wall")
			return
	_last = gp
	_last_y = gp.y
	var u := at / maxf(length, 0.1)
	var h := lerpf(0.9, 1.75, u) * power * randf_range(0.85, 1.15)
	var b := Basis.looking_at(dir, Vector3.UP).rotated(Vector3.UP, randf_range(-0.35, 0.35))
	spikes.append([0.0, Transform3D(b, gp), h])
	mmi.multimesh.visible_instance_count = spikes.size()
	if i % 2 == 0:
		FxDebris.spawn(self, gp, {"count": 3, "size": 0.09, "up": 3.5, "out": 1.2, "ground_y": gp.y, "color": EarthPalette.color(m["kind"], "debris")})
	if i % 3 == 0:
		FxBurst.spawn(self, &"dust", gp, {"color": EarthPalette.color(m["kind"], "dust"), "count": 0.35, "size": 0.7, "speed": 0.7})
	if i % 4 == 0:
		BendingFeedback.sound(ElementDefs.Element.EARTH, &"spikes", gp, -3.0)
	for r: Dictionary in BendingHits.sphere(ctx, gp + Vector3.UP * 0.55, radius, hit, attack_id, ability_id, {"push": &"forward", "dir": dir, "los": false}):
		hit_log.append([r["target"], r["result"], _t])


func _puff(p: Vector3, k: StringName) -> void:
	FxBurst.spawn(self, &"snow" if k == &"ice" else (&"spray" if k == &"deep_water" else &"dust"), p, {"count": 0.5, "size": 0.6})


func _stop(reason: StringName) -> void:
	if stopped:
		return
	stopped = true
	stop_reason = reason
	if spikes.size() >= 2 and ctx != null and ctx.is_valid():
		var a: Vector3 = (spikes[0][1] as Transform3D).origin
		var b: Vector3 = (spikes[spikes.size() - 1][1] as Transform3D).origin
		EarthEnv.fissure(ctx, a, b, 0.5, kind, 0)


func _animate(delta: float) -> void:
	var mm := mmi.multimesh
	var alive := 0
	for i in spikes.size():
		var s: Array = spikes[i]
		s[0] = float(s[0]) + delta
		var age := float(s[0])
		var k := 0.0
		if age < 0.09:
			var u := age / 0.09
			k = 1.0 + 2.2 * pow(u - 1.0, 3.0) + 1.2 * pow(u - 1.0, 2.0)
		elif age < hold:
			k = 1.0
		else:
			k = clampf(1.0 - (age - hold) / 0.35, 0.0, 1.0)
		if age < hold + 0.35:
			alive += 1
		var base: Transform3D = s[1]
		var h := float(s[2])
		var sink := (1.0 - clampf(k, 0.0, 1.0)) * h * 0.9
		mm.set_instance_transform(i, Transform3D(base.basis * Basis.from_scale(Vector3(h * 0.55, h, h * 0.55)), base.origin + Vector3.DOWN * sink))
	if stopped and alive == 0:
		_finish()


func _finish() -> void:
	_done = true
	live.erase(self)
	queue_free()


func _exit_tree() -> void:
	live.erase(self)
