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
