class_name NpcSteering
extends RefCounted
## Local steering for walking NPCs: three whisker rays at knee and chest height against the
## world (re-cast at most every 0.2 s per NPC), separation from nearby NPCs, and a polite berth
## around the player (sidestep when the player blocks the way, never shove through). Returns a
## horizontal unit direction (or zero to wait).

const WHISKER := 1.6
const PERSONAL := 1.1
const PLAYER_BERTH := 1.7


static func steer(npc: NpcCharacter, dir: Vector3, delta: float) -> Vector3:
	var d := Vector3(dir.x, 0.0, dir.z).normalized()
	if d == Vector3.ZERO:
		return d
	# walls / props ahead (only the full tier has collision around it)
	if npc.full:
		npc._avoid_t -= delta
		if npc._avoid_t <= 0.0:
			npc._avoid_t = 0.2
			npc._avoid = _whiskers(npc, d)
		if npc._avoid != Vector3.ZERO:
			d = (d + npc._avoid * 1.4).normalized()
	var p := npc.global_position
	var push := Vector3.ZERO
	# people
	var dir_node: Variant = npc.director
	if dir_node != null and dir_node is NpcDirector:
		for o: NpcCharacter in (dir_node as NpcDirector).neighbors(npc):
			var off := p - o.global_position
			off.y = 0.0
			var dist := off.length()
			if dist > 0.01 and dist < PERSONAL:
				push += off / dist * (PERSONAL - dist) / PERSONAL
	# the player
	var pl := Quests.get_player()
	if pl != null:
		var off2 := p - pl.global_position
		off2.y = 0.0
		var dist2 := off2.length()
		if dist2 < PLAYER_BERTH and dist2 > 0.01:
			var away := off2 / dist2
			if d.dot(-away) > 0.55 and dist2 < 1.0:
				return Vector3.ZERO      # the player stands right in the way: wait
			var side := Vector3(-d.z, 0.0, d.x)
			if side.dot(away) < 0.0:
				side = -side
			push += (away * 0.6 + side * 0.8) * (PLAYER_BERTH - dist2) / PLAYER_BERTH
	if push != Vector3.ZERO:
		d = (d + push * 1.6).normalized()
	return d


static func _whiskers(npc: NpcCharacter, d: Vector3) -> Vector3:
	if not npc.is_inside_tree():
		return Vector3.ZERO
	var space := npc.get_world_3d().direct_space_state
	var p := npc.global_position
	var right := Vector3(-d.z, 0.0, d.x)
	var avoid := Vector3.ZERO
	for i in 3:
		var side := float(i - 1)
		var ray := (d + right * side * 0.55).normalized() * (WHISKER if i == 1 else WHISKER * 0.8)
		for h: float in [0.45, 1.3]:
			var from := p + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + ray, Layers.SOLID)
			q.exclude = [npc.get_rid()]
			var r := space.intersect_ray(q)
			if not r.is_empty():
				var n := r["normal"] as Vector3
				if absf(n.y) > 0.7:
					continue   # floor / stair tread, not a wall
				var k := 1.0 - (from.distance_to(r["position"]) / ray.length())
				avoid += Vector3(n.x, 0.0, n.z).normalized() * k
				if i == 1:
					avoid += -right * (1.0 if side >= 0.0 else -1.0) * k * 0.3
				break
	return avoid


## True when a person can walk straight from `a` to `b`: no wall at knee / chest height and the
## floor at `b` within `max_dy` of `a` (physics ray down). Used to pick wander / stroll targets.
static func walkable(npc: Node3D, a: Vector3, b: Vector3, max_dy: float = 1.2) -> bool:
	if not npc.is_inside_tree():
		return false
	var space := npc.get_world_3d().direct_space_state
	var excl: Array[RID] = []
	if npc is CollisionObject3D:
		excl.append((npc as CollisionObject3D).get_rid())
	for h: float in [0.5, 1.4]:
		var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, h, 0), b + Vector3(0, h, 0), Layers.SOLID)
		q.exclude = excl
		var r := space.intersect_ray(q)
		if not r.is_empty() and absf((r["normal"] as Vector3).y) < 0.7:
			return false
	var g := PhysicsRayQueryParameters3D.create(b + Vector3.UP * 1.5, b + Vector3.DOWN * 2.5, Layers.SOLID)
	g.exclude = excl
	var gr := space.intersect_ray(g)
	if gr.is_empty():
		return false
	return absf((gr["position"] as Vector3).y - a.y) <= max_dy
