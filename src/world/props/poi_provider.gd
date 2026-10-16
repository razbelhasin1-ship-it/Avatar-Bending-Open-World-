class_name PoiProvider
extends ContentProvider
## Streams the structures of WorldData POIs (PoiStructures: shrines, ruins, enemy camps, training
## grounds, docks, vistas, spirit spots, resource sites, landmarks) in 256 m cells. Each POI is
## built twice on the worker - full detail (LOD0, ink outline, lights, collision) and a simplified
## LOD1 silhouette for distant views - and the two hand over with visibility ranges. Extras become
## nodes under the cell root: ResourcePickups, group markers (&"shrine", &"enemy_spawn",
## &"training_dummy", &"dock_berth", &"vista", &"spirit_spot", ...), ambient particles and sounds.
##
## POIs inside city footprints (settlement territory), village-type POIs and features of
## LandmarkProvider are skipped; another system can take over any POI with ContentClaims.claim(id).

var cfg: Dictionary = {}
var _by_cell: Dictionary = {}          # Vector2i -> Array[Dictionary] (immutable snapshot)
var _claims_version := -1
## Harvested pickups: key -> Time.get_ticks_msec() when they regrow (survives cell reloads).
static var harvested: Dictionary = {}


func _init() -> void:
	id = &"poi_structures"
	cell_size = 256.0
	priority = 8
	unload_margin = 80.0


func configure() -> bool:
	var c := PropSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["poi_range"])
	NationPalette.prepare_materials()
	_index()
	return changed


func tick() -> void:
	if ContentClaims.version != _claims_version:
		var before := _by_cell.hash()
		_index()
		if before != _by_cell.hash() and content:
			content.refresh(id)


func _index() -> void:
	_claims_version = ContentClaims.version
	var by := {}
	for poi in WorldData.get_pois():
		if ContentClaims.is_claimed(poi["id"]) or not PoiStructures.handles(poi):
			continue
		var p: Vector3 = poi["position"]
		var key := coord_of(p.x, p.z)
		if not by.has(key):
			by[key] = []
		(by[key] as Array).append(poi)
	_by_cell = by


func wants_cell(coord: Vector2i) -> bool:
	return _by_cell.has(coord)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var list: Array = _by_cell.get(cell.coord, [])
	var lod0 := float(cfg["poi_lod0"])
	var far := float(cfg["poi_range"]) + cell_size
	var shadows: bool = cfg["shadows"]
	var root := cell.origin()
	for poi: Dictionary in list:
		var full := PoiStructures.build(poi, 0)
		var t := Transform3D(Basis(), (full["origin"] as Vector3) - root)
		(full["kit"] as KitResult).add_to_payload(p, t, {"vis_end": lod0, "margin": 8.0, "shadow": shadows,
				"tag": StringName(String(poi["id"]))})
		var simple := PoiStructures.build(poi, 1)
		(simple["kit"] as KitResult).add_to_payload(p, t, {"vis_begin": lod0, "vis_end": far, "margin": 8.0,
				"shadow": false, "collision": false, "lights": false, "tag": StringName(String(poi["id"]) + "_lod1")})
		var extras: Array = full["extras"]
		if not extras.is_empty():
			var pid: StringName = poi["id"]
			p.add_call(func(c: ContentCell) -> void: _spawn_extras(c, pid, extras))
	cell.payload = p


## Main thread: pickups, markers, particles, sounds of one POI.
static func _spawn_extras(cell: ContentCell, poi_id: StringName, extras: Array) -> void:
	var root := cell.root
	var origin := cell.origin()
	var n := 0
	for e: Dictionary in extras:
		var pos: Vector3 = (e["position"] as Vector3) - origin
		match e["type"]:
			&"pickup":
				var key := "%s:%d" % [poi_id, n]
				n += 1
				var pk := ResourcePickup.create(e["item"], int(e.get("count", 1)), PropFx.pickup_mesh(e.get("mesh_kind", &"herb")), e["name"])
				pk.name = "Pickup%d" % n
				pk.position = pos
				pk.set_meta(&"harvest_key", key)
				root.add_child(pk)
				var left := int(harvested.get(key, 0)) - Time.get_ticks_msec()
				if left > 0:
					pk.start_regrow(left / 1000.0)
				pk.harvested.connect(func() -> void: harvested[key] = Time.get_ticks_msec() + int(pk.respawn_time * 1000.0))
			&"marker":
				root.add_child(PropFx.marker(e["group"], pos, float(e.get("yaw", 0.0)), {"poi": poi_id}))
			&"particles":
				var fx := PropFx.particles(e["kind"])
				fx.position = pos
				root.add_child(fx)
			&"sound":
				var id := Audio.play_loop(e["name"], null, float(e.get("db", -6.0)), 2.0, e["position"])
				if id > 0:
					cell.loops.append(id)
