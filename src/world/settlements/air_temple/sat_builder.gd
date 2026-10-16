class_name SatBuilder
extends SettlementBuilder
## Recipe dispatcher of the Southern Air Temple (thread-safe). Piece kinds map to the recipe
## libraries:
##   SatTowers  spire great_spire
##   SatCivic   tier_wall edge_rail stair gateway sky_bridge court
##   SatPlaces  sanctuary stable airball_court pavilion dormitory hall garden statue
##   SatProps   flag_line chime_post lantern bench gong prayer_wheels planter hay
## Extras: the gardens' blossom trees, shrubs and flowers (VegetationLibrary MultiMeshes),
## incense smoke at the sanctuary, spirit motes over the Meditation Ledge.

const TOWERS: Array[StringName] = [&"spire", &"great_spire"]
const CIVIC: Array[StringName] = [&"tier_wall", &"edge_rail", &"stair", &"gateway", &"sky_bridge", &"court"]
const PLACES: Array[StringName] = [&"sanctuary", &"stable", &"airball_court", &"pavilion", &"dormitory", &"hall", &"garden", &"statue"]
const PROPS: Array[StringName] = [&"flag_line", &"chime_post", &"lantern", &"bench", &"gong", &"prayer_wheels", &"planter", &"hay"]


func _init(p_plan: SettlementPlan = null) -> void:
	super(p_plan)
	nation = &"air_nomads"


func build_piece(kit: BuildingKit, piece: Dictionary) -> void:
	var kind: StringName = piece["kind"]
	var spec: Dictionary = piece["spec"]
	if TOWERS.has(kind):
		SatTowers.build(kit, kind, spec)
	elif CIVIC.has(kind):
		SatCivic.build(kit, kind, spec)
	elif PLACES.has(kind):
		SatPlaces.build(kit, kind, spec)
	elif PROPS.has(kind):
		SatProps.build(kit, kind, spec)


func piece_extras(piece: Dictionary) -> Array:
	var out: Array = []
	var pos: Vector3 = piece["pos"]
	var yaw := float(piece["yaw"])
	var basis := Basis(Vector3.UP, yaw)
	match piece["kind"]:
		&"garden":
			var items := garden_plants(piece)
			if not items.is_empty():
				out.append({"type": &"node", "make": func(cell: ContentCell) -> Node3D:
					return SettlementFx.vegetation_node(items, cell.origin())})
		&"sanctuary":
			for sx: float in [-1.0, 1.0]:
				out.append({"type": &"particles", "kind": &"smoke", "position": pos + basis * Vector3(sx * 4.0, 2.8, -6.2)})
		&"pavilion":
			if plan and plan.data.get("meditation_ledge", Vector3.INF) == pos:
				out.append({"type": &"particles", "kind": &"motes", "position": pos + Vector3(0, 2.5, 0)})
			out.append(_chime(pos + Vector3(0, 3.0, 0)))
		&"chime_post":
			out.append(_chime(pos + Vector3(0, 2.4, 0)))
	return out


## Extra: wind chimes that ring now and then while the player is close.
static func _chime(p: Vector3) -> Dictionary:
	var seed := ContentHash.hash4(int(p.x * 10.0), int(p.z * 10.0), 17)
	return {"type": &"node", "make": func(cell: ContentCell) -> Node3D: return SettlementFx.chime_node(p, cell.origin(), seed)}


