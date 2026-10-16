class_name LandmarkProvider
extends ContentProvider
## Streams the large natural features and spans of WorldData in 1 km cells with a long range so
## they read from far away: waterfalls (WaterfallBuilder: animated sheets, plunge foam, mist,
## roar), natural arches (ArchBuilder), bridges (BridgeBuilder: suspended rope bridges and stone
## spans, walkable collision) and cave mouths (CaveBuilder: mouth shell, dark veil, interior tube
## with collision, a TerrainHoles capsule so the player can walk in). Claimed ids
## (ContentClaims) are left to their owners.

const TUBE_OPTS := {"vertex_color": true, "outline": false, "rim": 0.0, "shade_tint": Color(0.55, 0.52, 0.6)}
const VEIL_SHADER := preload("res://assets/shaders/content/cave_veil.gdshader")

var cfg: Dictionary = {}
var _by_cell: Dictionary = {}          # Vector2i -> Array[[kind, record]]
var _claims_version := -1
var _tube_mat: Material
var _veil_mat: ShaderMaterial


func _init() -> void:
	id = &"landmarks"
	cell_size = 1024.0
	priority = 9
	unload_margin = 200.0


func configure() -> bool:
	var c := PropSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["landmark_range"])
	NationPalette.prepare_materials()
	WaterfallBuilder.sheet_material(0, 10.0)
	WaterfallBuilder.foam_material()
	WaterfallBuilder.mist_material()
	if _tube_mat == null:
		_tube_mat = ToonMaterials.make(Color.WHITE, TUBE_OPTS)
		_veil_mat = ShaderMaterial.new()
		_veil_mat.shader = VEIL_SHADER
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
	var add := func(kind: StringName, rec: Dictionary, at: Vector3) -> void:
		if ContentClaims.is_claimed(rec.get("id", &"")):
			return
		var key := coord_of(at.x, at.z)
		if not by.has(key):
			by[key] = []
		(by[key] as Array).append([kind, rec])
	for w in WorldData.get_waterfalls():
		add.call(&"waterfall", w, w["top"])
	for a in WorldData.get_arches():
		add.call(&"arch", a, ((a["a"] as Vector3) + (a["b"] as Vector3)) * 0.5)
	for b in WorldData.get_bridges():
		add.call(&"bridge", b, ((b["a"] as Vector3) + (b["b"] as Vector3)) * 0.5)
	for p in WorldData.get_pois():
		if p["type"] == &"cave":
			add.call(&"cave", p, p["position"])
	_by_cell = by


func wants_cell(coord: Vector2i) -> bool:
	return _by_cell.has(coord)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var root := cell.origin()
	var far := float(cfg["landmark_range"]) + cell_size
	var shadows: bool = cfg["shadows"]
	for e: Array in _by_cell.get(cell.coord, []):
		var rec: Dictionary = e[1]
		var tag := StringName(String(rec.get("id", e[0])))
		match e[0]:
			&"waterfall":
				var data := WaterfallBuilder.build(rec)
				p.add_call(func(c: ContentCell) -> void:
					var n := WaterfallBuilder.instantiate(data, c.root, c.loops)
					n.name = String(tag))
			&"arch":
				var data := ArchBuilder.build(rec)
				(data["kit"] as KitResult).add_to_payload(p, Transform3D(Basis(), (data["origin"] as Vector3) - root),
						{"vis_end": far, "margin": 30.0, "shadow": shadows, "tag": tag})
			&"bridge":
				var data := BridgeBuilder.build(rec)
				(data["kit"] as KitResult).add_to_payload(p, Transform3D(Basis(), (data["origin"] as Vector3) - root),
						{"vis_end": far, "margin": 30.0, "shadow": shadows, "tag": tag})
			&"cave":
				_build_cave(p, rec, root, tag, shadows)
	cell.payload = p


func _build_cave(p: CellPayload, poi: Dictionary, root: Vector3, tag: StringName, shadows: bool) -> void:
	var data := CaveBuilder.build(poi)
	var t := Transform3D(Basis(), -root)          # cave data is in world space
	var vis := float(cfg["cave_range"])
	(data["kit"] as KitResult).add_to_payload(p, t, {"vis_end": vis * 1.5, "margin": 20.0, "shadow": shadows, "tag": tag})
	p.add_mesh(data["tube"], _tube_mat, t, {"vis_end": vis, "margin": 20.0, "shadow": false, "tag": StringName(String(tag) + "_tube")})
	p.add_mesh(data["veil"], _veil_mat, t, {"vis_end": vis, "margin": 20.0, "shadow": false, "tag": StringName(String(tag) + "_veil")})
	var faces: PackedVector3Array = data["faces"]
	var local := PackedVector3Array()
	local.resize(faces.size())
	for i in faces.size():
		local[i] = faces[i] - root
	p.add_static_faces(local)
	var hole: Array = data["hole"]
	var markers: Dictionary = data["markers"]
	var pid: StringName = poi["id"]
	p.add_call(func(c: ContentCell) -> void:
		if not c.user.has("holes"):
			c.user["holes"] = []
		(c.user["holes"] as Array).append(TerrainHoles.add_capsule(hole[0], hole[1], float(hole[2])))
		for k: StringName in markers:
			var mt: Transform3D = markers[k]
			var m := PropFx.marker(&"cave_entrance" if k == &"entrance" else &"cave_end", mt.origin - root, mt.basis.get_euler().y, {"poi": pid})
			c.root.add_child(m))


func release_cell(cell: ContentCell) -> void:
	for h: int in cell.user.get("holes", []):
		TerrainHoles.remove(h)
	cell.user.erase("holes")
