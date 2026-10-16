class_name WaterWaveRunner
extends Node
## A travelling wave of bent water as a gameplay hazard (Water Surge, the Water
## Wave crash, Tidal Torrent): a crest that rides the ground or the water
## surface, hits each target once (one attack_id) along its front, carries the
## targets it hit, douses fires and enemy fire projectiles, leaves a wet / snow
## trail and crashes at the end of its run or against a wall.
## Outlives the ability that launched it (it is a node under FxRoot).
##
##   WaterWaveRunner.launch(ctx, start_ground, dir, {"speed": 14, "distance": 10, "width": 4,
##       "height": 1.8, "hit": hit_dict, "attack_id": id, "ability_id": &"water_surge"})
##   WaterWaveRunner.ring(ctx, center, {"r0": 1.0, "r1": 9.0, "speed": 16, "height": 1.6, "hit": ...})
##
## Hits are delivered on physics ticks as the crest reaches the targets
## (never ahead of the visible water).

signal crashed(runner: WaterWaveRunner, pos: Vector3)

var ctx: BendingContext
var dir := Vector3.FORWARD
var pos := Vector3.ZERO
var speed := 14.0
var distance := 10.0
var width := 4.0
var height := 1.8
var depth := 1.4
var hit: Dictionary = {}
var attack_id := 0
var ability_id: StringName = &""
var carry := 0.6
var is_ring := false
var r0 := 1.0
var r1 := 9.0
var radius := 1.0
var traveled := 0.0
var fx: WaterWaveFx = null
var results: Array[Dictionary] = []
var hit_targets: Array[Node] = []
var _trail := 0.0
var _douse := 0.0
var _done := false
var _age := 0.0

## Live runners (tests).
static var live: Array[WaterWaveRunner] = []


static func launch(p_ctx: BendingContext, start: Vector3, p_dir: Vector3, opts: Dictionary) -> WaterWaveRunner:
	var r := WaterWaveRunner.new()
	r.name = "WaterWave"
	r.ctx = p_ctx
	var d := Vector3(p_dir.x, 0.0, p_dir.z)
	r.dir = d.normalized() if d.length_squared() > 1e-4 else p_ctx.forward()
	r.pos = start
	r._configure(opts)
	FxLib.root(p_ctx.caster).add_child(r)
	# A ~70 degree crescent whose chord is the wave's width.
	var span := 1.2
	r.fx = WaterWaveFx.spawn(p_ctx.caster, span, r.width / (2.0 * sin(span * 0.5)), r.height, r.depth, {"rise_time": float(opts.get("rise_time", 0.14))})
	r._place_fx()
	live.append(r)
	return r


## Expanding ring wave around `center` (from r0 to r1 m).
static func ring(p_ctx: BendingContext, center: Vector3, opts: Dictionary) -> WaterWaveRunner:
	var r := WaterWaveRunner.new()
	r.name = "WaterRing"
	r.ctx = p_ctx
	r.is_ring = true
	r.pos = center
	r._configure(opts)
	r.r0 = float(opts.get("r0", 1.0))
	r.r1 = float(opts.get("r1", 9.0))
	r.radius = r.r0
	r.distance = r.r1 - r.r0
	FxLib.root(p_ctx.caster).add_child(r)
	# Unit ring scaled by the radius: the profile depth (0.18 of the radius) widens as it spreads.
	r.fx = WaterWaveFx.spawn(p_ctx.caster, TAU, 1.0, r.height, 0.2, {"rise_time": 0.1})
	r._place_fx()
	live.append(r)
	return r


func _configure(opts: Dictionary) -> void:
	speed = float(opts.get("speed", 14.0))
	distance = float(opts.get("distance", 10.0))
	width = float(opts.get("width", 4.0))
	height = float(opts.get("height", 1.8))
	depth = float(opts.get("depth", height * 0.8))
	hit = opts.get("hit", {})
	attack_id = int(opts.get("attack_id", HitInfo.new_attack_id()))
	ability_id = opts.get("ability_id", &"")
	carry = float(opts.get("carry", 0.6))


func _place_fx() -> void:
	if fx == null or not is_instance_valid(fx):
		return
	if is_ring:
		fx.place(Transform3D(Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)), pos))
		# The ring loses height as it spreads (the same water over a longer front).
		fx.set_height_scale(lerpf(1.0, 0.4, clampf(traveled / maxf(distance, 0.1), 0.0, 1.0)))
		return
	var b := Basis.looking_at(dir, Vector3.UP)
	# The crest arc's centre sits behind the crest by the mesh radius.
	fx.place(Transform3D(b, pos - dir * fx.radius))


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if ctx == null or not ctx.is_valid() or _age > 6.0:
		_crash()
		return
	var step := speed * delta
	if is_ring:
		radius = minf(r1, radius + step)
		traveled = radius - r0
		_hit_ring()
	else:
		var next := pos + dir * step
		# Walls stop the wave (it crashes against them).
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, next + dir * 0.4 + Vector3.UP * 0.6, Layers.SOLID)
		q.exclude = ctx.exclude()
		var wall := ctx.space().intersect_ray(q)
		if not wall.is_empty() and Combat.find_damageable(wall["collider"] as Node) == null:
			pos = Vector3((wall["position"] as Vector3).x, pos.y, (wall["position"] as Vector3).z) - dir * 0.3
			_hit_front()
			_crash()
			return
		var y := WaterEnv.surface_y(ctx, next + Vector3.UP * 1.0, 1.6, 3.0)
		# Too steep a drop or climb: the wave breaks there.
		if absf(y - pos.y) > 1.4:
			_crash()
			return
		pos = Vector3(next.x, lerpf(pos.y, y, 0.5), next.z)
		traveled += step
		_hit_front()
	_trail -= speed * delta
	if _trail <= 0.0:
		_trail = 1.3
		_leave_trail()
	_douse -= delta
	if _douse <= 0.0:
		_douse = 0.1
		var c := pos + Vector3.UP * 0.6
		WaterEnv.extinguish(ctx, c, (radius + 0.6) if is_ring else width * 0.5 + 0.4)
	_place_fx()
	if traveled >= distance:
		_crash()


