class_name PlayerTargeting
extends Node
## Soft aim assist + hard lock-on (docs/GAME_DESIGN.md §5).
## * Soft target: best damageable of another team inside a 25° cone around the
##   camera forward (within SOFT_RANGE, line of sight), refreshed at 15 Hz.
## * Lock-on (lock_on action): locks the best target in a wider cone (or the
##   nearest in front); pressing again releases. While locked, a mouse flick /
##   right-stick flick / cycle(dir) switches to the next target in that screen
##   direction. Auto-release when the target dies, leaves LOCK_RANGE, or is out
##   of sight for LOS_GRACE s. Emits Events.target_locked / target_unlocked.
## Targets: nodes in group &"damageable" with a `team` different from ours,
## alive, Node3D, not tagged with meta &"no_lock" (constructs).

signal lock_changed(target: Node3D)

const SOFT_CONE_DEG := 25.0
const LOCK_CONE_DEG := 50.0
const SOFT_RANGE := 22.0
const LOCK_RANGE := 30.0
const RELEASE_RANGE := 36.0
const LOS_GRACE := 2.0
const FLICK_PIXELS := 90.0
const FLICK_WINDOW := 0.2

var owner_body: Node3D
var team: int = Combat.Team.PLAYER
## Camera giving the aim cone (PlayerCamera's Camera3D).
var camera: Camera3D = null
var soft_target: Node3D = null
var lock_target: Node3D = null
var enabled := true

var _soft_timer := 0.0
var _los_lost := 0.0
var _flick_accum := 0.0
var _flick_t := 0.0
var _stick_ready := true
var _switch_cool := 0.0


func setup(p_owner: Node3D, p_team: int) -> void:
	owner_body = p_owner
	team = p_team


## Per physics tick.
func tick(delta: float) -> void:
	_switch_cool = maxf(0.0, _switch_cool - delta)
	_flick_t += delta
	if _flick_t > FLICK_WINDOW:
		_flick_accum = 0.0
	if not enabled:
		if lock_target:
			unlock()
		soft_target = null
		return
	_soft_timer -= delta
	if _soft_timer <= 0.0:
		_soft_timer = 1.0 / 15.0
		soft_target = _best(SOFT_CONE_DEG, SOFT_RANGE, null)
	if lock_target != null:
		if not _valid(lock_target) or owner_body.global_position.distance_to(lock_target.global_position) > RELEASE_RANGE:
			unlock()
			return
		if _has_los(lock_target):
			_los_lost = 0.0
		else:
			_los_lost += delta
			if _los_lost > LOS_GRACE:
				unlock()
				return
		# Right-stick flick switches targets.
		var sx := Input.get_action_strength(&"look_right") - Input.get_action_strength(&"look_left")
		if absf(sx) > 0.85 and _stick_ready:
			_stick_ready = false
			cycle(signf(sx))
		elif absf(sx) < 0.3:
			_stick_ready = true


## Mouse / touch look while locked: a quick horizontal flick switches target.
func feed_look(delta_px: Vector2) -> void:
	if lock_target == null:
		return
	if _flick_t > FLICK_WINDOW:
		_flick_accum = 0.0
	_flick_t = 0.0
	_flick_accum += delta_px.x
	if absf(_flick_accum) > FLICK_PIXELS:
		cycle(signf(_flick_accum))
		_flick_accum = 0.0


func toggle_lock() -> void:
	if lock_target != null:
		unlock()
		return
	var t := _best(LOCK_CONE_DEG, LOCK_RANGE, null)
	if t == null:
		t = _nearest_in_front(LOCK_RANGE)
	if t != null:
		lock(t)


func lock(t: Node3D) -> void:
	if t == lock_target:
		return
	lock_target = t
	_los_lost = 0.0
	Events.target_locked.emit(t)
	lock_changed.emit(t)


func unlock() -> void:
	if lock_target == null:
		return
	lock_target = null
	Events.target_unlocked.emit()
	lock_changed.emit(null)


## Switches the lock to the next target to the right (dir > 0) or left on screen.
func cycle(dir: float) -> void:
	if lock_target == null or _switch_cool > 0.0 or camera == null:
		return
	var cur_x := _screen_x(lock_target)
	var best: Node3D = null
	var best_dx := INF
	for t in candidates(LOCK_RANGE):
		if t == lock_target:
			continue
		var dx := (_screen_x(t) - cur_x) * signf(dir)
		if dx > 0.01 and dx < best_dx:
			best_dx = dx
			best = t
	if best != null:
		_switch_cool = 0.25
		lock(best)


func get_lock_target() -> Node3D:
	return lock_target if _valid(lock_target) else null


## Lock target if locked, else the soft-aim target (may be null).
func aim_target() -> Node3D:
	if _valid(lock_target):
		return lock_target
	if _valid(soft_target):
		return soft_target
	return null


func candidates(range_m: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if owner_body == null:
		return out
	var o := owner_body.global_position
	for n in owner_body.get_tree().get_nodes_in_group(&"damageable"):
		if not (n is Node3D) or n == owner_body:
			continue
		var t := n as Node3D
		if not _valid(t):
			continue
		if t.global_position.distance_to(o) <= range_m:
			out.append(t)
	return out


func _valid(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return false
	if t.has_meta(&"no_lock"):
		return false
	if "team" in t and int(t.get("team")) == team and team != Combat.Team.NEUTRAL:
		return false
	return Combat.is_alive(t)


func _view() -> Transform3D:
	if camera != null and is_instance_valid(camera):
		return camera.global_transform
	return owner_body.global_transform


func _best(cone_deg: float, range_m: float, exclude: Node3D) -> Node3D:
	var view := _view()
	var fwd := -view.basis.z
	var cos_lim := cos(deg_to_rad(cone_deg))
	var best: Node3D = null
	var best_score := -INF
	for t in candidates(range_m):
		if t == exclude:
			continue
		var p := BendingContext.target_point(t)
		var to := p - view.origin
		var d := to.length()
		if d < 0.01:
			continue
		var c := fwd.dot(to / d)
		if c < cos_lim:
			continue
		if not _has_los(t):
			continue
		var dist := owner_body.global_position.distance_to(t.global_position)
		var score := c * 2.0 - dist / range_m
		if score > best_score:
			best_score = score
			best = t
	return best


func _nearest_in_front(range_m: float) -> Node3D:
	var o := owner_body.global_position
	var f := -_view().basis.z
	f.y = 0.0
	f = f.normalized()
	var best: Node3D = null
	var best_d := INF
	for t in candidates(range_m):
		var to := t.global_position - o
		to.y = 0.0
		if to.length() > 0.5 and f.dot(to.normalized()) < -0.2:
			continue
		var d := to.length()
		if d < best_d and _has_los(t):
			best_d = d
			best = t
	return best


func _has_los(t: Node3D) -> bool:
	var space := owner_body.get_world_3d().direct_space_state
	var from := owner_body.global_position + Vector3.UP * 1.4
	var to := BendingContext.target_point(t)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	var ex: Array[RID] = []
	if owner_body is CollisionObject3D:
		ex.append((owner_body as CollisionObject3D).get_rid())
	if t is CollisionObject3D:
		ex.append((t as CollisionObject3D).get_rid())
	q.exclude = ex
	var r := space.intersect_ray(q)
	return r.is_empty()


func _screen_x(t: Node3D) -> float:
	if camera == null or not is_instance_valid(camera):
		return 0.0
	var p := BendingContext.target_point(t)
	if camera.is_position_behind(p):
		var local := camera.global_transform.affine_inverse() * p
		return signf(local.x) * 10000.0
	return camera.unproject_position(p).x
