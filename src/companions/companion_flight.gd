class_name CompanionFlight
extends RefCounted
## Flight dynamics for the sky bison and the dragon, used both when ridden (CompanionRide
## maps the player's input) and when flying on their own (CompanionBrain escort / call).
##
## Phases: NONE (on the ground) -> TAKEOFF (rig "takeoff": crouch, then climb from the
## "leap" event) -> FLY -> LANDING (decelerate + descend, rig "land" near the ground,
## touchdown) -> NONE. Every phase has a timeout.
##
## Model (per physics tick, from the intent fields below):
## * airspeed approaches a target: glide (no input), cruise (thrust), boost (sprint), hover /
##   minimum (brake). The dragon never drops below its minimum airspeed (no stall); diving
##   gains speed, climbing costs some.
## * heading turns toward `want_dir` with a speed-dependent turn rate; the bank angle is the
##   coordinated-turn roll atan(v * yaw_rate / g), clamped per species; pitch follows the
##   climb angle.
## * vertical speed from `climb` (-1..1) or `hold_altitude`; gliding sinks slowly.
## * terrain + sea avoidance: WorldData heights sampled along the path up to 3 s ahead and a
##   forward physics ray (trees, buildings) force a pull-up; a ceiling and the world edge
##   push back; the body never goes below the terrain / water surface.

enum Phase { NONE, TAKEOFF, FLY, LANDING }

const G := 9.8
const LOOKAHEAD: Array[float] = [0.0, 0.5, 1.0, 1.8, 2.8]
const WORLD_EDGE := 3880.0
const CEILING_ABOVE_TERRAIN := 320.0
const CEILING_ABS := 1500.0
const TAKEOFF_TIMEOUT := 4.5
const LANDING_TIMEOUT := 9.0

var body: CharacterBody3D
var rig: CreatureRig
var prof: CompanionProfile
var t: Dictionary = {}
var phase: int = Phase.NONE
var phase_time := 0.0
## Horizontal airspeed (m/s), heading (rad, 0 = -Z), turn rate (rad/s).
var speed := 0.0
var heading := 0.0
var yaw_rate := 0.0
var vy := 0.0
## Visual attitude fed to CreatureRig.set_flight (rad): bank + = right side down.
var bank := 0.0
var pitch := 0.0
var leap_seen := false
## Last terrain/obstacle pull-up strength (0..1) and whether the world edge pushed back.
var avoiding := 0.0
var edge_push := false

# --- intent (written every tick by the rider controls or the brain) ---------------------------
## Horizontal direction to fly toward (ZERO = keep heading).
var want_dir := Vector3.ZERO
## 0 = glide, 1 = full cruise thrust.
var throttle := 0.0
var boost := false
var brake := false
## -1 (descend) .. 1 (climb); ignored when hold_altitude is finite.
var climb := 0.0
## Autonomous flight: target height of the body origin (INF = use `climb`).
var hold_altitude := INF
## Autonomous flight: target airspeed (< 0 = from throttle / boost / brake).
var hold_speed := -1.0
## Lower terrain clearance while deliberately descending to land (ridden).
var low_pass := false

var _land_vx := Vector3.ZERO
var _ray_t := 0.0
var _ray_block := 0.0


func _init(p_body: CharacterBody3D, p_rig: CreatureRig, p_prof: CompanionProfile) -> void:
	body = p_body
	rig = p_rig
	prof = p_prof
	t = prof.flight
	if rig:
		rig.action_event.connect(_on_rig_event)


func is_active() -> bool:
	return phase != Phase.NONE


## In the air (after the takeoff leap, during flight and landing).
func is_airborne() -> bool:
	return phase == Phase.FLY or phase == Phase.LANDING or (phase == Phase.TAKEOFF and leap_seen)


func is_landing() -> bool:
	return phase == Phase.LANDING


func phase_name() -> String:
	return ["none", "takeoff", "fly", "landing"][phase]


func reset_intent() -> void:
	want_dir = Vector3.ZERO
	throttle = 0.0
	boost = false
	brake = false
	climb = 0.0
	hold_altitude = INF
	hold_speed = -1.0
	low_pass = false


