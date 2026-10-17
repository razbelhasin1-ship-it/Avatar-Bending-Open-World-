class_name EarthShockwave
extends Node3D
## An earth shockwave travelling over the ground from a centre (Earth Stomp,
## Earthquake): every target ON THE GROUND is hit once (one attack id) at the
## moment the front reaches it; targets in the air (more than `clearance` m
## above the ground) are missed - jumping is the counter. Walls and constructs
## between the centre and a target stop the wave (line of sight). The visible
## front (EarthWaveFx) is spawned by the ability on the same timing. Outlives
## the ability that started it (lives under FxRoot).
##
##   EarthShockwave.start(ctx, ground_pos, 5.0, 0.3, hit_dict, attack_id, &"earth_stomp")
##
## Public for tests: step(dt), `live`, `hit_log` ([[target, result, time]]).

signal target_hit(target: Node, result: int)

const REQUERY := 0.1

var ctx: BendingContext
var center := Vector3.ZERO
var radius := 5.0
var duration := 0.3
var hit: Dictionary = {}
var attack_id := 0
var ability_id: StringName = &""
## Max height above the ground a target can be and still be hit.
var clearance := 1.3
## Starting radius of the front (the caster's own footprint).
var inner := 0.4
var t := 0.0
var hit_log: Array = []
var _cands: Dictionary = {}
var _requery_t := 0.0
var _done := false

static var live: Array[EarthShockwave] = []


static func start(p_ctx: BendingContext, p_center: Vector3, p_radius: float, p_duration: float, h: Dictionary, p_attack_id: int,
		p_ability: StringName, opts: Dictionary = {}) -> EarthShockwave:
	var w := EarthShockwave.new()
	w.name = "EarthShockwave"
	w.ctx = p_ctx
	w.center = p_center
	w.radius = p_radius
	w.duration = maxf(p_duration, 0.02)
	w.hit = h
	w.attack_id = p_attack_id
	w.ability_id = p_ability
	w.clearance = float(opts.get("clearance", 1.3))
	w.inner = float(opts.get("inner", 0.4))
	FxLib.root(p_ctx.caster).add_child(w)
	w.global_position = p_center
	live.append(w)
	w._query()
	w.step(0.0)
	return w


func _physics_process(delta: float) -> void:
	step(delta)


## Current radius of the front.
func front() -> float:
	return lerpf(inner, radius, clampf(t / duration, 0.0, 1.0))


func step(delta: float) -> void:
	if _done:
		return
	t += delta
	if ctx == null or not ctx.is_valid():
		_finish()
		return
	_requery_t -= delta
	if _requery_t <= 0.0:
		_query()
	var r := front()
	for id: int in _cands.keys():
		var n: Node = _cands[id]
		if not is_instance_valid(n) or not (n is Node3D):
			_cands.erase(id)
			continue
		var tn := n as Node3D
		var flat := tn.global_position - center
		flat.y = 0.0
		if flat.length() > r + 0.35:
			continue
		_cands.erase(id)
		_try_hit(tn)
	if t >= duration:
		_finish()


func _query() -> void:
	_requery_t = REQUERY
	for n in BendingHits.targets_in_sphere(ctx, center, radius + 0.6):
		var id := n.get_instance_id()
		if not _cands.has(id) and not BendingHits.already_hit(attack_id, n):
			_cands[id] = n


func _try_hit(tn: Node3D) -> void:
	var gy := EarthEnv.ground_y(ctx, tn.global_position + Vector3.UP * 0.5)
	if tn.global_position.y - gy > clearance:
		return  # in the air: the wave passes under it
	var tp := BendingContext.target_point(tn)
	if not BendingHits.line_of_sight(ctx, center + Vector3.UP * 0.5, tp, tn):
		return
	var dir := tn.global_position - center
	dir.y = 0.0
	if dir.length_squared() < 1e-4:
		dir = ctx.forward()
	var h := ctx.make_hit(hit, dir.normalized(), attack_id, ability_id)
	h.origin = center
	h.position = tp.lerp(Vector3(tp.x, gy + 0.3, tp.z), 0.4)
	var res := BendingHits.deliver(ctx, tn, h)
	hit_log.append([tn, res, t])
	target_hit.emit(tn, res)


func _finish() -> void:
	_done = true
	live.erase(self)
	queue_free()


func _exit_tree() -> void:
	live.erase(self)
