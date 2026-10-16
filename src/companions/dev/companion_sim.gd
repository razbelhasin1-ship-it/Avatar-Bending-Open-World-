class_name CompanionSim
extends RefCounted
## Deterministic stepping for companion tests (like PlayerSim): a companion with manual
## physics + animation stepping next to a PlayerSim player with virtual input.
##
##   var ground := PlayerSim.ground(self)
##   var p := PlayerSim.player(self, ElementDefs.Element.AIR, Vector3.ZERO)
##   var c := CompanionSim.companion(self, &"sky_bison", Vector3(6, 0, 4), p)
##   await CompanionSim.step(c, p, 120)     # 2 s: companion tick, player tick, rig animation
##
## The companion ticks before the player inside each step (as in the game, where its
## process_physics_priority is lower), then both rigs animate.

const DT := 1.0 / 60.0


static func companion(parent: Node, species: StringName, pos: Vector3, player: PlayerCharacter = null, yaw: float = 0.0) -> Companion:
	var c := Companion.create(species, {"rig": {"sounds": false}})
	c.player = player
	parent.add_child(c)
	c.set_physics_process(false)
	c.rig.set_process(false)
	c.motor.teleport(pos, yaw)
	c.rig.reset_feet()
	if player != null:
		player.companion = c
	return c


static func step(c: Companion, p: PlayerCharacter, frames: int) -> void:
	if not Engine.is_in_physics_frame():
		var n: Node = c if c != null and is_instance_valid(c) else p
		await n.get_tree().physics_frame
	for i in frames:
		step_once(c, p)


static func step_once(c: Companion, p: PlayerCharacter) -> void:
	if c != null and is_instance_valid(c):
		c._physics_process(DT)
	PlayerSim.step_once(p)
	if c != null and is_instance_valid(c) and c.rig != null:
		c.rig._process(DT)


## Steps until `cond` is true (max `max_frames`). Returns frames taken or -1.
static func step_until(c: Companion, p: PlayerCharacter, cond: Callable, max_frames: int = 600) -> int:
	if not Engine.is_in_physics_frame():
		await c.get_tree().physics_frame
	for i in max_frames:
		if cond.call():
			return i
		step_once(c, p)
	return max_frames if cond.call() else -1


## Press for a few frames then release (a buffered press the companion / player sees once).
static func tap(c: Companion, p: PlayerCharacter, action: StringName, hold_frames: int = 3) -> void:
	p.input.press(action)
	await step(c, p, hold_frames)
	p.input.release(action)
	await step(c, p, 1)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
