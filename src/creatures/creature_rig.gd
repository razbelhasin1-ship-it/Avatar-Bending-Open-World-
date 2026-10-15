class_name CreatureRig
extends Node3D
## A procedurally built and animated creature (companions and wildlife).
##
##   var bison := CreatureRig.create(&"sky_bison", {"seed": 3})
##   add_child(bison)
##   bison.set_locomotion(body.velocity, body.is_on_floor(), delta)   # every physics frame
##   bison.set_flight(true, body.velocity, bank, pitch)                 # flyers
##   var d := bison.play_action(&"call")                                 # -> duration
##   saddle_point = bison.get_socket(&"saddle")
##
## Faces -Z; the origin is the ground point under the body center (dragon: under the
## shoulders, the serpentine body trails behind). Behaviour/AI and mount controllers
## live elsewhere (src/companions) and drive this API; the rig only renders and
## animates. Full API: docs/modules/creatures.md.

## Timed action event (e.g. ("bite", "hit"), ("takeoff", "leap"), ("land", "touchdown")).
signal action_event(action_name: StringName, event: StringName)
signal action_finished(action_name: StringName)
## Flight state requested by set_flying/set_flight changed.
signal flight_changed(flying: bool)
## A paw planted (after Events.footstep was emitted).
signal foot_planted(leg_index: int, position: Vector3)

const SPECIES_PATHS := {
	&"sky_bison": "res://src/creatures/species/sky_bison.gd",
	&"dragon": "res://src/creatures/species/dragon.gd",
	&"polar_bear_dog": "res://src/creatures/species/polar_bear_dog.gd",
	&"badgermole": "res://src/creatures/species/badgermole.gd",
	&"otter_penguin": "res://src/creatures/species/otter_penguin.gd",
	&"turtle_duck": "res://src/creatures/species/turtle_duck.gd",
	&"ostrich_horse": "res://src/creatures/species/ostrich_horse.gd",
	&"komodo_rhino": "res://src/creatures/species/komodo_rhino.gd",
}
const COMPANIONS: Array[StringName] = [&"sky_bison", &"dragon", &"polar_bear_dog", &"badgermole"]
const WILDLIFE: Array[StringName] = [&"otter_penguin", &"turtle_duck", &"ostrich_horse", &"komodo_rhino"]

static var _mesh_cache: Dictionary = {}

var species_id: StringName
var species: CreatureSpecies
var config: Dictionary = {}
var skel: RigSkeleton
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var motor: CreatureMotor
var gait: GaitEngine
var legs: Array[CreatureLeg] = []
var gaits: Array[Dictionary] = []
var pose := CreaturePose.new()
var actions := ActionPlayer.new()

## Node passed as `actor` in Events.footstep (defaults to this rig). Set it to the
## companion's body so footprints are attributed to the gameplay actor.
var footstep_actor: Node3D = null
## Play creature sounds (vocals, heavy steps, wing flaps) on action/gait events.
var sounds := true
## Random idle behaviours when standing still.
var idle_enabled := true

# Locomotion state.
var velocity := Vector3.ZERO
var grounded := true
var local_velocity := Vector3.ZERO
var local_accel := Vector3.ZERO
var yaw_rate := 0.0
var time := 0.0
var walk_speed := 1.5
var run_speed := 5.0
var width_hint := 1.0
var breath_period := 3.5

# Flight / swimming state.
var flying := false
## 0 = grounded pose, 1 = full flight pose.
var flight_w := 0.0
var flight_velocity := Vector3.ZERO
var flight_bank := 0.0
var flight_pitch := 0.0
var swimming := false
var water_y := 0.0
var swim_w := 0.0
var air_w := 0.0

## Current LOD level 0..3 (see set_lod).
var lod := 0
var last_probe_normal := Vector3.UP

