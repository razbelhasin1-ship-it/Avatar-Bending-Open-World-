class_name CompanionAssist
extends RefCounted
## Optional combat assist: the companion joins fights the player is in (enemies that are
## engaged and within ENGAGE_RADIUS of the player), one move per cooldown:
##
## | Species | Move | Hit |
## | --- | --- | --- |
## | dragon | fire breath: faces the enemy, `breathe_fire_start` (flames on `fire_start`), a damage cone ticks while it breathes, `breathe_fire_end` | 7 ticks x 5 dmg + burn, 13 m cone |
## | sky bison | tail gust: turns its back to the enemy, `tail_gust` (tail raised, slammed down: event `gust`), a wind blast from the tail | knockback 15 m/s + lift, 10 m cone |
## | polar bear dog | pounce: crouch, leap at the enemy, bite on landing | knockdown, 2.4 m radius at the landing point |
## | badgermole | tremor: `rear_up`, slams down (event `land`), ground shockwave | stagger (knockdown inside 3 m), 6.5 m radius |
##
## Hits are real HitInfo through BendingHits.deliver (once per attack id, line of sight,
## impact VFX only for applied hits). The hit's source is the player: the companion fights
## as the player's partner, so XP / loot and enemy aggro stay with the player. Every phase
## has a timeout; cooldowns run in every mode.

enum Phase { NONE, APPROACH, ACT, RECOVER }

const ENGAGE_RADIUS := 18.0
const REACH := 30.0
const APPROACH_TIMEOUT := 5.0
const ACT_TIMEOUT := 4.0

var c: Companion
var kind: StringName = &""
var phase: int = Phase.NONE
var target: Node3D = null
var t := 0.0
var cooldown_left := 2.0
## Moves performed / hits applied (tests, tuning).
var uses := 0
var landed := 0
var ctx: BendingContext

var _flames: CPUParticles3D = null
var _fire_on := false
var _ticks_left := 0
var _tick_t := 0.0
var _struck := false
var _leap_t := -1.0
var _leap_dir := Vector3.ZERO
var _leap_speed := 0.0
var _attack_id := 0
var _recover := 0.8


func _init(p_c: Companion) -> void:
	c = p_c
	kind = StringName(c.prof.assist.get("kind", &""))
	ctx = BendingContext.new(c, null, c.prof.element, Combat.Team.PLAYER)
	c.rig.action_event.connect(_on_rig_event)


func ready() -> bool:
	return kind != &"" and cooldown_left <= 0.0 and phase == Phase.NONE


func cool(delta: float) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)


func is_active() -> bool:
	return phase != Phase.NONE


## Best enemy to help with: alive, engaged in a fight, near the player and within reach.
func find_target() -> Node3D:
	var p := c.player
	if p == null or not is_instance_valid(p) or not c.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := INF
	for n in c.get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or not _valid_enemy(e):
			continue
		if e.has_method("in_combat") and not bool(e.call("in_combat")):
			continue
		if e.global_position.distance_to(p.global_position) > ENGAGE_RADIUS:
			continue
		var d := e.global_position.distance_to(c.global_position)
		if d < REACH and d < best_d:
			best_d = d
			best = e
	return best


## Nearest living enemy to `pos` within `radius` (retreat direction).
func nearest_enemy(pos: Vector3, radius: float) -> Node3D:
	if not c.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := radius
	for n in c.get_tree().get_nodes_in_group(&"enemy"):
		var e := n as Node3D
		if e == null or not _valid_enemy(e):
			continue
		var d := e.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = e
	return best


func begin(p_target: Node3D) -> void:
	target = p_target
	phase = Phase.APPROACH
	t = 0.0
	_struck = false
	_leap_t = -1.0
	_attack_id = HitInfo.new_attack_id()


func tick(delta: float) -> void:
	t += delta
	match phase:
		Phase.APPROACH:
			_approach(delta)
		Phase.ACT:
			_act(delta)
		Phase.RECOVER:
			c.motor.brake(delta, 10.0)
			if t > _recover:
				_finish(float(c.prof.assist.get("cooldown", 8.0)))
		_:
			c.set_mode(Companion.Mode.FOLLOW)


