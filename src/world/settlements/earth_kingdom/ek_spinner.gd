class_name EkSpinner
extends Node3D
## Turns its `spin` child about `axis` (windmill sails, water wheels, harbour cranes): cheap,
## and it stops when the camera is far (checked twice a second).

var spin: Node3D
var axis := Vector3(0, 0, 1)
## Radians per second.
var speed := 0.5
## Beyond this distance from the camera the spinner sleeps.
var active_range := 260.0
var _check := 0.0
var _awake := true


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5 + randf() * 0.1
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		_awake = cam != null and cam.global_position.distance_squared_to(global_position) < active_range * active_range
	if _awake and spin:
		spin.rotate_object_local(axis, speed * delta)