## Night glows (SettlementBuilder.piece_glows): stone lanterns, the spires' and houses' lit
## windows, the sanctuary's lanterns and incense, stable lamps, stair lanterns.
func piece_glows(piece: Dictionary) -> Array:
	var out: Array = []
	var spec: Dictionary = piece["spec"]
	var v := int(spec.get("v", 0))
	var pos: Vector3 = piece["pos"]
	var h := ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 91)
	var lamp := SettlementFx.GLOW_LAMP
	var win := SettlementFx.GLOW_WINDOW
	match piece["kind"]:
		&"lantern":
			out.append([pos + Vector3(0, (1.6 + (v % 2) * 0.4) * 0.82, 0), lamp, 0.9])
		&"edge_rail":
			if spec.get("lamp", false):
				out.append([at(piece, Vector3(-float(spec.get("L", 8.0)) * 0.5, 2.05, 0)), lamp, 0.8])
		&"stair":
			var sw := float(spec.get("W", 12.0)) - 3.0
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * (sw * 0.5 + 0.75), 3.0, 1.0)), lamp, 1.0])
		&"spire":
			var r := float(spec.get("r", 4.0))
			var hh := float(spec.get("h", 22.0))
			var n := 1 + posmod(h, 3)
			for k in n:
				var a := TAU * ContentHash.unit(h + k * 13)
				var y := hh * (0.28 + 0.26 * posmod(h >> (k + 1), 3))
				out.append([pos + Vector3(cos(a) * (r + 0.2), y, sin(a) * (r + 0.2)), win, 1.1])
		&"great_spire":
			for k in 8:
				var a := TAU * k / 8.0 + 0.3
				out.append([pos + Vector3(cos(a) * 9.6, 1.2 + 14.0 + (k % 4) * 11.0, sin(a) * 9.6), win, 1.5])
			out.append([pos + Vector3(0, 1.2 + 64.0 + 1.1 + 38.0 * 0.4 + 2.5, 0), win, 2.0])
		&"dormitory", &"hall":
			var fp := SatPlaces.footprint(piece["kind"], v)
			if ContentHash.unit(h) < 0.7:
				out.append([at(piece, Vector3((ContentHash.unit(h + 5) - 0.5) * fp.x * 0.6, 2.2 + posmod(h >> 3, 2) * 3.4, -fp.y * 0.5 - 0.2)), win, 0.9])
		&"sanctuary":
			for sx: float in [-1.0, 1.0]:
				out.append([at(piece, Vector3(sx * 8.5, 1.65, -9.2)), lamp, 1.2])
				out.append([at(piece, Vector3(sx * 4.0, 2.4, -6.2)), SettlementFx.GLOW_FIRE, 0.7])
				out.append([at(piece, Vector3(sx * 7.5, 6.4, -0.3)), win, 1.0])
		&"stable":
			var L := float(spec.get("L", 30.0))
			for k in 2:
				out.append([at(piece, Vector3(lerpf(-L * 0.3, L * 0.3, k), 6.0, 0.5)), win, 1.3])
		&"tier_wall":
			if float(spec.get("H", 0.0)) > 12.0 and (v % 4 == 0 or v % 4 == 3) and ContentHash.unit(h) < 0.6:
				var hl := float(spec["L"]) * 0.5
				out.append([at(piece, Vector3((ContentHash.unit(h + 1) - 0.5) * hl, 4.0 + 5.5 * posmod(h >> 2, 2), -0.3)), win, 1.0])
		&"pavilion":
			out.append([at(piece, Vector3(0, 3.2, -float(spec.get("r", 3.6)) * (0.6 if spec.get("cantilever", false) else 0.0))), lamp, 0.8])
	return out


## Plants of a garden bed (world transforms): spec.plants = "blossom" (a blossom tree with
## shrubs and flowers around it) or "mixed" (shrubs, ferns and flowers, a small maple).
func garden_plants(piece: Dictionary) -> Array:
	var pos: Vector3 = piece["pos"]
	var spec: Dictionary = piece["spec"]
	var basis := Basis(Vector3.UP, float(piece["yaw"]))
	var rng := ContentHash.rng(ContentHash.hash4(int(pos.x * 10.0), int(pos.z * 10.0), 61))
	var items: Array = []
	var top := 0.56
	var add := func(sp: StringName, local: Vector3, s: float) -> void:
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), pos + basis * local + Vector3(0, top, 0))
		items.append([sp, 0, t, Color(1, 1, 1, rng.randf())])
	var blossom: bool = String(spec.get("plants", "blossom")) == "blossom"
	if spec.has("r"):
		var r := float(spec["r"])
		if blossom:
			add.call(&"blossom", Vector3.ZERO, rng.randf_range(0.85, 1.1))
		else:
			add.call(&"maple", Vector3.ZERO, rng.randf_range(0.5, 0.65))
		for k in 5:
			var a := TAU * k / 5.0 + rng.randf() * 0.4
			add.call(&"shrub" if k % 2 == 0 else &"flowers_warm", Vector3(cos(a), 0, sin(a)) * (r - 1.2), rng.randf_range(0.7, 1.0))
	else:
		var w := float(spec.get("w", 8.0))
		var d := float(spec.get("d", 4.0))
		var n_trees := 2 if w > 7.0 else 1
		for k in n_trees:
			var x := (float(k) + 0.5) / n_trees * w - w * 0.5
			add.call(&"blossom" if blossom else &"maple", Vector3(x, 0, 0), rng.randf_range(0.75, 1.0) if blossom else 0.55)
		for k in int(w / 1.6):
			var x := lerpf(-w * 0.5 + 0.7, w * 0.5 - 0.7, (k + 0.5) / int(w / 1.6))
			var z := (d * 0.5 - 0.7) * (1.0 if k % 2 == 0 else -1.0)
			var sp: StringName = [&"shrub", &"flowers_white", &"flowers_cool", &"fern"][k % 4]
			add.call(sp, Vector3(x, 0, z), rng.randf_range(0.7, 1.05))
	return items
