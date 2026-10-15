extends TestCase
## World data: heightmap sampling, maps, water, POIs, spawns, settlements, load time.

const WORLD_SCRIPT := "res://src/autoload/world_data.gd"

var _raw: PackedByteArray = PackedByteArray()


func before_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	WorldData.load_world()


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()


## Independent decode of the heightmap file (does not use WorldHeightfield).
func _raw_heights() -> PackedByteArray:
	if _raw.is_empty():
		var comp := FileAccess.get_file_as_bytes(WorldConstants.DATA_DIR + WorldConstants.HEIGHTMAP_FILE)
		_raw = comp.decompress(4096 * 4096 * 2, FileAccess.COMPRESSION_DEFLATE)
	return _raw


func _texel_h(i: int, j: int) -> float:
	return _raw_heights().decode_u16((j * 4096 + i) * 2) * WorldConstants.HEIGHT_SCALE + WorldConstants.HEIGHT_MIN


func _center(i: int) -> float:
	return WorldConstants.WORLD_MIN + (float(i) + 0.5) * WorldConstants.TEXEL_SIZE


func test_world_data_present_and_loads_fast() -> void:
	expect(WorldData.has_world_data(), "baked world data loaded (%s)" % WorldData.load_error)
	# Measure a cold load with a fresh instance of the autoload script.
	var fresh: Node = (load(WORLD_SCRIPT) as GDScript).new()
	add_child(fresh)
	var t0 := Time.get_ticks_usec()
	fresh.load_world()
	var secs := (Time.get_ticks_usec() - t0) / 1000000.0
	print("        cold load: %.3f s" % secs)
	expect(fresh.has_world_data(), "fresh instance loads data")
	expect(secs < 2.0, "load under 2 s (took %.3f s)" % secs)
	var t1 := Time.get_ticks_usec()
	fresh.load_world()
	expect((Time.get_ticks_usec() - t1) < 1000, "repeated load_world() is free")
	fresh.queue_free()


func test_async_load_emits_world_ready() -> void:
	var fresh: Node = (load(WORLD_SCRIPT) as GDScript).new()
	add_child(fresh)
	var fired := [false]
	var cb := func() -> void: fired[0] = true
	Events.world_ready.connect(cb)
	fresh.load_world_async()
	expect(not fresh.is_loaded() or fired[0], "async load does not block")
	var t := 0.0
	while not fresh.is_loaded() and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	Events.world_ready.disconnect(cb)
	expect(fresh.is_loaded(), "async load completes")
	expect(fired[0], "world_ready emitted")
	expect(fresh.has_world_data(), "async load has data")
	fresh.queue_free()


func test_height_matches_texels_exactly() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for k in 400:
		var i := rng.randi_range(0, 4095)
		var j := rng.randi_range(0, 4095)
		var expected := _texel_h(i, j)
		var got := WorldData.get_height(_center(i), _center(j))
		if not expect(got == expected, "texel (%d,%d): %f != %f" % [i, j, got, expected]):
			return


func test_height_interpolates_bilinearly() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 300:
		var i := rng.randi_range(0, 4094)
		var j := rng.randi_range(0, 4094)
		var fx := rng.randf()
		var fz := rng.randf()
		var x := _center(i) + fx * 2.0
		var z := _center(j) + fz * 2.0
		var h00 := _texel_h(i, j)
		var h10 := _texel_h(i + 1, j)
		var h01 := _texel_h(i, j + 1)
		var h11 := _texel_h(i + 1, j + 1)
		var a := h00 + (h10 - h00) * fx
		var b := h01 + (h11 - h01) * fx
		var expected := a + (b - a) * fz
		if not expect_near(WorldData.get_height(x, z), expected, 1e-6, "bilinear at %f,%f" % [x, z]):
			return
	# midpoint of four texels is their average
	var mid := WorldData.get_height(_center(2000) + 1.0, _center(2100) + 1.0)
	var avg := (_texel_h(2000, 2100) + _texel_h(2001, 2100) + _texel_h(2000, 2101) + _texel_h(2001, 2101)) * 0.25
	expect_near(mid, avg, 1e-6, "midpoint average")
	# outside the map clamps to the edge texels
	expect_eq(WorldData.get_height(-5000.0, -5000.0), _texel_h(0, 0), "clamped corner")


