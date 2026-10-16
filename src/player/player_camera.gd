class_name PlayerCamera
extends Node3D
## Third-person orbit camera for the player (and mounts / flight / cinematics).
##
## * Orbit with mouse (captured), Events.look_input (touch drags) and the
##   look_* actions (controller); Settings: fov, mouse/controller/touch
##   sensitivity, invert Y, camera_distance, camera_shake. Mouse motion emulated
##   from touch is ignored while touch controls are active.
## * Collision: sphere cast against Layers.CAMERA_BLOCKERS pulls the camera in
##   instantly and eases back out.
## * Lock-on framing keeps the player and target readable (auto yaw, wider
##   distance with separation); mouse flicks switch targets instead.
## * Feel: trauma shake (Events.camera_shake, add_trauma), spring impulses
##   (Events.camera_impulse), hitstop (Events.hitstop -> TimeDilation).
##
## API for other modules:
##   set_mode(&"default" | &"mount" | &"flight" | &"cinematic", params := {})
##     mount:     {"height": 3.2, "distance": 7.5, "shoulder": 0.0, "fov": +4}
##     flight:    {"height": 2.5, "distance": 11.0, "fov": +10, "auto_align": true}
##     cinematic: {"transform": Transform3D, "fov": 50.0, "blend": 0.8}
##   set_target_override(node) / clear_target_override()
##   add_trauma(amount 0..1), impulse(dir, strength)
##   get_yaw() / set_yaw(rad), get_view_basis() (yaw-only basis for movement input)

const BASE_DISTANCE := 4.3
const PIVOT_HEIGHT := 1.55
const SHOULDER := 0.42
const LOCK_SHOULDER := 0.95
const PITCH_MIN := deg_to_rad(-38.0)
const PITCH_MAX := deg_to_rad(72.0)
const MOUSE_RAD_PER_PX := 0.0026
const PAD_RAD_PER_S := 2.8
const TOUCH_RAD_PER_PX := 0.0042
const COLLISION_RADIUS := 0.22

var camera: Camera3D
## Node followed (the player); set_target_override() replaces it temporarily.
var target: Node3D = null
var targeting: PlayerTargeting = null
var mode: StringName = &"default"
var mode_params: Dictionary = {}
## Orbit angles (rad): yaw 0 = camera behind a -Z facing target; pitch + = above.
var yaw := 0.0
var pitch := deg_to_rad(14.0)
## When true mouse motion only rotates the camera while the mouse is captured.
var require_capture := true
## Capture the mouse on the first click into the game (desktop, not touch).
var auto_capture := true
var input_enabled := true
## Extra FOV (sprint kick etc.), degrees.
var fov_offset := 0.0

var _override: Node3D = null
var _pivot := Vector3.ZERO
var _pivot_init := false
var _distance := BASE_DISTANCE
var _shoulder := SHOULDER
var _trauma := 0.0
var _trauma_hold := 0.0
var _shake_t := 0.0
var _imp_pos := Vector3.ZERO
var _imp_vel := Vector3.ZERO
var _cine_from := Transform3D.IDENTITY
var _cine_t := 1.0
var _idle_look := 0.0
var _noise := FastNoiseLite.new()
var _last_real := 0


func _init() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.08
	camera.far = 9000.0
	add_child(camera)
	_noise.seed = 77
	_noise.frequency = 1.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = Settings.fov()
	Events.look_input.connect(_on_look_input)
	Events.camera_shake.connect(_on_shake)
	Events.camera_impulse.connect(impulse)
	Events.hitstop.connect(_on_hitstop)
	Events.settings_applied.connect(_on_settings)
	_last_real = Time.get_ticks_usec()


func make_current() -> void:
	camera.make_current()


func get_camera() -> Camera3D:
	return camera


func get_yaw() -> float:
	return yaw


func set_yaw(v: float) -> void:
	yaw = wrapf(v, -PI, PI)


## Yaw-only basis for camera-relative movement input.
func get_view_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Points the camera behind `node` facing its -Z (spawns, respawn).
func snap_behind(node: Node3D) -> void:
	var f := -node.global_basis.z
	yaw = atan2(-f.x, -f.z)
	_pivot_init = false


func set_mode(new_mode: StringName, params: Dictionary = {}) -> void:
	if new_mode == &"cinematic" or mode == &"cinematic":
		_cine_from = camera.global_transform
		_cine_t = 0.0
	mode = new_mode
	mode_params = params


func set_target_override(node: Node3D) -> void:
	_override = node


func clear_target_override() -> void:
	_override = null


func add_trauma(amount: float, hold: float = 0.0) -> void:
	_trauma = clampf(maxf(_trauma, amount), 0.0, 1.0)
	_trauma_hold = maxf(_trauma_hold, hold)


