class_name EnemySim
extends RefCounted
## Deterministic stepping for enemy tests (like PlayerSim): advances the player,
## enemies, projectiles, constructs and an optional director by fixed 1/60 s steps
## inside one physics frame, with a sim clock for AttackTokens.
##
##   var ground := PlayerSim.ground(self)
##   var p := PlayerSim.player(self, ElementDefs.Element.FIRE, Vector3(0, 0, 6))
##   var e := EnemySim.enemy(self, &"bandit_brawler", Vector3.ZERO, p)
##   await EnemySim.step([p, e], 120)

const DT := 1.0 / 60.0

static var time := 0.0


## Installs the sim clock (AttackTokens) and resets token state.
static func begin() -> void:
	time = 0.0
	AttackTokens.reset()
	AttackTokens.clock = func() -> float: return EnemySim.time


static func end() -> void:
	AttackTokens.clock = Callable()
	AttackTokens.reset()
	AttackTokens.limit_override = -1
	AttackTokens.start_spacing = -1.0


## An enemy facing `face` (default: toward the player / -Z), stepped manually.
static func enemy(parent: Node, archetype: StringName, pos: Vector3, face_to: Node3D = null, opts: Dictionary = {}) -> EnemyBase:
	var yaw := 0.0
	if face_to != null:
		var d := face_to.global_position - pos
		yaw = atan2(-d.x, -d.z)
	var o := opts.duplicate()
	o["home"] = Transform3D(Basis(Vector3.UP, yaw), pos)
	if not o.has("seed"):
		o["seed"] = 1234
	var e := EnemyBase.create(archetype, o)
	parent.add_child(e)
	e.set_physics_process(false)
	if e.visual and e.visual.rig:
		e.visual.rig.set_process(false)
	return e


## New bodies only become visible to physics queries after a physics step.
static func settle(node: Node) -> void:
	await node.get_tree().physics_frame
	await node.get_tree().physics_frame


static func _in_physics(node: Node) -> void:
	if not Engine.is_in_physics_frame():
		await node.get_tree().physics_frame


## Steps every node in `nodes` (players, enemies, directors) plus live projectiles
## and constructs by `frames` fixed steps.
static func step(nodes: Array, frames: int) -> void:
	if nodes.is_empty():
		return
	var any: Node = null
	for n: Variant in nodes:
		if n is Node and is_instance_valid(n):
			any = n
			break
	if any == null:
		return
	await _in_physics(any)
	for i in frames:
		step_once(nodes)


static func step_once(nodes: Array) -> void:
	time += DT
	for n: Variant in nodes:
		if n is Node and is_instance_valid(n) and (n as Node).is_inside_tree() and (n as Node).has_method("_physics_process"):
			(n as Node).call("_physics_process", DT)
	for proj: BendingProjectile in BendingProjectile.live.duplicate():
		if is_instance_valid(proj) and proj.alive:
			proj.step(DT)
	for c: BendingConstruct in BendingConstruct.live.duplicate():
		if is_instance_valid(c):
			c._physics_process(DT)


## Steps until `cond` holds (max `max_frames`). Returns frames taken or -1.
static func step_until(nodes: Array, cond: Callable, max_frames: int = 600) -> int:
	if nodes.is_empty():
		return -1
	await _in_physics(nodes[0])
	for i in max_frames:
		if cond.call():
			return i
		step_once(nodes)
	return max_frames if cond.call() else -1
