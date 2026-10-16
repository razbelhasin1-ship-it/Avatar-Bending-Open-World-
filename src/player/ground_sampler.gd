class_name GroundSampler
extends RefCounted
## Surface / snow / water queries used by the player motor, bending (water
## sources, surface-aware VFX) and dev arenas.
##
## Everything forwards to WorldData, except inside registered *zones*: small
## rectangles that override the surface and snow depth. Dev scenes and tests
## use them to put an ice rink or deep snow on a flat test world:
##
##   GroundSampler.add_zone(&"rink", Rect2(-10, 4, 8, 8), &"ice", 0.0)
##   GroundSampler.surface(pos)      # &"ice" inside the rect, WorldData outside
##   GroundSampler.clear_zones()     # always clear them when the scene exits

## zone id -> {"rect": Rect2 (x, z), "surface": StringName, "snow": float}
static var _zones: Dictionary = {}


static func add_zone(id: StringName, rect_xz: Rect2, surface_name: StringName, snow_depth_m: float = 0.0) -> void:
	_zones[id] = {"rect": rect_xz, "surface": surface_name, "snow": snow_depth_m}


static func remove_zone(id: StringName) -> void:
	_zones.erase(id)


static func clear_zones() -> void:
	_zones.clear()


static func has_zones() -> bool:
	return not _zones.is_empty()


static func _zone_at(pos: Vector3) -> Dictionary:
	if _zones.is_empty():
		return {}
	var p := Vector2(pos.x, pos.z)
	for id: StringName in _zones:
		var z: Dictionary = _zones[id]
		if (z["rect"] as Rect2).has_point(p):
			return z
	return {}


## Surface material at a point (&"snow", &"ice", &"stone", &"grass", &"dirt", &"sand", &"water", &"ash", &"wood").
static func surface(pos: Vector3) -> StringName:
	var z := _zone_at(pos)
	if not z.is_empty():
		return z["surface"]
	return WorldData.get_surface(pos)


## Loose snow depth in meters at a point.
static func snow_depth(pos: Vector3) -> float:
	var z := _zone_at(pos)
	if not z.is_empty():
		return float(z["snow"])
	return WorldData.get_snow_depth(pos.x, pos.z)


## True on snow/ice (water benders skate there and can draw water from it).
static func is_frozen(pos: Vector3) -> bool:
	var s := surface(pos)
	return s == &"snow" or s == &"ice"


## Water surface height at x/z, or -INF.
static func water_height(pos: Vector3) -> float:
	return WorldData.get_water_height(pos.x, pos.z)


## Nearest bendable water within `radius` (WorldData.find_water_source + zones:
## snow/ice zones count as sources where you stand).
static func find_water_source(pos: Vector3, radius: float) -> Dictionary:
	var r := WorldData.find_water_source(pos, radius)
	if bool(r.get("found", false)):
		return r
	var z := _zone_at(pos)
	if not z.is_empty() and (z["surface"] == &"snow" or z["surface"] == &"ice"):
		return {"found": true, "position": Vector3(pos.x, WorldData.get_height(pos.x, pos.z), pos.z), "kind": z["surface"], "distance": 0.0}
	return r
