class_name CompanionBrain
extends RefCounted
## Autonomous behaviour of an unridden companion:
## * FOLLOW: a formation slot behind-left / behind-right of the player (side chosen with
##   hysteresis from where the companion already is, so it never cuts across), pushed out of
##   the camera -> player line of sight and kept out of the player's personal space; speed
##   matches the player plus a catch-up term. At rest: faces the player, idles and reacts.
## * ESCORT (flyers): flies along above the player (lead when moving, a wide circle when the
##   player stands still) and lands on a flat, open spot nearby once the player settles.
## * CALLED: runs to the player (flyers fly in and land beside; the badgermole may tunnel;
##   far / stuck companions appear at a safe spot out of view first).
## * RETREAT: badly hurt -> moves away from the threat, lies down and recovers.
## * WAIT: stays put (player in a cinematic / dead, or the `stay` command).
## Reactions: greets the player after time apart, growls at alerted enemies, looks at the
## player's hits, shakes off snow / rain, rests at night, plays when the player idles.

const ESCORT_LAND_DELAY := 2.5
const DRAGON_LAND_DELAY := 6.0

var c: Companion
## Formation side: -1 = player's left, +1 = right.
var side := -1.0
var land_requested := false

var _player_still := 0.0
var _player_moving := 0.0
var _player_fast := 0.0
var _rest_t := 0.0
var _idle_t := 5.0
var _greet_cd := 0.0
var _react_cd := 0.0
var _vocal_cd := 0.0
var _apart := 0.0
var _assist_t := 0.0
var _look_t := 0.0
var _look_target: Node3D = null
var _look_pos := Vector3.INF
var _land_spot := Vector3.INF
var _land_search_t := 0.0
var _slot_t := 0.0
var _slot_cache := Vector3.INF
var _greet_on_arrival := false
var _retreat_to := Vector3.INF
var _resting := false
var _play_t := 0.0
var _play_angle := 0.0
var _weather: StringName = &"clear"
var _stay := false
var _emitting := false
var _orbit_dir := 1.0
var _occlude_t := 0.0


func _init(p_c: Companion) -> void:
	c = p_c
	_orbit_dir = 1.0 if randf() < 0.5 else -1.0


func connect_events() -> void:
	if not Events.enemy_alerted.is_connected(_on_enemy_alerted):
		Events.enemy_alerted.connect(_on_enemy_alerted)
		Events.hit_landed.connect(_on_hit_landed)
		Events.weather_changed.connect(_on_weather_changed)
		Events.companion_command.connect(_on_command)


func disconnect_events() -> void:
	if Events.enemy_alerted.is_connected(_on_enemy_alerted):
		Events.enemy_alerted.disconnect(_on_enemy_alerted)
		Events.hit_landed.disconnect(_on_hit_landed)
		Events.weather_changed.disconnect(_on_weather_changed)
		Events.companion_command.disconnect(_on_command)


# --- commands (any unridden mode) -------------------------------------------------------------------

## Reads the player's companion_call / mount presses (PlayerInput buffers both).
func commands() -> void:
	var p := c.player
	if p == null or not is_instance_valid(p) or p.input == null:
		return
	if p.input.consume(&"companion_call"):
		c.call_companion()
		_emitting = true
		Events.companion_command.emit(&"call")
		_emitting = false
	if p.input.peek(&"mount") and c.can_mount(p):
		p.input.consume(&"mount")
		c.request_mount(p)


func on_called() -> void:
	var p := c.player
	if p == null or not is_instance_valid(p):
		return
	_stay = false
	_greet_on_arrival = true
	_vocal(&"greet", 0.0)
	_look_target = p
	_look_t = 2.0
	var d := _flat(p.global_position - c.global_position).length()
	if c.prof.can_fly:
		if d > 420.0:
			c.teleport_near_player(true)
		if c.is_airborne() or d > 30.0:
			land_requested = true
			_land_spot = Vector3.INF
			_land_search_t = 0.0
			c.set_mode(Companion.Mode.ESCORT)
			return
	elif c.burrow != null and d > 24.0 and d < 160.0 and not c.motor.is_stuck():
		if c.burrow.start_to(_beside_player(p), false):
			return
	if d > 60.0 or c.motor.is_stuck(1.0):
		c.teleport_near_player()
	c.set_mode(Companion.Mode.CALLED)


