extends TestCase
## World content: streaming framework, providers, determinism, budgets, collision pool,
## vegetation rules/density scaling, building kit, bridges (walkability).


## Scatters `per_cell` boxes per cell; records which thread built it.
class GridProvider extends ContentProvider:
	var per_cell := 6
	var built_on_main := 0
	var built := 0
	var step_delay_usec := 0
	var mesh: Mesh
	var _m := Mutex.new()

	func _init(p_id: StringName = &"grid", size: float = 32.0, rng_m: float = 64.0) -> void:
		id = p_id
		cell_size = size
		range_m = rng_m
		unload_margin = 16.0
		var g := GeoBuilder.new()
		g.box(Transform3D.IDENTITY, Vector3.ONE)
		mesh = g.to_mesh()

	func build_cell(cell: ContentCell) -> void:
		_m.lock()
		built += 1
		if OS.get_thread_caller_id() == OS.get_main_thread_id():
			built_on_main += 1
		_m.unlock()
		var p := CellPayload.new()
		var buf := PackedFloat32Array()
		var rng := cell.rng()
		for i in per_cell:
			var x := cell.rect.position.x + rng.randf() * cell_size
			var z := cell.rect.position.y + rng.randf() * cell_size
			CellPayload.write_instance(buf, Transform3D(Basis(), Vector3(x, 0, z) - cell.origin()), Color(rng.randf(), 1, 1, 1))
			p.add_collider(&"cylinder", Transform3D(Basis(), Vector3(x, 1, z)), Vector3(0.3, 2, 0))
		p.add_multimesh(mesh, null, buf, per_cell, AABB(Vector3(-cell_size, -1, -cell_size), Vector3(cell_size * 2, 2, cell_size * 2)))
		cell.payload = p

	func instantiate_step(cell: ContentCell) -> bool:
		if step_delay_usec > 0:
			# busy-wait: a sleep can oversleep by milliseconds on a loaded machine
			var t0 := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t0 < step_delay_usec:
				pass
		return super.instantiate_step(cell)


func _content(providers: Array = []) -> WorldContent:
	var wc := WorldContent.new()
	wc.use_default_providers = false
	add_child(wc)
	for p: ContentProvider in providers:
		wc.register_provider(p)
	return wc


func _focus_at(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	return n


# --- framework ---------------------------------------------------------------------------------

func test_hash_is_deterministic_and_spread() -> void:
	expect_eq(ContentHash.hash4(1, 2, 3, 4), ContentHash.hash4(1, 2, 3, 4), "same inputs")
	expect(ContentHash.hash4(1, 2, 3, 4) != ContentHash.hash4(1, 2, 3, 5), "different inputs differ")
	expect(ContentHash.hash4(-5, 7) >= 0, "non-negative")
	var sum := 0.0
	for i in 2000:
		sum += ContentHash.unit2(9, i, -i * 3)
	expect_near(sum / 2000.0, 0.5, 0.04, "unit() is uniform-ish")
	expect_eq(ContentHash.hash_name("trees"), ContentHash.hash_name("trees"), "name hash stable")
	var a := ContentHash.rng(42)
	var b := ContentHash.rng(42)
	expect_eq(a.randi(), b.randi(), "seeded rng")


func test_geo_builder_front_faces_match_normals() -> void:
	var g := GeoBuilder.new()
	g.box(Transform3D(Basis(Vector3.UP, 0.4), Vector3(1, 2, 3)), Vector3(1, 2, 0.5))
	g.cylinder(Vector3.ZERO, Vector3(0.5, 3, 0.2), 0.4, 0.2, 7, Color.WHITE, 3, true)
	g.cylinder(Vector3(2, 0, 0), Vector3(2, 2, 0), 0.4, 0.4, 6, Color.WHITE, 3, false)
	g.cone(Vector3(4, 0, 0), Vector3(4, 2, 0), 1.0, 9)
	g.blob(Vector3(0, 5, 0), 1.0, 1, Color.GREEN)
	g.blob(Vector3(0, 8, 0), 1.0, 1, Color.GREEN, null, 0.0, Vector3.ONE, Vector3.INF, 0.0, Color(-1, 0, 0), Vector2.ZERO, true)
	g.tube(PackedVector3Array([Vector3(0, 0, 5), Vector3(0.5, 1, 5), Vector3(1, 2, 5.5)]), PackedFloat32Array([0.3, 0.2, 0.1]), 6, Color.WHITE, Color(-1, 0, 0), Vector2.ZERO, Vector2.ZERO, true)
	g.extrude(PackedVector2Array([Vector2(0, 0), Vector2(3, 0), Vector2(3, -2), Vector2(0, -2)]), 0.0, 2.0, Color.WHITE, 3)
	g.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0, -2), Vector2(3, -2), Vector2(3, 0)]), 3.0, 4.0, Color.WHITE, 3)
	var bad := 0
	for k in range(0, g.indices.size(), 3):
		var i0 := g.indices[k]
		var i1 := g.indices[k + 1]
		var i2 := g.indices[k + 2]
		var geo := (g.verts[i1] - g.verts[i0]).cross(g.verts[i2] - g.verts[i0])
		if geo.length_squared() < 1e-10:
			continue
		var n := g.normals[i0] + g.normals[i1] + g.normals[i2]
		# Godot front faces are clockwise: the right-hand normal of the emitted order points inward
		if geo.dot(n) >= 0.0:
			bad += 1
	expect_eq(bad, 0, "triangles facing against their normals")
	expect(g.triangle_count() > 100, "geometry generated")