func cancel() -> void:
	if phase == Phase.ACT and kind == &"fire_breath":
		_stop_fire()
		c.rig.play_action(&"breathe_fire_end")
	c.motor.speed_scale = 1.0
	if phase != Phase.NONE and phase != Phase.RECOVER:
		cooldown_left = maxf(cooldown_left, 3.0)
	phase = Phase.NONE
	target = null


func cleanup() -> void:
	_stop_fire()
	if _flames != null and is_instance_valid(_flames):
		_flames.queue_free()
	_flames = null
	phase = Phase.NONE


# --- phases ----------------------------------------------------------------------------------------

func _approach(delta: float) -> void:
	if not _valid_enemy(target) or t > APPROACH_TIMEOUT:
		_finish(3.0)
		return
	var a := c.prof.assist
	var rng := float(a.get("range", 8.0))
	var lo := float(a.get("min_range", 2.0))
	var hi := rng * 0.75
	var face_away := kind == &"tail_gust"
	match kind:
		&"tremor":
			lo = 0.0
			hi = rng * 0.5
		&"pounce":
			hi = rng * 0.9
	var to := _flat(target.global_position - c.global_position)
	var d := to.length()
	var face := -to if face_away else to
	if not face_away:
		c.rig.look_at_point(BendingContext.target_point(target), 0.8)
	if d > hi:
		c.motor.move(delta, to / maxf(d, 0.01), c.prof.follow_speed("sprint"), {"avoid": true, "accel": 12.0})
		return
	if d < lo and kind != &"tremor":
		c.motor.move(delta, -to, c.prof.follow_speed("run"), {"avoid": true})
		return
	c.motor.move(delta, Vector3.ZERO, 0.0, {"face": face, "turn": c.prof.f(c.prof.follow, "turn", 160.0) * 1.4})
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	if fwd.dot(face.normalized()) > cos(deg_to_rad(18.0)):
		_start_act()


func _start_act() -> void:
	phase = Phase.ACT
	t = 0.0
	uses += 1
	c.rig.stop_action()
	match kind:
		&"fire_breath":
			_ticks_left = int(c.prof.assist.get("ticks", 6))
			_tick_t = 0.0
			c.rig.play_action(&"breathe_fire_start")
			_recover = 0.9
		&"tail_gust":
			if c.rig.play_action(&"tail_gust") <= 0.0:
				c.rig.play_action(&"rear_up")
			_recover = 0.9
		&"pounce":
			_leap_t = -1.0
			_recover = 0.75
			c.rig.play_action(&"growl", {"duration": 0.6})
		&"tremor":
			c.rig.play_action(&"rear_up")
			_recover = 0.8


func _act(delta: float) -> void:
	if t > ACT_TIMEOUT:
		if kind == &"fire_breath":
			_stop_fire()
			c.rig.play_action(&"breathe_fire_end")
		_to_recover()
		return
	match kind:
		&"fire_breath":
			_act_fire(delta)
		&"tail_gust":
			c.motor.brake(delta, 10.0)
			if not _struck and t > 1.2:
				_gust()   # backstop when the rig never sends "gust"
		&"pounce":
			_act_pounce(delta)
		&"tremor":
			c.motor.brake(delta, 10.0)
			if not _struck and t > 2.0:
				_tremor()


func _act_fire(delta: float) -> void:
	# Head (and the flames on the mouth socket) on the target while breathing; the body
	# turns after it.
	var face := Vector3.ZERO
	if _valid_enemy(target):
		face = _flat(target.global_position - c.global_position)
		c.rig.look_at_point(BendingContext.target_point(target), 1.0)
	c.motor.move(delta, Vector3.ZERO, 0.0, {"face": face, "turn": 90.0})
	if not _fire_on:
		if t > 1.2:
			_start_fire()   # backstop for the fire_start event
		return
	_tick_t -= delta
	if _tick_t <= 0.0 and _ticks_left > 0:
		_tick_t = float(c.prof.assist.get("tick_time", 0.22))
		_ticks_left -= 1
		_fire_tick()
		if _ticks_left <= 0:
			_stop_fire()
			c.rig.play_action(&"breathe_fire_end")
			_to_recover()