## Fly back to the player (far away, not lost yet).
func fly_to_player() -> void:
	land_requested = true
	c.set_mode(Companion.Mode.ESCORT)


func on_damaged(_hit: HitInfo) -> void:
	if c.is_ridden():
		return
	if c.health.ratio() < 0.3 and c.mode != Companion.Mode.RETREAT:
		_vocal(&"hurt", 0.0)
		_retreat_to = Vector3.INF
		_resting = false
		c.set_mode(Companion.Mode.RETREAT)
	else:
		_vocal(&"angry", 6.0)


# --- tick ---------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_timers(delta)
	var p := c.player
	if p == null or not is_instance_valid(p) or not c.autonomous:
		_hold(delta)
		return
	_observe(delta, p)
	var pst := p.get_state()
	if pst == PlayerCharacter.State.CINEMATIC or pst == PlayerCharacter.State.DEAD:
		_hold(delta)
		_update_look(p)
		return
	if _stay and c.mode != Companion.Mode.WAIT and c.mode != Companion.Mode.RETREAT:
		c.set_mode(Companion.Mode.WAIT)
	match c.mode:
		Companion.Mode.FOLLOW:
			_follow(delta, p)
		Companion.Mode.ESCORT:
			_escort(delta, p)
		Companion.Mode.CALLED:
			_called(delta, p)
		Companion.Mode.RETREAT:
			_retreat(delta, p)
		Companion.Mode.WAIT:
			_wait(delta, p)
		_:
			_hold(delta)
	_update_look(p)


func _timers(delta: float) -> void:
	_greet_cd = maxf(0.0, _greet_cd - delta)
	_react_cd = maxf(0.0, _react_cd - delta)
	_vocal_cd = maxf(0.0, _vocal_cd - delta)
	_look_t = maxf(0.0, _look_t - delta)
	_land_search_t -= delta
	_slot_t -= delta
	_assist_t -= delta


func _observe(delta: float, p: PlayerCharacter) -> void:
	var ps := _flat(p.velocity).length()
	if ps < 0.6:
		_player_still += delta
		_player_moving = 0.0
	else:
		_player_still = 0.0
		_player_moving += delta
	_player_fast = _player_fast + delta if ps > 8.0 else maxf(0.0, _player_fast - delta * 2.0)
	var d := _flat(p.global_position - c.global_position).length()
	if d > 25.0:
		_apart += delta
	elif d < 8.0 and _apart > 5.0 and _greet_cd <= 0.0 and c.mode == Companion.Mode.FOLLOW:
		_greet(p)
		_apart = 0.0
	elif d < 8.0:
		_apart = 0.0


# --- follow ---------------------------------------------------------------------------------------------

func _follow(delta: float, p: PlayerCharacter) -> void:
	var pp := p.global_position
	var to_p := _flat(pp - c.global_position)
	var d := to_p.length()
	var ps := _flat(p.velocity).length()
	var prof := c.prof
	if prof.can_fly:
		var air_reason := d > 42.0 or (_player_fast > 1.5 and d > 14.0) or (_player_moving > 1.0 and prof.prefers_air) or d > 22.0 and prof.prefers_air
		if air_reason and _can_take_off():
			c.set_mode(Companion.Mode.ESCORT)
			_escort(delta, p)
			return
	if c.burrow != null and d > 48.0 and d < Companion.LOST_GROUND * 0.85 and not c.motor.swimming:
		if c.burrow.start_to(_beside_player(p), false):
			return
	if _try_assist():
		return
	if _play_t > 0.0:
		_play(delta, p)
		return
	var slot := _slot(p)
	var to_slot := _flat(slot - c.global_position)
	var ds := to_slot.length()
	var space := prof.f(prof.follow, "space", 2.0)
	var want := 0.0
	var dir := to_slot.normalized() if ds > 0.01 else Vector3.ZERO
	if ds > 1.0:
		want = clampf(ps * 1.02 + (ds - 0.8) * 0.85, 0.0, prof.follow_speed("max"))
		if ps < 0.4 and ds < 4.0:
			want = minf(want, prof.follow_speed("walk") * 1.3)
	if d < space:
		# Never crowd (or block) the player: step out of the way.
		dir = -to_p.normalized() if d > 0.05 else CompanionNav.dir_of(c.motor.yaw)
		want = maxf(want, prof.follow_speed("walk") * 1.4)
	var resting := want < 0.05 and ps < 0.4
	if resting:
		_rest_t += delta
		var face := (to_p.normalized() + _flat(-p.global_basis.z) * 0.6)
		c.motor.move(delta, Vector3.ZERO, 0.0, {"face": face})
		_idle(delta, p)
	else:
		_rest_t = 0.0
		if c.rig.is_action_playing(&"lie_down") or c.rig.is_action_playing(&"sit"):
			c.rig.stop_action()
		c.motor.move(delta, dir, want, {"avoid": true, "accel": 9.0, "decel": 12.0})
	if c.motor.is_stuck(4.0) and d > 14.0:
		c.teleport_near_player()


