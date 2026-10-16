class_name EnemyPerception
extends RefCounted
## What an enemy knows about the player: a sight cone with line of sight and a
## gradual awareness meter (fast when close, slow at the edge of sight), a short
## proximity sense, hearing of combat noise, and memory (last seen position, time
## since seen). Ticked at ~8 Hz (staggered per enemy).
##
## awareness >= 1 -> spotted. While engaged the cone widens (enemies track a target
## they are fighting) and awareness never decays.

const INTERVAL := 0.12
const PROXIMITY := 3.2
## Awareness gain per second at point blank and at the edge of the sight range.
const GAIN_NEAR := 5.0
const GAIN_FAR := 0.75
const DECAY := 0.22

var enemy: Node3D
var sight := 24.0
var fov_deg := 130.0
var hearing := 28.0
var eye_height := 1.6
## The current target (player) or null.
var target: Node3D = null
var awareness := 0.0
var can_see := false
var engaged := false
var last_seen_pos := Vector3.INF
var since_seen := INF
var heard_pos := Vector3.INF
var since_heard := INF
## Forces full awareness of `target` (being hit, ally alert).
var forced := false

var _t := 0.0


func setup(p_enemy: Node3D, a: Dictionary, p_eye: float) -> void:
	enemy = p_enemy
	sight = float(a.get("sight", 24.0))
	fov_deg = float(a.get("fov", 130.0))
	hearing = float(a.get("hearing", 28.0))
	eye_height = p_eye
	_t = randf() * INTERVAL


func is_spotted() -> bool:
	return awareness >= 1.0


## Immediately aware of `t` at `pos` (got hit, an ally called out, noise right next to it).
func alert_to(t: Node3D, pos: Vector3 = Vector3.INF) -> void:
	if t == null:
		return
	target = t
	awareness = 1.0
	forced = true
	last_seen_pos = pos if pos.is_finite() else t.global_position
	since_seen = 0.0


func hear(pos: Vector3, loudness: float = 1.0) -> bool:
	if enemy == null or not pos.is_finite():
		return false
	if enemy.global_position.distance_to(pos) > hearing * loudness:
		return false
	heard_pos = pos
	since_heard = 0.0
	return true


func forget() -> void:
	awareness = 0.0
	forced = false
	engaged = false
	can_see = false
	last_seen_pos = Vector3.INF
	since_seen = INF
	heard_pos = Vector3.INF
	since_heard = INF


func tick(delta: float) -> void:
	since_seen += delta
	since_heard += delta
	_t -= delta
	if _t > 0.0:
		return
	var dt := INTERVAL - _t
	_t = INTERVAL
	_look(dt)


func _look(dt: float) -> void:
	var p := _find_target()
	if p == null:
		can_see = false
		if not engaged:
			awareness = maxf(0.0, awareness - DECAY * dt)
		return
	target = p
	var seen := sees(p)
	can_see = seen
	if seen:
		last_seen_pos = p.global_position
		since_seen = 0.0
		var d := enemy.global_position.distance_to(p.global_position)
		var k := clampf(d / maxf(sight, 1.0), 0.0, 1.0)
		var gain := lerpf(GAIN_NEAR, GAIN_FAR, k)
		awareness = minf(1.0, awareness + gain * dt)
	elif not engaged and not forced:
		awareness = maxf(0.0, awareness - DECAY * dt)


## Sight test: range, cone (or proximity / engaged), line of sight to the chest.
func sees(p: Node3D) -> bool:
	if p == null or enemy == null or not enemy.is_inside_tree():
		return false
	var from := enemy.global_position + Vector3.UP * eye_height
	var to := BendingContext.target_point(p)
	var d := from.distance_to(to)
	var range_m := sight * (1.35 if engaged else 1.0)
	if d > range_m:
		return false
	if d > PROXIMITY and not engaged:
		var fwd := -enemy.global_basis.z
		fwd.y = 0.0
		var dir := to - from
		dir.y = 0.0
		if fwd.length_squared() > 1e-6 and dir.length_squared() > 1e-6:
			if rad_to_deg(fwd.normalized().angle_to(dir.normalized())) > fov_deg * 0.5:
				return false
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	var ex: Array[RID] = []
	if enemy is CollisionObject3D:
		ex.append((enemy as CollisionObject3D).get_rid())
	if p is CollisionObject3D:
		ex.append((p as CollisionObject3D).get_rid())
	q.exclude = ex
	var r := enemy.get_world_3d().direct_space_state.intersect_ray(q)
	return r.is_empty()


func _find_target() -> Node3D:
	if target != null and is_instance_valid(target) and target.is_inside_tree() and Combat.is_alive(target) and _targetable(target):
		return target
	var p := enemy.get_tree().get_first_node_in_group(&"player") as Node3D
	if p != null and Combat.is_alive(p) and _targetable(p):
		return p
	target = null
	return null


## Players in cinematics / mounted flight / interiors handled by the scene are ignored.
static func _targetable(p: Node3D) -> bool:
	if p.has_method("get_state"):
		var st := int(p.call("get_state"))
		if st == PlayerCharacter.State.CINEMATIC or st == PlayerCharacter.State.DEAD or st == PlayerCharacter.State.MOUNTED:
			return false
	return true
