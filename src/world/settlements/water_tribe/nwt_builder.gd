class_name NwtBuilder
extends SettlementBuilder
## Recipe dispatcher of the Northern Water Tribe and the arctic villages (thread-safe). Piece
## kinds map to the recipe libraries:
##   NwtHomes      dome_home block_house tower_house warehouse noble_house igloo hide_tent
##   NwtProps      stall fish_rack crates lamp_post brazier banner_pole sculpture bench canoe ship mooring
##                 fire_pit ice_hole
##   NwtCivic      tier_wall grand_stair canal_bridge pier plaza gateway
##   NwtLandmarks  sea_wall sea_tower sea_gate palace land_gate city_tower
##   NwtPlaces     healer_hut training_hall family_home oasis canal_fall
##   BuildingPresets.wt_hall  (council / guild halls)
## Extras: the Spirit Oasis plants (VegetationLibrary MultiMeshes), the two koi, its warm light
## and spirit motes; animated water sheets, foam, mist and sound of the canal falls.

const HOMES: Array[StringName] = [&"dome_home", &"block_house", &"tower_house", &"warehouse", &"noble_house", &"igloo", &"hide_tent"]
const PROPS: Array[StringName] = [&"stall", &"fish_rack", &"crates", &"lamp_post", &"brazier", &"banner_pole", &"sculpture",
	&"bench", &"canoe", &"ship", &"mooring", &"fire_pit", &"ice_hole"]
const CIVIC: Array[StringName] = [&"tier_wall", &"grand_stair", &"canal_bridge", &"pier", &"plaza", &"gateway"]
const LANDMARKS: Array[StringName] = [&"sea_wall", &"sea_tower", &"sea_gate", &"palace", &"land_gate", &"city_tower"]
const PLACES: Array[StringName] = [&"healer_hut", &"training_hall", &"family_home", &"oasis", &"canal_fall"]


func _init(p_plan: SettlementPlan = null) -> void:
	super(p_plan)
	nation = &"water_tribe"


func build_piece(kit: BuildingKit, piece: Dictionary) -> void:
	var kind: StringName = piece["kind"]
	var spec: Dictionary = piece["spec"]
	if HOMES.has(kind):
		NwtHomes.build(kit, kind, int(spec.get("v", 0)))
	elif PROPS.has(kind):
		NwtProps.build(kit, kind, int(spec.get("v", 0)), spec)
	elif CIVIC.has(kind):
		NwtCivic.build(kit, kind, spec)
	elif LANDMARKS.has(kind):
		NwtLandmarks.build(kit, kind, spec)
	elif PLACES.has(kind):
		NwtPlaces.build(kit, kind, spec)
	elif kind == &"wt_hall":
		BuildingPresets.wt_hall(kit, Transform3D(), spec)


func piece_extras(piece: Dictionary) -> Array:
	var out: Array = []
	var pos: Vector3 = piece["pos"]
	var basis := Basis(Vector3.UP, float(piece["yaw"]))
	match piece["kind"]:
		&"oasis":
			var spec: Dictionary = piece["spec"]
			var pond := float(spec.get("pond", 10.5))
			var level := float(spec.get("level", pos.y - 0.35))
			var items := _oasis_plants(piece)
			out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
				return SettlementFx.vegetation_node(items, cell.origin())})
			var koi_at := Vector3(pos.x, level, pos.z)
			out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
				var k := SpiritKoi.new()
				k.position = koi_at - cell.origin()
				k.radius = minf(pond * 0.42, 4.2)
				return k})
			var light_at := pos + Vector3(0, 5.0, 0)
			out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
				return SettlementFx.warm_light(light_at - cell.origin(), Color(1.0, 0.86, 0.62), 26.0, 1.4)})
			out.append({"type": &"particles", "kind": &"motes", "position": pos + Vector3(0, 2.0, 0)})
		&"canal_fall":
			var dir := basis * Vector3.FORWARD
			out.append({"type": &"particles", "kind": &"steam", "position": pos + dir * 4.0 - Vector3(0, float(piece["spec"].get("drop", 14.2)) - 0.5, 0)})
			out.append({"type": &"sound", "name": &"amb_rain", "position": pos + dir * 3.0 - Vector3(0, 10.0, 0), "db": -10.0})
	return out


