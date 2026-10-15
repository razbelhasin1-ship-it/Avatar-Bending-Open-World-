class_name CreatureDriver
extends Node
## Test/showcase helper that moves a CreatureRig along simple paths and feeds
## set_locomotion()/set_flight(), the way a companion controller would. Not used by
## gameplay (src/companions owns real controllers).

enum Mode { IDLE, LINE, CIRCLE, FLY_CIRCLE, FLY_LINE }

var rig: CreatureRig
var mode: Mode = Mode.IDLE
var speed := 0.0
var center := Vector3.ZERO
var radius := 10.0
var altitude := 0.0
var direction := Vector3.FORWARD
var _angle := 0.0
var _speed_now := 0.0
var _alt_now := 0.0
var accel := 4.0


func _init(target: CreatureRig = null) -> void:
	rig = target


func idle() -> void:
	mode = Mode.IDLE


func line(dir: Vector3, spd: float) -> void:
	mode = Mode.LINE
	direction = Vector3(dir.x, 0.0, dir.z).normalized()
	speed = spd


## Walks/runs counter-clockwise around `c` (seen from above) at radius `r`.
func circle(c: Vector3, r: float, spd: float) -> void:
	mode = Mode.CIRCLE
	center = c
	radius = r
	speed = spd
	var d := rig.global_position - c
	_angle = atan2(d.z, d.x)


func fly_circle(c: Vector3, r: float, spd: float, alt: float) -> void:
	circle(c, r, spd)
	mode = Mode.FLY_CIRCLE
	altitude = alt
	_alt_now = rig.global_position.y


func fly_line(dir: Vector3, spd: float, alt: float) -> void:
	line(dir, spd)
	mode = Mode.FLY_LINE
	altitude = alt
	_alt_now = rig.global_position.y


func _physics_process(delta: float) -> void:
	if rig == null or not is_instance_valid(rig):
		return
	var target_speed := speed if mode != Mode.IDLE else 0.0
	_speed_now = move_toward(_speed_now, target_speed, accel * delta)
	var pos := rig.global_position
	var vel := Vector3.ZERO
	var flying := mode == Mode.FLY_CIRCLE or mode == Mode.FLY_LINE
	match mode:
		Mode.IDLE:
			_speed_now = 0.0
		Mode.LINE, Mode.FLY_LINE:
			vel = direction * _speed_now
		Mode.CIRCLE, Mode.FLY_CIRCLE:
			_angle -= _speed_now / maxf(radius, 0.1) * delta
			var p := center + Vector3(cos(_angle), 0.0, sin(_angle)) * radius
			vel = (p - Vector3(pos.x, center.y, pos.z)) / maxf(delta, 1e-4)
			vel.y = 0.0
	var bank := 0.0
	if flying:
		if rig.flight_w > 0.6 or not rig.can_fly():
			_alt_now = move_toward(_alt_now, altitude, delta * 3.0)
		vel.y = (_alt_now - pos.y) / maxf(delta, 1e-4) * 0.2
		if mode == Mode.FLY_CIRCLE:
			bank = clampf(_speed_now * _speed_now / maxf(radius, 1.0) / 9.8, 0.0, 0.8) * -1.0
	elif rig.flight_w > 0.0 and not rig.flying:
		_alt_now = move_toward(pos.y, 0.0, delta * 4.0)
		vel.y = (_alt_now - pos.y) / maxf(delta, 1e-4)
	pos += vel * delta
	if not flying and rig.flight_w <= 0.0:
		pos.y = WorldData.get_height(pos.x, pos.z)
	rig.global_position = pos
	var hv := Vector3(vel.x, 0.0, vel.z)
	if hv.length() > 0.2:
		var yaw := atan2(-hv.x, -hv.z)
		var cur := rig.rotation.y
		rig.rotation.y = lerp_angle(cur, yaw, 1.0 - exp(-delta * 6.0))
	var grounded := pos.y <= WorldData.get_height(pos.x, pos.z) + 0.05
	rig.set_locomotion(vel, grounded or not flying and rig.flight_w <= 0.0, delta)
	if rig.can_fly():
		rig.set_flight(flying, vel, bank, clampf(vel.y * 0.05, -0.4, 0.4))