## Formation slot (cached 4 Hz): beside and behind the player's travel direction.
func _slot(p: PlayerCharacter) -> Vector3:
	if _slot_t > 0.0 and _slot_cache != Vector3.INF:
		return _slot_cache
	_slot_t = 0.25
	var prof := c.prof
	var pp := p.global_position
	var pv := _flat(p.velocity)
	var ps := pv.length()
	var fwd := pv.normalized() if ps > 1.0 else _flat(-p.global_basis.z).normalized()
	if fwd == Vector3.ZERO:
		fwd = Vector3.FORWARD
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var k := clampf(ps / 8.0, 0.0, 1.0)
	# Level with the player at rest (in view, not in the camera's face), trailing a little
	# when moving.
	var off_side := prof.f(prof.follow, "side") * lerpf(1.0, 0.85, k)
	var off_back := prof.f(prof.follow, "back") * lerpf(-0.25, 0.7, k)
	# Keep the side the companion is already on (hysteresis): it never crosses in front.
	var lat := (c.global_position - pp).dot(right)
	if side < 0.0 and lat > off_side * 0.55:
		side = 1.0
	elif side > 0.0 and lat < -off_side * 0.55:
		side = -1.0
	var best := Vector3.INF
	for s: float in [side, -side]:
		var cand := pp + right * off_side * s - fwd * off_back
		if _slot_ok(p, cand):
			best = cand
			if s != side:
				side = s
			break
	if best == Vector3.INF:
		# No room beside the player (a corridor, a ledge): drop back behind the camera, where
		# it can neither block the view nor the way.
		var cam := c.get_viewport().get_camera_3d() if c.is_inside_tree() else null
		var cam_d := _flat(cam.global_position - pp).length() if cam else 5.0
		best = pp - fwd * (cam_d + prof.radius() + 1.5)
		if not _slot_ok(p, best):
			best = pp - fwd * (off_back + off_side * 0.6)
	best.y = WorldData.get_height(best.x, best.z)
	best = _clear_of_camera(p, best, right * side, fwd)
	_slot_cache = best
	return best


func _slot_ok(p: PlayerCharacter, s: Vector3) -> bool:
	if not CompanionNav.walkable(s.x, s.z, c.motor.max_slope, 1.4 if c.prof.can_swim else 0.4):
		return false
	var space := c.get_world_3d().direct_space_state
	var gy := WorldData.get_height(s.x, s.z)
	return CompanionNav.clear_line(space, p.global_position + Vector3.UP * 1.2, Vector3(s.x, gy + 1.0, s.z), [c.get_rid(), p.get_rid()])