## Starts a takeoff from the ground. False if already flying.
func takeoff(current_yaw: float) -> bool:
	if phase != Phase.NONE:
		return false
	phase = Phase.TAKEOFF
	phase_time = 0.0
	leap_seen = false
	heading = current_yaw
	speed = Vector2(body.velocity.x, body.velocity.z).length()
	vy = 0.0
	yaw_rate = 0.0
	if rig:
		rig.set_flying(true)
	return true


## Enters flight directly (teleported into the sky, re-entering the air after a fall).
func start_airborne(current_yaw: float, airspeed: float) -> void:
	phase = Phase.FLY
	phase_time = 0.0
	leap_seen = true
	heading = current_yaw
	speed = maxf(airspeed, f("min"))
	vy = 0.0
	if rig:
		rig.set_flying(true)
		rig.flight_w = maxf(rig.flight_w, 0.95)


## Begins landing where the creature is. Returns false (keeps flying) when the ground
## below is not landable (water, steep, a roof).
func land() -> bool:
	if phase != Phase.FLY:
		return phase == Phase.LANDING
	if not can_land_below():
		return false
	phase = Phase.LANDING
	phase_time = 0.0
	_land_vx = CompanionNav.dir_of(heading) * speed
	if rig:
		rig.set_flying(false)
	return true


## Walkable (species slope limit), dry ground under the body.
func can_land_below() -> bool:
	var p := body.global_position
	var slope := prof.f(prof.follow, "max_slope", 34.0)
	var r := prof.radius() * 0.9
	return CompanionNav.flat_area(p.x, p.z, r, slope, r * tan(deg_to_rad(slope)) + 0.4)


## Height of the body above the terrain / water surface below it.
func altitude() -> float:
	var p := body.global_position
	return p.y - CompanionNav.surface_y(p.x, p.z)


## Drops out of flight immediately (teleports, external resets).
func cancel() -> void:
	phase = Phase.NONE
	phase_time = 0.0
	speed = 0.0
	vy = 0.0
	bank = 0.0
	pitch = 0.0
	yaw_rate = 0.0
	if rig:
		rig.set_flying(false)


func step(delta: float) -> void:
	phase_time += delta
	match phase:
		Phase.TAKEOFF:
			_takeoff(delta)
		Phase.FLY:
			_fly(delta)
		Phase.LANDING:
			_landing(delta)


# --- phases ---------------------------------------------------------------------------------------

func _takeoff(delta: float) -> void:
	var leap_at := float(prof.f(t, "leap", 0.72))
	if not leap_seen and phase_time >= leap_at + 0.15:
		leap_seen = true   # the rig event is the cue; time is the backstop
	if not leap_seen:
		# Crouch on the ground, turning toward the wish.
		speed = move_toward(speed, 0.0, 8.0 * delta)
		_turn(delta, 1.6)
		vy = -2.0
		_apply(delta, false)
		return
	var climb_rate := f("climb") * 0.95
	vy = move_toward(vy, climb_rate, 22.0 * delta)
	speed = move_toward(speed, maxf(f("glide") * 0.8, f("min")), f("accel") * 0.8 * delta)
	_turn(delta, 1.0)
	_attitude(delta)
	_apply(delta, true)
	if altitude() > 6.0 or phase_time > leap_at + 2.4 or phase_time > TAKEOFF_TIMEOUT:
		phase = Phase.FLY
		phase_time = 0.0