func test_height_block_matches_samples() -> void:
	var ox := _center(1500)
	var oz := _center(1700)
	var blk := WorldData.get_height_block(ox, oz, 9, 7, 4.0)
	expect_eq(blk.size(), 63, "block size")
	for j in 7:
		for i in 9:
			expect_eq(blk[j * 9 + i], float(_texel_h(1500 + i * 2, 1700 + j * 2)) as float, "aligned block %d,%d" % [i, j])
	var blk2 := WorldData.get_height_block(123.3, -456.7, 5, 5, 3.3)
	for j in 5:
		for i in 5:
			expect_near(blk2[j * 5 + i], WorldData.get_height(123.3 + i * 3.3, -456.7 + j * 3.3), 1e-3, "unaligned block")


func test_height_map_shape_fill() -> void:
	var shape := HeightMapShape3D.new()
	expect(WorldData.fill_height_map_shape(shape, 2000, 2100, 33, 33), "shape filled")
	expect_eq(shape.map_width, 33)
	expect_near(shape.map_data[0], _texel_h(2000, 2100), 0.002, "first sample")
	expect_near(shape.map_data[33 * 33 - 1], _texel_h(2032, 2132), 0.002, "last sample")
	var c := WorldData.texel_block_center(2000, 2100, 33, 33)
	expect_near(c.x, _center(2016), 1e-6, "block centre x")


func test_normals_and_slopes() -> void:
	var bss: Dictionary = WorldData.get_city(&"ba_sing_se")
	var p: Vector3 = bss["center"]
	var n := WorldData.get_normal(p.x + 20.0, p.z + 5.0)
	expect_near(n.length(), 1.0, 1e-4, "unit normal")
	expect(n.y > 0.999, "palace terrace is flat")
	expect(WorldData.get_slope_deg(p.x + 20.0, p.z + 5.0) < 1.0, "flat slope")


func test_spawns_are_valid() -> void:
	for e: int in ElementDefs.ALL:
		var t := WorldData.get_spawn(e)
		var pos := t.origin
		var region: StringName = ElementDefs.DATA[e]["home_region"]
		expect(pos.y > WorldConstants.SEA_LEVEL + 1.0, "%s spawn above sea" % ElementDefs.id_of(e))
		expect_near(pos.y, WorldData.get_height(pos.x, pos.z), 0.2, "%s spawn on ground" % ElementDefs.id_of(e))
		expect(not WorldData.is_underwater(pos + Vector3.UP * 0.5), "%s spawn dry" % ElementDefs.id_of(e))
		expect_eq(WorldData.get_region(pos.x, pos.z), region, "%s spawn region" % ElementDefs.id_of(e))
		for k in 8:
			var a := TAU * k / 8.0
			var q := pos + Vector3(sin(a), 0, cos(a)) * 3.0
			expect(WorldData.get_slope_deg(q.x, q.z) < 30.0, "%s spawn walkable around" % ElementDefs.id_of(e))
		var fwd := -t.basis.z
		expect(absf(fwd.y) < 1e-4, "spawn faces horizontally")
		var cam := WorldData.get_arrival_camera(e)
		expect(not cam.is_empty(), "arrival camera exists")
		if not cam.is_empty():
			var end: Transform3D = cam["end"]
			expect(end.origin.distance_to(pos) < 15.0, "camera ends near the spawn")
			expect((-end.basis.z).dot(fwd) > 0.8, "camera ends looking where the player looks")
			var start: Transform3D = cam["start"]
			expect(start.origin.y > WorldData.get_height(start.origin.x, start.origin.z) + 10.0, "camera starts above ground")


func test_city_centers_report_regions() -> void:
	var expect_regions := {
		&"northern_water_tribe": &"water_tribe", &"ba_sing_se": &"earth_kingdom", &"omashu": &"earth_kingdom",
		&"fire_nation_capital": &"fire_nation", &"fire_harbor": &"fire_nation", &"southern_air_temple": &"air_temple",
	}
	for id: StringName in expect_regions:
		var c := WorldData.get_city(id)
		expect(not c.is_empty(), "city %s exists" % id)
		if c.is_empty():
			continue
		var p: Vector3 = c["center"]
		expect_eq(WorldData.get_region(p.x, p.z), expect_regions[id], "region of %s" % id)
		expect_eq(c["region"], expect_regions[id], "record region of %s" % id)
	expect_eq(WorldData.get_region(-300, -3050), &"water_tribe", "task coordinate: Water Tribe city")
	expect_eq(WorldData.get_region(2000, 200), &"earth_kingdom", "task coordinate: Ba Sing Se")
	expect_eq(WorldData.get_region(-2600, 2600), &"fire_nation", "task coordinate: Fire capital")
	expect_eq(WorldData.get_region(2500, 3350), &"air_temple", "task coordinate: Air Temple")
	expect_eq(WorldData.get_region(1240, -2100), &"wilds", "frozen strait is the wilds")
	expect_eq(WorldData.get_region(-3900, 0), &"ocean", "open sea")