## Targets in the band just behind/at the crest line.
func _hit_front() -> void:
	var center := pos + Vector3.UP * height * 0.45
	var half := width * 0.5
	var right := Vector3(-dir.z, 0.0, dir.x)
	for t in BendingHits.targets_in_sphere(ctx, center, half + 0.8):
		if not (t is Node3D):
			continue
		var tp := (t as Node3D).global_position - pos
		var fwd := tp.dot(dir)
		var lat := absf(tp.dot(right))
		if lat > half + 0.5 or fwd > 0.9 or fwd < -depth - 0.6 or tp.y > height + 1.0 or tp.y < -1.5:
			continue
		_touch(t as Node3D, dir + right * signf(tp.dot(right)) * 0.25 * (lat / maxf(half, 0.1)))


func _hit_ring() -> void:
	for t in BendingHits.targets_in_sphere(ctx, pos + Vector3.UP * height * 0.4, radius + 0.6):
		if not (t is Node3D):
			continue
		var tp := (t as Node3D).global_position - pos
		var flat := Vector2(tp.x, tp.z).length()
		if flat < radius - depth - 0.6 or tp.y > height + 1.0 or tp.y < -1.5:
			continue
		var out := Vector3(tp.x, 0.0, tp.z).normalized() if flat > 0.05 else ctx.forward()
		_touch(t as Node3D, out)


func _touch(t: Node3D, push: Vector3) -> void:
	var push_dir := Vector3(push.x, 0.0, push.z).normalized()
	if hit_targets.has(t):
		if carry > 0.0:
			WaterCommon.carry(ctx, t, push_dir, speed * carry)
		return
	if BendingHits.already_hit(attack_id, t):
		hit_targets.append(t)
		return
	var tp := BendingContext.target_point(t)
	if not BendingHits.line_of_sight(ctx, Vector3(tp.x, pos.y + 0.6, tp.z) - push_dir * 1.2, tp, t):
		return
	var h := ctx.make_hit(hit, push_dir, attack_id, ability_id)
	h.origin = tp - push_dir * 2.0
	h.position = tp - push_dir * 0.3
	var res := BendingHits.deliver(ctx, t, h)
	results.append({"target": t, "result": res, "hit": h})
	hit_targets.append(t)
	if carry > 0.0 and (res == Combat.Result.HIT or res == Combat.Result.KILLED):
		WaterCommon.carry(ctx, t, push_dir, speed * carry)


func _leave_trail() -> void:
	if is_ring:
		var n := 6 if FxLib.tier() > 0 else 3
		for i in n:
			var a := TAU * float(i) / n + randf() * 0.5
			var p := pos + Vector3(cos(a), 0.0, sin(a)) * radius
			WaterEnv.splash_ground(ctx.caster, Vector3(p.x, WaterEnv.surface_y(ctx, p + Vector3.UP, 1.5, 3.0), p.z), 0.6)
		return
	var right := Vector3(-dir.z, 0.0, dir.x)
	for s: float in [-0.3, 0.3]:
		var p := pos - dir * 0.6 + right * width * s
		WaterEnv.splash_ground(ctx.caster, Vector3(p.x, WaterEnv.surface_y(ctx, p + Vector3.UP, 1.5, 3.0), p.z), 0.7)


func _crash() -> void:
	if _done:
		return
	_done = true
	if fx != null and is_instance_valid(fx):
		fx.crash(0.4)
	fx = null
	var c := pos + (Vector3.ZERO if is_ring else dir * 0.5)
	if ctx != null and ctx.is_valid():
		var size := clampf(width * 0.3, 0.6, 2.0) if not is_ring else 1.6
		BendingFeedback.world_impact(ctx.caster, ElementDefs.Element.WATER, c + Vector3.UP * 0.4, Vector3.UP, size)
		WaterEnv.splash_ground(ctx.caster, c, size)
	crashed.emit(self, c)
	live.erase(self)
	queue_free()


func _exit_tree() -> void:
	live.erase(self)
	if not _done and fx != null and is_instance_valid(fx):
		fx.crash(0.2)
