class_name Combat
extends RefCounted
## Combat helpers shared by the player, bending abilities, enemies and hazards.
##
## Damageable contract: any node in group &"damageable" implementing
##     func receive_hit(hit: HitInfo) -> int   # returns Combat.Result
##     var team: int                            # Combat.Team
## and optionally `func is_alive() -> bool`. Colliders that belong to a
## damageable (hurtboxes, child bodies) are resolved by walking up parents.

enum Team { PLAYER = 0, ENEMY = 1, NEUTRAL = 2, WILDLIFE = 3 }
enum Result { IGNORED = 0, HIT = 1, BLOCKED = 2, DEFLECTED = 3, DODGED = 4, KILLED = 5 }

const GROUP_DAMAGEABLE := &"damageable"


## Walks up from `node` to find the owning damageable (or null).
static func find_damageable(node: Node) -> Node:
	var n := node
	var depth := 0
	while n != null and depth < 8:
		if n.is_in_group(GROUP_DAMAGEABLE):
			return n
		n = n.get_parent()
		depth += 1
	return null


static func is_alive(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method("is_alive"):
		return target.is_alive()
	return true


## True if `hit` is allowed to affect `target` (team check, alive check).
static func can_hit(target: Node, hit: HitInfo) -> bool:
	if not is_alive(target):
		return false
	if hit.source == target:
		return false
	if "team" in target and target.team == hit.team and hit.team != Team.NEUTRAL:
		return false
	return true


## Delivers a hit, emits the global hit signal and returns the Result.
static func deal(target: Node, hit: HitInfo) -> int:
	var dmg := find_damageable(target)
	if dmg == null or not can_hit(dmg, hit):
		return Result.IGNORED
	if hit.position == Vector3.ZERO and dmg is Node3D:
		hit.position = (dmg as Node3D).global_position + Vector3.UP
	var result: int = dmg.receive_hit(hit)
	if result != Result.IGNORED:
		var tree := Engine.get_main_loop() as SceneTree
		var events: Node = tree.root.get_node_or_null(^"/root/Events") if tree else null
		if events:
			events.hit_landed.emit(hit, dmg, result)
	return result


## Returns unique damageables overlapping a sphere (excluding `exclude` nodes).
static func query_sphere(world: World3D, center: Vector3, radius: float, mask: int, exclude: Array = []) -> Array[Node]:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collision_mask = mask
	params.collide_with_areas = true
	params.collide_with_bodies = true
	return _collect(world.direct_space_state.intersect_shape(params, 64), exclude)


## Returns unique damageables overlapping an oriented box.
static func query_box(world: World3D, xform: Transform3D, half_extents: Vector3, mask: int, exclude: Array = []) -> Array[Node]:
	var shape := BoxShape3D.new()
	shape.size = half_extents * 2.0
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = xform
	params.collision_mask = mask
	params.collide_with_areas = true
	params.collide_with_bodies = true
	return _collect(world.direct_space_state.intersect_shape(params, 64), exclude)


## Returns damageables inside a horizontal cone (for sweeps, gusts, flame jets).
static func query_cone(world: World3D, origin: Vector3, forward: Vector3, range_m: float, half_angle_deg: float, mask: int, exclude: Array = []) -> Array[Node]:
	var out: Array[Node] = []
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var cos_limit := cos(deg_to_rad(half_angle_deg))
	for n in query_sphere(world, origin, range_m, mask, exclude):
		if not (n is Node3D):
			continue
		var to := (n as Node3D).global_position - origin
		to.y = 0.0
		if to.length() < 0.6 or fwd.dot(to.normalized()) >= cos_limit:
			out.append(n)
	return out


static func _collect(results: Array, exclude: Array) -> Array[Node]:
	var out: Array[Node] = []
	for r in results:
		var col: Object = r.get("collider")
		if col == null or not (col is Node):
			continue
		var d := find_damageable(col as Node)
		if d != null and not out.has(d) and not exclude.has(d):
			out.append(d)
	return out


## Damage multiplier when `attacker_element` hits a target with `defender_element`.
## Kept mild: elements differ by style, not by hard counters.
static func element_multiplier(attacker_element: int, defender_element: int) -> float:
	const E = ElementDefs.Element
	if attacker_element == E.WATER and defender_element == E.FIRE:
		return 1.15
	if attacker_element == E.FIRE and defender_element == E.AIR:
		return 1.1
	if attacker_element == E.EARTH and defender_element == E.WATER:
		return 1.1
	if attacker_element == E.AIR and defender_element == E.EARTH:
		return 1.05
	return 1.0
