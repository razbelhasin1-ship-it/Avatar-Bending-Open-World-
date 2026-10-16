class_name CompanionBurrow
extends RefCounted
## Badgermole tunnelling: dig in where it stands, travel a short distance underground and
## burst out at the target point.
##
## * DIG: the rig's `dig_in` (scoops, sinks, "burrowed" at 2.8 s); collision off.
## * TRAVEL: the body origin slides along the terrain surface toward the exit (the rig hides
##   the mesh and leaves dirt puffs); here: crack decals + dust along the path, a rumble
##   (dig sound, light camera shake for the rider / a nearby player).
## * EMERGE: the rig's `emerge` (rock burst, shake-off), collision back on.
## The exit is validated before digging (walkable, dry, open ground on the line, within
## MAX_DISTANCE): no burrow starts that cannot end. A ridden badgermole hides its rider
## while the saddle is underground (the rider's seat stays at the surface).

enum Phase { NONE, DIG, TRAVEL, EMERGE }

const MAX_DISTANCE := 42.0
const MIN_DISTANCE := 8.0
const SPEED := 11.0
const DIG_TIMEOUT := 3.6
const EMERGE_TIME := 1.9

var c: Companion
var phase: int = Phase.NONE
var ridden := false
var target := Vector3.INF
var start := Vector3.ZERO
var t := 0.0
## Completed tunnels (tests / stats).
var tunnels := 0

var _burrowed := false
var _rumble_t := 0.0
var _mark_dist := 0.0
var _last := Vector3.ZERO
var _layer := 0
var _mask := 0
var _mound: MeshInstance3D = null
var _mound_w := 0.0


func _init(p_c: Companion) -> void:
	c = p_c
	c.rig.action_event.connect(_on_rig_event)


func is_active() -> bool:
	return phase != Phase.NONE


func phase_name() -> String:
	return ["none", "dig", "travel", "emerge"][phase]


## Starts a tunnel toward `want` (clamped to MAX_DISTANCE; the exit is the furthest valid
## point on the line). False when it cannot dig here or there is no valid exit.
func start_to(want: Vector3, p_ridden: bool) -> bool:
	if phase != Phase.NONE or c.motor.swimming or not c.motor.on_floor or not c.is_inside_tree():
		return false
	var from := c.global_position
	var flat := Vector3(want.x - from.x, 0.0, want.z - from.z)
	var d := flat.length()
	if d < MIN_DISTANCE:
		return false
	if d > MAX_DISTANCE:
		want = from + flat / d * MAX_DISTANCE
	# Diggable ground here: natural terrain (not a bridge, deck or roof), not under water.
	if absf(from.y - WorldData.get_height(from.x, from.z)) > 1.0 or CompanionNav.water_depth(from.x, from.z) > 0.2:
		return false
	var space := c.get_world_3d().direct_space_state
	var ex: Array[RID] = [c.get_rid()]
	if c.player != null and is_instance_valid(c.player):
		ex.append(c.player.get_rid())
	var exit := CompanionNav.burrow_exit(space, from, want, c.prof.radius(), 52.0, ex)
	if exit == Vector3.INF:
		return false
	target = exit
	start = from
	ridden = p_ridden
	phase = Phase.DIG
	t = 0.0
	_burrowed = false
	_last = from
	_mark_dist = 0.0
	c.rig.stop_action()
	c.rig.play_action(&"dig_in")
	c.motor.speed = 0.0
	c.set_mode(Companion.Mode.BURROW)
	_set_collision(false)
	Audio.play_sfx(&"badgermole_snort", from, -3.0)
	return true


func tick(delta: float) -> void:
	t += delta
	_rumble_t -= delta
	match phase:
		Phase.DIG:
			c.velocity = Vector3.ZERO
			_update_mound(delta, false)
			_rumble(0.08)
			if _burrowed or t > DIG_TIMEOUT:
				phase = Phase.TRAVEL
				t = 0.0
		Phase.TRAVEL:
			_travel(delta)
		Phase.EMERGE:
			c.velocity = Vector3.ZERO
			_update_mound(delta, false)
			if t > 0.3 and c.collision_layer == 0:
				_set_collision(true)
			if t > EMERGE_TIME:
				_finish()
		_:
			c.set_mode(Companion.Mode.FOLLOW)


