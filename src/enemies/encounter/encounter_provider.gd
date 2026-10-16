class_name EncounterProvider
extends ContentProvider
## Streams the structures of the authored encounter sites (outposts, dens) through
## WorldContent: geometry is built on worker threads by OutpostBuilder (LOD0 near,
## LOD1 far), static collision for tents / barricades / boulders, budgeted lights,
## camp-fire smoke, and a Marker3D in group &"enemy_camp" (meta site) per site.
## WorldData camp POIs are built by the worldcontent PoiProvider instead.

const LOD0_END := 120.0

var sites: Array[EncounterSite] = []
var _range := 600.0


func _init(p_sites: Array[EncounterSite] = []) -> void:
	id = &"encounter_sites"
	cell_size = 256.0
	priority = 2
	unload_margin = 64.0
	for s in p_sites:
		if s.kind == &"outpost" or s.kind == &"den":
			sites.append(s)


func configure() -> bool:
	NationPalette.prepare_materials()
	var old := _range
	_range = clampf(Settings.view_distance_m() * 0.3, 450.0, 900.0)
	range_m = _range
	return absf(old - _range) > 1.0


func wants_cell(coord: Vector2i) -> bool:
	var r := rect_of(coord)
	for s in sites:
		if r.has_point(Vector2(s.center.x, s.center.z)):
			return true
	return false


## WORKER THREAD.
func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	for s in sites:
		if not cell.rect.has_point(Vector2(s.center.x, s.center.z)):
			continue
		var near := OutpostBuilder.build(s, 0)
		var far := OutpostBuilder.build(s, 1)
		var origin: Vector3 = near["origin"]
		var t := Transform3D(Basis(), origin - cell.origin())
		(near["kit"] as KitResult).add_to_payload(p, t, {"vis_end": LOD0_END + 10.0, "tag": &"enemy_camp"})
		(far["kit"] as KitResult).add_to_payload(p, t, {"vis_begin": LOD0_END, "vis_end": _range, "collision": false, "lights": false,
			"shadow": false, "tag": &"enemy_camp"})
		var smoke: Array = near["smoke"]
		var sid := s.id
		var center := s.center
		var yaw := s.yaw
		p.add_call(func(c: ContentCell) -> void:
			for q: Vector3 in smoke:
				var pt := PropFx.particles(&"smoke")
				pt.position = origin + Basis(Vector3.UP, yaw) * q - c.origin()
				c.root.add_child(pt)
			var m := PropFx.marker(&"enemy_camp", center - c.origin(), yaw, {"site": sid})
			c.root.add_child(m))
	cell.payload = p