func test_payload_buffer_layout_matches_multimesh() -> void:
	var t := Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), 0.7).scaled(Vector3(1.5, 2, 1.5)), Vector3(3, 4, 5))
	var buf := PackedFloat32Array()
	CellPayload.write_instance(buf, Transform3D.IDENTITY, Color(0, 0, 0, 0))
	CellPayload.write_instance(buf, t, Color(0.1, 0.2, 0.3, 0.4))
	var back := CellPayload.read_instance(buf, 1)
	expect(back.is_equal_approx(t), "read_instance round trip")
	if DisplayServer.get_name() == "headless":
		return     # the dummy renderer stores no multimesh data (checked by the playtests)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = 2
	mm.buffer = buf
	expect(mm.get_instance_transform(1).is_equal_approx(t), "MultiMesh reads the same transform")
	expect(mm.get_instance_custom_data(1).is_equal_approx(Color(0.1, 0.2, 0.3, 0.4)), "custom data layout")


func test_cells_stream_in_and_out_around_focus() -> void:
	var p := GridProvider.new(&"grid", 32.0, 64.0)
	var wc := _content([p])
	var f := _focus_at(Vector3(16, 0, 16))
	wc.setup(f)
	expect(wc.load_now(), "load_now completes")
	var cells := wc.get_cells(&"grid")
	# cells whose closest point is within 64 m of (16,16) on a 32 m grid: compute expected
	var expected := 0
	for j in range(-4, 5):
		for i in range(-4, 5):
			var r := Rect2(i * 32.0, j * 32.0, 32.0, 32.0)
			var c := Vector2(clampf(16.0, r.position.x, r.end.x), clampf(16.0, r.position.y, r.end.y))
			if c.distance_to(Vector2(16, 16)) <= 64.0:
				expected += 1
	expect_eq(cells.size(), expected, "cell count in range")
	var all_active := true
	for c in cells:
		all_active = all_active and c.is_active()
	expect(all_active, "all cells active after load_now")
	expect_eq(p.built_on_main, 0, "threaded builds ran on workers")
	var stats := wc.get_stats()
	expect_eq(int(stats["providers"][&"grid"]["instances"]), expected * p.per_cell, "instance stats")
	expect_eq(int(stats["multimesh_nodes"]), expected, "one multimesh per cell")
	# move away: everything released, nodes recycled
	f.global_position = Vector3(2000, 0, 2000)
	expect(wc.load_now(), "load_now at new place")
	var old := wc.get_cell(&"grid", Vector2i(0, 0))
	expect(old == null, "old cells released")
	expect(wc.get_cell(&"grid", p.coord_of(2000, 2000)) != null, "new cells loaded")
	expect(int(wc.get_stats()["cells_released"]) >= expected, "release counted")
	wc.queue_free()
	f.queue_free()


func test_cell_generation_is_deterministic() -> void:
	var p := GridProvider.new(&"det", 64.0, 64.0)
	p.per_cell = 50
	var a := ContentCell.new(p, Vector2i(3, -7))
	var b := ContentCell.new(p, Vector2i(3, -7))
	var c := ContentCell.new(p, Vector2i(4, -7))
	p.build_cell(a)
	p.build_cell(b)
	p.build_cell(c)
	var ba: PackedFloat32Array = (a.payload as CellPayload).multimeshes[0]["buffer"]
	var bb: PackedFloat32Array = (b.payload as CellPayload).multimeshes[0]["buffer"]
	var bc: PackedFloat32Array = (c.payload as CellPayload).multimeshes[0]["buffer"]
	expect(ba == bb, "same cell -> identical buffer")
	expect(ba != bc, "neighbour cell differs")
	expect_eq(a.seed, b.seed, "seed stable")


