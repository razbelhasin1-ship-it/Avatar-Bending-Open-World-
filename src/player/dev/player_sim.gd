class_name PlayerSim
extends RefCounted
## Deterministic stepping helpers for tests and tools: build a flat test
## ground, spawn a player driven by virtual input, and advance the player,
## its projectiles and constructs by fixed 1/60 s steps without waiting for
## real physics frames (a 3000-frame fuzz runs in a few seconds headless).
##
##   var ground := PlayerSim.ground(self)
##   var p := PlayerSim.player(self, ElementDefs.Element.AIR, Vector3.ZERO)
##   p.input.press(&"move_forward")
##   await PlayerSim.step(p, 60)          # one second of game time
##
## Steps always run inside a physics frame (CharacterBody3D.move_and_slide
## uses the process delta outside of one), so every helper is a coroutine.

const DT := 1.0 / 60.0


static func ground(parent: Node, size: float = 400.0, y: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "TestGround"
	sb.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 1.0, size)
	cs.shape = box
	cs.position = Vector3(0, y - 0.5, 0)
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func box(parent: Node, pos: Vector3, size: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.WORLD
	sb.position = pos
	sb.rotation_degrees = rot_deg
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


## A player with virtual input and manual stepping.
static func player(parent: Node, element: int, pos: Vector3 = Vector3.ZERO, use_camera: bool = false) -> PlayerCharacter:
	var p := PlayerCharacter.new()
	p.element = element
	p.use_camera = use_camera
	p.auto_respawn = true
	parent.add_child(p)
	p.set_physics_process(false)
	p.input.virtual_mode = true
	p.teleport(Transform3D(Basis.IDENTITY, pos))
	p.motor.sense()
	return p


## Waits for a physics frame unless already inside one.
static func _in_physics(node: Node) -> void:
	if not Engine.is_in_physics_frame():
		await node.get_tree().physics_frame


## Advances the player (and live projectiles / constructs) by `frames` fixed steps.
static func step(p: PlayerCharacter, frames: int, extra: Array = []) -> void:
	await _in_physics(p)
	for i in frames:
		step_once(p, extra)


static func step_once(p: PlayerCharacter, extra: Array = []) -> void:
	if is_instance_valid(p):
		p._physics_process(DT)
	for proj: BendingProjectile in BendingProjectile.live.duplicate():
		if is_instance_valid(proj) and proj.alive:
			proj.step(DT)
	for c: BendingConstruct in BendingConstruct.live.duplicate():
		if is_instance_valid(c):
			c._physics_process(DT)
	for n: Variant in extra:
		if n is Node and is_instance_valid(n) and (n as Node).has_method("_physics_process"):
			(n as Node).call("_physics_process", DT)


## Steps until `cond` is true (max `max_frames`). Returns frames taken or -1.
static func step_until(p: PlayerCharacter, cond: Callable, max_frames: int = 600) -> int:
	await _in_physics(p)
	for i in max_frames:
		if cond.call():
			return i
		step_once(p)
	return max_frames if cond.call() else -1


## Press for `hold_frames`, release, and step once more so the release is seen
## (a release + press without a poll in between would not be a new press).
static func tap(p: PlayerCharacter, action: StringName, hold_frames: int = 3) -> void:
	p.input.press(action)
	await step(p, hold_frames)
	p.input.release(action)
	await step(p, 1)