## Spring kick of the camera (hits, launches): `dir` world direction.
func impulse(dir: Vector3, strength: float) -> void:
	_imp_vel += dir.normalized() * strength * 6.0 * Settings.camera_shake_scale()


func _on_shake(strength: float, duration: float) -> void:
	add_trauma(clampf(strength, 0.0, 1.0), duration * 0.5)


func _on_hitstop(duration: float) -> void:
	TimeDilation.request(0.05, duration)


func _on_settings() -> void:
	camera.fov = Settings.fov()


func _on_look_input(delta_px: Vector2) -> void:
	if not input_enabled or mode == &"cinematic":
		return
	var s := TOUCH_RAD_PER_PX * Settings.touch_camera_sensitivity()
	_apply_look(delta_px * s, delta_px)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.device == InputEvent.DEVICE_ID_EMULATION and Settings.touch_controls_enabled():
			return
		if require_capture and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var rel := mm.screen_relative if mm.screen_relative != Vector2.ZERO else mm.relative
		_apply_look(rel * MOUSE_RAD_PER_PX * Settings.mouse_sensitivity(), rel)
	elif event is InputEventMouseButton and auto_capture and (event as InputEventMouseButton).pressed:
		if not Settings.touch_controls_enabled() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_look(rad: Vector2, px: Vector2) -> void:
	if mode == &"cinematic":
		return
	_idle_look = 0.0
	var locked := targeting != null and targeting.get_lock_target() != null and mode == &"default"
	if locked:
		targeting.feed_look(px)
		# Small freedom while locked (framing stays automatic).
		yaw -= rad.x * 0.15
		pitch = clampf(pitch + rad.y * (-1.0 if Settings.invert_y() else 1.0) * 0.4, PITCH_MIN, PITCH_MAX)
		return
	yaw = wrapf(yaw - rad.x, -PI, PI)
	pitch = clampf(pitch + rad.y * (-1.0 if Settings.invert_y() else 1.0), PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf(float(now - _last_real) / 1000000.0, 0.0, 0.1)
	_last_real = now
	var follow := _override if _override != null and is_instance_valid(_override) else target
	if follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
		return
	if input_enabled and mode != &"cinematic":
		var lx := Input.get_action_strength(&"look_right") - Input.get_action_strength(&"look_left")
		var ly := Input.get_action_strength(&"look_down") - Input.get_action_strength(&"look_up")
		if absf(lx) + absf(ly) > 0.01:
			var k := PAD_RAD_PER_S * Settings.controller_sensitivity() * real_dt
			var locked := targeting != null and targeting.get_lock_target() != null and mode == &"default"
			if not locked:
				_apply_look(Vector2(lx, ly) * k, Vector2.ZERO)
	_idle_look += real_dt
	if mode == &"cinematic":
		_update_cinematic(real_dt)
		return
	var tpos := _follow_pos(follow)
	var height := float(mode_params.get("height", PIVOT_HEIGHT))
	var shoulder := float(mode_params.get("shoulder", SHOULDER if mode == &"default" else 0.0))
	var base_dist := float(mode_params.get("distance", BASE_DISTANCE)) * clampf(float(Settings.get_value("controls", "camera_distance", 1.0)), 0.5, 2.0)
	var lock := targeting.get_lock_target() if targeting != null and mode == &"default" else null
	if lock != null:
		var to := lock.global_position - tpos
		to.y = 0.0
		if to.length() > 0.3:
			# Camera forward (-sin yaw, 0, -cos yaw) points from the player at the target.
			var want_yaw := atan2(-to.x, -to.z)
			yaw = lerp_angle(yaw, want_yaw, 1.0 - exp(-real_dt * 5.0))
			var sep := to.length()
			base_dist += clampf(sep * 0.18, 0.0, 2.5)
			var dy := (lock.global_position.y - tpos.y)
			var want_pitch := clampf(deg_to_rad(12.0) - atan2(dy, maxf(sep, 1.0)) * 0.6, deg_to_rad(-10.0), deg_to_rad(40.0))
			pitch = lerpf(pitch, want_pitch, 1.0 - exp(-real_dt * 3.0))
			# Wider over-the-shoulder offset so the player never hides the target.
			shoulder = maxf(shoulder, LOCK_SHOULDER)
	elif mode == &"flight" and bool(mode_params.get("auto_align", true)) and _idle_look > 1.2:
		var v: Vector3 = follow.get("velocity") if "velocity" in follow else Vector3.ZERO
		var hv := Vector3(v.x, 0, v.z)
		if hv.length() > 2.0:
			yaw = lerp_angle(yaw, atan2(-hv.x, -hv.z), 1.0 - exp(-real_dt * 1.2))
	var pivot_target := tpos + Vector3.UP * height
	if not _pivot_init:
		_pivot = pivot_target
		_pivot_init = true
	var kh := 1.0 - exp(-delta * 16.0)
	var kv := 1.0 - exp(-delta * 9.0)
	_pivot = Vector3(lerpf(_pivot.x, pivot_target.x, kh), lerpf(_pivot.y, pivot_target.y, kv), lerpf(_pivot.z, pivot_target.z, kh))
	if _pivot.distance_to(pivot_target) > 6.0:
		_pivot = pivot_target
	var yb := Basis(Vector3.UP, yaw)
	var right := yb.x
	var offset_dir := yb * Vector3(0.0, sin(pitch), cos(pitch))
	_shoulder = lerpf(_shoulder, shoulder, 1.0 - exp(-real_dt * 4.0))
	var pivot := _pivot + right * _shoulder
	# Collision: never put the camera behind a wall / under the terrain.
	var want := base_dist
	var hit := _cast(_pivot, pivot + offset_dir * want, follow)
	if hit < want:
		_distance = hit
	else:
		_distance = lerpf(_distance, want, 1.0 - exp(-delta * 4.0))
	var cam_pos := pivot + offset_dir * _distance
	var ground := WorldData.get_height(cam_pos.x, cam_pos.z) + 0.3
	if cam_pos.y < ground and WorldData.is_loaded():
		cam_pos.y = ground
	# Impulse spring: exact critically damped solution (stable at any frame
	# time), in real time so hitstop never freezes it.
	var omega := 11.0
	var decay := exp(-omega * real_dt)
	var x0 := _imp_pos
	var v0 := _imp_vel
	_imp_pos = (x0 + (v0 + omega * x0) * real_dt) * decay
	_imp_vel = (v0 - omega * real_dt * (v0 + omega * x0)) * decay
	_imp_pos = _imp_pos.limit_length(0.6)
	var look_at_pos := pivot - Vector3.UP * 0.05
	if lock != null:
		look_at_pos = pivot.lerp(BendingContext.target_point(lock), 0.3)
	var xf := Transform3D(Basis.IDENTITY, cam_pos + _imp_pos)
	xf = xf.looking_at(look_at_pos, Vector3.UP)
	xf = _apply_shake(xf, real_dt)
	global_transform = xf
	camera.transform = Transform3D.IDENTITY
	var fov := Settings.fov() + fov_offset + float(mode_params.get("fov", 0.0))
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-real_dt * 6.0))