func test_main_thread_budget_slices_instantiation() -> void:
	var p := GridProvider.new(&"slow", 32.0, 96.0)
	p.step_delay_usec = 1500
	var wc := _content([p])
	wc.frame_budget_usec = 2000
	var f := _focus_at(Vector3(0, 0, 0))
	wc.setup(f)
	await frames(2)
	# wait for some builds to complete, then measure per-frame main-thread time
	var worst := 0
	var frames_n := 0
	var times := PackedInt32Array()
	while not wc.is_settled() and frames_n < 600:
		await frames(1)
		frames_n += 1
		var us := int(wc.get_stats()["main_usec_last"])
		worst = maxi(worst, us)
		if us > 0:
			times.append(us)
	expect(wc.is_settled(), "settled eventually (%d frames)" % frames_n)
	# one step may overrun the budget: budget + one step + overhead. Allow rare outliers from the
	# OS preempting the main thread on a shared machine, never systematic overruns.
	var bound := 2000 + 1500 + 1500
	var over := 0
	for us in times:
		if us > bound:
			over += 1
	times.sort()
	var median := times[times.size() / 2] if not times.is_empty() else 0
	expect(median <= 2000 + 1500 + 500, "median main-thread time per frame within budget + one step (%d us)" % median)
	expect(over <= maxi(1, times.size() / 10), "frames over budget + one step: %d of %d (worst %d us)" % [over, times.size(), worst])
	expect(worst < bound * 3, "no runaway frame (worst %d us)" % worst)
	expect(frames_n > 5, "work was spread over frames (%d)" % frames_n)
	wc.queue_free()
	f.queue_free()


func test_provider_registration_and_refresh() -> void:
	var p := GridProvider.new(&"reg", 64.0, 64.0)
	var wc := _content([p])
	expect(wc.get_provider(&"reg") == p, "registered")
	expect(p.content == wc, "content back-reference")
	var f := _focus_at(Vector3(10, 0, 10))
	wc.setup(f)
	wc.load_now()
	var built_before := p.built
	wc.refresh(&"reg")
	wc.load_now()
	expect(p.built > built_before, "refresh rebuilt cells")
	p.enabled = false
	wc.load_now()
	expect(wc.get_cells(&"reg").is_empty(), "disabled provider releases its cells")
	wc.unregister_provider(&"reg")
	expect(wc.get_provider(&"reg") == null, "unregistered")
	wc.queue_free()
	f.queue_free()


func test_exclusion_zones() -> void:
	var wc := _content()
	wc.add_exclusion(Vector3(100, 0, 100), 20.0, ContentExclusions.TAG_TREES, 10.0)
	var cap := wc.add_exclusion_capsule(Vector2(0, 0), Vector2(0, 50), 3.0, ContentExclusions.TAG_ALL)
	var ex := wc.get_exclusions()
	expect(ex.blocked(100, 110, ContentExclusions.TAG_TREES), "inside circle")
	expect(not ex.blocked(100, 110, ContentExclusions.TAG_GRASS), "other tags unaffected")
	expect_near(ex.factor(100, 125, ContentExclusions.TAG_TREES), 0.5, 0.01, "soft falloff")
	expect_near(ex.factor(100, 140, ContentExclusions.TAG_TREES), 1.0, 0.001, "outside")
	expect(ex.blocked(1, 25, ContentExclusions.TAG_GRASS), "capsule")
	expect(ex.touches(Rect2(80, 80, 10, 10), ContentExclusions.TAG_TREES), "touches rect")
	wc.remove_exclusion(cap)
	expect(not wc.get_exclusions().blocked(1, 25, ContentExclusions.TAG_GRASS), "removed")
	wc.queue_free()