func _travel(delta: float) -> void:
	var p := c.global_position
	var to := Vector3(target.x - p.x, 0.0, target.z - p.z)
	var dist := to.length()
	var limit := start.distance_to(target) / SPEED + 3.0
	if dist < 0.25 or t > limit:
		_emerge_at(target)
		return
	var dir := to / dist
	var step := minf(SPEED * delta, dist)
	var np := p + dir * step
	np.y = WorldData.get_height(np.x, np.z)
	c.global_position = np
	c.velocity = dir * SPEED
	c.motor.yaw = CompanionNav.yaw_of(dir)
	c.rotation = Vector3(0.0, c.motor.yaw, 0.0)
	# The tunnel shows on the surface: a travelling mound of earth, clods torn up, cracks and
	# dust every few metres, a steady rumble.
	_update_mound(delta, true)
	_mark_dist += step
	if _mark_dist > 2.6:
		_mark_dist = 0.0
		var surf := WorldData.get_surface(np)
		EarthFx.tear_out(c, np - dir * 1.2, 0.3, surf)
		EarthFx.dust_trail(c, np, dir, surf, 1.4)
	_rumble(0.16)


## The travelling hump of earth over the tunnel (grows in, follows, sinks out).
func _update_mound(delta: float, on: bool) -> void:
	if on and _mound == null:
		_mound = MeshInstance3D.new()
		_mound.name = "BurrowMound"
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 14 if Settings.detail_level() > 0 else 8
		sm.rings = 7 if Settings.detail_level() > 0 else 4
		_mound.mesh = sm
		_mound.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		c.add_child(_mound)
	if _mound == null:
		return
	if on:
		var col := FxLib.surface_color(WorldData.get_surface(c.global_position)).darkened(0.3)
		_mound.material_override = ToonMaterials.make(col)
	_mound_w = move_toward(_mound_w, 1.0 if on else 0.0, delta * 3.5)
	_mound.visible = _mound_w > 0.01
	var r := c.prof.radius()
	var wob := 1.0 + 0.06 * sin(t * 13.0)
	_mound.scale = Vector3(r * 1.15 * wob, 0.8, r * 1.7) * maxf(_mound_w, 0.01)
	_mound.position = Vector3(0.0, -0.22, 0.4 * r)


func _rumble(strength: float) -> void:
	if _rumble_t > 0.0:
		return
	_rumble_t = 0.45
	Audio.play_sfx(&"badgermole_dig", c.global_position, -6.0, 0.15, 60.0)
	var p := c.player
	if ridden or (p != null and is_instance_valid(p) and p.global_position.distance_to(c.global_position) < 14.0):
		Events.camera_shake.emit(strength, 0.35)


func _emerge_at(at: Vector3) -> void:
	c.global_position = at
	c.velocity = Vector3.ZERO
	phase = Phase.EMERGE
	t = 0.0
	c.rig.play_action(&"emerge")
	Events.camera_shake.emit(0.3 if ridden else 0.15, 0.4)
	EarthFx.quake(c, at, 3.0, WorldData.get_surface(at))
	Audio.play_sfx(&"earth_crumble", at, -2.0)


## Emerge right now (timeouts, teleports): where it is if that is valid ground, else at
## the nearest safe ground.
func force_emerge() -> void:
	match phase:
		Phase.DIG, Phase.TRAVEL:
			var p := c.global_position
			var at := p if CompanionNav.walkable(p.x, p.z, 52.0, 0.2) else WorldData.get_safe_ground(p)
			_emerge_at(at)
		Phase.EMERGE:
			_finish()


func _finish() -> void:
	phase = Phase.NONE
	tunnels += 1
	_mound_w = 0.0
	if _mound != null:
		_mound.visible = false
	_set_collision(true)
	c.motor.teleport(c.global_position, c.motor.yaw)
	c.set_mode(Companion.Mode.RIDDEN if ridden and c.rider.phase == CompanionRider.Phase.RIDING else Companion.Mode.FOLLOW)
	ridden = false


## Aborts without the emerge animation (teleports, scene exit).
func cleanup() -> void:
	if phase == Phase.NONE:
		return
	phase = Phase.NONE
	ridden = false
	_set_collision(true)
	_mound_w = 0.0
	if _mound != null:
		_mound.visible = false
	if c.rig and (c.rig.is_action_playing(&"dig_in") or c.rig.is_action_playing(&"emerge")):
		c.rig.stop_action()


func _set_collision(on: bool) -> void:
	if on:
		if c.collision_layer == 0:
			c.collision_layer = _layer if _layer != 0 else Layers.COMPANION
			c.collision_mask = _mask if _mask != 0 else Layers.SOLID
	elif c.collision_layer != 0:
		_layer = c.collision_layer
		_mask = c.collision_mask
		c.collision_layer = 0
		c.collision_mask = 0


func _on_rig_event(action_name: StringName, event: StringName) -> void:
	if action_name == &"dig_in" and event == &"burrowed":
		_burrowed = true