func _act_pounce(delta: float) -> void:
	if _leap_t < 0.0:
		c.motor.brake(delta, 14.0)
		if t >= 0.3:
			var d := 4.0
			if _valid_enemy(target):
				var to := _flat(target.global_position - c.global_position)
				d = to.length()
				if d > 0.1:
					_leap_dir = to / d
			else:
				_leap_dir = CompanionNav.dir_of(c.motor.yaw)
			var air := 0.62
			_leap_speed = clampf((d - 1.2) / air, 3.0, 16.0)
			c.motor.jump(5.6)
			c.motor.speed = _leap_speed
			_leap_t = 0.0
			Audio.play_sfx(&"dog_bark", c.global_position, -2.0)
		return
	_leap_t += delta
	c.motor.move(delta, _leap_dir, _leap_speed, {"avoid": false, "accel": 60.0, "decel": 6.0, "turn": 400.0})
	if (_leap_t > 0.25 and c.motor.on_floor) or _leap_t > 1.2:
		if not _struck:
			_struck = true
			c.rig.play_action(&"bite")
			var center := c.global_position + CompanionNav.dir_of(c.motor.yaw) * 1.4 + Vector3.UP * 0.8
			_area_hit(center, 2.4, CompanionNav.dir_of(c.motor.yaw), 180.0)
			FxBurst.spawn(c, &"dust", c.global_position, {"color": FxLib.surface_color(WorldData.get_surface(c.global_position)), "count": 0.7})
		if _leap_t > 0.55:
			_to_recover()


# --- strikes ----------------------------------------------------------------------------------------

func _start_fire() -> void:
	if _fire_on:
		return
	_fire_on = true
	var mouth := c.rig.get_socket(&"mouth")
	if mouth != null and (_flames == null or not is_instance_valid(_flames)):
		_flames = CreatureFx.fire_breath(mouth, float(c.prof.assist.get("range", 12.0)))
	if _flames != null and is_instance_valid(_flames):
		_flames.emitting = true


func _stop_fire() -> void:
	_fire_on = false
	if _flames != null and is_instance_valid(_flames):
		_flames.emitting = false


func _fire_tick() -> void:
	var mouth := c.rig.get_socket(&"mouth")
	var origin := mouth.global_position if mouth else c.global_position + Vector3.UP * 2.0
	var dir := _flat(-mouth.global_basis.z) if mouth else CompanionNav.dir_of(c.motor.yaw)
	if dir == Vector3.ZERO:
		dir = CompanionNav.dir_of(c.motor.yaw)
	var rng := float(c.prof.assist.get("range", 12.0))
	var cone := float(c.prof.assist.get("cone", 24.0))
	# One attack id per tick: each tick may burn each target once; anything right at the
	# jaws is caught in the splash.
	_attack_id = HitInfo.new_attack_id()
	_area_hit(origin, rng, dir, cone, 0.0, 2.6)


func _gust() -> void:
	if _struck:
		return
	_struck = true
	var tail := c.rig.get_socket(&"tail")
	var origin := tail.global_position if tail else c.global_position + Vector3.UP
	var dir := -CompanionNav.dir_of(c.motor.yaw)
	if _valid_enemy(target):
		var to := _flat(target.global_position - origin)
		if to.length() > 0.5 and to.normalized().dot(dir) > 0.5:
			dir = to.normalized()
	var rng := float(c.prof.assist.get("range", 10.0))
	var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), origin + Vector3.UP * 0.3)
	AirFx.gust(c, xf, rng, 2.6, 0.45)
	AirFx.ground_puff(c, Vector3(origin.x, WorldData.get_height(origin.x, origin.z), origin.z), WorldData.get_surface(origin), 1.4, dir)
	Audio.play_sfx(&"air_blast", origin, 0.0)
	_area_hit(origin, rng, dir, 40.0)
	_to_recover()


