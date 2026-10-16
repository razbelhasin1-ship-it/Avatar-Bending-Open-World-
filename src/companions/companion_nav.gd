class_name CompanionNav
extends RefCounted
## Terrain-aware placement queries for companions (no navmesh across the 8 km world):
## ground height (physics first, WorldData fallback), walkability (slope, water, open
## space), safe spots near the player (preferably out of the camera's view), landing spots
## for flyers and burrow targets. Static helpers; `space` is the caller's
## PhysicsDirectSpaceState3D (null = WorldData only).

const UP := Vector3.UP


## Ground height under `p`: a ray on Layers.SOLID from `p.y + up` down `down` m, else the
## WorldData terrain height. `exclude` = RIDs to ignore.
static func ground_y(space: PhysicsDirectSpaceState3D, p: Vector3, up: float = 3.0, down: float = 12.0, exclude: Array[RID] = []) -> float:
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(p + UP * up, p - UP * down, Layers.SOLID, exclude)
		var r := space.intersect_ray(q)
		if not r.is_empty():
			return (r["position"] as Vector3).y
	return WorldData.get_height(p.x, p.z)


## True when a physics ray finds something solid below `p` within `down` m.
static func has_floor(space: PhysicsDirectSpaceState3D, p: Vector3, down: float = 60.0, exclude: Array[RID] = []) -> bool:
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(p + UP * 0.5, p - UP * down, Layers.SOLID, exclude)
	return not space.intersect_ray(q).is_empty()


## Terrain or water surface height (what a flyer must stay above).
static func surface_y(x: float, z: float) -> float:
	return maxf(WorldData.get_height(x, z), WorldData.get_water_height(x, z))


## Water depth over the terrain at x/z (0 when dry).
static func water_depth(x: float, z: float) -> float:
	var w := WorldData.get_water_height(x, z)
	if not is_finite(w):
		return 0.0
	return maxf(0.0, w - WorldData.get_height(x, z))


## Walkable ground at x/z for a creature: slope below `max_slope`, no deep water.
static func walkable(x: float, z: float, max_slope: float, max_water: float = 0.6) -> bool:
	if not WorldData.get_bounds().has_point(Vector2(x, z)):
		return false
	if WorldData.get_slope_deg(x, z) > max_slope:
		return false
	return water_depth(x, z) <= max_water


## Flat enough over a disc of `radius` (landing, burrow exits): checks 7 samples.
static func flat_area(x: float, z: float, radius: float, max_slope: float, max_step: float = 1.2) -> bool:
	if not walkable(x, z, max_slope, 0.15):
		return false
	var h0 := WorldData.get_height(x, z)
	for k in 6:
		var a := TAU * float(k) / 6.0
		var sx := x + cos(a) * radius
		var sz := z + sin(a) * radius
		if absf(WorldData.get_height(sx, sz) - h0) > max_step or water_depth(sx, sz) > 0.15:
			return false
	return true


## Nothing solid overlaps a sphere of `radius` resting on `ground` (no trees, walls, rocks).
static func open_space(space: PhysicsDirectSpaceState3D, ground: Vector3, radius: float, exclude: Array[RID] = []) -> bool:
	if space == null:
		return true
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	# Raised enough that a walkable slope under it does not count as an obstacle.
	params.transform = Transform3D(Basis.IDENTITY, ground + UP * (radius * 1.6 + 0.4))
	params.collision_mask = Layers.SOLID
	params.exclude = exclude
	return space.intersect_shape(params, 1).is_empty()


## Clear line between two points (walls, buildings, terrain ridges).
static func clear_line(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, exclude: Array[RID] = []) -> bool:
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, Layers.SOLID, exclude)
	return space.intersect_ray(q).is_empty()


