class_name TerrainClipmap
extends Node3D
## GPU geometry clipmap of the world terrain: nested square rings of grid pieces around the
## camera, displaced in the vertex shader from the shared heightmap (exact WorldData formula).
##
## Level l has spacing `base_spacing * 2^l` and is snapped to its own grid so vertices never
## swim; odd vertices geomorph to the next level in the outer part of each ring, trims fill the
## snap gap and seams close T-junctions, so rings are crack-free. Every piece is a separate
## RenderingServer instance with a tight AABB (HeightBounds) for frustum/shadow culling.
## Call `update_center(camera_position)` every frame (WorldRenderer does).

## World x/z of grid vertices are GRID_ORIGIN + k * spacing: odd metres = heightmap texel
## centres, so levels with spacing >= 2 m sample stored heights exactly.
const GRID_ORIGIN := 1.0
## Extra vertical AABB padding (snow trails, morph between coarse/fine heights).
const AABB_PAD := 2.0

var tile_res: int = 32
var base_spacing: float = 0.25
var level_count: int = 9
var material: ShaderMaterial
var bounds: HeightBounds

var _meshes: ClipmapMeshes
var _levels: Array[Dictionary] = []
var _built := false
var _world_rect := Rect2(WorldConstants.WORLD_MIN, WorldConstants.WORLD_MIN, WorldConstants.WORLD_SIZE, WorldConstants.WORLD_SIZE)
var _center := Vector3.INF
var _bounds_ready_seen := false


## Sets resolution and reach. `view_distance` decides how many levels are needed.
func configure(p_tile_res: int, p_base_spacing: float, view_distance: float) -> void:
	tile_res = p_tile_res
	base_spacing = p_base_spacing
	level_count = levels_for(tile_res, base_spacing, view_distance)


## Number of levels whose outermost ring reaches `view_distance`.
static func levels_for(t: int, s0: float, view_distance: float) -> int:
	var n := 1
	while 2.0 * t * s0 * pow(2.0, n - 1) < view_distance and n < 16:
		n += 1
	return n


## Geomorph range in cells (Chebyshev distance from the camera / spacing): starts after the
## inner ring's outer edge ((T + 1) cells) and reaches 1 before the level's own outer edge
## (2T cells), so ring boundaries always match exactly.
func morph_range() -> Vector2:
	return Vector2(float(tile_res + 1) + float(tile_res - 1) * 0.3, float(2 * tile_res) - 0.5)


## CPU mirror of the vertex shader's morph factor for a vertex at `xz` on a level of spacing `s`.
func morph_factor(xz: Vector2, cam: Vector2, s: float) -> float:
	var r := morph_range()
	var d := maxf(absf(xz.x - cam.x), absf(xz.y - cam.y)) / s
	return clampf((d - r.x) / (r.y - r.x), 0.0, 1.0)


## CPU mirror of the vertex shader's surface height (without snow trails): odd vertices blend
## towards the midpoint of their coarse edge / diagonal by the morph factor.
func vertex_height(xz: Vector2, cam: Vector2, s: float) -> float:
	var g := Vector2(roundf((xz.x - GRID_ORIGIN) / s), roundf((xz.y - GRID_ORIGIN) / s))
	var odd := Vector2(absf(g.x - 2.0 * floorf(g.x * 0.5)), absf(g.y - 2.0 * floorf(g.y * 0.5)))
	var h := WorldData.get_height(xz.x, xz.y)
	var m := morph_factor(xz, cam, s)
	if m > 0.0 and odd.x + odd.y > 0.5:
		var o := odd * s
		var hc := 0.5 * (WorldData.get_height(xz.x - o.x, xz.y - o.y) + WorldData.get_height(xz.x + o.x, xz.y + o.y))
		h = lerpf(h, hc, m)
	return h


## Spacing of level `l` in metres.
func spacing(l: int) -> float:
	return base_spacing * pow(2.0, l)


## Outer half-extent (m) of the whole clipmap.
func reach() -> float:
	return 2.0 * tile_res * spacing(level_count - 1)


## Snapped origin of level l for a camera x/z.
func level_origin(l: int, cam: Vector2) -> Vector2:
	var s := spacing(l)
	return Vector2(floor((cam.x - GRID_ORIGIN) / s) * s + GRID_ORIGIN, floor((cam.y - GRID_ORIGIN) / s) * s + GRID_ORIGIN)


## (Re)creates all ring pieces. Needs to be inside the tree (scenario).
func build() -> void:
	_free_instances()
	_meshes = ClipmapMeshes.new(tile_res)
	var scenario := get_world_3d().scenario
	var mat_rid := material.get_rid()
	_levels.clear()
	for l in level_count:
		var lv := {"tiles": [], "origins": _meshes.tile_origins(l), "p": Vector2.INF, "pn": Vector2.INF}
		for o in lv["origins"]:
			lv["tiles"].append(_make_instance(_meshes.tile, scenario, mat_rid))
		lv["filler"] = _make_instance(_meshes.cross if l == 0 else _meshes.filler, scenario, mat_rid)
		if l < level_count - 1:
			lv["trim"] = _make_instance(_meshes.trims[0], scenario, mat_rid)
			lv["seam"] = _make_instance(_meshes.seam, scenario, mat_rid)
			lv["trim_variant"] = 0
		_levels.append(lv)
	material.set_shader_parameter(&"morph_start", morph_range().x)
	material.set_shader_parameter(&"morph_end", morph_range().y)
	material.set_shader_parameter(&"grid_origin", GRID_ORIGIN)
	_built = true
	_center = Vector3.INF
	_apply_visibility()


