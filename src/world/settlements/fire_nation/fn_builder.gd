class_name FnBuilder
extends SettlementBuilder
## Recipe dispatcher of the Fire Nation settlements (the capital, Crimson Harbor, the villages and
## the resort isle; thread-safe). Piece kinds map to the recipe libraries:
##   FnWalls    fn_tier_wall fn_stair fn_gate gate_fort fn_curtain fn_brazier
##   FnHomes    fn_house fn_townhouse noble_house fn_villa fisher_hut tea_house_fn
##   FnCivic    fn_plaza sun_monument kata_grounds fn_garden fn_stall fn_lamp fn_statue fn_temple
##   FnPalace   fn_podium fn_throne_hall fn_hall fn_palace_gate flame_pillar
##   FnHarbor   warship fn_quay fn_pier crane coal_pile fn_warehouse watchtower
##   FnPlaces   fn_dojo noble_interior (enterable)
##   FnVillage  tea_rows tea_shed fire_shrine cabana hot_spring
##   shared     crates cart bench well (EkProps), ek_pier fish_rack boathouse (EkVillages), sampan,
##              rowboat, tree_row (plants only)
## Extras: garden plants and tree rows (VegetationLibrary), embers over the great braziers of the
## palace and the Plaza of the Sun, the crackle of the sun monument, smoke from the warships'
## stacks, steam over the hot spring.

const WALLS: Array[StringName] = [&"fn_tier_wall", &"fn_stair", &"fn_gate", &"gate_fort", &"fn_curtain", &"fn_brazier"]
const HOMES: Array[StringName] = [&"fn_house", &"fn_townhouse", &"noble_house", &"fn_villa", &"fisher_hut", &"tea_house_fn"]
const CIVIC: Array[StringName] = [&"fn_plaza", &"sun_monument", &"kata_grounds", &"fn_garden", &"fn_stall", &"fn_lamp", &"fn_statue", &"fn_temple"]
const PALACE: Array[StringName] = [&"fn_podium", &"fn_throne_hall", &"fn_hall", &"fn_palace_gate", &"flame_pillar"]
const HARBOR: Array[StringName] = [&"warship", &"fn_quay", &"fn_pier", &"crane", &"coal_pile", &"fn_warehouse", &"watchtower"]
const PLACES: Array[StringName] = [&"fn_dojo", &"noble_interior"]
const PROPS: Array[StringName] = [&"crates", &"cart", &"bench", &"well"]
const SHARED: Array[StringName] = [&"ek_pier", &"fish_rack", &"boathouse"]


func _init(p_plan: SettlementPlan = null) -> void:
	super(p_plan)
	nation = &"fire_nation"


func build_piece(kit: BuildingKit, piece: Dictionary) -> void:
	var kind: StringName = piece["kind"]
	var spec: Dictionary = piece["spec"]
	if WALLS.has(kind):
		FnWalls.build(kit, kind, spec)
	elif HOMES.has(kind):
		FnHomes.build(kit, kind, int(spec.get("v", 0)), int(spec.get("style", FnStyle.LOWER)))
	elif CIVIC.has(kind):
		FnCivic.build(kit, kind, spec)
	elif PALACE.has(kind):
		FnPalace.build(kit, kind, spec)
	elif HARBOR.has(kind):
		FnHarbor.build(kit, kind, spec)
	elif PLACES.has(kind):
		FnPlaces.build(kit, kind, spec)
	elif FnVillage.KINDS.has(kind):
		FnVillage.build(kit, kind, spec)
	elif PROPS.has(kind):
		EkProps.build(kit, kind, int(spec.get("v", 0)), spec)
	elif SHARED.has(kind):
		EkVillages.build(kit, kind, spec)
	else:
		match kind:
			&"sampan":
				BoatBuilder.sampan(kit)
			&"rowboat":
				BoatBuilder.rowboat(kit)


