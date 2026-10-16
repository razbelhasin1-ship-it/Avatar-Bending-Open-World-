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
			OS.delay_usec(step_delay_usec)
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
	while not wc.is_settled() and frames_n < 600:
		await frames(1)
		frames_n += 1
		worst = maxi(worst, int(wc.get_stats()["main_usec_last"]))
	expect(wc.is_settled(), "settled eventually (%d frames)" % frames_n)
	# one step may overrun the budget; never more than budget + one step + overhead
	expect(worst < 2000 + 1500 + 1500, "main-thread time per frame bounded (worst %d us)" % worst)
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