var _sockets: Dictionary = {}       # name -> {node, bone, offset}
var _dims: Dictionary = {}
var _manual_loco := false
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var _last_local_vel := Vector3.ZERO
var _feet_ready := false
var _lod_manual := false
var _lod_timer := 0.0
var _lod_accum := 0.0
var _materials: Dictionary = {}     # surface index -> [lod0, lod1, lod2]
var _leg_free_extra: PackedFloat32Array = PackedFloat32Array()
var _look_pos := Vector3.ZERO
var _look_w := 0.0
var _look_w_target := 0.0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _blink_t := 2.0
var _blink_phase := -1.0
var _idle_t := 5.0
var _air_t := 0.0
var _takeoff_hold := 0.0
var _flash := 0.0
var _probe_exclude: Array[RID] = []
var _step_sound_t := 0.0
var _notifier: VisibleOnScreenNotifier3D


## Creates a creature. config: seed (int), scale (float, default 1), colors
## (Dictionary of species color overrides, e.g. {"fur": Color(...)}), detail (0..3,
## default Settings.detail_level()), sounds (bool), idle (bool), lod (int, -1 = auto).
static func create(species_name: StringName, cfg: Dictionary = {}) -> CreatureRig:
	if not SPECIES_PATHS.has(species_name):
		push_error("CreatureRig: unknown species %s" % species_name)
		return null
	var script := load(SPECIES_PATHS[species_name]) as GDScript
	var rig := CreatureRig.new()
	rig.name = String(species_name).to_pascal_case()
	rig._build(species_name, script.new(), cfg)
	return rig


## Every species id create() accepts.
static func species_list() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in SPECIES_PATHS:
		out.append(k)
	return out


static func clear_mesh_cache() -> void:
	_mesh_cache.clear()


# --- Public API ---------------------------------------------------------------------------

## Feeds locomotion each physics frame: world velocity (m/s) and whether the body is
## on the ground. Without calls, the rig derives velocity from its own movement.
func set_locomotion(world_velocity: Vector3, is_grounded: bool, _delta: float = 0.0) -> void:
	_manual_loco = true
	velocity = world_velocity
	grounded = is_grounded


## Flight control for flyers: `active` requests flight (takeoff/landing transitions are
## played automatically), `vel` world velocity, `bank` roll (rad, + = right wing down /
## turning right), `pitch` (rad, + = nose up).
func set_flight(active: bool, vel: Vector3 = Vector3.ZERO, bank: float = 0.0, pitch: float = 0.0) -> void:
	flight_velocity = vel
	flight_bank = bank
	flight_pitch = pitch
	if _manual_loco:
		velocity = vel
	set_flying(active)


## Requests flight on/off. Plays "takeoff" / "land" (see action_event "leap" /
## "touchdown"). Returns the transition duration (0 if unchanged or cannot fly).
func set_flying(active: bool) -> float:
	if active == flying or not can_fly():
		return 0.0
	flying = active
	var d := 0.0
	if active:
		if flight_w < 0.3:
			d = play_action(&"takeoff")
			_takeoff_hold = float(species.tune.get("takeoff_leap", 0.5))
	else:
		d = play_action(&"land")
	flight_changed.emit(active)
	return d


func is_flying() -> bool:
	return flying


func can_fly() -> bool:
	return species != null and species.can_fly()


## Floats on water at `water_height` and paddles (swimmers).
func set_swimming(active: bool, water_height: float = 0.0) -> void:
	swimming = active
	water_y = water_height


## Plays an action; returns its duration in seconds (0 if unsupported). Hold actions
## (sit, lie_down, dig_in) return the time to reach the held pose and stay until
## stop_action() (or locomotion for sit/lie_down). opts are passed to the species.
func play_action(action_name: StringName, opts: Dictionary = {}) -> float:
	if species == null:
		return 0.0
	var a := species.make_action(action_name, opts)
	if a == null:
		return 0.0
	actions.play(a)
	_idle_t = rng_range(4.0, 9.0)
	return a.duration


## Stops the current action (blends back to locomotion).
func stop_action() -> void:
	actions.stop()


func is_action_playing(action_name: StringName = &"") -> bool:
	return actions.is_playing(action_name)


func current_action() -> StringName:
	return actions.current.name if actions.current != null else &""


