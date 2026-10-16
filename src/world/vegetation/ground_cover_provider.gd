class_name GroundCoverProvider
extends ContentProvider
## Grass, meadow grass, flower patches, reeds near water, crops on farm plots and dry tufts in
## 32 m cells close to the focus (height-aware: nothing loads while flying high).
##
## Cost control: world attributes are sampled on a 4 m grid per cell and interpolated per clump
## (only the height is exact), clump spacing grows as Settings lower the density (clumps scale
## up to keep coverage), instances are sorted by their random so far cells draw only the share
## the shader would keep (visible_instance_count), and the shader shrinks clumps into the ground
## over the last 45% of grass_range where the terrain's own lush colour takes over.

const ATTR := 4.0
const BASE_SPACING := 0.62

var cfg: Dictionary = {}
var spacing := BASE_SPACING
var clump_scale := 1.0


func _init() -> void:
	id = &"groundcover"
	cell_size = 32.0
	priority = 30
	use_height = true
	unload_margin = 10.0


func configure() -> bool:
	TerrainPatterns.load_data()
	VegetationLibrary.build_async()
	var c := VegetationSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	var dens := clampf(float(cfg["grass_density"]), 0.2, 1.6)
	spacing = clampf(BASE_SPACING / sqrt(dens), 0.5, 1.4)
	clump_scale = clampf(pow(spacing / BASE_SPACING, 0.6), 1.0, 1.6)
	range_m = float(cfg["grass_range"])
	VegetationProvider._prepare_materials()
	return changed


func tick() -> void:
	VegetationLibrary.poll()


func wants_cell(_coord: Vector2i) -> bool:
	return VegetationLibrary.is_ready()


func update_cell(cell: ContentCell, distance: float) -> void:
	# draw only the share of (rnd-descending) instances the shader keeps at this cell's nearest point
	var r := float(cfg["grass_range"])
	var band := r * 0.45
	var x_out := clampf((distance - (r - band)) / band, 0.0, 1.0)
	for n in cell.pooled:
		if n is MultiMeshInstance3D and is_instance_valid(n):
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm and mm.instance_count > 0:
				var vis := int(ceil(mm.instance_count * (1.0 - x_out)))
				mm.visible_instance_count = -1 if vis >= mm.instance_count else maxi(vis, 0)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var origin := cell.origin()
	var x0 := cell.rect.position.x
	var z0 := cell.rect.position.y
	var na := int(cell_size / ATTR) + 1
	var sites: Array[VegetationRules.Site] = []
	var tints: Array[Color] = []
	var any := false
	for j in na:
		for i in na:
			var s := VegetationRules.sample(x0 + i * ATTR, z0 + j * ATTR, false)
			sites.append(s)
			tints.append(TerrainPatterns.lush_color(s.x, s.z, s.region, s.biome, TerrainPatterns.macro(s.x, s.z)))
			if not s.wet and s.biome != VegetationRules.Bio.OCEAN and s.biome != VegetationRules.Bio.CITY:
				any = true
	if not any:
		cell.payload = p
		return
	var groups := {}       # species -> Array of [rnd, Transform3D, Color]
	var n := int(ceil(cell_size / spacing))
	var ex := cell.exclusions
	var dens_k := float(cfg["grass_density"])
	for j in n:
		for i in n:
			var h := ContentHash.hash4(cell.seed, i, j)
			var fx := (i + ContentHash.unit(h)) * spacing
			var fz := (j + ContentHash.unit(h >> 7)) * spacing
			if fx >= cell_size or fz >= cell_size:
				continue
			var x := x0 + fx
			var z := z0 + fz
			# nearest attribute site + bilinear weights
			var ax := fx / ATTR
			var az := fz / ATTR
			var ix := mini(int(ax), na - 2)
			var iz := mini(int(az), na - 2)
			var tx := ax - ix
			var tz := az - iz
			var s00 := sites[iz * na + ix]
			var s10 := sites[iz * na + ix + 1]
			var s01 := sites[(iz + 1) * na + ix]
			var s11 := sites[(iz + 1) * na + ix + 1]
			var near_s := s00 if (tx < 0.5 and tz < 0.5) else (s10 if tz < 0.5 else (s01 if tx < 0.5 else s11))
			if near_s.wet or near_s.biome == VegetationRules.Bio.OCEAN or near_s.biome == VegetationRules.Bio.CITY:
				continue
			var splat := s00.splat.lerp(s10.splat, tx).lerp(s01.splat.lerp(s11.splat, tx), tz)
			var ground := s00.ground.lerp(s10.ground, tx).lerp(s01.ground.lerp(s11.ground, tx), tz)
			var slope := lerpf(lerpf(s00.slope, s10.slope, tx), lerpf(s01.slope, s11.slope, tx), tz)
			var u := ContentHash.unit(ContentHash.hash4(h, 3))
			var u2 := ContentHash.unit(ContentHash.hash4(h, 5))
			var sp := _choose(near_s, splat, ground, slope, x, z, u, u2, ex)
			if sp == &"":
				continue
			var y := WorldData.get_height(x, z)
			var wh := WorldData.get_water_height(x, z)
			if wh > y - 0.05 and sp != &"reeds":
				continue
			var tint := tints[iz * na + ix].lerp(tints[iz * na + ix + 1], tx).lerp(tints[(iz + 1) * na + ix].lerp(tints[(iz + 1) * na + ix + 1], tx), tz)
			var k := 0.86 + 0.26 * u2
			if sp == &"wheat":
				tint = Color(1.0, 0.97, 0.9)
			if sp == &"tuft" and (near_s.biome == VegetationRules.Bio.ASH or near_s.biome == VegetationRules.Bio.VOLCANIC):
				tint = Color(0.16, 0.14, 0.11)
			var rnd := ContentHash.unit(ContentHash.hash4(h, 9))
			var sc := clump_scale * (0.75 + 0.55 * ContentHash.unit(ContentHash.hash4(h, 11)))
			var up := Vector3.UP.lerp(near_s.normal, 0.35).normalized()
			var basis := VegetationScatter._up_basis(up, u * TAU * 7.0).scaled(Vector3.ONE * sc)
			if not groups.has(sp):
				groups[sp] = []
			(groups[sp] as Array).append([rnd, Transform3D(basis, Vector3(x, y, z) - origin), Color(tint.r * k, tint.g * k, tint.b * k, rnd)])
	for sp: StringName in groups:
		var list: Array = groups[sp]
		list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var buf := PackedFloat32Array()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for e: Array in list:
			var t: Transform3D = e[1]
			CellPayload.write_instance(buf, t, e[2])
			lo = lo.min(t.origin)
			hi = hi.max(t.origin)
		var aabb := AABB(lo - Vector3(1.5, 1.0, 1.5), (hi - lo) + Vector3(3, 3.5, 3))
		p.add_multimesh(VegetationLibrary.get_mesh(sp), VegetationLibrary.get_material(sp, 0), buf, list.size(), aabb,
				{"shadow": false, "vis_end": float(cfg["grass_range"]) + 24.0, "sorted": true, "tag": sp})
	cell.payload = p


