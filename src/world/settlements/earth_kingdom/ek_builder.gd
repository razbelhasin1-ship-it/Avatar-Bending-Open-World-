class_name EkBuilder
extends SettlementBuilder
## Recipe dispatcher of the Earth Kingdom settlements (Ba Sing Se, Omashu, the villages;
## thread-safe). Piece kinds map to the recipe libraries:
##   EkWalls   city_wall wall_tower great_gate ring_wall wall_stair grand_stair gate_arch ramp_cheeks
##   EkHomes   row_house tenement shack town_house court_house mansion farmhouse
##   EkCivic   plaza garden pavilion teahouse footbridge canal
##   EkPlaces  tea_shop training_hall (enterable)
##   EkPalace  palace_podium throne_hall palace_hall palace_gate pagoda
##   EkFarm    windmill water_wheel granary field_hut
##   EkProps   lamp_post stall crates cart bench well banner_pole statue planter haystack scarecrow noticeboard
##   OmashuCity  omashu_* (Omashu's tiers, bridge, chutes, palace)
##   others    tree_row orchard (plants only), lake_pier, rowboat, sampan, ek_pier, ek_boathouse
## Extras: VegetationLibrary plants of gardens, avenue tree rows and orchards; the spinning
## windmill sails and water wheels; stove smoke of the tea shop.

const WALLS: Array[StringName] = [&"city_wall", &"wall_tower", &"great_gate", &"ring_wall", &"wall_stair", &"grand_stair", &"gate_arch"]
const HOMES: Array[StringName] = [&"row_house", &"tenement", &"shack", &"town_house", &"court_house", &"mansion", &"farmhouse"]
const CIVIC: Array[StringName] = [&"plaza", &"garden", &"pavilion", &"teahouse", &"footbridge", &"canal"]
const PLACES: Array[StringName] = [&"tea_shop", &"training_hall"]
const PALACE: Array[StringName] = [&"palace_podium", &"throne_hall", &"palace_hall", &"palace_gate", &"pagoda"]
const FARM: Array[StringName] = [&"windmill", &"water_wheel", &"granary", &"field_hut", &"veg_plot"]
const PROPS: Array[StringName] = [&"lamp_post", &"stall", &"crates", &"cart", &"bench", &"well", &"banner_pole", &"statue",
	&"planter", &"haystack", &"scarecrow", &"noticeboard"]


func _init(p_plan: SettlementPlan = null) -> void:
	super(p_plan)
	nation = &"earth_kingdom"


func build_piece(kit: BuildingKit, piece: Dictionary) -> void:
	var kind: StringName = piece["kind"]
	var spec: Dictionary = piece["spec"]
	if WALLS.has(kind):
		EkWalls.build(kit, kind, spec)
	elif kind == &"ramp_cheeks":
		EkWalls.grand_stair(kit, spec.merged({"steps": false}))
	elif HOMES.has(kind):
		EkHomes.build(kit, kind, int(spec.get("v", 0)), int(spec.get("style", EkStyle.LOWER)))
	elif CIVIC.has(kind):
		EkCivic.build(kit, kind, spec)
	elif PLACES.has(kind):
		EkPlaces.build(kit, kind, spec)
	elif PALACE.has(kind):
		EkPalace.build(kit, kind, spec)
	elif FARM.has(kind):
		EkFarm.build(kit, kind, spec)
	elif PROPS.has(kind):
		EkProps.build(kit, kind, int(spec.get("v", 0)), spec)
	elif String(kind).begins_with("omashu_") or OmashuCity.KINDS.has(kind):
		OmashuCity.build(kit, kind, spec)
	elif EkVillages.KINDS.has(kind):
		EkVillages.build(kit, kind, spec)
	else:
		match kind:
			&"lake_pier":
				EkVillages.pier(kit, spec)
			&"rowboat":
				BoatBuilder.rowboat(kit)
			&"sampan":
				BoatBuilder.sampan(kit)