## Animated water of the canal falls: two layered sheets + plunge foam (shared shader materials
## prepared on the main thread by SettlementFx.prepare). WORKER THREAD.
func piece_payload(piece: Dictionary, p: CellPayload, origin: Vector3) -> void:
	if piece["kind"] != &"canal_fall":
		return
	var spec: Dictionary = piece["spec"]
	var top: Vector3 = piece["pos"]
	var dir := Basis(Vector3.UP, float(piece["yaw"])) * Vector3.FORWARD
	var drop := float(spec.get("drop", 14.2))
	var w := float(spec.get("W", 9.0))
	var bottom := top + dir * 5.0 - Vector3(0, drop, 0)
	var path := WaterfallBuilder.fall_path(top, bottom)
	p.add_mesh(WaterfallBuilder._sheet(path, w * 1.05, 0.0, origin), WaterfallBuilder.sheet_material(0, drop), Transform3D.IDENTITY,
			{"vis_end": 1200.0, "shadow": false, "tag": &"fall_sheet"})
	p.add_mesh(WaterfallBuilder._sheet(path, w * 0.9, -0.5, origin), WaterfallBuilder.sheet_material(1, drop), Transform3D.IDENTITY,
			{"vis_end": 900.0, "shadow": false, "tag": &"fall_sheet_back"})
	p.add_mesh(WaterfallBuilder._foam_disc(path[path.size() - 1] - origin, w * 0.8), WaterfallBuilder.foam_material(),
			Transform3D.IDENTITY, {"vis_end": 600.0, "shadow": false, "tag": &"fall_foam"})


## Plants of the Spirit Oasis (world transforms): shade trees by the pond, bamboo along the
## wall, shrubs, ferns and reeds (the lawn grass is kit geometry, see NwtPlaces.oasis).
func _oasis_plants(piece: Dictionary) -> Array:
	var pos: Vector3 = piece["pos"]
	var spec: Dictionary = piece["spec"]
	var R := float(spec.get("r", 33.0))
	var pond := float(spec.get("pond", 10.5))
	var gate_yaw := float(piece["yaw"])
	var rng := ContentHash.rng(ContentHash.hash_name("spirit_oasis"))
	var items: Array = []
	var add := func(sp: StringName, p: Vector3, s: float, tint: Color = Color(1, 1, 1)) -> void:
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p)
		items.append([sp, 0, t, Color(tint.r, tint.g, tint.b, rng.randf())])
	var gate_dir := Basis(Vector3.UP, gate_yaw) * Vector3.FORWARD
	var gate_a := atan2(gate_dir.z, gate_dir.x)
	# shade trees (one large, two smaller) on the far side of the pond
	for k in 3:
		var a := gate_a + PI + (k - 1) * 0.55
		var rr := pond + 4.5 + (k % 2) * 3.0
		add.call(&"maple" if k != 1 else &"blossom", pos + Vector3(cos(a) * rr, 0.05, sin(a) * rr), 1.15 if k == 1 else 0.85)
	# bamboo clumps and shrubs along the wall, away from the gate
	for k in 14:
		var a := gate_a + PI * 0.25 + (TAU - PI * 0.5) * (k + 0.5) / 14.0
		var rr := R - 3.0 - rng.randf() * 1.5
		var p := pos + Vector3(cos(a) * rr, 0.05, sin(a) * rr)
		if k % 3 == 0:
			add.call(&"bamboo", p, rng.randf_range(0.7, 0.9))
		else:
			add.call(&"shrub" if k % 3 == 1 else &"fern", p, rng.randf_range(0.9, 1.3))
	# reeds at the pond edge
	for k in 10:
		var a := rng.randf() * TAU
		add.call(&"reeds", pos + Vector3(cos(a) * (pond + 0.9), 0.0, sin(a) * (pond + 0.9)), 1.0)
	return items