func piece_extras(piece: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = piece["spec"]
	match piece["kind"]:
		&"tree_row":
			out.append(EkBuilder.veg_extra(EkBuilder.tree_row_items(piece)))
		&"fn_garden":
			out.append(EkBuilder.veg_extra(garden_plants(piece)))
		&"sun_monument":
			out.append({"type": &"particles", "kind": &"embers", "position": at(piece, Vector3(0, 13.0, 0))})
			out.append({"type": &"sound", "name": &"fire_loop", "position": at(piece, Vector3(0, 2.0, 0)), "db": -16.0})
		&"flame_pillar":
			if int(spec.get("embers", 0)) > 0:
				out.append({"type": &"particles", "kind": &"embers", "position": at(piece, Vector3(0, float(spec.get("h", 6.0)) + 2.0, 0))})
		&"kata_grounds":
			var hw := float(spec.get("w", 40.0)) * 0.5 - 2.0
			out.append({"type": &"particles", "kind": &"embers", "position": at(piece, Vector3(hw, 3.6, float(spec.get("d", 34.0)) * 0.5 - 2.0))})
		&"warship":
			if int(spec.get("v", 0)) % 2 == 0 and not bool(spec.get("cold", false)):
				var L := float(spec.get("L", 56.0))
				out.append({"type": &"particles", "kind": &"smoke", "position": at(piece, Vector3(0, 3.2 + 2.6 + 7.2, L * 0.16))})
		&"hot_spring":
			out.append({"type": &"particles", "kind": &"steam", "position": at(piece, Vector3(0, 0.4, 0))})
	return out


## Plants of a fn_garden (world transforms): palms and maples at the back, blossom by the pond,
## bamboo on one side, shrubs and flower beds, reeds at the pond (mirrors FnCivic.garden).
func garden_plants(piece: Dictionary) -> Array:
	var spec: Dictionary = piece["spec"]
	var w := float(spec.get("w", 24.0))
	var d := float(spec.get("d", 20.0))
	var v := int(spec.get("v", 0))
	var dens := int(spec.get("plants", 2))
	var pos: Vector3 = piece["pos"]
	var rng := ContentHash.rng(ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 93))
	var pc := Vector2(w * (0.14 if v % 2 == 0 else -0.14), d * 0.06)
	var pr := minf(w, d) * 0.25
	var pv := Vector2(-pc.x * 1.6, -d * 0.26)
	var items: Array = []
	var add := func(sp: StringName, lx: float, lz: float, s: float) -> void:
		var q := Vector2(lx, lz)
		if q.distance_to(pc) < pr + 1.2 or q.distance_to(pv) < 4.2:
			return
		var wp := SettlementBuilder.at(piece, Vector3(lx, 0.08, lz))
		items.append([sp, 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), wp), Color(1, 1, 1, rng.randf())])
	var trees: Array[StringName] = [&"palm", &"maple", &"tropical", &"blossom"]
	var nt := 3 + dens
	for k in nt:
		var t := (k + 0.5) / nt
		add.call(trees[(k + v) % trees.size()], lerpf(-w * 0.42, w * 0.42, t), d * 0.4 + rng.randf_range(-1.5, 0.3), rng.randf_range(0.7, 1.0))
	for sx: float in [-1.0, 1.0]:
		add.call(&"palm" if v % 2 == 0 else &"cypress", sx * w * 0.42, -d * 0.36, rng.randf_range(0.7, 0.95))
	var bside := 1.0 if v % 2 == 0 else -1.0
	for k in 2 + dens:
		add.call(&"bamboo", bside * w * 0.44, lerpf(-d * 0.3, d * 0.3, (k + 0.5) / (2 + dens)), rng.randf_range(0.6, 0.85))
	for k in 6 + dens * 3:
		var a := rng.randf() * TAU
		var lx := clampf(pc.x + cos(a) * (pr + rng.randf_range(1.5, 6.0)), -w * 0.46, w * 0.46)
		var lz := clampf(pc.y + sin(a) * (pr + rng.randf_range(1.5, 5.0)), -d * 0.46, d * 0.46)
		add.call([&"shrub", &"flowers_warm", &"tropical", &"fern", &"flowers_warm"][k % 5], lx, lz, rng.randf_range(0.6, 1.1))
	for k in 6:
		var a := TAU * k / 6.0 + rng.randf() * 0.5
		var q := pc + Vector2(cos(a), sin(a)) * (pr * 0.95)
		items.append([&"reeds", 0, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), SettlementBuilder.at(piece, Vector3(q.x, 0.12, q.y))), Color(1, 1, 1, rng.randf())])
	return items