func piece_extras(piece: Dictionary) -> Array:
	var out: Array = []
	var pos: Vector3 = piece["pos"]
	var yaw := float(piece["yaw"])
	var spec: Dictionary = piece["spec"]
	match piece["kind"]:
		&"tree_row":
			out.append(veg_extra(tree_row_items(piece)))
		&"orchard":
			var items: Array = []
			var h := ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 19)
			var i := 0
			for it: Array in spec.get("plants", []):
				var p: Vector3 = it[1]
				p.y = WorldData.get_height(p.x, p.z) - 0.1
				var s := float(it[2])
				items.append([it[0], 0, Transform3D(Basis(Vector3.UP, ContentHash.unit(h + i) * TAU).scaled(Vector3(s, s, s)), p), Color(1, 1, 1, ContentHash.unit(h + i * 5))])
				i += 1
			out.append(veg_extra(items))
		&"garden":
			out.append(veg_extra(garden_plants(piece)))
		&"windmill":
			var hub := SettlementBuilder.at(piece, EkFarm.SAIL_HUB)
			var sd := ContentHash.hash4(int(pos.x), int(pos.z), 5)
			out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
				return EkFarm.spinner(&"sails", hub, yaw, cell.origin(), sd)})
		&"water_wheel":
			var hub := SettlementBuilder.at(piece, EkFarm.WHEEL_HUB)
			var sd := ContentHash.hash4(int(pos.x), int(pos.z), 6)
			out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
				return EkFarm.spinner(&"wheel", hub, yaw, cell.origin(), sd)})
		_:
			if OmashuCity.KINDS.has(piece["kind"]) or EkVillages.KINDS.has(piece["kind"]):
				out.append_array(OmashuCity.extras(piece) if OmashuCity.KINDS.has(piece["kind"]) else EkVillages.extras(piece))
	return out


static func veg_extra(items: Array) -> Dictionary:
	return {"type": &"node", "make": func(cell: ContentCell) -> Node3D:
		return SettlementFx.vegetation_node(items, cell.origin())}


## Plants of a tree_row piece (spec points: world positions, species; any nation's builder).
static func tree_row_items(piece: Dictionary) -> Array:
	var pos: Vector3 = piece["pos"]
	var spec: Dictionary = piece["spec"]
	var items: Array = []
	var h := ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 17)
	var i := 0
	var smin := float(spec.get("scale", 0.85))
	for p: Vector3 in spec.get("points", []):
		var s := smin + ContentHash.unit(h + i * 7) * 0.3
		items.append([spec.get("species", &"cypress"), 0, Transform3D(Basis(Vector3.UP, ContentHash.unit(h + i * 3) * TAU).scaled(Vector3(s, s, s)), p),
			Color(1, 1, 1, ContentHash.unit(h + i * 11))])
		i += 1
	return items


## Plants of a garden piece (world transforms): trees at the back corners and along the edges,
## bamboo on one side, shrubs and flower beds, reeds at the pond (mirrors EkCivic.garden).
func garden_plants(piece: Dictionary) -> Array:
	var spec: Dictionary = piece["spec"]
	var w := float(spec.get("w", 30.0))
	var d := float(spec.get("d", 24.0))
	var v := int(spec.get("v", 0))
	var dens := int(spec.get("plants", 2))
	var pos: Vector3 = piece["pos"]
	var rng := ContentHash.rng(ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 91))
	var pc := Vector2(w * (0.12 if v % 2 == 0 else -0.12), d * 0.08)
	var pr := minf(w, d) * 0.26
	var pv := Vector2(-pc.x * 1.6, -d * 0.24)
	var items: Array = []
	var add := func(sp: StringName, lx: float, lz: float, s: float) -> void:
		var q := Vector2(lx, lz)
		if q.distance_to(pc) < pr + 1.2 or q.distance_to(pv) < 4.0:
			return
		var wp := SettlementBuilder.at(piece, Vector3(lx, 0.08, lz))
		items.append([sp, 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), wp), Color(1, 1, 1, rng.randf())])
	var trees: Array[StringName] = [&"maple", &"blossom", &"cypress", &"maple"]
	var nt := 3 + dens
	for k in nt:
		var t := (k + 0.5) / nt
		add.call(trees[(k + v) % trees.size()], lerpf(-w * 0.44, w * 0.44, t), d * 0.4 + rng.randf_range(-1.5, 0.5), rng.randf_range(0.75, 1.05))
	for sx: float in [-1.0, 1.0]:
		add.call(&"blossom" if v % 2 == 0 else &"maple", sx * w * 0.42, -d * 0.36, rng.randf_range(0.7, 0.95))
	var bside := 1.0 if v % 2 == 0 else -1.0
	for k in 2 + dens:
		add.call(&"bamboo", bside * w * 0.45, lerpf(-d * 0.3, d * 0.3, (k + 0.5) / (2 + dens)), rng.randf_range(0.65, 0.9))
	for k in 6 + dens * 3:
		var a := rng.randf() * TAU
		var lx := clampf(pc.x + cos(a) * (pr + rng.randf_range(1.5, 6.0)), -w * 0.46, w * 0.46)
		var lz := clampf(pc.y + sin(a) * (pr + rng.randf_range(1.5, 5.0)), -d * 0.46, d * 0.46)
		add.call([&"shrub", &"flowers_warm", &"flowers_white", &"fern", &"flowers_cool"][k % 5], lx, lz, rng.randf_range(0.8, 1.3))
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf() * 0.5
		var q := pc + Vector2(cos(a), sin(a)) * (pr * 0.95)
		var wp := SettlementBuilder.at(piece, Vector3(q.x, 0.12, q.y))
		items.append([&"reeds", 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), wp), Color(1, 1, 1, rng.randf())])
	return items