func _make_instance(mesh: Mesh, scenario: RID, mat: RID) -> RID:
	var rid := RenderingServer.instance_create2(mesh.get_rid(), scenario)
	RenderingServer.instance_geometry_set_material_override(rid, mat)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rid, RenderingServer.SHADOW_CASTING_SETTING_ON)
	return rid


## Moves the rings to follow `cam` (world position). Cheap when nothing snaps.
func update_center(cam: Vector3) -> void:
	if not _built:
		return
	material.set_shader_parameter(&"clip_center", cam)
	if bounds and bounds.ready and not _bounds_ready_seen:
		_bounds_ready_seen = true
		for lv in _levels:
			lv["p"] = Vector2.INF   # refresh AABBs with real bounds
	_center = cam
	var c2 := Vector2(cam.x, cam.z)
	for l in level_count:
		var lv: Dictionary = _levels[l]
		var p := level_origin(l, c2)
		var pn := level_origin(l + 1, c2) if l < level_count - 1 else Vector2.ZERO
		if p == lv["p"] and pn == lv["pn"]:
			continue
		lv["p"] = p
		lv["pn"] = pn
		_place_level(l, lv, p, pn)


func _place_level(l: int, lv: Dictionary, p: Vector2, pn: Vector2) -> void:
	var s := spacing(l)
	var t := tile_res
	var basis := Basis.from_scale(Vector3(s, 1.0, s))
	var origins: Array = lv["origins"]
	var tiles: Array = lv["tiles"]
	for k in tiles.size():
		var o: Vector2i = origins[k]
		var wo := p + Vector2(o) * s
		var rect := Rect2(wo, Vector2(t * s, t * s))
		_set_piece(tiles[k], Transform3D(basis, Vector3(wo.x, 0.0, wo.y)), rect, Vector2.ZERO, Vector2(t, t), s)
	var ext := Rect2(p + Vector2(-2 * t, -2 * t) * s, Vector2(4 * t + 1, 4 * t + 1) * s)
	_set_piece(lv["filler"], Transform3D(basis, Vector3(p.x, 0.0, p.y)), ext, Vector2(-2 * t, -2 * t), Vector2(4 * t + 1, 4 * t + 1), s)
	if lv.has("trim"):
		var ox := int(roundf((p.x - pn.x) / s))
		var oz := int(roundf((p.y - pn.y) / s))
		var variant := clampi(ox, 0, 1) + 2 * clampi(oz, 0, 1)
		if variant != lv["trim_variant"]:
			RenderingServer.instance_set_base(lv["trim"], _meshes.trims[variant].get_rid())
			lv["trim_variant"] = variant
		var hole := Rect2(pn + Vector2(-2 * t, -2 * t) * s, Vector2(4 * t + 2, 4 * t + 2) * s)
		var xf := Transform3D(basis, Vector3(pn.x, 0.0, pn.y))
		_set_piece(lv["trim"], xf, hole, Vector2(-2 * t, -2 * t), Vector2(4 * t + 2, 4 * t + 2), s)
		_set_piece(lv["seam"], xf, hole, Vector2(-2 * t, -2 * t), Vector2(4 * t + 2, 4 * t + 2), s)


func _set_piece(rid: RID, xf: Transform3D, world_rect: Rect2, local_pos: Vector2, local_size: Vector2, _s: float) -> void:
	RenderingServer.instance_set_transform(rid, global_transform * xf)
	var hr := bounds.range_for_rect(world_rect) if bounds else Vector2(WorldConstants.HEIGHT_MIN, WorldConstants.HEIGHT_MAX)
	if not WorldData.has_world_data():
		hr = Vector2(-1.0, 1.0)
	var aabb := AABB(Vector3(local_pos.x, hr.x - AABB_PAD, local_pos.y),
			Vector3(local_size.x, hr.y - hr.x + 2.0 * AABB_PAD, local_size.y))
	RenderingServer.instance_set_custom_aabb(rid, aabb)
	# pieces entirely beyond the baked square would only draw sea floor under the ocean
	var grown := _world_rect.grow(64.0)
	RenderingServer.instance_set_visible(rid, is_visible_in_tree() and grown.intersects(world_rect))


## Total triangle count submitted when every piece is visible (budget diagnostics).
func triangle_budget() -> int:
	if _meshes == null:
		return 0
	var n := 0
	for l in level_count:
		n += _meshes.level_triangles(l)
	return n


## Number of RenderingServer instances (draw calls before culling).
func piece_count() -> int:
	var n := 0
	for lv in _levels:
		n += (lv["tiles"] as Array).size() + 1 + (2 if lv.has("trim") else 0)
	return n


func _apply_visibility() -> void:
	for lv in _levels:
		lv["p"] = Vector2.INF
	if _center != Vector3.INF:
		update_center(_center)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				for lv in _levels:
					for rid: RID in _level_rids(lv):
						RenderingServer.instance_set_visible(rid, false)
			_apply_visibility()
		NOTIFICATION_PREDELETE:
			_free_instances()


func _level_rids(lv: Dictionary) -> Array[RID]:
	var out: Array[RID] = []
	for r: RID in lv["tiles"]:
		out.append(r)
	out.append(lv["filler"])
	if lv.has("trim"):
		out.append(lv["trim"])
		out.append(lv["seam"])
	return out


func _free_instances() -> void:
	for lv in _levels:
		for rid: RID in _level_rids(lv):
			RenderingServer.free_rid(rid)
	_levels.clear()
	_built = false
