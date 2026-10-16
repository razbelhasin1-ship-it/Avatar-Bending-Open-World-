class_name CompanionMotor
extends RefCounted
## Ground locomotion of a companion body (CharacterBody3D): creatures move along their
## heading (they turn, they do not strafe), accelerate toward a desired speed, follow the
## terrain (floor snap, slopes by species), slow in deep snow / up steep slopes, swim in deep
## water, and steer around obstacles with whisker rays (no navmesh across the 8 km world).
## Stuck detection reports `stuck_time` so the brain can unstick or teleport.
##
##   motor.move(delta, dir, speed, {"avoid": true})   # once per physics tick
##   motor.brake(delta)                               # stop in place (turning allowed)

const GRAVITY := 22.0
## Whisker angles (deg) relative to the wanted direction, best first when equally clear.
const WHISKERS: Array[float] = [0.0, -28.0, 28.0, -55.0, 55.0, -85.0, 85.0, -125.0, 125.0]
const PROBE_INTERVAL := 0.1

var body: CharacterBody3D
var prof: CompanionProfile
## Current heading (rad, 0 = facing -Z).
var yaw := 0.0
## Horizontal speed along the heading (m/s, may be negative briefly when backing up).
var speed := 0.0
var on_floor := true
var swimming := false
var water_y := -INF
## Seconds without progress while trying to move (brain unsticks / teleports).
var stuck_time := 0.0
## Last position on solid, dry, walkable ground (teleport fallback).
var last_safe := Vector3.INF
var max_slope := 40.0
## Gameplay multiplier (retreat limp, assist charges).
var speed_scale := 1.0
## Snow slow-down 0..1 (fraction lost in deep snow; 0 = polar bear dog).
var snow_slow := 0.2
var rugged := false

var _probe_t := 0.0
var _avoid_dir := Vector3.ZERO
var _escape_dir := Vector3.ZERO
var _escape_t := 0.0
var _progress_t := 0.0
var _progress_from := Vector3.ZERO
var _wanted_dist := 0.0
var _safe_t := 0.0
var _vy := 0.0


func _init(p_body: CharacterBody3D, p_prof: CompanionProfile) -> void:
	body = p_body
	prof = p_prof
	max_slope = prof.f(prof.follow, "max_slope", 40.0)
	snow_slow = prof.f(prof.ride, "snow", 0.2)
	rugged = bool(prof.ride.get("rugged", false))


func configure_body() -> void:
	body.floor_max_angle = deg_to_rad(max_slope + 6.0)
	body.floor_snap_length = clampf(prof.radius() * 0.6, 0.5, 1.2)
	body.floor_stop_on_slope = true
	body.floor_constant_speed = true
	body.safe_margin = 0.04
	body.max_slides = 5


func set_ride_mode(on: bool) -> void:
	max_slope = prof.f(prof.ride if on else prof.follow, "max_slope", 40.0)
	configure_body()


## Steers toward `dir` (horizontal) at `want_speed` m/s and integrates. opts:
##   avoid (bool, true)   obstacle whiskers
##   turn (deg/s)         turn rate (default profile follow turn)
##   accel, decel (m/s²)  defaults by species size
##   face (Vector3)       heading to turn to while standing still
func move(delta: float, dir: Vector3, want_speed: float, opts: Dictionary = {}) -> void:
	var d := CompanionNav.flat_dir(dir)
	var turn := float(opts.get("turn", prof.f(prof.follow, "turn", 160.0)))
	var accel := float(opts.get("accel", 8.0))
	var decel := float(opts.get("decel", 10.0))
	want_speed = maxf(0.0, want_speed) * speed_scale
	if d != Vector3.ZERO and want_speed > 0.05:
		if bool(opts.get("avoid", true)):
			d = _avoid(delta, d, want_speed)
		if _escape_t > 0.0:
			_escape_t -= delta
			d = _escape_dir
		var target_yaw := CompanionNav.yaw_of(d)
		var diff := wrapf(target_yaw - yaw, -PI, PI)
		var max_step := deg_to_rad(turn) * delta
		yaw = wrapf(yaw + clampf(diff, -max_step, max_step), -PI, PI)
		# Big turns slow the creature down (it pivots instead of drifting wide).
		var align := clampf(cos(diff), 0.0, 1.0)
		want_speed *= lerpf(0.25, 1.0, align)
		want_speed *= terrain_factor(CompanionNav.dir_of(yaw))
		speed = move_toward(speed, want_speed, (accel if want_speed > speed else decel) * delta)
		_track_progress(delta, want_speed)
	else:
		speed = move_toward(speed, 0.0, decel * delta)
		var face: Vector3 = opts.get("face", Vector3.ZERO)
		var fd := CompanionNav.flat_dir(face)
		if fd != Vector3.ZERO:
			var diff2 := wrapf(CompanionNav.yaw_of(fd) - yaw, -PI, PI)
			var st := deg_to_rad(turn * 0.6) * delta
			yaw = wrapf(yaw + clampf(diff2, -st, st), -PI, PI)
		_track_progress(delta, 0.0)
	integrate(delta)


