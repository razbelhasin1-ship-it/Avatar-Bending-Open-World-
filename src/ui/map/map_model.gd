class_name MapModel
extends RefCounted
## Data behind the world map (no UI): map <-> world coordinates, every place the map can show
## (cities, villages, ports, points of interest) with whether the player knows it, fast-travel
## points and their guard rails, hand-placed region / sea lettering, and the explored-area
## mask ("map reveal": the world loop's "discover POIs -> map reveal").
##
##   MapModel.world_to_uv(pos) / uv_to_world(uv)       # WorldData.world_to_map_uv contract
##   MapModel.places()                                 # [{id, kind, type, name, region, position, radius, description, known, travel}]
##   MapModel.travel_block_reason(place)               # "" or why fast travel is refused
##   MapModel.travel_transform(place)                  # where the player lands
##   MapModel.note_position(pos)                       # visits + reveal (the progression hook, 1 Hz)
##   MapModel.reveal_image()                           # L8 128x128 explored mask for the map shader
##
## State lives in GameState.world_flags (saved with no extra code):
##   "visited_places": {place_id: true}      cities / villages / ports the player walked into
##   "map_reveal": base64 bitset (128 x 128 cells of 64 m, row-major north -> south)

const REVEAL_N := 128
const CELL_M := 8192.0 / 128.0
const WALK_REVEAL_M := 320.0
const POI_REVEAL_M := 260.0
## Fast travel needs at least this distance to the destination.
const MIN_TRAVEL_M := 60.0

## Place types that are fast-travel points once known.
const TRAVEL_KINDS: Array[StringName] = [&"city", &"village", &"port"]
const TRAVEL_POI_TYPES: Array[StringName] = [&"shrine", &"training_ground", &"village", &"dock"]

const POI_ICONS := {
	&"shrine": "map_shrine", &"ruin": "map_ruin", &"cave": "map_cave", &"training_ground": "map_training",
	&"landmark": "map_landmark", &"vista": "map_vista", &"spirit_spot": "map_spirit", &"camp": "map_camp",
	&"resource": "map_resource", &"waterfall": "map_waterfall", &"dock": "map_port", &"village": "map_village",
	&"bridge": "map_bridge",
}
const TYPE_NAMES := {
	&"shrine": "Shrine", &"ruin": "Ruin", &"cave": "Cave", &"training_ground": "Training Ground", &"landmark": "Landmark",
	&"vista": "Vista", &"spirit_spot": "Spirit Place", &"camp": "Camp", &"resource": "Resource", &"waterfall": "Waterfall",
	&"dock": "Harbour", &"village": "Village", &"bridge": "Bridge", &"capital": "Capital", &"city": "City", &"town": "Town",
	&"temple": "Temple", &"port": "Ferry Port", &"port_town": "Port Town", &"farming_village": "Farming Village",
	&"forest_village": "Forest Village", &"fishing_village": "Fishing Village", &"tea_village": "Tea Village",
	&"resort": "Resort", &"camp_village": "Camp",
}

## Hand-lettered region / sea names: world (x, z), size class and the brush seal glyph.
const LETTERING: Array[Dictionary] = [
	{"text": "NORTHERN WATER TRIBE", "pos": Vector2(900, -3560), "size": 46, "kind": &"region", "region": &"water_tribe", "glyph": "水", "city": &"northern_water_tribe"},
	{"text": "EARTH KINGDOM", "pos": Vector2(700, 1250), "size": 58, "kind": &"region", "region": &"earth_kingdom", "glyph": "土"},
	{"text": "FIRE NATION", "pos": Vector2(-2780, 600), "size": 50, "kind": &"region", "region": &"fire_nation", "glyph": "火"},
	{"text": "SOUTHERN AIR TEMPLE", "pos": Vector2(2620, 2700), "size": 34, "kind": &"region", "region": &"air_temple", "glyph": "气", "city": &"southern_air_temple"},
	{"text": "THE FROZEN STRAIT", "pos": Vector2(1500, -2000), "size": 22, "kind": &"wilds", "region": &"wilds", "glyph": ""},
	{"text": "The Northern Sea", "pos": Vector2(-2500, -1950), "size": 30, "kind": &"sea", "region": &"ocean", "glyph": ""},
	{"text": "The Western Sea", "pos": Vector2(-3300, -500), "size": 26, "kind": &"sea", "region": &"ocean", "glyph": ""},
	{"text": "Mo Ce Sea", "pos": Vector2(-600, 3350), "size": 30, "kind": &"sea", "region": &"ocean", "glyph": ""},
	{"text": "The Eastern Sea", "pos": Vector2(3500, -2010), "size": 22, "kind": &"sea", "region": &"ocean", "glyph": ""},
]