func _fly(delta: float) -> void:
	# --- airspeed ---
	var target := f("glide")
	if hold_speed >= 0.0:
		target = hold_speed
	elif brake:
		target = f("hover")
	elif boost:
		target = f("boost")
	elif throttle > 0.05:
		target = lerpf(f("glide"), f("cruise"), clampf(throttle, 0.0, 1.0))
	# Diving trades height for speed; climbing costs a little.
	if vy < -2.0:
		target += minf(-vy - 2.0, 10.0) * 0.6
	elif vy > 2.0:
		target -= (vy - 2.0) * 0.35
	# Coming down to land: bleed off speed so the descent is steep enough to reach a spot
	# instead of skimming on over the slope ahead.
	if low_pass and climb < -0.05 and altitude() < 30.0:
		target = minf(target, maxf(f("min"), f("glide") * 0.55))
	target = clampf(target, f("min"), f("boost") + 8.0)
	var rate := f("boost_accel") if boost and target > speed else (f("accel") if target > speed else f("decel"))
	speed = move_toward(speed, target, rate * delta)
	speed = maxf(speed, f("min"))   # stall prevention
	# --- heading ---
	_turn(delta, 1.0)
	# --- vertical ---
	var want_vy := 0.0
	if is_finite(hold_altitude):
		var err := hold_altitude - body.global_position.y
		want_vy = clampf(err * 0.6, -f("descend"), f("climb"))
	elif climb > 0.05:
		want_vy = f("climb") * climb
	elif climb < -0.05:
		want_vy = f("descend") * climb
	elif throttle <= 0.05 and not brake:
		want_vy = -f("glide_sink")
	want_vy = _avoid_terrain(delta, want_vy)
	vy = move_toward(vy, want_vy, (14.0 if absf(want_vy) > absf(vy) else 10.0) * delta)
	_attitude(delta)
	_apply(delta, true)


func _landing(delta: float) -> void:
	var alt := maxf(altitude(), _ground_alt())
	# Glide in: forward speed bleeds off as the ground comes up, then a soft vertical touchdown.
	var fwd_target := clampf(alt * 0.7, 0.0, 6.0)
	speed = move_toward(speed, fwd_target, maxf(f("decel"), 5.0) * 1.3 * delta)
	_turn(delta, 0.6)
	var want_vy := -clampf(alt * 1.0 + 0.8, 1.2, f("descend") * 0.6)
	vy = move_toward(vy, want_vy, 12.0 * delta)
	bank = lerpf(bank, 0.0, 1.0 - exp(-delta * 4.0))
	pitch = lerpf(pitch, 0.06, 1.0 - exp(-delta * 3.0))
	_apply(delta, true)
	if body.is_on_floor() or alt < 0.12 or phase_time > LANDING_TIMEOUT:
		if phase_time > LANDING_TIMEOUT and body.is_inside_tree():
			body.global_position.y = CompanionNav.ground_y(body.get_world_3d().direct_space_state, body.global_position, 2.0, 30.0, [body.get_rid()])
		phase = Phase.NONE
		phase_time = 0.0
		vy = 0.0
		bank = 0.0
		pitch = 0.0


# --- helpers --------------------------------------------------------------------------------------

func f(key: String, fallback: float = 0.0) -> float:
	return float(t.get(key, fallback))


func _turn(delta: float, scale: float) -> void:
	var want := CompanionNav.flat_dir(want_dir)
	var p := body.global_position
	edge_push = false
	if absf(p.x) > WORLD_EDGE or absf(p.z) > WORLD_EDGE:
		# The open sea beyond the world: the winds turn the flyer back toward land.
		var home := CompanionNav.flat_dir(-p)
		want = home if want == Vector3.ZERO else (want + home * 2.5).normalized()
		edge_push = true
	var target_rate := 0.0
	if want != Vector3.ZERO:
		var diff := wrapf(CompanionNav.yaw_of(want) - heading, -PI, PI)
		var k := clampf(speed / maxf(f("cruise"), 1.0), 0.0, 1.0)
		var max_rate := deg_to_rad(lerpf(f("turn_slow"), f("turn_fast"), k)) * scale
		target_rate = clampf(diff * 2.4, -max_rate, max_rate)
	yaw_rate = lerpf(yaw_rate, target_rate, 1.0 - exp(-delta * 5.0))
	heading = wrapf(heading + yaw_rate * delta, -PI, PI)