## Ground cover type for a clump candidate (or &"" for bare ground).
func _choose(s: VegetationRules.Site, splat: Color, ground: Color, slope: float, x: float, z: float, u: float, u2: float, ex: ContentExclusions) -> StringName:
	if slope > 42.0 or splat.r > 0.38:
		return &""
	if WorldData.get_road(x, z) > 0.12 or ground.g > 0.25:
		return &""
	if ex and ex.factor(x, z, ContentExclusions.TAG_GRASS) < u2:
		return &""
	var lush := splat.b
	var b := s.biome
	var wet := ground.a
	# reeds on wet shores
	if wet > 0.55 and lush > 0.2 and u < 0.5 and _near_water(x, z):
		return &"reeds"
	# farm plots: crops in rows, paths at the borders
	if ground.b > 0.45 and b == VegetationRules.Bio.FARMLAND or (ground.b > 0.6 and b != VegetationRules.Bio.FOREST):
		var fp := TerrainPatterns.farm_plot(x, z)
		if float(fp["border"]) < 1.4:
			return &"tuft" if u < 0.25 else &""
		var dir: Vector2 = fp["dir"]
		var furrow := sin(Vector2(x, z).dot(dir) * 2.3) * 0.5 + 0.5
		match int(fp["type"]):
			0: return &"wheat" if furrow > 0.3 and u < 0.92 else &""
			1: return &"rice" if furrow > 0.25 and u < 0.85 else &""
			2: return &"grass_tall" if furrow > 0.35 and u < 0.7 else &""
			_: return &"tuft" if u < 0.18 else &""
	match b:
		VegetationRules.Bio.TUNDRA, VegetationRules.Bio.SNOW:
			return &"tuft" if u < 0.35 * (1.0 - splat.r * 2.0) else &""
		VegetationRules.Bio.MOUNTAIN, VegetationRules.Bio.ROCK:
			return &"tuft" if u < 0.3 * lush + 0.05 else &""
		VegetationRules.Bio.VOLCANIC, VegetationRules.Bio.ASH:
			return &"tuft" if u < 0.06 else &""
		VegetationRules.Bio.BEACH:
			return &"tuft" if u < 0.08 + lush * 0.4 else &""
		VegetationRules.Bio.ICE:
			return &""
	var p := smoothstep(0.12, 0.5, lush)
	if b == VegetationRules.Bio.FOREST:
		p *= 0.55
	elif b == VegetationRules.Bio.TEMPLE:
		p = smoothstep(0.4, 0.65, lush)
	p *= 1.0 - smoothstep(0.22, 0.5, splat.a)
	if u >= p:
		return &""
	# flower patches (low-frequency noise) in meadows, temple gardens and grassland
	if b != VegetationRules.Bio.FOREST:
		var fl := TerrainPatterns.noise(x / 37.0, z / 37.0)
		if fl.b > 0.6 and u2 < (fl.b - 0.6) * 2.4:
			return [&"flowers_warm", &"flowers_cool", &"flowers_white"][int(fl.a * 2.99)]
		if (b == VegetationRules.Bio.GRASSLAND or b == VegetationRules.Bio.TEMPLE) and fl.r > 0.55 and u2 < 0.55:
			return &"grass_tall"
	return &"grass"


static func _near_water(x: float, z: float) -> bool:
	for k in 4:
		var a := k * PI * 0.5
		var px := x + cos(a) * 4.0
		var pz := z + sin(a) * 4.0
		var wh := WorldData.get_water_height(px, pz)
		if wh > -INF and wh > WorldData.get_height(px, pz) - 0.2:
			return true
	return false