## A safe place to put a creature of `radius` near `center` (the player): on walkable, dry,
## open ground with a clear line to the player, at `dist_min..dist_max`. Candidates behind
## `view_dir` (the camera's view) score best so a teleport happens off-screen. Returns
## Vector3.INF when nothing fits (caller falls back to WorldData.get_safe_ground).
static func find_spot_near(space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, max_slope: float,
		dist_min: float, dist_max: float, view_dir: Vector3 = Vector3.ZERO, exclude: Array[RID] = []) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	var vd := Vector3(view_dir.x, 0.0, view_dir.z)
	if vd.length_squared() > 1e-4:
		vd = vd.normalized()
	var rings := 3
	for ring in rings:
		var dist := lerpf(dist_min, dist_max, float(ring) / float(maxi(rings - 1, 1)))
		for k in 12:
			var a := TAU * float(k) / 12.0 + float(ring) * 0.26
			var dir := Vector3(sin(a), 0.0, cos(a))
			var p := center + dir * dist
			if not walkable(p.x, p.z, max_slope, 0.2):
				continue
			var gy := ground_y(space, Vector3(p.x, maxf(center.y, WorldData.get_height(p.x, p.z)) + 2.0, p.z), 4.0, 30.0, exclude)
			var g := Vector3(p.x, gy, p.z)
			if absf(gy - WorldData.get_height(p.x, p.z)) > 3.0 and absf(gy - center.y) > 6.0:
				continue   # on a roof / in a pit
			var score := -dist * 0.05
			if vd != Vector3.ZERO:
				score += -dir.dot(vd) * 2.0   # behind the camera's view = off-screen
			score += -absf(gy - center.y) * 0.15
			if score <= best_score:
				continue
			if not open_space(space, g, radius * 0.9, exclude):
				continue
			if not clear_line(space, center + UP * 1.2, g + UP * minf(radius + 0.5, 2.0), exclude):
				continue
			best_score = score
			best = g
	return best


## Landing spot for a flyer near `near` (flat disc of `radius`, dry, open sky above).
static func find_landing_spot(space: PhysicsDirectSpaceState3D, near: Vector3, radius: float, max_slope: float,
		search: float = 18.0, exclude: Array[RID] = []) -> Vector3:
	var tries: Array[Vector3] = [near]
	for ring in 3:
		var r := search * float(ring + 1) / 3.0
		for k in 8:
			var a := TAU * float(k) / 8.0 + float(ring) * 0.4
			tries.append(near + Vector3(sin(a), 0.0, cos(a)) * r)
	var step := radius * tan(deg_to_rad(max_slope)) + 0.3
	for p in tries:
		if not flat_area(p.x, p.z, radius, max_slope, step):
			continue
		var top := WorldData.get_height(p.x, p.z) + 60.0
		var gy := ground_y(space, Vector3(p.x, top, p.z), 0.0, 90.0, exclude)
		if absf(gy - WorldData.get_height(p.x, p.z)) > 1.5:
			continue   # a roof, a tree or a structure: not here
		var g := Vector3(p.x, gy, p.z)
		if open_space(space, g, radius, exclude):
			return g
	return Vector3.INF


## Valid burrow exit on the line from `from` toward `to` (walkable, dry, open), stepping
## back from `to` in 3 m steps. Vector3.INF when none.
static func burrow_exit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, radius: float, max_slope: float,
		exclude: Array[RID] = []) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := flat.length()
	if length < 4.0:
		return Vector3.INF
	var dir := flat / length
	var d := length
	while d >= 6.0:
		var p := from + dir * d
		if walkable(p.x, p.z, max_slope, 0.05):
			var gy := ground_y(space, Vector3(p.x, WorldData.get_height(p.x, p.z) + 2.0, p.z), 4.0, 12.0, exclude)
			var g := Vector3(p.x, gy, p.z)
			if absf(gy - WorldData.get_height(p.x, p.z)) < 1.0 and open_space(space, g, radius * 0.8, exclude):
				return g
		d -= 3.0
	return Vector3.INF


## Closest distance from point `p` to the segment a-b.
static func segment_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func flat_dir(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.ZERO


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))