## Night glows beyond lod1_end (SettlementBuilder.piece_glows).
func piece_glows(piece: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = piece["spec"]
	var v := int(spec.get("v", 0))
	var pos: Vector3 = piece["pos"]
	var h := ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 79)
	var lamp := SettlementFx.GLOW_LAMP
	var fire := SettlementFx.GLOW_FIRE
	var win := SettlementFx.GLOW_WINDOW
	match piece["kind"]:
		&"fn_brazier":
			out.append([pos + Vector3(0, 2.4 if v == 0 else 3.7, 0), fire, 1.0 + v * 0.6])
		&"fn_lamp":
			out.append([at(piece, Vector3(0.78, 2.95, 0)) if v % 2 == 0 else pos + Vector3(0, 1.4, 0), lamp, 0.8])
		&"fn_tier_wall":
			if float(spec["H"]) > 9.0 and v % 3 == 1:
				out.append([at(piece, Vector3(float(spec["L"]) * 0.15, 2.4, -0.9)), fire, 1.2])
		&"fn_stair":
			var sw := float(spec.get("W", 18.0)) - 4.0
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * (sw * 0.5 + 1.0), 3.7, 1.6)), fire, 1.4])
				out.append([at(piece, Vector3(sx * (sw * 0.5 + 1.0), float(spec["H"]) + 2.4, -float(spec["R"]) - 1.6)), fire, 1.2])
		&"gate_fort":
			var hw := float(spec.get("W", 14.0)) * 0.5
			var Wt := float(spec.get("Wt", 12.0))
			var Ht := float(spec.get("H", 20.0)) + 6.0
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * (hw + Wt * 0.5), Ht + 2.6, 0)), lamp, 2.0])
				out.append([at(piece, Vector3(sx * (hw + 2.4), 3.7, -float(spec.get("D", 16.0)) * 0.5 - 3.0)), fire, 1.6])
		&"fn_gate":
			out.append([at(piece, Vector3(0, float(spec.get("height", 8.0)) + 2.8, 0)), fire, 0.8])
		&"fn_house", &"fn_townhouse", &"noble_house", &"fn_villa", &"tea_house_fn", &"fisher_hut":
			var fp := FnHomes.footprint(piece["kind"], v)
			var n := 0 if ContentHash.unit(h) < 0.3 else (1 if ContentHash.unit(h + 1) < 0.65 else 2)
			for k in n:
				var x := (ContentHash.unit(h + 7 * k + 3) - 0.5) * fp.x * 0.7
				var y := 1.8 + float(posmod(h >> (k + 2), 2)) * 3.0
				out.append([at(piece, Vector3(x, y, -fp.y * 0.5 - 0.3)), win, 0.9])
		&"fn_throne_hall":
			var hd := float(spec.get("d", 24.0)) * 0.5
			for k in 5:
				out.append([at(piece, Vector3(lerpf(-14.0, 14.0, k / 4.0), 17.2, -float(spec.get("d", 24.0)) * 0.32)), win, 1.8])
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * 4.0, 9.6, -hd + 0.5)), lamp, 1.6])
		&"fn_hall", &"fn_palace_gate", &"fn_temple":
			out.append([at(piece, Vector3(0, 6.0, -float(spec.get("d", 10.0)) * 0.5 - 0.6)), lamp, 1.5])
		&"flame_pillar":
			out.append([pos + Vector3(0, float(spec.get("h", 6.0)) + 0.8 + 2.0, 0), fire, 1.8])
		&"fn_podium":
			var d := float(spec.get("d", 56.0))
			var lh := float(spec.get("lh", 2.6))
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * 10.0, 7.5, -d * 0.5 - lh * 2.2 - 1.5)), fire, 1.8])
		&"sun_monument":
			var r := float(spec.get("r", 22.0))
			out.append([pos + Vector3(0, 12.6, 0), fire, 2.4])
			for i in 8:
				var a := TAU * (i + 0.5) / 8.0
				out.append([at(piece, Vector3(cos(a) * r * 0.72, 3.7, sin(a) * r * 0.72)), fire, 1.4])
		&"kata_grounds":
			var hw := float(spec.get("w", 40.0)) * 0.5 - 2.0
			var hd := float(spec.get("d", 34.0)) * 0.5 - 2.0
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					out.append([at(piece, Vector3(sx * hw, 3.8, sz * hd)), fire, 1.4])
		&"fn_plaza":
			if v % 3 == 0:
				out.append([pos + Vector3(0, 3.7, 0), fire, 1.6])
		&"fn_stall":
			if v % 3 == 0:
				out.append([pos + Vector3(0, 2.2, 0), lamp, 0.7])
		&"fn_dojo", &"noble_interior":
			var d := FnPlaces.DOJO_D if piece["kind"] == &"fn_dojo" else FnPlaces.NOBLE_D
			out.append([at(piece, Vector3(0, 2.4, -d * 0.5 - 0.6)), fire, 1.4])
		&"warship":
			var L := float(spec.get("L", 56.0))
			out.append([at(piece, Vector3(0, 3.2 + 2.6 + 7.9, L * 0.02 - L * 0.045)), lamp, 1.6])
		&"watchtower":
			out.append([pos + Vector3(0, float(spec.get("h", 16.0)) + 2.3, 0), fire, 2.2])
		&"fn_pier":
			var W := float(spec.get("W", 7.0))
			out.append([at(piece, Vector3(W * 0.5 - 0.6 + 0.78, 2.95, -float(spec.get("L", 30.0)) + 0.6)), lamp, 1.0])
		&"fire_shrine":
			out.append([pos + Vector3(0, 1.9, 0), fire, 1.0])
	return out