func _tremor() -> void:
	if _struck:
		return
	_struck = true
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var center := c.global_position + fwd * 1.6
	center.y = WorldData.get_height(center.x, center.z)
	var rng := float(c.prof.assist.get("range", 6.5))
	EarthFx.quake(c, center, rng, WorldData.get_surface(center))
	Audio.play_sfx(&"earth_quake", center, 0.0)
	var p := c.player
	if p != null and is_instance_valid(p) and p.global_position.distance_to(center) < 16.0:
		Events.camera_shake.emit(0.3, 0.35)
	_area_hit(center + Vector3.UP * 0.6, rng, fwd, 180.0, 3.0)
	_to_recover()


## Damages enemies in a sphere / cone. `close` (m): targets inside get a knockdown.
func _area_hit(center: Vector3, radius: float, dir: Vector3, half_angle: float, close: float = 0.0, near: float = 0.8) -> void:
	var h: Dictionary = (c.prof.assist.get("hit", {}) as Dictionary).duplicate(true)
	var cos_lim := cos(deg_to_rad(half_angle))
	for n in BendingHits.targets_in_sphere(ctx, center, radius):
		var e := n as Node3D
		if e == null or not e.is_in_group(&"enemy") or not _valid_enemy(e):
			continue
		var tp := BendingContext.target_point(e)
		var to := _flat(tp - center)
		if half_angle < 179.0 and to.length() > near and to.normalized().dot(dir) < cos_lim:
			continue
		if not BendingHits.line_of_sight(ctx, center + Vector3.UP * 0.3, tp, e):
			continue
		var hd := h
		if close > 0.0 and to.length() < close:
			hd = h.duplicate()
			hd["reaction"] = HitInfo.Reaction.KNOCKDOWN
		_deliver(e, hd, to.normalized() if to.length() > 0.1 else dir)


func _deliver(e: Node3D, h: Dictionary, dir: Vector3) -> int:
	var hit := ctx.make_hit(h, dir, _attack_id, StringName("companion_%s" % kind))
	# Fights as the player's partner: credit and aggro go to the player.
	if c.player != null and is_instance_valid(c.player):
		hit.source = c.player
	hit.team = Combat.Team.PLAYER
	hit.origin = c.global_position
	var r := BendingHits.deliver(ctx, e, hit)
	if r == Combat.Result.HIT or r == Combat.Result.KILLED:
		landed += 1
	return r


func _to_recover() -> void:
	phase = Phase.RECOVER
	t = 0.0


func _finish(cooldown: float) -> void:
	cooldown_left = cooldown
	phase = Phase.NONE
	target = null
	c.rig.clear_look()
	c.motor.speed_scale = 1.0
	if c.mode == Companion.Mode.ASSIST:
		c.set_mode(Companion.Mode.FOLLOW)


## Untyped: the assist target can be freed while held (a fled enemy vanishing, a despawn) and a
## freed instance passed to a typed argument is a script error every tick (bughunt_gameplay).
func _valid_enemy(v: Variant) -> bool:
	if v == null or not is_instance_valid(v) or not (v is Node3D):
		return false
	var e := v as Node3D
	if not e.is_inside_tree() or not Combat.is_alive(e):
		return false
	if e.get("dormant") == true or e.get("surrendered") == true:
		return false
	return true


func _on_rig_event(action_name: StringName, event: StringName) -> void:
	if phase != Phase.ACT:
		return
	match event:
		&"fire_start":
			if kind == &"fire_breath":
				_start_fire()
		&"gust":
			if kind == &"tail_gust":
				_gust()
		&"land":
			if kind == &"tremor" and action_name == &"rear_up":
				_tremor()
			elif kind == &"tail_gust" and action_name == &"rear_up":
				_gust()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