## Stops (decelerates) in place.
func brake(delta: float, rate: float = 14.0) -> void:
	speed = move_toward(speed, 0.0, rate * delta)
	_track_progress(delta, 0.0)
	integrate(delta)


## Gravity, swimming, move_and_slide, heading, world-floor safety.
func integrate(delta: float) -> void:
	var fwd := CompanionNav.dir_of(yaw)
	var v := fwd * speed
	var p := body.global_position
	_update_water(p)
	if swimming:
		var target_y := water_y - prof.body_height() * 0.42
		_vy = clampf((target_y - p.y) * 3.0, -3.0, 3.0)
		v *= 0.55
	elif on_floor and _vy <= 0.0:
		_vy = -1.0
	else:
		_vy = maxf(_vy - GRAVITY * delta, -40.0)
	body.velocity = Vector3(v.x, _vy, v.z)
	body.rotation = Vector3(0.0, yaw, 0.0)
	body.move_and_slide()
	on_floor = body.is_on_floor()
	if on_floor and _vy < 0.0:
		_vy = 0.0
	# The slide may have changed the horizontal speed (walls): keep it honest.
	var hv := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if hv.length() < absf(speed) - 0.5:
		speed = signf(speed) * hv.length()
	_floor_safety(delta)


## Vertical launch (pounce, mounted leap).
func jump(vy: float) -> void:
	_vy = vy
	on_floor = false
	body.global_position += Vector3.UP * 0.05


func vertical_speed() -> float:
	return _vy


## Places the body (teleports): resets speeds and stuck tracking.
func teleport(pos: Vector3, p_yaw: float = INF) -> void:
	body.global_position = pos
	if is_finite(p_yaw):
		yaw = p_yaw
	body.rotation = Vector3(0.0, yaw, 0.0)
	body.velocity = Vector3.ZERO
	speed = 0.0
	_vy = 0.0
	stuck_time = 0.0
	_escape_t = 0.0
	_progress_t = 0.0
	_progress_from = pos
	_wanted_dist = 0.0
	on_floor = true


## Speed factor for moving along `dir` here: deep snow, steep uphill, wading.
func terrain_factor(dir: Vector3) -> float:
	var p := body.global_position
	var f := 1.0
	if snow_slow > 0.0:
		var sd := WorldData.get_snow_depth(p.x, p.z)
		if sd > 0.05:
			f *= 1.0 - snow_slow * clampf((sd - 0.05) / 0.45, 0.0, 1.0)
	if not rugged:
		var ahead := p + dir * 2.0
		var rise := WorldData.get_height(ahead.x, ahead.z) - WorldData.get_height(p.x, p.z)
		var grade := rad_to_deg(atan2(rise, 2.0))
		if grade > 14.0:
			f *= 1.0 - clampf((grade - 14.0) / 30.0, 0.0, 0.45)
	if not swimming:
		var wd := CompanionNav.water_depth(p.x, p.z)
		if wd > 0.3:
			f *= 1.0 - clampf((wd - 0.3) / 1.2, 0.0, 0.4)
	return f


func is_stuck(threshold: float = 1.6) -> bool:
	return stuck_time >= threshold


# --- steering ------------------------------------------------------------------------------------