func _follow_pos(n: Node3D) -> Vector3:
	if get_tree().physics_interpolation:
		return n.get_global_transform_interpolated().origin
	return n.global_position


func _cast(from: Vector3, to: Vector3, follow: Node3D) -> float:
	var full := from.distance_to(to)
	if full < 0.01:
		return full
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = COLLISION_RADIUS
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, from)
	params.motion = to - from
	params.collision_mask = Layers.CAMERA_BLOCKERS
	var ex: Array[RID] = []
	if follow is CollisionObject3D:
		ex.append((follow as CollisionObject3D).get_rid())
	if target is CollisionObject3D and target != follow:
		ex.append((target as CollisionObject3D).get_rid())
	params.exclude = ex
	var r := space.cast_motion(params)
	if r.size() < 2 or r[0] >= 1.0:
		return INF
	var d := (from.distance_to(to) * r[0]) - 0.05
	# from -> pivot includes the shoulder offset: distance along the offset ray.
	return maxf(0.35, d)


func _apply_shake(xf: Transform3D, real_dt: float) -> Transform3D:
	if _trauma_hold > 0.0:
		_trauma_hold -= real_dt
	else:
		_trauma = maxf(0.0, _trauma - real_dt * 1.8)
	var amt := _trauma * _trauma * Settings.camera_shake_scale()
	if amt <= 0.0001:
		return xf
	_shake_t += real_dt * 28.0
	var ox := _noise.get_noise_2d(_shake_t, 0.0)
	var oy := _noise.get_noise_2d(0.0, _shake_t)
	var rz := _noise.get_noise_2d(_shake_t, 50.0)
	var b := xf.basis
	xf.origin += (b.x * ox + b.y * oy) * 0.32 * amt
	xf.basis = b * Basis(Vector3.BACK, rz * 0.06 * amt) * Basis(Vector3.RIGHT, oy * 0.02 * amt)
	return xf


func _update_cinematic(real_dt: float) -> void:
	var to: Transform3D = mode_params.get("transform", global_transform)
	var blend := float(mode_params.get("blend", 0.8))
	_cine_t = minf(1.0, _cine_t + real_dt / maxf(blend, 0.01))
	var e := _cine_t * _cine_t * (3.0 - 2.0 * _cine_t)
	global_transform = _cine_from.interpolate_with(to, e)
	camera.transform = Transform3D.IDENTITY
	camera.fov = lerpf(camera.fov, float(mode_params.get("fov", Settings.fov())), 1.0 - exp(-real_dt * 4.0))
