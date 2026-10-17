class_name WildlifeAnimal
extends Node3D
## One wild animal: a CreatureRig moved kinematically over the terrain (WorldData height; water
## level when swimming) with a small mind — graze, look around, wander inside its herd's area,
## and flee from the player or from nearby combat / bending, then settle again. Large animals
## carry a kinematic capsule on Layers.NPC so the player cannot walk through them. Resting sky
## bison lie in their stalls. Faces -Z like every creature.

signal startled

const SPEC := {
	&"otter_penguin": {"walk": 0.7, "run": 2.6, "flee": 7.0, "graze": &"preen", "calm": 5.0},
	&"turtle_duck": {"walk": 0.45, "run": 1.4, "flee": 5.0, "graze": &"preen", "calm": 4.0},
	&"ostrich_horse": {"walk": 1.6, "run": 7.5, "flee": 13.0, "graze": &"eat", "calm": 7.0, "body": Vector2(0.5, 2.6)},
	&"komodo_rhino": {"walk": 1.2, "run": 4.5, "flee": 9.0, "graze": &"eat", "calm": 6.0, "body": Vector2(0.9, 1.6)},
	&"sky_bison": {"walk": 1.0, "run": 2.0, "flee": 0.0, "graze": &"eat", "calm": 0.0, "body": Vector2(2.2, 3.6)},
}

var species: StringName = &"otter_penguin"
var herd_center := Vector3.ZERO
var herd_radius := 8.0
var swim_level := -INF
var resting := false
var rig: CreatureRig = null
var scale_factor := 1.0
var state: StringName = &"idle"
var rng := RandomNumberGenerator.new()

var _target := Vector3.INF
var _speed := 1.0
var _t := 0.0
var _think := 0.0
var _flee_from := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw_target := 0.0
var _body: AnimatableBody3D = null


static func create(p_species: StringName, at: Vector3, yaw: float, p_seed: int, p_scale: float = 1.0) -> WildlifeAnimal:
	var a := WildlifeAnimal.new()
	a.species = p_species
	a.scale_factor = p_scale
	a.rng.seed = p_seed
	a.position = at
	a.rotation.y = yaw
	a._yaw_target = yaw
	return a


func _ready() -> void:
	add_to_group(&"wildlife")
	rig = CreatureRig.create(species, {"seed": int(rng.seed % 1000), "scale": scale_factor, "idle": true})
	if rig == null:
		queue_free()
		return
	rig.footstep_actor = self
	add_child(rig)
	var spec: Dictionary = SPEC.get(species, SPEC[&"otter_penguin"])
	if spec.has("body"):
		var b: Vector2 = spec["body"]
		_body = AnimatableBody3D.new()
		_body.sync_to_physics = false
		_body.collision_layer = Layers.NPC
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = b.x * scale_factor
		cap.height = maxf(b.y * scale_factor, cap.radius * 2.0 + 0.1)
		cs.shape = cap
		cs.position = Vector3(0, cap.height * 0.5, 0)
		_body.add_child(cs)
		add_child(_body)
	if swim_level > -INF:
		position.y = swim_level
		# float a little proud of the line: the water shader hides anything level with its surface
		rig.set_swimming(true, swim_level + 0.1 * scale_factor)
	else:
		position.y = WorldData.get_height(position.x, position.z)
	if resting:
		state = &"rest"
		rig.play_action(&"lie_down")
	_think = rng.randf_range(0.2, 2.0)


func _physics_process(delta: float) -> void:
	_think -= delta
	if _think <= 0.0:
		_think = 0.3
		_decide()
	var spd := 0.0
	if _target.is_finite():
		var to := _target - global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.4:
			_target = Vector3.INF
			if state == &"flee":
				_t = minf(_t, 1.5)
		else:
			var dir := to / d
			_yaw_target = atan2(-dir.x, -dir.z)
			spd = _speed * clampf(d / 0.8, 0.3, 1.0)
	var dy := wrapf(_yaw_target - rotation.y, -PI, PI)
	rotation.y += clampf(dy, -4.0 * delta, 4.0 * delta)
	var fwd := -global_basis.z
	_vel = _vel.lerp(Vector3(fwd.x, 0.0, fwd.z) * spd, minf(1.0, delta * 6.0))
	var p := global_position + _vel * delta
	if swim_level > -INF:
		if WorldData.get_water_height(p.x, p.z) == -INF:
			_vel = Vector3.ZERO
			_target = Vector3.INF
			p = global_position
		p.y = swim_level
	else:
		p.y = lerpf(global_position.y, WorldData.get_height(p.x, p.z), minf(1.0, delta * 12.0))
	global_position = p
	if rig != null:
		rig.set_locomotion(_vel, true, delta)


func _decide() -> void:
	var spec: Dictionary = SPEC.get(species, SPEC[&"otter_penguin"])
	_t -= 0.3
	var pl := Quests.get_player()
	var flee_r := float(spec["flee"])
	if pl != null and flee_r > 0.0 and state != &"flee" and pl.global_position.distance_to(global_position) < flee_r * scale_factor + 1.0:
		startle(pl.global_position)
		return
	match state:
		&"rest":
			# lying in the stall (a hold action): only the rig's own breathing and idle motion
			if pl != null and pl.global_position.distance_to(global_position) < 9.0:
				rig.look_at_point(pl.global_position + Vector3(0, 1.5, 0), 0.6)
			else:
				rig.clear_look()
		&"flee":
			if _t <= 0.0:
				state = &"idle"
				_t = rng.randf_range(1.0, 3.0)
				if species == &"otter_penguin":
					rig.stop_action()
		_:
			if _target.is_finite():
				return
			if _t > 0.0:
				return
			var r := rng.randf()
			if r < 0.35:
				state = &"graze"
				rig.play_action(StringName(str(spec["graze"])))
				_t = rng.randf_range(3.0, 7.0)
			elif r < 0.55:
				state = &"idle"
				rig.play_action(&"look_around" if rng.randf() < 0.5 else &"sniff")
				_t = rng.randf_range(2.0, 4.0)
			else:
				state = &"wander"
				var a := rng.randf() * TAU
				_target = herd_center + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(1.0, herd_radius)
				_speed = float(spec["walk"]) * sqrt(scale_factor)
				_t = rng.randf_range(4.0, 9.0)


## Runs from `from` (player, combat). Never for resting bison.
func startle(from: Vector3) -> void:
	var spec: Dictionary = SPEC.get(species, SPEC[&"otter_penguin"])
	if float(spec["flee"]) <= 0.0 or state == &"rest":
		return
	state = &"flee"
	_flee_from = from
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	away = away.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
	_target = global_position + away * rng.randf_range(12.0, 20.0)
	_speed = float(spec["run"]) * sqrt(scale_factor)
	_t = float(spec["calm"])
	rig.stop_action()
	if species == &"otter_penguin" and WorldData.get_surface(global_position) in [&"snow", &"ice"]:
		rig.play_action(&"belly_slide")
	elif species == &"turtle_duck":
		rig.play_action(&"quack")
	startled.emit()
