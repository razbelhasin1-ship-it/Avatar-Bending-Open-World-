extends Node
## World queries (autoload "WorldData").
##
## Single source of truth for terrain height, biomes, surfaces, regions, water
## and points of interest. Gameplay code must use these queries instead of
## raycasting the terrain where possible (they work for unloaded areas too).
##
## FOUNDATION STUB: until the world module loads real data, this behaves like a
## flat grass plane at y = 0 so other systems can be developed and tested.

enum Biome { OCEAN, BEACH, SNOW, ICE, TUNDRA, GRASSLAND, FOREST, FARMLAND, ROCK, MOUNTAIN, VOLCANIC, ASH, TEMPLE, CITY }

const SEA_LEVEL := 0.0

var loaded: bool = false
## Optional override used by small test arenas: Callable(x, z) -> float.
var height_override: Callable = Callable()


## Loads world data (blocking). Safe to call repeatedly.
func load_world() -> void:
	loaded = true
	Events.world_ready.emit()


func is_loaded() -> bool:
	return loaded


## World bounds in meters (x/z min, size).
func get_bounds() -> Rect2:
	return Rect2(-4096.0, -4096.0, 8192.0, 8192.0)


func get_height(x: float, z: float) -> float:
	if height_override.is_valid():
		return height_override.call(x, z)
	return 0.0


func get_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var hx := get_height(x + e, z) - get_height(x - e, z)
	var hz := get_height(x, z + e) - get_height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func get_biome(_x: float, _z: float) -> int:
	return Biome.GRASSLAND


## Surface material for footsteps/VFX: &"snow", &"ice", &"stone", &"grass",
## &"dirt", &"sand", &"wood", &"water", &"ash".
func get_surface(pos: Vector3) -> StringName:
	match get_biome(pos.x, pos.z):
		Biome.SNOW, Biome.TUNDRA: return &"snow"
		Biome.ICE: return &"ice"
		Biome.BEACH: return &"sand"
		Biome.ROCK, Biome.MOUNTAIN, Biome.TEMPLE, Biome.CITY: return &"stone"
		Biome.VOLCANIC, Biome.ASH: return &"ash"
		Biome.FARMLAND: return &"dirt"
	return &"grass"


## Depth of loose snow at a point in meters (0 if none).
func get_snow_depth(x: float, z: float) -> float:
	var b := get_biome(x, z)
	return 0.35 if b == Biome.SNOW else (0.15 if b == Biome.TUNDRA else 0.0)


## Region id: &"water_tribe", &"earth_kingdom", &"fire_nation", &"air_temple",
## &"wilds" (between nations) or &"ocean".
func get_region(_x: float, _z: float) -> StringName:
	return &"wilds"


func get_region_name(region_id: StringName) -> String:
	match region_id:
		&"water_tribe": return "Northern Water Tribe"
		&"earth_kingdom": return "Earth Kingdom"
		&"fire_nation": return "Fire Nation"
		&"air_temple": return "Southern Air Temple"
		&"ocean": return "Open Sea"
	return "The Wilds"


## Water surface height at x/z, or -INF if there is no water there.
func get_water_height(x: float, z: float) -> float:
	return SEA_LEVEL if get_height(x, z) < SEA_LEVEL else -INF


func is_underwater(pos: Vector3) -> bool:
	return pos.y < get_water_height(pos.x, pos.z)


## Nearest bendable water source within `radius`.
## Returns {"found": bool, "position": Vector3, "kind": &"water"|&"snow"|&"ice"|&"source"}.
## Snow/ice biomes count as sources everywhere; sea/lakes/rivers/fountains count
## within range. Registered sources (fountains, canals) are included.
func find_water_source(pos: Vector3, radius: float) -> Dictionary:
	var best := {"found": false, "position": pos, "kind": &""}
	var best_d := INF
	for s: Dictionary in _sources:
		var d := (s["position"] as Vector3).distance_to(pos)
		if d <= radius + float(s.get("radius", 0.0)) and d < best_d:
			best_d = d
			best = {"found": true, "position": s["position"], "kind": s.get("kind", &"source")}
	if best["found"]:
		return best
	var surf := get_surface(pos)
	if surf == &"snow" or surf == &"ice":
		return {"found": true, "position": Vector3(pos.x, get_height(pos.x, pos.z), pos.z), "kind": surf}
	return best


var _sources: Array[Dictionary] = []


## Registers a bendable water source (fountain, canal, pond). Returns an id.
func register_water_source(position: Vector3, radius: float, kind: StringName = &"water") -> int:
	_sources.append({"position": position, "radius": radius, "kind": kind, "id": _sources.size()})
	return _sources.size() - 1


func clear_water_sources() -> void:
	_sources.clear()


## Points of interest: Array of {"id", "name", "type", "region", "position": Vector3, "radius"}.
func get_pois() -> Array[Dictionary]:
	return []


func get_poi(_poi_id: StringName) -> Dictionary:
	return {}


## Spawn transform for a new game of the given element (home region).
func get_spawn(_element: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(0, get_height(0, 0) + 1.0, 0))


## Safe ground position near `pos` (above terrain, not in water). Used for
## respawning and unsticking companions.
func get_safe_ground(pos: Vector3) -> Vector3:
	return Vector3(pos.x, get_height(pos.x, pos.z) + 0.2, pos.z)
