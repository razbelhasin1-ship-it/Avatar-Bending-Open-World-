class_name EncounterSite
extends RefCounted
## One encounter location: a camp (WorldData camp POI), an outpost (authored, with its
## own structure), a patrol route on a road, or a beast den. Holds the roster and its
## persistent state (which members are still alive, when it was cleared) while the
## enemy nodes come and go with the player's distance (EncounterDirector).

var id: StringName = &""
var display_name := ""
## &"camp", &"outpost", &"patrol", &"den".
var kind: StringName = &"camp"
var faction: StringName = &"bandits"
var region: StringName = &""
var center := Vector3.ZERO
var radius := 20.0
var yaw := 0.0
var poi_id: StringName = &""
## Nation style of an authored outpost structure (NationPalette id).
var style: StringName = &""
## [{"archetype", "pos" (world), "yaw", "alive", "seed", "level", "node"}]
var members: Array[Dictionary] = []
## Patrol polyline (world, on the road) walked back and forth.
var route := PackedVector3Array()
var route_index := 0
var respawn_time := 480.0
## GameState.play_time of the clear (-1 = not cleared).
var cleared_at := -1.0
var active := false
var leash := 36.0
var level := 1


func add_member(archetype: StringName, pos: Vector3, p_yaw: float, seed_v: int) -> void:
	members.append({"archetype": archetype, "pos": pos, "yaw": p_yaw, "alive": true, "seed": seed_v, "level": level, "node": null})


## Distance from `p` to the site (patrols: to the nearest route point).
func distance_to(p: Vector3) -> float:
	if kind == &"patrol" and route.size() > 0:
		var best := INF
		for q in route:
			best = minf(best, Vector2(q.x - p.x, q.z - p.z).length())
		return best
	return maxf(0.0, Vector2(center.x - p.x, center.z - p.z).length() - radius)


func alive_members() -> int:
	var n := 0
	for m in members:
		if bool(m["alive"]):
			n += 1
	return n


func is_cleared() -> bool:
	return alive_members() == 0


func any_engaged() -> bool:
	for m in members:
		var e: EnemyBase = m["node"]
		if e != null and is_instance_valid(e) and e.is_alive() and e.in_combat():
			return true
	return false


## Spawns every living member through the director. Returns how many were spawned.
func activate(director: EncounterDirector) -> int:
	active = true
	var n := 0
	var patrol_pts := _patrol_points()
	var i := 0
	for m in members:
		i += 1
		if not bool(m["alive"]):
			continue
		var node: EnemyBase = m["node"]
		if node != null and is_instance_valid(node):
			continue
		var p: Vector3 = m["pos"]
		if kind == &"patrol" and not patrol_pts.is_empty():
			# March in file along the route from the group's current point.
			var k := (route_index + patrol_pts.size()) % patrol_pts.size()
			var base := patrol_pts[k]
			var nxt := patrol_pts[(k + 1) % patrol_pts.size()]
			var back := (base - nxt)
			back.y = 0.0
			back = back.normalized() if back.length_squared() > 1e-4 else Vector3.BACK
			p = base + back * 2.2 * (i - 1) + Vector3(-back.z, 0, back.x) * (0.8 if i % 2 == 0 else -0.8)
		p.y = WorldData.get_height(p.x, p.z)
		var xf := Transform3D(Basis(Vector3.UP, float(m["yaw"])), p)
		var opts := {"seed": int(m["seed"]), "level": int(m["level"]), "site_id": id, "leash": leash, "faction": faction}
		if kind == &"patrol" and not patrol_pts.is_empty():
			var mine := PackedVector3Array()
			var off := p - patrol_pts[route_index % patrol_pts.size()]
			off.y = 0.0
			for q in patrol_pts:
				var w := q + off
				w.y = WorldData.get_height(w.x, w.z)
				mine.append(w)
			opts["patrol"] = mine
			opts["leash"] = leash + 20.0
		var e := director.spawn_enemy(m["archetype"], xf, opts)
		if kind == &"patrol" and e.brain:
			e.brain.set_patrol_index(route_index + 1)
		m["node"] = e
		n += 1
	return n


## Despawns the living members (calm, far away): they come back on the next visit.
func deactivate(director: EncounterDirector) -> void:
	active = false
	for m in members:
		var e: EnemyBase = m["node"]
		if e != null and is_instance_valid(e):
			if kind == &"patrol" and e.brain:
				route_index = e.brain.get_patrol_index()
			director.enemies.erase(e)
			e.queue_free()
		m["node"] = null


func forget_node(e: EnemyBase) -> void:
	for m in members:
		if m["node"] == e:
			m["node"] = null


func mark_defeated(e: EnemyBase) -> void:
	for m in members:
		if m["node"] == e:
			m["alive"] = false


func mark_all_defeated() -> void:
	for m in members:
		m["alive"] = false


## Revives a cleared (or thinned) site once its respawn time passed, out of sight.
func tick_respawn(play_time: float, scale: float, unseen: bool) -> void:
	if alive_members() == members.size() or not unseen:
		return
	if cleared_at < 0.0:
		# Partially defeated groups refill after the same delay from the first loss.
		cleared_at = play_time
		return
	if play_time - cleared_at >= respawn_time * scale:
		for m in members:
			m["alive"] = true
		cleared_at = -1.0


## Far patrols keep moving along their route (no physics): advance the route index.
func advance_patrol(delta: float) -> void:
	for m in members:
		var e: EnemyBase = m["node"]
		if e != null and is_instance_valid(e) and e.dormant and e.is_alive():
			e.advance_dormant_patrol(delta)


## Ping-pong route as a loop: p0 .. pn .. p1.
func _patrol_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in route:
		out.append(q)
	for k in range(route.size() - 2, 0, -1):
		out.append(route[k])
	return out