## Whisker rays at chest height that follow the terrain: picks the clearest direction
## close to `want` (walls, trees, rocks, steep or flooded ground count as blocked).
func _avoid(delta: float, want: Vector3, want_speed: float) -> Vector3:
	_probe_t -= delta
	if _probe_t > 0.0 and _avoid_dir != Vector3.ZERO:
		# Re-use the last decision but keep it close to the current wish.
		return _avoid_dir if _avoid_dir.dot(want) > 0.2 else want
	_probe_t = PROBE_INTERVAL
	var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
	var reach := clampf(want_speed * 1.3, 2.5, 9.0) + prof.radius()
	var chest := clampf(prof.body_height() * 0.45, 0.6, 2.2)
	var best := want
	var best_score := -INF
	var ex: Array[RID] = [body.get_rid()]
	for deg: float in WHISKERS:
		var dir := want.rotated(Vector3.UP, deg_to_rad(deg))
		var clear := _clearance(space, dir, reach, chest, ex)
		var score := clear * 2.0 - absf(deg) / 90.0 * 0.9
		if deg == 0.0 and clear >= 0.98:
			_avoid_dir = want
			return want
		if score > best_score:
			best_score = score
			best = dir
	_avoid_dir = best
	return best


## 0..1 free fraction of a whisker (1 = nothing within reach).
func _clearance(space: PhysicsDirectSpaceState3D, dir: Vector3, reach: float, chest: float, ex: Array[RID]) -> float:
	var p := body.global_position
	var end := p + dir * reach
	# Ground that is too steep or flooded counts as an obstacle at that distance.
	var ground_frac := 1.0
	for f: float in [0.45, 1.0]:
		var q := p + dir * reach * f
		if not CompanionNav.walkable(q.x, q.z, max_slope + 4.0, 1.4 if prof.can_swim else 0.45):
			ground_frac = minf(ground_frac, f * 0.9)
			break
	if space == null:
		return ground_frac
	var from := p + Vector3.UP * chest
	var to := Vector3(end.x, WorldData.get_height(end.x, end.z) + chest, end.z)
	to.y = maxf(to.y, end.y + chest * 0.5)
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID, ex))
	if r.is_empty():
		return ground_frac
	var d := from.distance_to(r["position"])
	return minf(ground_frac, clampf((d - prof.radius() * 0.6) / reach, 0.0, 1.0))


func _track_progress(delta: float, want_speed: float) -> void:
	_progress_t += delta
	_wanted_dist += want_speed * delta
	if _progress_t < 1.0:
		return
	var moved := Vector2(body.global_position.x - _progress_from.x, body.global_position.z - _progress_from.z).length()
	if _wanted_dist > 1.2 and moved < _wanted_dist * 0.25:
		stuck_time += _progress_t
		if stuck_time > 1.0 and _escape_t <= 0.0:
			_start_escape()
	elif _wanted_dist <= 1.2 or moved >= _wanted_dist * 0.5:
		stuck_time = maxf(0.0, stuck_time - _progress_t * 2.0)
	_progress_t = 0.0
	_wanted_dist = 0.0
	_progress_from = body.global_position


## Backs off sideways along the clearest whisker for a moment (unstick).
func _start_escape() -> void:
	var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
	var fwd := CompanionNav.dir_of(yaw)
	var best := -fwd
	var best_c := -1.0
	var ex: Array[RID] = [body.get_rid()]
	for deg: float in [90.0, -90.0, 135.0, -135.0, 180.0, 60.0, -60.0]:
		var dir := fwd.rotated(Vector3.UP, deg_to_rad(deg + randf_range(-15.0, 15.0)))
		var c := _clearance(space, dir, 6.0, clampf(prof.body_height() * 0.45, 0.6, 2.2), ex)
		if c > best_c:
			best_c = c
			best = dir
	_escape_dir = best
	_escape_t = 1.2


func _update_water(p: Vector3) -> void:
	var w := WorldData.get_water_height(p.x, p.z)
	water_y = w
	if not is_finite(w):
		swimming = false
		return
	var depth := w - p.y
	var need := prof.body_height() * 0.55
	swimming = depth > (need * 0.85 if swimming else need)


## Never below the world: a body found under the terrain with nothing solid beneath it is
## put back on top (caves keep their floor, so they are fine). Tracks the last safe spot.
func _floor_safety(delta: float) -> void:
	_safe_t -= delta
	var p := body.global_position
	if not p.is_finite():
		return
	var th := WorldData.get_height(p.x, p.z)
	var deep := p.y < th - 3.0
	if _safe_t > 0.0 and not deep:
		return
	_safe_t = 0.25
	if p.y < th - 0.6:
		var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
		var ex: Array[RID] = [body.get_rid()]
		if not CompanionNav.has_floor(space, p, 60.0, ex):
			body.global_position = Vector3(p.x, th + 0.05, p.z)
			_vy = 0.0
			on_floor = true
			return
	if on_floor and not swimming and CompanionNav.walkable(p.x, p.z, max_slope, 0.3):
		last_safe = p
