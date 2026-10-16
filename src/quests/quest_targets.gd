class_name QuestTargets
extends RefCounted
## Resolves world target specs used by quest objectives, dialogue `travel` actions, NPC
## placements and quest props to a world position (Vector3.INF when unknown).
##
##   {"poi": &"wt_ice_flats"}                 WorldData POI position
##   {"npc": &"wt_siku"}                      the live NPC (or its home placement)
##   {"anchor": {"settlement": &"northern_water_tribe", "kind": &"trainer", "tags": ["training_hall"]}}
##   {"site": &"wt_fire_navy_landing"}        encounter site centre (EncounterSites)
##   {"spawn": &"water"}                      an element's new-game spawn
##   {"port": &"port_water_tribe"}            a ferry port's quay
##   {"city": &"omashu"} / {"village": &"saltspark"}
##   {"pos": Vector3(...)}
## Any spec may add "offset": Vector3 (world axes) and "ground": true (snap y to WorldData).

static var _site_cache: Dictionary = {}
static var _anchor_cache: Dictionary = {}


static func resolve(spec: Variant) -> Vector3:
	if spec is Vector3:
		return spec
	if not (spec is Dictionary):
		return Vector3.INF
	var d: Dictionary = spec
	var p := Vector3.INF
	if d.has("pos"):
		p = d["pos"]
	elif d.has("npc"):
		p = NpcRegistry.position_of(StringName(str(d["npc"])))
	elif d.has("poi"):
		var poi := WorldData.get_poi(StringName(str(d["poi"])))
		if not poi.is_empty():
			p = to_vec3(poi.get("position"))
	elif d.has("anchor"):
		var a := find_anchor(d["anchor"])
		if not a.is_empty():
			p = a["position"]
	elif d.has("site"):
		p = site_center(StringName(str(d["site"])))
	elif d.has("spawn"):
		p = WorldData.get_spawn(ElementDefs.from_id(StringName(str(d["spawn"])))).origin
	elif d.has("port"):
		for port in WorldData.get_ports():
			if StringName(str(port.get("id", ""))) == StringName(str(d["port"])):
				p = TravelSystem.quay_transform(port).origin
				break
	elif d.has("city"):
		var c := WorldData.get_city(StringName(str(d["city"])))
		if not c.is_empty():
			p = to_vec3(c.get("center", c.get("position")))
	elif d.has("village"):
		for v in WorldData.get_villages():
			if StringName(str(v.get("id", ""))) == StringName(str(d["village"])):
				p = to_vec3(v.get("center", v.get("position")))
				break
	if not p.is_finite():
		return Vector3.INF
	if d.has("offset"):
		p += d["offset"] as Vector3
	if bool(d.get("ground", false)):
		p.y = WorldData.get_height(p.x, p.z)
	return p


## First settlement anchor matching {settlement, kind, tags (all must be present), index}.
## Cached per query (plans are deterministic for a world bake).
static func find_anchor(q: Variant) -> Dictionary:
	if not (q is Dictionary):
		return {}
	var qd: Dictionary = q
	var key := str(qd)
	if _anchor_cache.has(key):
		return _anchor_cache[key]
	var tags: Array = qd.get("tags", [])
	var matches: Array[Dictionary] = []
	for a in Settlements.get_anchors(StringName(str(qd.get("settlement", ""))), StringName(str(qd.get("kind", "")))):
		var at: Array = a.get("tags", [])
		var ok := true
		for t: Variant in tags:
			if not at.has(String(t)):
				ok = false
				break
		if ok:
			matches.append(a)
	var out: Dictionary = {}
	if not matches.is_empty():
		out = matches[clampi(int(qd.get("index", 0)), 0, matches.size() - 1)]
	_anchor_cache[key] = out
	return out


## Encounter site centre by id (the live director's site when present).
static func site_center(id: StringName) -> Vector3:
	var dir := EncounterDirector.instance()
	if dir != null:
		var s := dir.get_site(id)
		if s != null:
			return s.center
	if _site_cache.is_empty() and WorldData.has_world_data():
		for s2 in EncounterSites.build_all():
			_site_cache[s2.id] = s2.center
	return _site_cache.get(id, Vector3.INF)


static func clear_cache() -> void:
	_site_cache.clear()
	_anchor_cache.clear()


## Vector3 from a WorldData record field ([x, y, z] array, Vector3, or {x, y, z}).
static func to_vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if v is Array and (v as Array).size() == 2:
		var a2: Array = v
		return Vector3(float(a2[0]), WorldData.get_height(float(a2[0]), float(a2[1])), float(a2[1]))
	if v is Dictionary:
		var dv: Dictionary = v
		return Vector3(float(dv.get("x", 0.0)), float(dv.get("y", 0.0)), float(dv.get("z", 0.0)))
	return Vector3.INF