## Names the species supports in play_action().
func supported_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for n: StringName in [&"roar", &"call", &"howl", &"bark", &"growl", &"shake", &"sit", &"lie_down",
			&"dig_in", &"emerge", &"takeoff", &"land", &"bite", &"swipe", &"rear_up", &"eat", &"sniff",
			&"yawn", &"look_around", &"scratch", &"ear_twitch", &"breathe_fire_start", &"breathe_fire_end",
			&"belly_slide", &"tail_slap", &"preen", &"flap"]:
		if species.make_action(n, {}) != null:
			out.append(n)
	return out


## Socket node (child of the rig, follows its bone): &"saddle", &"head", &"mouth",
## &"tail", &"rider_left", &"rider_right", &"back", &"chest" (species may add more).
func get_socket(socket_name: StringName) -> Node3D:
	var s: Dictionary = _sockets.get(socket_name, {})
	return s.get("node") as Node3D


func get_socket_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for n: StringName in _sockets:
		out.append(n)
	return out


## {length, height, width, saddle_height, paw_size, weight, can_fly, walk_speed,
## run_speed, sprint_speed, fly_speed, collision_radius, collision_height, mass}.
func get_dimensions() -> Dictionary:
	return _dims.duplicate()


## Turns head/neck/eyes toward a world point (smoothly, within species limits).
func look_at_point(pos: Vector3, weight: float = 1.0) -> void:
	_look_pos = pos
	_look_w_target = clampf(weight, 0.0, 1.0)


func clear_look() -> void:
	_look_w_target = 0.0


## LOD: 0 full (fur shells, IK raycasts, springs, every frame), 1 reduced shells,
## 2 no shells/springs, physics-free ground, 20 Hz, 3 minimal 6 Hz. -1 = automatic
## (distance to the active camera + on-screen test).
func set_lod(level: int) -> void:
	if level < 0:
		_lod_manual = false
		_lod_timer = 0.0
		return
	_lod_manual = true
	_apply_lod(clampi(level, 0, 3))


## Re-plants all feet under the body (call after teleporting the creature).
func reset_feet() -> void:
	if is_inside_tree():
		_solve_pose(0.0)
		gait.reset_feet(self)
		for s in motor.springs:
			s.reset()
		_last_pos = global_position
		_feet_ready = true


## White hit flash on the whole body (fades out).
func flash_hit(strength: float = 1.0) -> void:
	_flash = maxf(_flash, strength)


## Tints the body (wet, frozen, burned...): amount 0..1.
func set_status(color: Color, amount: float) -> void:
	if mesh_instance:
		mesh_instance.set_instance_shader_parameter(&"status_color", color)
		mesh_instance.set_instance_shader_parameter(&"status_amount", clampf(amount, 0.0, 1.0))


## World position of a paw contact (for VFX), by leg index.
func get_paw_position(leg_index: int) -> Vector3:
	return legs[leg_index].foot_world if leg_index < legs.size() else global_position


# --- Build (used by species scripts) --------------------------------------------------------

## Declares a socket on `bone` with a local offset (bone frame == creature axes at rest).
func add_socket(socket_name: StringName, bone_name: StringName, offset: Transform3D = Transform3D.IDENTITY) -> void:
	var n := Node3D.new()
	n.name = "Socket_%s" % socket_name
	add_child(n)
	_sockets[socket_name] = {"node": n, "bone": skel.idx(bone_name), "offset": offset}


## Allows an action to free one leg from the ground this frame (0..1).
func set_leg_free(leg_index: int, w: float) -> void:
	if leg_index < _leg_free_extra.size():
		_leg_free_extra[leg_index] = maxf(_leg_free_extra[leg_index], w)


func rng_range(a: float, b: float) -> float:
	return species.rng.randf_range(a, b) if species else a