## Pushes the slot sideways until the companion's body is clear of the camera -> player
## line, and forward when it would stand right in front of the lens (a creature filling
## the screen).
func _clear_of_camera(p: PlayerCharacter, s: Vector3, outward: Vector3, fwd: Vector3) -> Vector3:
	var cam := c.get_viewport().get_camera_3d() if c.is_inside_tree() else null
	if cam == null or outward.length_squared() < 1e-4:
		return s
	var a := cam.global_position
	var b := p.global_position + Vector3.UP * 1.2
	var need := c.prof.radius() + 1.0
	var center := s + Vector3.UP * c.prof.body_height() * 0.5
	var dist := CompanionNav.segment_distance(center, a, b)
	if dist < need:
		s += outward.normalized() * (need - dist + 0.3)
	var keep := c.prof.radius() + 3.0
	var flat := _flat(s - a).length()
	if flat < keep:
		s += fwd * (keep - flat)
	return s


func _beside_player(p: PlayerCharacter) -> Vector3:
	var fwd := _flat(-p.global_basis.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return p.global_position + right * c.prof.f(c.prof.follow, "side") * side - fwd * 1.5


func _can_take_off() -> bool:
	return c.flight != null and not c.motor.swimming and c.mode != Companion.Mode.RETREAT


# --- idles and reactions ----------------------------------------------------------------------------------

func _idle(delta: float, p: PlayerCharacter) -> void:
	if _rest_t < 1.0:
		return
	if _look_t <= 0.0 and randf() < delta * 0.12:
		_look_target = p
		_look_t = randf_range(1.8, 3.2)
	_idle_t -= delta
	if _idle_t > 0.0 or c.rig.current_action() != &"":
		return
	_idle_t = randf_range(7.0, 13.0)
	var hour := GameState.time_of_day
	var night := hour >= 21.0 or hour < 5.0
	if _weather in [&"snow", &"blizzard", &"rain"] and randf() < 0.5:
		c.rig.play_action(&"shake")
	elif (night or _weather == &"blizzard") and randf() < 0.6:
		c.rig.play_action(&"lie_down" if c.species != &"polar_bear_dog" or randf() < 0.5 else &"sit")
	elif c.species == &"polar_bear_dog" and _player_still > 9.0 and randf() < 0.45:
		_play_t = 4.0
		_play_angle = atan2(c.global_position.z - p.global_position.z, c.global_position.x - p.global_position.x)
	elif not c.prof.play_actions.is_empty():
		var a: StringName = c.prof.play_actions[randi() % c.prof.play_actions.size()]
		if c.rig.play_action(a) > 0.0 and a in [&"howl", &"call", &"groan", &"snort"]:
			_look_t = 0.0


## The polar bear dog's zoomies: a quick lap around the idle player, then a happy bark.
func _play(delta: float, p: PlayerCharacter) -> void:
	_play_t -= delta
	var r := 5.5
	_play_angle += delta * 1.8
	var tgt := p.global_position + Vector3(cos(_play_angle), 0.0, sin(_play_angle)) * r
	c.motor.move(delta, _flat(tgt - c.global_position), c.prof.follow_speed("sprint") * 0.75, {"avoid": true, "accel": 14.0})
	if _player_moving > 0.3 or _play_t <= 0.0:
		_play_t = 0.0
		if _player_moving <= 0.3:
			c.rig.play_action(&"rear_up")
			_vocal(&"greet", 0.0)


func _greet(p: PlayerCharacter) -> void:
	_greet_cd = 25.0
	_look_target = p
	_look_t = 2.5
	_vocal(&"greet", 0.0)
	if c.species == &"polar_bear_dog" and randf() < 0.6:
		c.rig.play_action(&"rear_up")


func _vocal(kind: StringName, cooldown: float) -> void:
	if _vocal_cd > 0.0 and cooldown > 0.0:
		return
	var a: StringName = c.prof.vocals.get(kind, &"")
	if a == &"" or c.is_airborne() and a != &"roar" and a != &"call":
		return
	c.rig.play_action(a)
	_vocal_cd = maxf(cooldown, 2.0)


func _update_look(p: PlayerCharacter) -> void:
	if _look_t > 0.0:
		var pos := Vector3.INF
		if _look_target != null and is_instance_valid(_look_target):
			pos = BendingContext.target_point(_look_target) if _look_target.has_method("get_aim_point") else _look_target.global_position + Vector3.UP * 1.5
		elif _look_pos.is_finite():
			pos = _look_pos
		if pos.is_finite():
			c.rig.look_at_point(pos, 0.8)
			return
	if c.mode == Companion.Mode.FOLLOW and _rest_t > 0.5 and p.global_position.distance_to(c.global_position) < 20.0:
		c.rig.look_at_point(p.global_position + Vector3.UP * 1.5, 0.35)
	else:
		c.rig.clear_look()


func _on_enemy_alerted(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or c.is_ridden() or _react_cd > 0.0:
		return
	if enemy.global_position.distance_to(c.global_position) > 40.0:
		return
	_react_cd = 10.0
	_look_target = enemy
	_look_t = 2.5
	_vocal(&"angry", 0.0)


func _on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if hit == null or result == Combat.Result.IGNORED or c.is_ridden() or _look_t > 0.6:
		return
	if c.player != null and hit.source == c.player and target is Node3D and (target as Node3D).global_position.distance_to(c.global_position) < 30.0:
		_look_target = target as Node3D
		_look_t = 1.2


func _on_weather_changed(w: StringName) -> void:
	_weather = w
	if w in [&"snow", &"rain", &"blizzard"] and c.mode == Companion.Mode.FOLLOW and _rest_t > 1.0:
		_idle_t = minf(_idle_t, 1.5)


## Other systems may command the companion: &"call", &"stay", &"follow".
func _on_command(command: StringName) -> void:
	if _emitting:
		return
	match command:
		&"call":
			c.call_companion()
		&"stay":
			_stay = true
		&"follow":
			_stay = false
			if c.mode == Companion.Mode.WAIT:
				c.set_mode(Companion.Mode.FOLLOW)


# --- assist -------------------------------------------------------------------------------------------------

func _try_assist() -> bool:
	if _assist_t > 0.0:
		return false
	_assist_t = 0.25
	if not c.assist_enabled or not c.assist.ready() or c.health.ratio() < 0.35:
		return false
	var t := c.assist.find_target()
	if t == null:
		return false
	if c.rig.is_action_playing(&"lie_down") or c.rig.is_action_playing(&"sit"):
		c.rig.stop_action()
	c.assist.begin(t)
	c.set_mode(Companion.Mode.ASSIST)
	return true


# --- escort flight ----------------------------------------------------------------------------------------------

func _escort(delta: float, p: PlayerCharacter) -> void:
	var f := c.flight
	if f == null:
		c.set_mode(Companion.Mode.FOLLOW)
		return
	if not f.is_active():
		if not f.takeoff(c.motor.yaw):
			c.set_mode(Companion.Mode.FOLLOW)
			return
		c.rig.stop_action()
	var pp := p.global_position
	var pv := _flat(p.velocity)
	var ps := pv.length()
	var d := _flat(pp - c.global_position).length()
	f.reset_intent()
	match f.phase:
		CompanionFlight.Phase.TAKEOFF:
			f.want_dir = _flat(pp - c.global_position).normalized() if d > 12.0 else CompanionNav.dir_of(f.heading)
			f.step(delta)
			return
		CompanionFlight.Phase.LANDING:
			f.step(delta)
			if not f.is_active():
				_touchdown(p)
			return
	# Settle near the player when they stop (bison soon, dragon after a while).
	var delay := DRAGON_LAND_DELAY if c.prof.prefers_air else ESCORT_LAND_DELAY
	var want_land := land_requested or (_player_still > delay and p.motor.on_floor)
	if want_land and d < 160.0 and c.mode != Companion.Mode.RETREAT:
		if _land_spot == Vector3.INF and _land_search_t <= 0.0:
			_land_search_t = 1.0
			_land_spot = _find_landing(p)
		if _land_spot != Vector3.INF:
			if ps > 3.5 and not land_requested:
				_land_spot = Vector3.INF
			else:
				_approach_landing(delta, p)
				return
	else:
		_land_spot = Vector3.INF
	var esc_h := f.f("escort_height", 15.0)
	var tgt: Vector3
	var falling := not p.motor.on_floor and not p.motor.swimming and pp.y - CompanionNav.surface_y(pp.x, pp.z) > 5.0
	if falling and p.get_state() == PlayerCharacter.State.AIRBORNE:
		# The rider let go (or jumped off a cliff): dive in under them, saddle up, so a
		# mount press catches them in the air.
		var saddle_h := float(c.rig.get_dimensions().get("saddle_height", c.prof.body_height()))
		tgt = pp + pv * 0.4
		f.want_dir = _flat(tgt - c.global_position).normalized()
		if f.want_dir == Vector3.ZERO:
			f.want_dir = CompanionNav.dir_of(f.heading)
		f.hold_altitude = pp.y - saddle_h - 0.8
		f.hold_speed = clampf(ps + d * 0.6, f.f("min"), f.f("boost"))
		f.step(delta)
		return
	if ps > 1.5:
		var fwd := pv.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		tgt = pp + pv * 1.2 + right * c.prof.f(c.prof.follow, "side") * 1.3 * side - fwd * c.prof.f(c.prof.follow, "back")
		f.hold_speed = clampf(ps * 1.05 + maxf(d - 10.0, 0.0) * 0.35, f.f("min"), f.f("boost"))
	else:
		# A wide lazy circle above the resting player.
		var r := 26.0 if not c.prof.prefers_air else 36.0
		var ang := atan2(c.global_position.z - pp.z, c.global_position.x - pp.x) + 0.55 * _orbit_dir
		tgt = pp + Vector3(cos(ang), 0.0, sin(ang)) * r
		f.hold_speed = maxf(f.f("glide") * 0.85, f.f("min"))
		if d > r * 1.6:
			f.hold_speed = f.f("cruise")
	var ground := maxf(CompanionNav.surface_y(tgt.x, tgt.z), pp.y)
	f.hold_altitude = ground + esc_h
	f.want_dir = _flat(tgt - c.global_position).normalized()
	if f.want_dir == Vector3.ZERO:
		f.want_dir = CompanionNav.dir_of(f.heading)
	f.step(delta)


func _find_landing(p: PlayerCharacter) -> Vector3:
	var space := c.get_world_3d().direct_space_state
	var near := _beside_player(p)
	var r := c.prof.radius() * (1.2 if c.prof.prefers_air else 1.0) + 0.6
	var ex: Array[RID] = [c.get_rid(), p.get_rid()]
	# Close and flat first; on mountain flanks accept a bit more slope further out.
	var spot := Vector3.INF
	for tier: Array in [[12.0, 26.0], [28.0, 31.0], [45.0, 34.0]]:
		spot = CompanionNav.find_landing_spot(space, near, r, tier[1], tier[0], ex)
		if spot != Vector3.INF:
			break
	if spot != Vector3.INF and spot.distance_to(p.global_position) < c.prof.f(c.prof.follow, "space") + r:
		return Vector3.INF
	return spot


func _approach_landing(delta: float, _p: PlayerCharacter) -> void:
	var f := c.flight
	var to := _flat(_land_spot - c.global_position)
	var dist := to.length()
	f.want_dir = to.normalized() if dist > 0.5 else CompanionNav.dir_of(f.heading)
	f.hold_speed = clampf(dist * 0.45, maxf(f.f("min"), 2.5), f.f("cruise"))
	f.hold_altitude = _land_spot.y + clampf(dist * 0.32, 2.0, f.f("escort_height"))
	f.step(delta)
	var trigger := maxf(4.0, f.speed * 1.1)
	if dist < trigger and f.altitude() < 16.0:
		if not f.land():
			_land_spot = Vector3.INF
			_land_search_t = 1.5


func _touchdown(p: PlayerCharacter) -> void:
	land_requested = false
	_land_spot = Vector3.INF
	c.motor.yaw = c.flight.heading
	c.motor.speed = 0.0
	c.motor.on_floor = true
	c.set_mode(Companion.Mode.FOLLOW)
	if _greet_on_arrival:
		_greet_on_arrival = false
		_greet(p)


# --- called / retreat / wait / hold --------------------------------------------------------------------------

func _called(delta: float, p: PlayerCharacter) -> void:
	var to_p := _flat(p.global_position - c.global_position)
	var d := to_p.length()
	var space := c.prof.f(c.prof.follow, "space", 2.0)
	if d < space + 2.0:
		c.set_mode(Companion.Mode.FOLLOW)
		if _greet_on_arrival:
			_greet_on_arrival = false
			_greet(p)
		return
	var tgt := _beside_player(p)
	c.motor.move(delta, _flat(tgt - c.global_position), c.prof.follow_speed("max"), {"avoid": true, "accel": 12.0})
	if c.motor.is_stuck(1.5) and (d < 22.0 or p.motor.swimming):
		# As close as it gets (the player is swimming, on a ledge ...): that is arriving.
		c.set_mode(Companion.Mode.FOLLOW)
		if _greet_on_arrival:
			_greet_on_arrival = false
			_greet(p)
	elif c.motor.is_stuck(2.5):
		c.teleport_near_player()


func _retreat(delta: float, p: PlayerCharacter) -> void:
	if c.health.ratio() >= 0.7:
		_resting = false
		_retreat_to = Vector3.INF
		if c.rig.is_action_playing(&"lie_down"):
			c.rig.stop_action()
		c.set_mode(Companion.Mode.ESCORT if c.is_airborne() else Companion.Mode.FOLLOW)
		return
	if c.is_airborne():
		# Flyers recover high above the player, out of reach.
		var f := c.flight
		f.reset_intent()
		var pp := p.global_position
		var ang := atan2(c.global_position.z - pp.z, c.global_position.x - pp.x) + 0.5 * _orbit_dir
		var tgt := pp + Vector3(cos(ang), 0.0, sin(ang)) * 40.0
		f.want_dir = _flat(tgt - c.global_position).normalized()
		f.hold_altitude = CompanionNav.surface_y(tgt.x, tgt.z) + f.f("escort_height") * 1.8
		f.hold_speed = f.f("glide")
		f.step(delta)
		return
	if _retreat_to == Vector3.INF:
		_retreat_to = _pick_retreat(p)
	var to := _flat(_retreat_to - c.global_position)
	if to.length() > 2.5 and not _resting:
		c.motor.move(delta, to, c.prof.follow_speed("run"), {"avoid": true})
		if c.motor.is_stuck(3.0):
			_retreat_to = c.global_position
	else:
		c.motor.move(delta, Vector3.ZERO, 0.0)
		if not _resting:
			_resting = true
			c.rig.play_action(&"lie_down")


func _pick_retreat(p: PlayerCharacter) -> Vector3:
	var threat := c.assist.nearest_enemy(c.global_position, 30.0)
	var from := threat.global_position if threat != null else p.global_position
	var away := _flat(c.global_position - from).normalized()
	if away == Vector3.ZERO:
		away = CompanionNav.dir_of(c.motor.yaw)
	var want := p.global_position + away * 22.0
	var space := c.get_world_3d().direct_space_state
	var spot := CompanionNav.find_spot_near(space, want, c.prof.radius(), c.motor.max_slope, 2.0, 10.0, Vector3.ZERO, [c.get_rid()])
	return spot if spot != Vector3.INF else WorldData.get_safe_ground(want)


func _wait(delta: float, p: PlayerCharacter) -> void:
	if not _stay:
		c.set_mode(Companion.Mode.FOLLOW)
		return
	_hold(delta)
	if c.global_position.distance_to(p.global_position) < 15.0:
		_rest_t += delta
		_idle(delta, p)


## Stay where it is: brake on the ground, circle in the air.
func _hold(delta: float) -> void:
	if c.is_airborne() or (c.flight != null and c.flight.is_active()):
		var f := c.flight
		f.reset_intent()
		if f.phase == CompanionFlight.Phase.FLY:
			f.want_dir = CompanionNav.dir_of(f.heading + 0.6 * _orbit_dir)
			f.hold_speed = maxf(f.f("glide") * 0.8, f.f("min"))
			f.hold_altitude = CompanionNav.surface_y(c.global_position.x, c.global_position.z) + f.f("escort_height")
		f.step(delta)
		if not f.is_active() and c.player != null:
			_touchdown(c.player)
		return
	c.motor.brake(delta)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