func test_city_layout_records() -> void:
	var bss := WorldData.get_city(&"ba_sing_se")
	var radii := []
	for w: Dictionary in bss["walls"]:
		radii.append(float(w["radius"]))
	expect(radii.has(700.0) and radii.has(380.0), "outer/inner wall rings")
	expect(bss["gates"].size() >= 4, "gates")
	for g: Dictionary in bss["gates"]:
		var gp: Vector3 = g["position"]
		expect_near(Vector2(gp.x, gp.z).distance_to(Vector2(2000, 200)), 700.0, 1.0, "gate on the outer wall")
		expect_near(gp.y, WorldData.get_height(gp.x, gp.z), 0.5, "gate on ground")
	var tiers: Array = bss["tiers"]
	var upper: Dictionary = tiers.filter(func(t: Dictionary) -> bool: return t["id"] == &"upper_ring")[0]
	expect(float(upper["height"]) - float(bss["base_height"]) >= 20.0, "upper ring raised 20+ m")
	# terrain follows the tier heights
	var up := WorldData.get_height(2000 + 100.0, 200 + 20.0)
	expect_near(up, float(upper["height"]), 0.05, "upper ring terrain height")
	var nwt := WorldData.get_city(&"northern_water_tribe")
	expect(nwt.has("sea_wall") and nwt.has("canals") and nwt.has("spirit_oasis"), "NWT layout")
	var palace: Dictionary = nwt["tiers"].filter(func(t: Dictionary) -> bool: return t["id"] == &"palace")[0]
	expect(float(palace["height"]) >= 45.0 and float(palace["height"]) <= 60.0, "palace tier 45-60 m")
	var fc := WorldData.get_city(&"fire_nation_capital")
	var floor_h := WorldData.get_height(-2600 + 330.0, 2600.0)
	expect(floor_h >= 105.0 and floor_h <= 145.0, "caldera floor 110-140 m (%f)" % floor_h)
	expect(fc.has("gorge"), "caldera pass recorded")
	var at := WorldData.get_city(&"southern_air_temple")
	var top := WorldData.get_height(2500.0 + 80.0, 3350.0)
	expect(top >= 780.0 and top <= 825.0, "temple terraces at 780-820 m (%f)" % top)


func test_pois_valid() -> void:
	var pois := WorldData.get_pois()
	expect(pois.size() >= 40, "40+ POIs (%d)" % pois.size())
	var per_region := {}
	var ids := {}
	var types := [&"shrine", &"ruin", &"cave", &"training_ground", &"landmark", &"vista", &"spirit_spot", &"camp",
			&"resource", &"waterfall", &"dock", &"village", &"bridge"]
	var bounds := WorldData.get_bounds()
	for p in pois:
		var pos: Vector3 = p["position"]
		expect(not ids.has(p["id"]), "unique id %s" % p["id"])
		ids[p["id"]] = true
		expect(types.has(p["type"]), "valid type %s" % p["type"])
		expect(bounds.has_point(Vector2(pos.x, pos.z)), "%s inside bounds" % p["id"])
		expect_near(pos.y, WorldData.get_height(pos.x, pos.z), 0.6, "%s on ground" % p["id"])
		expect(String(p["name"]).length() > 3 and String(p["description"]).length() > 20, "%s text" % p["id"])
		expect(pos.y > -0.5, "%s not under the sea" % p["id"])
		per_region[p["region"]] = int(per_region.get(p["region"], 0)) + 1
	for r: StringName in [&"water_tribe", &"earth_kingdom", &"fire_nation", &"air_temple"]:
		expect(int(per_region.get(r, 0)) >= 10, "10+ POIs in %s (%d)" % [r, int(per_region.get(r, 0))])
	var first: Dictionary = pois[0]
	expect_eq(WorldData.get_poi(first["id"]), first, "get_poi")
	var near := WorldData.get_nearest_poi(first["position"] + Vector3(3, 0, 3))
	expect_eq(near["id"], first["id"], "nearest POI")
	expect(WorldData.get_pois_in_radius(first["position"], 1.0).size() >= 1, "pois in radius")
	expect(WorldData.get_pois_in_region(&"fire_nation").size() >= 10, "pois by region")
	var caves := pois.filter(func(p: Dictionary) -> bool: return p["type"] == &"cave" and p.get("underground", false))
	expect(caves.size() >= 3, "underground cave POIs")