func _build(species_name: StringName, sp: CreatureSpecies, cfg: Dictionary) -> void:
	species_id = species_name
	species = sp
	config = cfg
	sounds = bool(cfg.get("sounds", true))
	idle_enabled = bool(cfg.get("idle", true))
	sp.k = float(cfg.get("scale", 1.0))
	sp.cfg = cfg
	sp.rng.seed = int(cfg.get("seed", hash(species_name)))
	skel = RigSkeleton.new()
	motor = CreatureMotor.new()
	motor.setup(skel)
	gait = GaitEngine.new()
	sp.build(self)
	_leg_free_extra.resize(legs.size())
	gait.setup(skel, legs, gaits)
	skeleton = skel.build_skeleton()
	add_child(skeleton)
	var detail := int(cfg.get("detail", _detail_level()))
	var key := "%s|%s|%d" % [species_name, str(sp.mesh_key()), detail]
	var mesh: ArrayMesh = _mesh_cache.get(key)
	if mesh == null:
		var kit := MeshKit.new([0.55, 0.75, 1.0, 1.3][clampi(detail, 0, 3)])
		sp.build_mesh(self, kit)
		mesh = kit.commit()
		_mesh_cache[key] = mesh
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = &"Body"
	mesh_instance.mesh = mesh
	mesh_instance.skin = skel.build_skin()
	add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("../Skeleton3D")
	var ext: float = maxf(float(_dims.get("length", 4.0)), float(_dims.get("height", 2.0))) * 1.6 + 2.0
	mesh_instance.custom_aabb = AABB(Vector3(-ext, -ext * 0.5, -ext), Vector3(ext * 2.0, ext * 1.5, ext * 2.0))
	mesh_instance.visibility_range_end = float(cfg.get("draw_distance", sp.draw_distance()))
	mesh_instance.visibility_range_end_margin = 10.0
	for si in mesh.get_surface_count():
		var sname := StringName(mesh.surface_get_name(si))
		var mats: Array = []
		for l in 3:
			mats.append(sp.material_for(sname, detail, l))
		_materials[si] = mats
	_apply_lod(0)
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-ext * 0.5, -1.0, -ext * 0.5), Vector3(ext, ext * 0.75, ext))
	add_child(_notifier)
	actions.event_fired.connect(_on_action_event)
	actions.finished.connect(func(n: StringName) -> void: action_finished.emit(n))
	if cfg.has("lod") and int(cfg["lod"]) >= 0:
		set_lod(int(cfg["lod"]))
	# Rest pose so the creature looks right before its first frame.
	_solve_pose(0.0, true)


## Sets dimension values (species build()).
func set_dimensions(d: Dictionary) -> void:
	_dims = d
	walk_speed = float(d.get("walk_speed", walk_speed))
	run_speed = float(d.get("run_speed", run_speed))
	width_hint = float(d.get("width", width_hint))


static func _detail_level() -> int:
	var s := Engine.get_main_loop() as SceneTree
	if s and s.root.has_node(^"Settings"):
		return s.root.get_node(^"Settings").detail_level()
	return 2


# --- Frame update --------------------------------------------------------------------------

func _ready() -> void:
	_last_pos = global_position
	_last_yaw = _yaw_of(global_basis)
	_lod_timer = species.rng.randf() * 0.3 if species else 0.0


func _process(delta: float) -> void:
	if species == null:
		return
	if not _feet_ready:
		reset_feet()
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.3
		if not _lod_manual:
			_auto_lod()
	var interval: float = [0.0, 0.0, 1.0 / 20.0, 1.0 / 6.0][lod]
	_lod_accum += delta
	if _lod_accum < interval:
		return
	var dt := minf(_lod_accum, 0.25)
	_lod_accum = 0.0
	_step(dt)


func _step(dt: float) -> void:
	time += dt
	_update_motion(dt)
	_update_flight(dt)
	actions.update(dt)
	var cur := actions.current
	if cur != null and cur.cancel_on_move and gait.speed > walk_speed * 0.35 and cur.t > 0.3:
		actions.stop()
	_update_idle(dt)
	_solve_pose(dt)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 4.0)
		mesh_instance.set_instance_shader_parameter(&"hit_flash", _flash)


