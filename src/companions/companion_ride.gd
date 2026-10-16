class_name CompanionRide
extends RefCounted
## Mounted controls, read from the rider's PlayerInput (InputMap actions only, so the touch
## overlay and rebinding work):
##
## | Input | Ground mount | Flying mount |
## | --- | --- | --- |
## | move (camera-relative) | walk / run toward the stick direction | steer toward the stick direction (banking turns), thrust = stick amount; pull back = brake / hover |
## | sprint | gallop (polar bear dog 15 m/s) | boost |
## | jump | leap (polar bear dog) / take off (flyers) | climb (hold) |
## | descend | burrow (badgermole) | dive (hold); near the ground: land |
## | mount / interact | hop down | let go (fall / glide) |
##
## The camera uses PlayerCamera's "flight" mode for both (auto-aligns behind the mount's
## velocity when the player stops steering it); boost widens the FOV.

const STATUS_COOLDOWN := 2.5

var c: Companion
var ridden_m := 0.0
var flown_m := 0.0

var _descend_prev := false
var _cam_mode: StringName = &""
var _fov_base := 0.0
var _kick := 0.0
var _status_cd := 0.0
var _stat_acc := 0.0
var _toast_ms := -100000
var _toast_text := ""


func _init(p_c: Companion) -> void:
	c = p_c


func on_mounted() -> void:
	c.motor.set_ride_mode(true)
	_cam_mode = &""
	var p := c.rider.player
	# A descend held from before the mount does not trigger anything.
	_descend_prev = p != null and is_instance_valid(p) and p.input.is_held(&"descend")
	update_camera()


func on_unmounted() -> void:
	c.motor.set_ride_mode(false)
	_cam_mode = &""


func tick(delta: float) -> void:
	var p := c.rider.player
	if p == null or not is_instance_valid(p) or p.get_state() != PlayerCharacter.State.MOUNTED:
		c.rider.release_rider()
		on_unmounted()
		c.set_mode(Companion.Mode.ESCORT if c.is_airborne() else Companion.Mode.FOLLOW)
		return
	_status_cd = maxf(0.0, _status_cd - delta)
	var inp := p.input
	# Gamepad / touch: interact also dismounts (mount has no pad binding).
	if inp.consume(&"interact"):
		c.request_dismount()
		return
	inp.clear(&"companion_call")
	var descend := inp.is_held(&"descend")
	var descend_pressed := descend and not _descend_prev
	_descend_prev = descend
	var before := c.global_position
	if c.flight != null and c.flight.is_active():
		_fly(delta, inp, descend)
	else:
		_ground(delta, p, inp, descend_pressed)
	var moved := before.distance_to(c.global_position)
	if moved < 50.0:
		if c.is_airborne():
			flown_m += moved
		else:
			ridden_m += moved
		_stat_acc += moved
		if _stat_acc >= 100.0:
			GameState.incr_stat("companion_flown_m" if c.is_airborne() else "companion_ridden_m", int(_stat_acc))
			_stat_acc = 0.0


# --- ground -------------------------------------------------------------------------------------

func _ground(delta: float, p: PlayerCharacter, inp: PlayerInput, descend_pressed: bool) -> void:
	var r := c.prof.ride
	var mv := inp.move_vector
	var mag := minf(mv.length(), 1.0)
	var want := 0.0
	if mag > 0.08:
		var walk := c.prof.f(r, "walk")
		var run := c.prof.f(r, "run")
		want = walk * mag / 0.55 if mag < 0.55 else lerpf(walk, run, (mag - 0.55) / 0.45)
		if inp.sprinting and mag > 0.5:
			want = c.prof.f(r, "sprint")
	c.motor.move(delta, mv / maxf(mag, 0.001) if mag > 0.08 else Vector3.ZERO, want,
			{"avoid": false, "turn": c.prof.f(r, "turn", 120.0), "accel": c.prof.f(r, "accel", 6.0), "decel": c.prof.f(r, "decel", 8.0)})
	if inp.consume(&"jump"):
		if c.flight != null and not c.motor.swimming:
			c.flight.takeoff(c.motor.yaw)
			c.rig.stop_action()
		elif c.prof.f(r, "jump") > 0.0 and c.motor.on_floor:
			c.motor.jump(c.prof.f(r, "jump"))
	if descend_pressed and c.burrow != null:
		var target := _burrow_target(p)
		if not c.burrow.start_to(target, true):
			_status("Can't burrow here")