## Tests: replace the fast-travel call (Callable(xform: Transform3D, opts: Dictionary) -> bool).
static var travel_override: Callable
## Tests: force the combat guard (-1 = live EncounterDirector state, 0 = calm, 1 = in combat).
static var combat_override := -1

static var _places: Array[Dictionary] = []
static var _places_ready := false
static var _reveal_cache: PackedByteArray = PackedByteArray()
static var _reveal_key := ""


# --- coordinates ----------------------------------------------------------------------------------

static func world_to_uv(pos: Vector3) -> Vector2:
	return WorldData.world_to_map_uv(pos)


static func uv_to_world(uv: Vector2) -> Vector3:
	return WorldData.map_uv_to_world(uv)


static func xz_to_uv(xz: Vector2) -> Vector2:
	return WorldData.world_to_map_uv(Vector3(xz.x, 0.0, xz.y))


# --- places --------------------------------------------------------------------------------------

## Every place the map knows about (static list, cached). `known` / `travel` are live: use
## is_known(p) / is_travel_point(p) for the current state.
static func places() -> Array[Dictionary]:
	if _places_ready and not _places.is_empty():
		return _places
	_places_ready = true
	_places.clear()
	var poi_ids := {}
	for c: Dictionary in WorldData.get_cities():
		_places.append({"id": StringName(c.get("id", &"")), "kind": &"city", "type": StringName(c.get("kind", &"city")),
			"name": String(c.get("name", "")), "region": StringName(c.get("region", &"")), "position": c.get("center", Vector3.ZERO),
			"radius": float(c.get("radius", 200.0)), "description": "", "icon": "map_city"})
	for v: Dictionary in WorldData.get_villages():
		var vid := StringName(v.get("id", &""))
		_places.append({"id": vid, "kind": &"village", "type": StringName(v.get("kind", &"village")), "name": String(v.get("name", "")),
			"region": StringName(v.get("region", &"")), "position": v.get("center", Vector3.ZERO), "radius": float(v.get("radius", 80.0)),
			"description": "", "icon": "map_village" if StringName(v.get("kind", &"")) != &"camp" else "map_camp"})
	for pt: Dictionary in WorldData.get_ports():
		_places.append({"id": StringName(pt.get("id", &"")), "kind": &"port", "type": &"port", "name": String(pt.get("name", "")),
			"region": StringName(pt.get("region", &"")), "position": pt.get("quay", Vector3.ZERO), "radius": 40.0,
			"description": "", "icon": "map_port", "settlement": StringName(pt.get("settlement", &""))})
	for p: Dictionary in WorldData.get_pois():
		var pid := StringName(p.get("id", &""))
		poi_ids[pid] = true
		var t := StringName(p.get("type", &"landmark"))
		_places.append({"id": pid, "kind": &"poi", "type": t, "name": String(p.get("name", "")), "region": StringName(p.get("region", &"")),
			"position": p.get("position", Vector3.ZERO), "radius": float(p.get("radius", 20.0)),
			"description": String(p.get("description", "")), "icon": String(POI_ICONS.get(t, "map_landmark"))})
	return _places


static func place_by_id(id: StringName) -> Dictionary:
	for p in places():
		if p["id"] == id:
			return p
	return {}