func _solve_pose(dt: float, rest_only: bool = false) -> void:
	pose.reset()
	_leg_free_extra.fill(0.0)
	if not rest_only:
		species.animate(self, pose, dt)
		if flight_w > 0.0 or flying:
			species.flight_pose(self, pose, dt)
		for a in actions.active():
			species.action_pose(self, a, pose)
		_update_blink(dt)
		_update_look(dt)
	# Leg release weights.
	var rooted := false
	for a in actions.active():
		if a.roots and a.weight > 0.5:
			rooted = true
	for l in legs:
		var f := maxf(flight_w, air_w)
		f = maxf(f, swim_w)
		if l.group == CreatureLeg.Group.HIND:
			f = maxf(f, pose.hind_free)
		else:
			f = maxf(f, pose.front_free)
		f = maxf(f, _leg_free_extra[l.index])
		l.free = clampf(f, 0.0, 1.0)
	if is_inside_tree() and _feet_ready and dt > 0.0:
		var can_step := flight_w < 0.5 and not rooted and air_w < 0.5
		gait.update(self, dt, velocity, can_step)
	motor.time = time
	motor.pose_body(pose)
	species.post_pose(self, dt)
	motor.pose_legs(legs, pose, global_transform if is_inside_tree() else Transform3D.IDENTITY)
	if lod < 2 and dt > 0.0 and is_inside_tree():
		motor.update_springs(global_transform, dt)
	species.final_pose(self, dt)
	skel.push(skeleton)
	_update_sockets()


func _update_motion(dt: float) -> void:
	var pos := global_position
	if not _manual_loco and dt > 0.0:
		var v := (pos - _last_pos) / dt
		velocity = velocity.lerp(v, 1.0 - exp(-dt * 12.0))
		grounded = true
	if pos.distance_to(_last_pos) > 12.0:
		reset_feet()
	_last_pos = pos
	var b := global_basis.orthonormalized()
	var yaw := _yaw_of(b)
	if dt > 0.0:
		yaw_rate = lerpf(yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / dt, 1.0 - exp(-dt * 8.0))
	_last_yaw = yaw
	local_velocity = b.transposed() * velocity
	if dt > 0.0:
		local_accel = local_accel.lerp((local_velocity - _last_local_vel) / dt, 1.0 - exp(-dt * 6.0))
	_last_local_vel = local_velocity
	# Airborne (jumping/falling, not flying): legs reach down after a short delay.
	if not grounded and flight_w < 0.5:
		_air_t += dt
	else:
		_air_t = 0.0
	air_w = move_toward(air_w, 1.0 if _air_t > 0.15 else 0.0, dt * 5.0)
	swim_w = move_toward(swim_w, 1.0 if swimming else 0.0, dt * 2.0)


func _update_flight(dt: float) -> void:
	if not can_fly():
		return
	var target := 1.0 if flying else 0.0
	var rate := 1.0 / maxf(float(species.tune.get("flight_blend", 1.0)), 0.1)
	if flying and _takeoff_hold > 0.0:
		_takeoff_hold -= dt
		target = flight_w
	if not flying and grounded and _manual_loco:
		rate *= 2.5
	flight_w = move_toward(flight_w, target, rate * dt)


func _update_idle(dt: float) -> void:
	if not idle_enabled or flying or flight_w > 0.0 or swimming:
		return
	if actions.current != null or gait.speed > 0.2:
		_idle_t = maxf(_idle_t, 2.5)
		return
	_idle_t -= dt
	if _idle_t <= 0.0:
		_idle_t = rng_range(5.0, 11.0)
		var options := species.idle_actions()
		if options.is_empty():
			return
		var a := species.make_action(options[species.rng.randi() % options.size()], {})
		if a != null:
			a.is_idle = true
			if a.hold:
				# Idle rests (sit, lie down) last a while, then the creature gets up again.
				a.hold = false
				a.duration = float(a.opts.get("intro", a.duration)) + rng_range(5.0, 12.0)
			actions.play(a)


func _update_blink(dt: float) -> void:
	_blink_t -= dt
	if _blink_t <= 0.0 and _blink_phase < 0.0:
		_blink_phase = 0.0
		_blink_t = rng_range(2.0, 6.0)
		if species.rng.randf() < 0.18:
			_blink_t = 0.3   # double blink
	if _blink_phase >= 0.0:
		_blink_phase += dt / 0.17
		pose.blink += sin(clampf(_blink_phase, 0.0, 1.0) * PI)
		if _blink_phase >= 1.0:
			_blink_phase = -1.0


