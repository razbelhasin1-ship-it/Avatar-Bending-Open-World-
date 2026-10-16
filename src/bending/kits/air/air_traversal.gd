class_name AirTraversal
extends Node
## The world answering an airbender's movement (no ability needed): cushioned
## landings flatten the grass in a ring and kick up the ground, air jumps push the
## grass down under the feet, gliding low leaves a wake through the grass, bushes
## and snow, and the Air Scooter (air_scooter.gd) drives its own wake.
##
## Attached to the player on Events.player_spawned (AirTraversal.watch() is called
## by the Air kit); dormant while the player is not an airbender.

const TICK := 0.1

var player: CharacterBody3D = null
var _t := 0.0
var _wake := 0
var _puff_t := 0.0
var _motor_connected: RefCounted = null

static var _watching := false
## Cushioned landings / air jump bursts / wake puffs (tests).
static var landings := 0
static var jump_bursts := 0


## Starts following airbender players (idempotent).
static func watch() -> void:
	if _watching:
		return
	_watching = true
	Events.player_spawned.connect(AirTraversal.attach)
	Events.landed.connect(AirTraversal._on_landed)


static func attach(p: Node) -> void:
	if not (p is CharacterBody3D) or not is_instance_valid(p) or p.get_node_or_null("AirTraversal") != null:
		return
	var t := AirTraversal.new()
	t.name = "AirTraversal"
	t.player = p
	p.add_child(t)


static func _is_air(p: Node) -> bool:
	return p != null and is_instance_valid(p) and "element" in p and int(p.get("element")) == ElementDefs.Element.AIR


static func _on_landed(actor: Node3D, position: Vector3, impact: float, _surface: StringName) -> void:
	if not _is_air(actor) or not actor.is_in_group(&"player") or impact < 5.0 or not actor.is_inside_tree():
		return
	landings += 1
	# The air cushion: a ring of wind spreads from the feet (grass lies down, dust / snow rings).
	var power := clampf(impact / 14.0, 0.35, 1.2)
	AirEnv.blow(actor, position + Vector3.UP * 0.2, 1.6 + power * 2.0, power, {"mode": &"radial", "fires": false, "by": actor})


func _ready() -> void:
	process_physics_priority = 10


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		queue_free()
		return
	if not _is_air(player):
		_end_wake()
		return
	if player.is_on_floor():
		# Touching the ground refills the aerial budgets (air dashes, hang time).
		if int(player.get_meta(&"air_dashes_used", 0)) != 0:
			player.set_meta(&"air_dashes_used", 0)
		player.set_meta(&"air_hang", AirCommon.HANG_BUDGET)
	_connect_motor()
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	var motor: Variant = player.get("motor")
	var gliding := motor != null and bool(motor.get("gliding"))
	if not gliding:
		_end_wake()
		return
	var p := player.global_position
	var gy := _ground_y(p)
	var h := p.y - gy
	if h > 6.0:
		_end_wake()
		return
	var v := player.velocity
	var below := Vector3(p.x, gy, p.z)
	var strength := 9.0 + 9.0 * (1.0 - h / 6.0)
	if _wake == 0:
		_wake = AirWindField.add(player, below, 2.6, strength, AirWindField.DIRECTIONAL, v, INF)
	else:
		AirWindField.move(_wake, below, v)
	_puff_t -= TICK
	if _puff_t <= 0.0 and h < 3.0:
		_puff_t = 0.45
		AirFx.ground_puff(player, below, GroundSampler.surface(below), 0.35, (Vector3(v.x, 0.0, v.z).normalized() + Vector3.UP).normalized())


func _end_wake() -> void:
	if _wake != 0:
		AirWindField.release(_wake)
		_wake = 0


func _connect_motor() -> void:
	var motor: Variant = player.get("motor")
	if motor == null or motor == _motor_connected or not (motor as Object).has_signal(&"jumped"):
		return
	_motor_connected = motor
	(motor as Object).connect(&"jumped", _on_jumped)


func _on_jumped(kind: StringName) -> void:
	if kind != &"air_jump" or not _is_air(player) or not player.is_inside_tree():
		return
	var p := player.global_position
	var gy := _ground_y(p)
	if p.y - gy > 4.5:
		return
	jump_bursts += 1
	# The burst of wind under the feet presses the ground cover down.
	AirEnv.blow(player, Vector3(p.x, gy + 0.1, p.z), 2.2, 0.45, {"mode": &"radial", "fires": false, "props": true, "by": player})


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 8.0, Layers.WORLD | Layers.CONSTRUCT)
	var r := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		return (r["position"] as Vector3).y
	return WorldData.get_height(p.x, p.z)


func _exit_tree() -> void:
	_end_wake()