## Night glows beyond lod1_end (SettlementBuilder.piece_glows).
func piece_glows(piece: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = piece["spec"]
	var v := int(spec.get("v", 0))
	var pos: Vector3 = piece["pos"]
	var h := ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 77)
	var lamp := SettlementFx.GLOW_LAMP
	var fire := SettlementFx.GLOW_FIRE
	var win := SettlementFx.GLOW_WINDOW
	match piece["kind"]:
		&"lamp_post":
			out.append([pos + (Vector3(0, 1.5, 0) if v % 2 == 1 else SettlementBuilder.at(piece, Vector3(0.72, 2.75, 0)) - pos), lamp, 1.0])
		&"city_wall":
			if v % 2 == 0:
				var hl := float(spec["L"]) * 0.25
				out.append([at(piece, Vector3(hl, float(spec["H"]) + 1.6, float(spec["T"]) * 0.5 - 1.6)), lamp, 1.2])
		&"wall_tower":
			var top := float(spec["H"]) + float(spec.get("top", 7.0))
			out.append([at(piece, Vector3(0, top + 2.7, -float(spec["T"]) * 0.5 + 1.0)), lamp, 1.6])
		&"great_gate":
			var hd := float(spec.get("D", 30.0)) * 0.5
			var hw := float(spec.get("W", 18.0)) * 0.5
			var top := float(spec["H"]) + 6.0
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * (hw + 2.5), 1.6, -hd - 3.5)), fire, 2.0])
				out.append([at(piece, Vector3(sx * 6.0, top + 4.0, -float(spec.get("D", 30.0)) * 0.5 + 3.0)), win, 1.6])
		&"row_house", &"tenement", &"town_house", &"court_house", &"mansion", &"farmhouse", &"teahouse":
			var fp := EkHomes.footprint(piece["kind"], v)
			var n := 0 if ContentHash.unit(h) < 0.35 else (1 if ContentHash.unit(h + 1) < 0.7 else 2)
			if piece["kind"] == &"teahouse":
				n = 3
			for k in n:
				var x := (ContentHash.unit(h + 7 * k + 3) - 0.5) * fp.x * 0.7
				var y := 1.8 + float(posmod(h >> (k + 2), 2)) * 3.0
				out.append([at(piece, Vector3(x, y, -fp.y * 0.5 - 0.3)), win if piece["kind"] != &"teahouse" else lamp, 0.9])
		&"throne_hall":
			for k in 5:
				out.append([at(piece, Vector3(lerpf(-14.0, 14.0, k / 4.0), 14.0, -7.0)), win, 1.8])
			out.append([at(piece, Vector3(0, 8.6, -11.0)), lamp, 1.8])
		&"palace_gate", &"palace_hall", &"pagoda":
			out.append([at(piece, Vector3(0, 6.0, -6.0)), lamp, 1.6])
		&"plaza":
			if v % 3 == 1:
				out.append([pos + Vector3(0, 2.0, 0), fire, 1.4])
		&"tea_shop", &"training_hall":
			out.append([at(piece, Vector3(0, 2.4, -(EkPlaces.TEA_D if piece["kind"] == &"tea_shop" else EkPlaces.HALL_D) * 0.5 - 0.6)), fire, 1.4])
		&"stall":
			if v % 3 == 0:
				out.append([pos + Vector3(0, 2.2, 0), lamp, 0.7])
		&"grand_stair", &"ramp_cheeks":
			var sw := float(spec.get("W", 24.0)) - 4.0
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * (sw * 0.5 + 1.0), 4.3, 1.4)), lamp, 1.2])
		_:
			if OmashuCity.KINDS.has(piece["kind"]):
				out.append_array(OmashuCity.glows(piece))
			elif EkVillages.KINDS.has(piece["kind"]):
				out.append_array(EkVillages.glows(piece))
	return out