func test_collider_pool_activates_near_focus_only() -> void:
	var wc := _content()
	await frames(1)
	var list: Array[Dictionary] = []
	for i in 200:
		list.append({"type": &"cylinder", "transform": Transform3D(Basis(), Vector3(i * 4.0 - 400.0, 1.0, 0.0)), "size": Vector3(0.4, 2.0, 0)})
	var gid := wc.colliders.add_group(list)
	wc.colliders.radius = 20.0
	wc.colliders.update(Vector3(0, 0, 0), 1.0)
	var n := wc.colliders.active_count()
	expect(n >= 9 and n <= 11, "only colliders within 20 m (%d)" % n)
	await physics_frames(2)
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -5, 0))
	var hit := wc.get_world_3d().direct_space_state.intersect_ray(q)
	expect(not hit.is_empty() and hit["collider"] == wc.colliders, "ray hits the pooled trunk (collider = pool node)")
	wc.colliders.update(Vector3(300, 0, 0), 1.0)
	await physics_frames(2)
	hit = wc.get_world_3d().direct_space_state.intersect_ray(q)
	expect(hit.is_empty(), "far trunk released")
	wc.colliders.max_bodies = 4
	wc.colliders.update(Vector3(-100, 0, 0), 1.0)
	expect(wc.colliders.active_count() <= 4, "cap respected")
	wc.colliders.remove_group(gid)
	expect_eq(wc.colliders.entry_count(), 0, "group removed")
	expect_eq(wc.colliders.active_count(), 0, "bodies released")
	wc.queue_free()


# --- vegetation --------------------------------------------------------------------------------

func test_biome_enum_mirrors_world_data() -> void:
	for k: String in WorldData.Biome.keys():
		expect(VegetationRules.Bio.has(k), "VegetationRules.Bio has %s" % k)
		if VegetationRules.Bio.has(k):
			expect_eq(int(VegetationRules.Bio[k]), int(WorldData.Biome[k]), "Bio.%s value" % k)


func test_vegetation_evaluation_is_deterministic() -> void:
	WorldData.load_world()
	if not WorldData.has_world_data():
		fail("world data needed")
		return
	var cfg := VegetationSettings.current()
	# an Earth Kingdom forest block: same answers on every evaluation
	var g0 := Vector2i(int(2030 / VegetationScatter.GRID), int(-1080 / VegetationScatter.GRID))
	var a := _scatter_signature(g0, cfg)
	var b := _scatter_signature(g0, cfg)
	expect(a.size() > 40, "forest block has vegetation (%d)" % (a.size() / 4))
	expect(a == b, "identical on re-evaluation")