## Where the badgermole tunnels to: the point the camera looks at on the ground (12-40 m
## ahead), else 28 m along the view.
func _burrow_target(p: PlayerCharacter) -> Vector3:
	var from := c.global_position
	var view := CompanionNav.dir_of(c.motor.yaw)
	if p.camera_rig and p.camera_rig.camera:
		var cam := p.camera_rig.camera
		var hit := WorldData.raycast_terrain(cam.global_position, -cam.global_basis.z, 90.0)
		var d0 := CompanionNav.flat_dir(-cam.global_basis.z)
		if d0 != Vector3.ZERO:
			view = d0
		if bool(hit.get("hit", false)):
			var hp: Vector3 = hit["position"]
			var dd := Vector2(hp.x - from.x, hp.z - from.z).length()
			if dd > 12.0 and dd < CompanionBurrow.MAX_DISTANCE:
				return hp
	return from + view * 28.0


# --- flight -------------------------------------------------------------------------------------

func _fly(delta: float, inp: PlayerInput, descend: bool) -> void:
	var f := c.flight
	f.reset_intent()
	var mv := inp.move_vector
	var mag := minf(mv.length(), 1.0)
	var fwd := CompanionNav.dir_of(f.heading)
	if mag > 0.15:
		var d := mv / mag
		if d.dot(fwd) < -0.55:
			f.brake = true
		else:
			f.want_dir = d
			f.throttle = mag
	f.boost = inp.sprinting and not f.brake
	var up := inp.is_held(&"jump")
	f.climb = (1.0 if up else 0.0) - (1.0 if descend else 0.0)
	f.low_pass = descend
	match f.phase:
		CompanionFlight.Phase.TAKEOFF:
			if f.want_dir == Vector3.ZERO:
				f.want_dir = fwd
			f.step(delta)
			return
		CompanionFlight.Phase.LANDING:
			f.step(delta)
			if not f.is_active():
				_touchdown()
			return
	if descend and f.altitude() < c.prof.f(c.prof.flight, "land_clearance", 1.2) + 4.5:
		if f.land():
			f.step(delta)
			return
		_status("Can't land here")
	f.step(delta)


func _touchdown() -> void:
	c.motor.yaw = c.flight.heading
	c.motor.speed = minf(c.flight.speed, 2.0)
	c.motor.on_floor = true
	update_camera()


func _status(text: String) -> void:
	if _status_cd > 0.0:
		return
	_status_cd = STATUS_COOLDOWN
	c.flash_status(text, 2.0)
	# The toast at most every 8 s (the HUD status line shows it every time).
	var now := Time.get_ticks_msec()
	if now - _toast_ms > 8000 or _toast_text != text:
		_toast_ms = now
		_toast_text = text
		Events.notify.emit(text, &"warning")


# --- camera ---------------------------------------------------------------------------------------

## Camera params for the current riding style (ground / air) + a boost FOV kick.
func update_camera() -> void:
	var p := c.rider.player
	if p == null or not is_instance_valid(p) or p.camera_rig == null:
		return
	var cam := p.camera_rig
	var air := c.flight != null and c.flight.is_airborne()
	var want: StringName = &"air" if air else &"ground"
	if want != _cam_mode or cam.mode != &"flight":
		_cam_mode = want
		var params: Dictionary = (c.prof.flight.get("camera", {}) if air else c.prof.ride.get("camera", {})).duplicate()
		_fov_base = float(params.get("fov", 0.0))
		cam.set_mode(&"flight", params)
		cam.set_target_override(c)
	var fast := false
	if air:
		fast = c.flight.boost and c.flight.speed > c.flight.f("cruise")
	else:
		fast = c.motor.speed > c.prof.f(c.prof.ride, "run") + 1.0
	var dt := c.get_physics_process_delta_time()
	_kick = lerpf(_kick, 1.0 if fast else 0.0, 1.0 - exp(-dt * 3.0))
	cam.mode_params["fov"] = _fov_base + _kick * (9.0 if air else 6.0)