func _attitude(delta: float) -> void:
	# Coordinated turn: yaw_rate > 0 turns left (counter-clockwise from above), so the
	# right side comes up: bank (+ = right side down) is negative.
	var want_bank := -atan(speed * yaw_rate / G)
	var mb := f("max_bank", 0.5)
	want_bank = clampf(want_bank, -mb, mb)
	bank = lerpf(bank, want_bank, 1.0 - exp(-delta * 3.5))
	var want_pitch := clampf(atan2(vy, maxf(speed, 5.0)) * 0.85, -0.55, 0.5)
	pitch = lerpf(pitch, want_pitch, 1.0 - exp(-delta * 3.0))


## Terrain / sea / obstacle avoidance and the ceiling. Returns the corrected vertical speed.
func _avoid_terrain(delta: float, want_vy: float) -> float:
	var p := body.global_position
	var dir := CompanionNav.dir_of(heading)
	var clearance := f("clearance", 6.0)
	if low_pass or is_finite(hold_altitude) and hold_altitude < p.y:
		clearance = maxf(f("land_clearance", 1.2) + 1.0, clearance * 0.35)
	var need := -INF
	for s: float in LOOKAHEAD:
		var q := p + dir * speed * s
		need = maxf(need, CompanionNav.surface_y(q.x, q.z) + clearance * (1.0 if s > 0.0 else 0.7))
	# Trees, buildings, arches: a forward ray at body height (10 Hz).
	_ray_t -= delta
	if _ray_t <= 0.0 and body.is_inside_tree():
		_ray_t = 0.1
		_ray_block = 0.0
		var from := p + Vector3.UP * prof.body_height() * 0.5
		var reach := maxf(speed * 1.6, 8.0)
		var q2 := PhysicsRayQueryParameters3D.create(from, from + dir * reach, Layers.SOLID, [body.get_rid()])
		var r := body.get_world_3d().direct_space_state.intersect_ray(q2)
		# Landable ground ahead is not an obstacle while deliberately coming down.
		if not r.is_empty() and not (low_pass and (r["normal"] as Vector3).y > 0.65):
			_ray_block = 1.0 - clampf(from.distance_to(r["position"]) / reach, 0.0, 1.0)
	avoiding = 0.0
	if p.y < need:
		var deficit := need - p.y
		avoiding = clampf(deficit / 8.0, 0.0, 1.0)
		want_vy = maxf(want_vy, minf(deficit * 2.2, f("climb") * 1.6))
	if _ray_block > 0.0:
		avoiding = maxf(avoiding, _ray_block)
		want_vy = maxf(want_vy, f("climb") * 1.4 * _ray_block)
		speed = move_toward(speed, maxf(f("min"), speed * 0.6), 12.0 * _ray_block * delta)
	var ceiling := minf(CompanionNav.surface_y(p.x, p.z) + CEILING_ABOVE_TERRAIN, CEILING_ABS)
	if p.y > ceiling:
		want_vy = minf(want_vy, -2.0 - (p.y - ceiling) * 0.2)
	return want_vy


func _ground_alt() -> float:
	if not body.is_inside_tree():
		return altitude()
	var p := body.global_position
	var gy := CompanionNav.ground_y(body.get_world_3d().direct_space_state, p, 0.5, 40.0, [body.get_rid()])
	return p.y - gy


func _apply(_delta: float, airborne: bool) -> void:
	var h := CompanionNav.dir_of(heading) * speed
	body.velocity = Vector3(h.x, vy, h.z)
	body.rotation = Vector3(0.0, heading, 0.0)
	body.move_and_slide()
	if not airborne:
		return
	# Never through the world: the body origin stays above the terrain / water surface.
	var p := body.global_position
	var floor_y := CompanionNav.surface_y(p.x, p.z)
	var min_y := floor_y + (0.0 if phase == Phase.LANDING else 0.4)
	if p.y < min_y:
		body.global_position.y = min_y
		vy = maxf(vy, 0.0)
	# Hitting the ceiling of an overhang / tree canopy: bleed off climb.
	if body.is_on_ceiling():
		vy = minf(vy, 0.0)


func _on_rig_event(action_name: StringName, event: StringName) -> void:
	if action_name == &"takeoff" and event == &"leap" and phase == Phase.TAKEOFF:
		leap_seen = true