## The POI that stands for a village / port record (same spot), if any.
static func _twin_poi(p: Dictionary) -> Dictionary:
	var best := {}
	var best_d := 140.0
	for q in places():
		if q["kind"] != &"poi" or (q["type"] != &"village" and q["type"] != &"dock"):
			continue
		var d := (q["position"] as Vector3).distance_to(p["position"])
		if d < best_d:
			best_d = d
			best = q
	return best


## Whether the player knows a place (it is shown with its name / can be travelled to).
static func is_known(p: Dictionary) -> bool:
	if p.is_empty():
		return false
	var visited: Dictionary = GameState.get_flag("visited_places", {}) if GameState.get_flag("visited_places", {}) is Dictionary else {}
	match p["kind"]:
		&"poi":
			return GameState.discovered_pois.has(String(p["id"]))
		&"city":
			if visited.has(String(p["id"])):
				return true
			return StringName(p["id"]) == home_city_id()
		&"village", &"port":
			if visited.has(String(p["id"])):
				return true
			var twin := _twin_poi(p)
			if not twin.is_empty() and GameState.discovered_pois.has(String(twin["id"])):
				return true
			if p["kind"] == &"port":
				var sid := StringName(p.get("settlement", &""))
				return visited.has(String(sid)) or sid == home_city_id()
	return false


## Cities are famous: always lettered on the map even before a visit (travel needs a visit).
static func is_lettered(p: Dictionary) -> bool:
	return p["kind"] == &"city" or is_known(p)


static func is_travel_point(p: Dictionary) -> bool:
	if p.is_empty():
		return false
	if p["kind"] in TRAVEL_KINDS:
		return true
	return p["kind"] == &"poi" and p["type"] in TRAVEL_POI_TYPES