func _update_look(dt: float) -> void:
	_look_w = move_toward(_look_w, _look_w_target, dt * 2.5)
	var yaw := 0.0
	var pitch := 0.0
	if _look_w > 0.0 and motor.head >= 0 and is_inside_tree():
		var local := global_transform.affine_inverse() * _look_pos
		var base := skel.rest_pos[motor.neck[0]] if not motor.neck.is_empty() else skel.rest_pos[motor.head]
		var d := local - base
		yaw = clampf(atan2(-d.x, -d.z), -motor.look_yaw_limit, motor.look_yaw_limit)
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -motor.look_pitch_limit, motor.look_pitch_limit)
		motor.eye_target_rig = local
	var k := 1.0 - exp(-dt * 5.0) if dt > 0.0 else 1.0
	_look_yaw = lerpf(_look_yaw, yaw * _look_w, k)
	_look_pitch = lerpf(_look_pitch, pitch * _look_w, k)
	motor.look_yaw = _look_yaw
	motor.look_pitch = _look_pitch
	motor.eye_target_w = _look_w


func _update_sockets() -> void:
	for s: Dictionary in _sockets.values():
		var b: int = s["bone"]
		if b >= 0:
			(s["node"] as Node3D).transform = skel.glob[b] * (s["offset"] as Transform3D)


func _on_action_event(action_name: StringName, event: StringName) -> void:
	if sounds and is_inside_tree() and lod < 3:
		var snd := species.sound_for(action_name, event)
		if snd != &"":
			var head_s := get_socket(&"head")
			Audio.play_sfx(snd, head_s.global_position if head_s else global_position, 0.0, 0.08, 160.0)
	action_event.emit(action_name, event)


# --- Ground / footsteps --------------------------------------------------------------------

## Ground point under `pos` (physics ray on Layers.SOLID, WorldData fallback). Sets
## last_probe_normal.
func probe_ground(pos: Vector3, from_y: float) -> Vector3:
	if lod < 2 and is_inside_tree():
		var space := get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, from_y, pos.z),
					Vector3(pos.x, from_y - 40.0, pos.z), Layers.SOLID, _probe_exclude)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				last_probe_normal = hit["normal"]
				return hit["position"]
	last_probe_normal = WorldData.get_normal(pos.x, pos.z)
	return Vector3(pos.x, WorldData.get_height(pos.x, pos.z), pos.z)


## Colliders the ground probe ignores (e.g. the companion's own body).
func set_probe_exclude(rids: Array[RID]) -> void:
	_probe_exclude = rids


func surface_at(pos: Vector3) -> StringName:
	return WorldData.get_surface(pos)


## Called by GaitEngine when a paw plants.
func on_foot_planted(l: CreatureLeg) -> void:
	if flight_w > 0.5 or lod >= 3:
		return
	var actor: Node3D = footstep_actor if is_instance_valid(footstep_actor) else self
	Events.footstep.emit(actor, l.foot_world, _yaw_of(global_basis), l.paw_size, l.weight, l.surface)
	foot_planted.emit(l.index, l.foot_world)
	if sounds and l.weight >= 0.7 and lod <= 1 and time - _step_sound_t > 0.12:
		_step_sound_t = time
		Audio.play_sfx(&"creature_step_heavy", l.foot_world, -4.0 + l.weight * 2.0, 0.1, 70.0)


static func _yaw_of(b: Basis) -> float:
	var f := -b.z
	return atan2(-f.x, -f.z)


# --- LOD ----------------------------------------------------------------------------------

func _auto_lod() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	if cam == null:
		_apply_lod(0)
		return
	var size := maxf(float(_dims.get("length", 3.0)), 1.0)
	var d := cam.global_position.distance_to(global_position)
	var level := 0
	if d > 220.0 + size * 12.0:
		level = 3
	elif d > 90.0 + size * 8.0:
		level = 2
	elif d > 30.0 + size * 5.0:
		level = 1
	if _notifier and not _notifier.is_on_screen() and d > size * 2.0:
		level = maxi(level, 2)
	if level != lod:
		_apply_lod(level)


func _apply_lod(level: int) -> void:
	lod = level
	if mesh_instance == null:
		return
	var mi := mini(level, 2)
	for si: int in _materials:
		mesh_instance.set_surface_override_material(si, _materials[si][mi])
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if level < 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