func test_water_queries() -> void:
	# open ocean
	expect_eq(WorldData.get_water_height(-3900.0, 0.0), 0.0, "sea level over ocean")
	expect(WorldData.is_underwater(Vector3(-3900, -2, 0)), "underwater in the sea")
	expect(not WorldData.is_underwater(Vector3(-3900, 1, 0)), "above the sea")
	# dry land
	expect_eq(WorldData.get_water_height(2000.0, 200.0), -INF, "no water in Ba Sing Se's palace")
	# lakes: water inside non-frozen lakes at their level, ice is solid
	var lake_ok := false
	var ice_ok := false
	for lk in WorldData.get_lakes():
		var c: Vector3 = lk["center"]
		var wh := WorldData.get_water_height(c.x, c.z)
		if lk["frozen"]:
			ice_ok = wh == -INF or ice_ok
		elif WorldData.get_height(c.x, c.z) < float(lk["level"]):
			lake_ok = is_equal_approx(wh, float(lk["level"])) or lake_ok
	expect(lake_ok, "lake water level")
	expect(ice_ok, "frozen lake is solid")
	# canals in the Water Tribe city
	var canal: Dictionary = WorldData.get_canals()[0]
	var cp: PackedVector2Array = canal["points"]
	var mid := (cp[0] + cp[1]) * 0.5
	expect_near(WorldData.get_water_height(mid.x, mid.y), float(canal["level"]), 1e-4, "canal level")
	expect(WorldData.get_height(mid.x, mid.y) < float(canal["level"]), "canal bed below water")


## First arctic snowfield found on a coarse scan (the polar ranges also have bare rock).
func _arctic_snow_point() -> Vector3:
	for k in 400:
		var x := -3000.0 + float(k % 20) * 300.0
		var z := -3700.0 + float(k / 20) * 60.0
		if WorldData.get_biome(x, z) == WorldData.Biome.SNOW and WorldData.get_splat(x, z).r > 0.6:
			return Vector3(x, WorldData.get_height(x, z), z)
	return Vector3.INF


func test_find_water_source() -> void:
	var near_sea := WorldData.find_water_source(Vector3(-1690, 5, 2010 + 175), 40.0)
	expect(near_sea["found"] and near_sea["kind"] == &"water", "harbour water found")
	var snow_p := _arctic_snow_point()
	expect(snow_p != Vector3.INF, "arctic snowfield exists")
	var arctic := WorldData.find_water_source(snow_p, 5.0)
	expect(arctic["found"] and (arctic["kind"] == &"snow" or arctic["kind"] == &"ice"), "snow/ice in the arctic")
	var dry := WorldData.find_water_source(Vector3(2000, 91, 200), 10.0)
	expect(not dry["found"], "no water source in the palace courtyard")
	var id := WorldData.register_water_source(Vector3(2000, 91, 200), 2.0, &"source")
	var fountain := WorldData.find_water_source(Vector3(2001, 91, 200), 3.0)
	expect(fountain["found"] and fountain["kind"] == &"source", "registered fountain")
	WorldData.clear_water_sources()
	expect(id >= 0)


func test_surfaces_and_snow() -> void:
	var nwt_snow := _arctic_snow_point()
	var s := WorldData.get_surface(nwt_snow)
	expect(s == &"snow" or s == &"ice", "arctic surface is snow/ice (%s)" % s)
	expect(WorldData.get_snow_depth(nwt_snow.x, nwt_snow.z) > 0.2, "deep snow on a snowfield")
	expect_eq(WorldData.get_snow_depth(2000 + 100, 200 + 20), 0.0, "no snow in Ba Sing Se")
	var bss := Vector3(2000 + 100, 86, 200 + 20)
	expect_eq(WorldData.get_surface(bss), &"stone", "city paving")
	expect_eq(WorldData.get_surface(Vector3(-3900, -3, 0)), &"water", "in the sea")
	var counts := {}
	for k in 200:
		var x := -3800.0 + float(k % 20) * 380.0
		var z := -3800.0 + float(k / 20) * 760.0
		var b := WorldData.get_biome(x, z)
		counts[b] = true
		expect(b >= 0 and b <= WorldData.Biome.CITY, "biome in range")
	expect(counts.size() >= 7, "varied biomes (%d kinds)" % counts.size())