static func type_name(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	return String(TYPE_NAMES.get(StringName(p.get("type", &"")), String(p.get("type", "")).capitalize()))


## The home city of the journey's element (where a new game starts).
static func home_city_id() -> StringName:
	match GameState.element:
		ElementDefs.Element.WATER: return &"northern_water_tribe"
		ElementDefs.Element.EARTH: return &"ba_sing_se"
		ElementDefs.Element.FIRE: return &"fire_nation_capital"
		ElementDefs.Element.AIR: return &"southern_air_temple"
	return &""


## Known fast-travel destinations.
static func travel_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in places():
		if is_travel_point(p) and is_known(p):
			out.append(p)
	return out


# --- fast travel ---------------------------------------------------------------------------------

static func in_combat() -> bool:
	if combat_override >= 0:
		return combat_override == 1
	var d := EncounterDirector.instance()
	return d != null and d.in_combat


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func world_scene() -> Node:
	var t := _tree()
	return t.get_first_node_in_group(&"world_scene") if t else null


static func _player() -> Node3D:
	var t := _tree()
	return t.get_first_node_in_group(&"player") as Node3D if t else null


## "" when the player may fast travel to `p` now, else a short reason for the map card.
static func travel_block_reason(p: Dictionary) -> String:
	if p.is_empty() or not is_travel_point(p):
		return "Not a place you can travel to."
	if not is_known(p):
		return "Discover this place first."
	if GameState.is_tutorial:
		return "Not in the training grounds."
	if in_combat():
		return "Not while enemies are near."
	var pl := _player()
	if pl != null:
		if pl.has_method("is_alive") and not bool(pl.call("is_alive")):
			return "Not now."
		if pl.global_position.distance_to(p["position"]) < MIN_TRAVEL_M:
			return "You are already here."
	if not travel_override.is_valid():
		var w := world_scene()
		var tr: Variant = w.get("travel") if w != null else null
		if not (tr is TravelSystem):
			return "Fast travel is not available here."
		if (tr as TravelSystem).busy:
			return "Already travelling."
	return ""


## Where the player stands after travelling to `p` (on dry, walkable ground facing inland).
static func travel_transform(p: Dictionary) -> Transform3D:
	match p["kind"]:
		&"city":
			for e: int in ElementDefs.ALL:
				if _home_of(e) == p["id"]:
					return WorldData.get_spawn(e)
			var c := WorldData.get_city(p["id"])
			var gates: Array = c.get("gates", [])
			if not gates.is_empty():
				var g: Dictionary = gates[0]
				var gp: Vector3 = g.get("position", p["position"])
				var center: Vector3 = p["position"]
				var out := Vector3(gp.x - center.x, 0, gp.z - center.z).normalized()
				var spot := WorldData.get_safe_ground(gp + out * 24.0)
				return Transform3D(Basis.looking_at(-out, Vector3.UP), spot)
		&"port":
			return TravelSystem.quay_transform(TravelSystem.port_by_id(p["id"]))
	var at := WorldData.get_safe_ground(p["position"] + Vector3(0, 0, 6.0))
	var toward := (p["position"] as Vector3) - at
	toward.y = 0.0
	var basis := Basis.looking_at(toward.normalized(), Vector3.UP) if toward.length() > 0.5 else Basis()
	return Transform3D(basis, at)


static func _home_of(e: int) -> StringName:
	match e:
		ElementDefs.Element.WATER: return &"northern_water_tribe"
		ElementDefs.Element.EARTH: return &"ba_sing_se"
		ElementDefs.Element.FIRE: return &"fire_nation_capital"
		ElementDefs.Element.AIR: return &"southern_air_temple"
	return &""


## Fast travel through the world scene's TravelSystem (or `travel_override`). Returns success.
static func travel(p: Dictionary) -> bool:
	if travel_block_reason(p) != "":
		return false
	var xf := travel_transform(p)
	var opts := {"text": "Travelling to %s" % String(p["name"])}
	if travel_override.is_valid():
		return bool(await travel_override.call(xf, opts))
	var w := world_scene()
	var tr := w.get("travel") as TravelSystem
	var ok: bool = await tr.travel_to(xf, opts)
	if ok:
		GameState.incr_stat("fast_travels")
		note_position(xf.origin)
	return ok


# --- visits + reveal -----------------------------------------------------------------------------

## Records where the player is: cities / villages / ports walked into, and the explored mask.
## Cheap (called at 1 Hz by the progression hook).
static func note_position(pos: Vector3) -> void:
	if not pos.is_finite() or not GameState.has_element() or GameState.is_tutorial:
		return
	var visited: Dictionary = GameState.get_flag("visited_places", {}) if GameState.get_flag("visited_places", {}) is Dictionary else {}
	var changed := false
	for p in places():
		if p["kind"] == &"poi":
			continue
		var r := float(p["radius"]) + (30.0 if p["kind"] == &"port" else 0.0)
		var d := Vector2(pos.x - (p["position"] as Vector3).x, pos.z - (p["position"] as Vector3).z).length()
		if d <= r and not visited.has(String(p["id"])):
			visited[String(p["id"])] = true
			changed = true
	if changed:
		GameState.set_flag("visited_places", visited)
	reveal(pos, WALK_REVEAL_M)


## Marks the explored mask around `pos`. Returns true if anything new was revealed.
static func reveal(pos: Vector3, radius: float) -> bool:
	var bits := _bits()
	var uv := world_to_uv(pos)
	var cx := uv.x * REVEAL_N
	var cy := uv.y * REVEAL_N
	var rc := radius / CELL_M
	var any := false
	for y in range(maxi(0, int(cy - rc - 1)), mini(REVEAL_N, int(cy + rc + 2))):
		for x in range(maxi(0, int(cx - rc - 1)), mini(REVEAL_N, int(cx + rc + 2))):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() > rc:
				continue
			var i := y * REVEAL_N + x
			var byte := i >> 3
			var mask := 1 << (i & 7)
			if (bits[byte] & mask) == 0:
				bits[byte] = bits[byte] | mask
				any = true
	if any:
		_store_bits(bits)
	return any


static func is_revealed(pos: Vector3) -> bool:
	var uv := world_to_uv(pos)
	var x := clampi(int(uv.x * REVEAL_N), 0, REVEAL_N - 1)
	var y := clampi(int(uv.y * REVEAL_N), 0, REVEAL_N - 1)
	var i := y * REVEAL_N + x
	return (_bits()[i >> 3] & (1 << (i & 7))) != 0


## Fraction of the world's land cells explored (0..1) - shown on the map legend.
static func revealed_ratio() -> float:
	var bits := _bits()
	var n := 0
	for b in bits:
		var v := b
		while v:
			n += v & 1
			v >>= 1
	return float(n) / float(REVEAL_N * REVEAL_N)


## Seeds the mask for a journey that has none yet (new game, older saves): the home city,
## every discovered POI, every visited place and the current position.
static func ensure_seeded(player_pos: Vector3 = Vector3.INF) -> void:
	if String(GameState.get_flag("map_reveal", "")) != "":
		return
	_store_bits(_empty_bits())
	var home := place_by_id(home_city_id())
	if not home.is_empty():
		reveal(home["position"], float(home["radius"]) + 420.0)
	for id: Variant in GameState.discovered_pois:
		var p := WorldData.get_poi(StringName(str(id)))
		if not p.is_empty():
			reveal(p["position"], POI_REVEAL_M)
	var visited: Variant = GameState.get_flag("visited_places", {})
	if visited is Dictionary:
		for id: Variant in visited:
			var q := place_by_id(StringName(str(id)))
			if not q.is_empty():
				reveal(q["position"], float(q["radius"]) + 200.0)
	if player_pos.is_finite():
		reveal(player_pos, WALK_REVEAL_M)


## L8 image of the mask (255 = explored) for the map shader.
static func reveal_image() -> Image:
	var bits := _bits()
	var data := PackedByteArray()
	data.resize(REVEAL_N * REVEAL_N)
	for i in REVEAL_N * REVEAL_N:
		data[i] = 255 if (bits[i >> 3] & (1 << (i & 7))) != 0 else 0
	return Image.create_from_data(REVEAL_N, REVEAL_N, false, Image.FORMAT_L8, data)


static func _empty_bits() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(REVEAL_N * REVEAL_N / 8)
	b.fill(0)
	return b


static func _bits() -> PackedByteArray:
	var s := String(GameState.get_flag("map_reveal", ""))
	if s == _reveal_key and not _reveal_cache.is_empty():
		return _reveal_cache
	var b := Marshalls.base64_to_raw(s) if s != "" else PackedByteArray()
	if b.size() != REVEAL_N * REVEAL_N / 8:
		b = _empty_bits()
	_reveal_cache = b
	_reveal_key = s
	return b


static func _store_bits(b: PackedByteArray) -> void:
	var s := Marshalls.raw_to_base64(b)
	GameState.set_flag("map_reveal", s)
	_reveal_cache = b
	_reveal_key = s


# --- lettering + routes --------------------------------------------------------------------------

## Ferry routes for the map: [{id, from, to, name, points: PackedVector2Array (x, z)}].
static func ferry_routes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in WorldData.get_ferries():
		var a := TravelSystem.port_by_id(StringName(f.get("from", &"")))
		var b := TravelSystem.port_by_id(StringName(f.get("to", &"")))
		out.append({"id": f.get("id", &""), "from": f.get("from", &""), "to": f.get("to", &""), "points": f.get("points", PackedVector2Array()),
			"name": "%s  -  %s" % [String(a.get("name", "?")), String(b.get("name", "?"))]})
	return out


## Distance text ("420 m", "3.2 km").
static func distance_text(m: float) -> String:
	if m < 1000.0:
		return "%d m" % int(round(m / 10.0) * 10.0)
	return "%.1f km" % (m / 1000.0)


## Compass direction of `to` seen from `from` ("north-east").
static func bearing_text(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 1.0:
		return ""
	var b := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(b / 45.0)) % 8]