func _scatter_signature(g0: Vector2i, cfg: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in 12:
		for i in 12:
			for it: VegetationScatter.Item in VegetationScatter.evaluate(g0.x + i, g0.y + j, cfg, null):
				out.append(it.pos.x)
				out.append(it.pos.z)
				out.append(float(it.layer))
				out.append(float(String(it.species).hash() & 0xffff))
	return out


func test_density_and_ranges_scale_with_settings() -> void:
	var snap := Settings.snapshot()
	Settings.apply_preset("mobile")
	var lo := VegetationSettings.current()
	var plo := PropSettings.current()
	Settings.apply_preset("high")
	var hi := VegetationSettings.current()
	var phi := PropSettings.current()
	Settings.apply_preset("ultra")
	var ul := VegetationSettings.current()
	Settings.restore_snapshot(snap)
	for k: String in ["tree_range", "far_range", "small_range", "grass_range", "tree_density", "small_density", "grass_density"]:
		expect(float(lo[k]) < float(hi[k]), "%s grows mobile -> high (%s < %s)" % [k, lo[k], hi[k]])
		expect(float(hi[k]) <= float(ul[k]), "%s grows high -> ultra" % k)
	expect(float(lo["tree_density"]) >= 0.55, "forests stay forests on phones")
	for k: String in ["poi_range", "landmark_range", "road_range", "cave_range", "poi_lod0"]:
		expect(float(plo[k]) <= float(phi[k]), "%s mobile <= high" % k)
	# the plant count of a real forest block follows the density setting
	WorldData.load_world()
	if WorldData.has_world_data():
		var g0 := Vector2i(int(2030 / VegetationScatter.GRID), int(-1080 / VegetationScatter.GRID))
		var n_lo := _scatter_signature(g0, lo).size() / 4
		var n_hi := _scatter_signature(g0, hi).size() / 4
		expect(n_lo < n_hi, "fewer plants on mobile (%d < %d)" % [n_lo, n_hi])


func test_streaming_budgets_follow_settings() -> void:
	var snap := Settings.snapshot()
	var wc := _content()
	Settings.apply_preset("mobile")
	wc._apply_settings()
	var mobile_budget := wc.frame_budget_usec
	var mobile_radius := wc.colliders.radius
	Settings.apply_preset("high")
	wc._apply_settings()
	var high_budget := wc.frame_budget_usec
	Settings.restore_snapshot(snap)
	wc._apply_settings()
	expect(mobile_budget < high_budget, "smaller main-thread budget on mobile (%d < %d)" % [mobile_budget, high_budget])
	expect(mobile_budget <= 2000 and high_budget <= 3000, "budgets stay a small part of a 16 ms frame")
	expect(mobile_radius < 48.0, "smaller collider radius on mobile")
	expect(wc.max_jobs >= 1 and wc.max_jobs <= 3, "worker jobs bounded (%d)" % wc.max_jobs)
	wc.queue_free()


# --- terrain holes, structures -----------------------------------------------------------------

func test_terrain_holes_punch_heightfield() -> void:
	TerrainHoles.clear()
	var v0 := TerrainHoles.version
	var id := TerrainHoles.add_capsule(Vector2(10, 10), Vector2(20, 10), 2.0)
	expect(TerrainHoles.version > v0, "version bumps on change")
	expect(TerrainHoles.contains(15, 11), "inside the capsule")
	expect(not TerrainHoles.contains(15, 14), "outside the capsule")
	expect(TerrainHoles.touches(Rect2(0, 0, 12, 12)), "touches a patch")
	var h := PackedFloat32Array()
	h.resize(32 * 32)
	h.fill(5.0)
	TerrainHoles.punch(Vector2(0, 0), 32, h)
	expect(is_nan(h[10 * 32 + 15]), "sample in the hole is NaN (Jolt hole)")
	expect(not is_nan(h[14 * 32 + 15]), "sample outside stays")
	var holes := 0
	for x in h:
		if is_nan(x):
			holes += 1
	expect(holes > 20 and holes < 80, "hole size plausible (%d samples)" % holes)
	TerrainHoles.remove(id)
	expect_eq(TerrainHoles.count(), 0, "removed")


func test_kit_build_collision_markers_and_lods() -> void:
	NationPalette.prepare_materials()
	var tris := []
	for lod in 3:
		var kit := BuildingKit.new(NationPalette.get_palette(&"earth_kingdom"), lod, 11)
		BuildingPresets.house(kit, Transform3D.IDENTITY, {"w": 8.0, "d": 6.0, "floors": 2, "interior": true, "lanterns": true})
		var res := kit.build()
		tris.append(res.triangle_count)
		if lod == 0:
			expect(not res.surfaces.is_empty(), "mesh surfaces")
			expect(not res.boxes.is_empty() or not res.faces.is_empty(), "collision recorded")
			expect(res.markers.has(&"door"), "door marker")
			expect(not res.lights.is_empty(), "lantern lights recorded")
			var body := res.make_body()
			expect(body.get_child_count() > 0, "static body has shapes")
			body.free()
	expect(int(tris[1]) < int(tris[0]) and int(tris[2]) < int(tris[1]), "LODs get cheaper %s" % str(tris))


func test_rope_bridge_is_walkable() -> void:
	NationPalette.prepare_materials()
	var kit := BuildingKit.new(NationPalette.get_palette(&"air_nomads"), 0, 3)
	var a := Vector3(0, 40, 0)
	var b := Vector3(46, 41, 8)
	var sag := 4.5
	BridgeBuilder.suspended(kit, a, b, 3.2, sag)
	var body := kit.build().make_body()
	add_child(body)
	var cb := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	cb.add_child(cs)
	cb.collision_layer = 0
	cb.collision_mask = Layers.WORLD
	cb.floor_snap_length = 0.6
	add_child(cb)
	var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	cb.global_position = a + dir * 1.0 + Vector3(0, 0.3, 0)
	await physics_frames(2)
	var worst := 0.0
	var s := 0.0
	for i in 900:
		await physics_frames(1)
		var dt := get_physics_process_delta_time()
		cb.velocity = Vector3(dir.x * 4.0, cb.velocity.y - 20.0 * dt, dir.z * 4.0)
		cb.move_and_slide()
		s = (cb.global_position - a).dot(dir) / length
		worst = maxf(worst, BridgeBuilder.deck_y(a, b, sag, clampf(s, 0.0, 1.0)) - cb.global_position.y)
		if s > 0.97 or cb.global_position.y < a.y - sag - 10.0:
			break
	expect(s > 0.97, "walked across the span (%.2f)" % s)
	expect(worst < 0.5, "stayed on the deck (max %.2f m below)" % worst)
	# the rope barriers keep a body that walks sideways on the bridge
	cb.global_position = a.lerp(b, 0.5) + Vector3(0, -sag + 0.5, 0)
	cb.velocity = Vector3.ZERO
	var side := dir.cross(Vector3.UP)
	for i in 120:
		await physics_frames(1)
		var dt := get_physics_process_delta_time()
		cb.velocity = Vector3(side.x * 4.0, cb.velocity.y - 20.0 * dt, side.z * 4.0)
		cb.move_and_slide()
	var mid_deck := BridgeBuilder.deck_y(a, b, sag, 0.5)
	expect(cb.global_position.y > mid_deck - 1.0, "rope barrier: did not fall off sideways (y %.1f, deck %.1f)" % [cb.global_position.y, mid_deck])
	cb.queue_free()
	body.queue_free()


func test_resource_pickup_adds_items_and_regrows() -> void:
	var before := GameState.item_count(&"jade_shard")
	var pk := ResourcePickup.create(&"jade_shard", 2, PropFx.pickup_mesh(&"jade"), "Jade Shard", 0.2)
	add_child(pk)
	var fired := [false]
	pk.harvested.connect(func() -> void: fired[0] = true)
	expect(pk.can_interact(null), "available")
	pk.interact(null)
	expect_eq(GameState.item_count(&"jade_shard"), before + 2, "GameState.add_item called")
	expect(fired[0], "harvested signal")
	expect(not pk.is_available() and not pk.model.visible, "hidden while regrowing")
	pk.interact(null)
	expect_eq(GameState.item_count(&"jade_shard"), before + 2, "no double harvest")
	await seconds(0.4)
	expect(pk.is_available() and pk.model.visible, "regrew")
	pk.queue_free()


func test_world_structures_build_from_world_data() -> void:
	WorldData.load_world()
	if not WorldData.has_world_data():
		fail("world data needed")
		return
	NationPalette.prepare_materials()
	var built := 0
	var types := {}
	for poi in WorldData.get_pois():
		if not PoiStructures.handles(poi):
			continue
		var k0: KitResult = PoiStructures.build(poi, 0)["kit"]
		var k1: KitResult = PoiStructures.build(poi, 1)["kit"]
		expect(k0.triangle_count > 50, "%s has geometry" % poi["id"])
		expect(k1.triangle_count <= k0.triangle_count, "%s LOD1 not heavier" % poi["id"])
		built += 1
		types[poi["type"]] = true
	expect(built >= 15, "POI structures built (%d)" % built)
	for t: StringName in [&"shrine", &"camp", &"training_ground", &"ruin", &"dock", &"vista", &"spirit_spot", &"resource", &"landmark"]:
		expect(types.has(t), "POI type %s present" % t)
	for w in WorldData.get_waterfalls():
		expect((WaterfallBuilder.build(w)["path"] as PackedVector3Array).size() > 4, "waterfall %s path" % w["id"])
	for br in WorldData.get_bridges():
		expect(not (BridgeBuilder.build(br)["kit"] as KitResult).faces.is_empty(), "bridge %s deck collision" % br["id"])
	for ar in WorldData.get_arches():
		expect((ArchBuilder.build(ar)["kit"] as KitResult).triangle_count > 200, "arch %s" % ar["id"])
	for poi in WorldData.get_pois():
		if poi["type"] == &"cave":
			var d := CaveBuilder.build(poi)
			expect(not (d["faces"] as PackedVector3Array).is_empty(), "cave %s tunnel collision" % poi["id"])
			var hole: Array = d["hole"]
			expect((hole[0] as Vector2).distance_to(hole[1]) > 2.0, "cave %s hole capsule" % poi["id"])


func test_claims_hand_features_to_other_builders() -> void:
	WorldData.load_world()
	ContentClaims.clear()
	var lp := LandmarkProvider.new()
	lp.configure()
	var n0 := _feature_count(lp)
	ContentClaims.claim(&"omashu_great_bridge", &"settlements")
	expect(ContentClaims.is_claimed(&"omashu_great_bridge"), "claimed")
	lp.tick()
	var n1 := _feature_count(lp)
	ContentClaims.clear()
	if WorldData.has_world_data():
		expect_eq(n1, n0 - 1, "claimed bridge is skipped (%d -> %d)" % [n0, n1])


func _feature_count(lp: LandmarkProvider) -> int:
	var n := 0
	for k: Vector2i in lp._by_cell:
		n += (lp._by_cell[k] as Array).size()
	return n