func test_flat_fallback_and_override() -> void:
	WorldData.use_flat_world(true)
	expect_eq(WorldData.get_height(2000, 200), 0.0, "flat height")
	expect_eq(WorldData.get_biome(2000, 200), WorldData.Biome.GRASSLAND, "flat biome")
	expect_eq(WorldData.get_region(2000, 200), &"wilds", "flat region")
	expect(WorldData.get_pois().is_empty(), "no POIs when flat")
	expect_eq(WorldData.get_water_height(0, 0), -INF, "flat world is dry")
	WorldData.use_flat_world(false)
	WorldData.height_override = func(_x: float, _z: float) -> float: return 5.0
	expect_eq(WorldData.get_height(123, 456), 5.0, "height override")
	expect_eq(WorldData.get_surface(Vector3(1, 5, 1)), &"grass", "override surface")
	WorldData.height_override = Callable()
	expect(WorldData.get_height(2000, 200) > 50.0, "real world back")


func test_safe_ground() -> void:
	var p := WorldData.get_safe_ground(Vector3(-1690, -5, 2010))   # middle of the harbour basin
	expect(not WorldData.is_underwater(p), "safe ground is dry")
	expect(WorldData.get_slope_deg(p.x, p.z) < 32.0, "safe ground walkable")
	expect(p.distance_to(Vector3(-1690, 0, 2010)) < 260.0, "safe ground nearby")


func test_roads_follow_terrain() -> void:
	var roads := WorldData.get_roads()
	expect(roads.size() >= 8, "road network")
	var total := 0
	var good := 0
	for r in roads:
		var pts: PackedVector3Array = r["points"]
		expect(pts.size() >= 2, "road %s has points" % r["id"])
		for p in pts:
			total += 1
			if absf(p.y - WorldData.get_height(p.x, p.z)) < 1.0:
				good += 1
	expect(float(good) / maxf(total, 1) > 0.9, "road points lie on the terrain (%d/%d)" % [good, total])
	expect(WorldData.get_road(roads[0]["points"][3].x, roads[0]["points"][3].z) > 0.5, "road mask under the road")
	expect(WorldData.get_ports().size() >= 4 and WorldData.get_ferries().size() >= 3, "ports and ferries")
	for f in WorldData.get_ferries():
		var fp: PackedVector2Array = f["points"]
		var wet := 0
		for k in range(1, fp.size() - 1):
			if WorldData.get_height(fp[k].x, fp[k].y) < 0.0:
				wet += 1
		expect(wet >= (fp.size() - 2) * 0.9, "ferry %s stays on water" % f["id"])


func test_textures_and_map() -> void:
	var ht := WorldData.get_height_texture()
	expect(ht != null and ht.get_width() == 4096, "height texture")
	var img := WorldData.get_height_image()
	expect(img != null and img.get_format() == Image.FORMAT_R16, "R16 height image")
	expect(WorldData.get_splat_texture() != null, "splat texture")
	expect(WorldData.get_biome_texture() != null, "biome texture")
	expect(WorldData.get_map_texture() != null and WorldData.get_map_texture().get_width() >= 1024, "map image")
	var p := Vector3(1234, 0, -987)
	var uv := WorldData.world_to_map_uv(p)
	var back := WorldData.map_uv_to_world(uv)
	expect_near(back.x, p.x, 1e-3, "map uv round trip x")
	expect_near(back.z, p.z, 1e-3, "map uv round trip z")
	expect(WorldData.world_to_map_uv(Vector3(-4096, 0, -4096)).is_equal_approx(Vector2.ZERO), "uv origin is NW corner")


func test_raycast_terrain() -> void:
	var hit := WorldData.raycast_terrain(Vector3(2000, 400, 200), Vector3.DOWN, 1000.0)
	expect(hit["hit"], "ray hits")
	expect_near((hit["position"] as Vector3).y, WorldData.get_height(2000, 200), 0.05, "hit height")
	var miss := WorldData.raycast_terrain(Vector3(0, 2000, 0), Vector3.UP, 100.0)
	expect(not miss["hit"], "ray into the sky misses")
