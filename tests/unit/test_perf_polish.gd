extends TestCase
## perf_polish (wave 4, docs/qa/perf_polish.md): the phone settlement LOD chain (outline-less
## distant LODs, quadrant HLOD LOD0 with collision identical to the desktop build, silhouette-kit
## LOD1, merged surfaces, mesh LODs), night-only content, visibility parents, garden / forest
## caps, the shader warm-up (program, a full headless run on its stage and its cleanup), the
## occluder fader (dither twins, fade + restore) and the lock-on close-quarters framing.

const E := ElementDefs.Element

var _saved_graphics := {}


func before_each() -> void:
	_saved_graphics = Settings.get_section("graphics")


func after_each() -> void:
	for k: String in _saved_graphics:
		Settings.set_value("graphics", k, _saved_graphics[k])
	WorldData.use_flat_world(false)
	GroundSampler.clear_zones()
	for c in get_children():
		c.queue_free()
	await frames(2)


# --- materials / settings ---------------------------------------------------------------------------

func test_distant_lods_have_no_outline_pass() -> void:
	for slot: StringName in [&"solid", &"ice"]:
		var with_line := NationPalette.material(slot) as ShaderMaterial
		var flat := NationPalette.material(slot, false) as ShaderMaterial
		expect(with_line.next_pass != null, "%s keeps its ink outline near" % slot)
		expect(flat.next_pass == null, "%s without outline pass for LOD1 / silhouettes" % slot)
		expect(flat.shader == with_line.shader, "%s: same toon shading" % slot)
		expect_eq(flat.get_shader_parameter(&"rim_strength"), with_line.get_shader_parameter(&"rim_strength"), "%s same look" % slot)
	expect(NationPalette.material(&"glow", false) == NationPalette.material(&"glow"), "glow has no outline anyway: one material")
	# the default call is unchanged (same cached material as before the change)
	expect(NationPalette.material(&"solid") == NationPalette.material(&"solid", true), "default = outlined")


func test_phone_budget_keys_and_lod0_range() -> void:
	Settings.apply_preset("mobile")
	var c := SettlementSettings.current()
	expect_eq(int(c["lod1_kit"]), 2, "phones build LOD1 from the silhouette recipes")
	expect(bool(c["merge_far"]) and bool(c["quad_lod0"]) and bool(c["mesh_lods"]), "phone LOD chain on")
	expect_near(SettlementSettings.lod0_end_for(c, 128.0), 96.5, 0.1, "128 m cells: half diagonal + 6 m")
	expect_near(SettlementSettings.lod0_end_for(c, 96.0), 73.9, 0.1, "96 m cells (Air Temple)")
	expect(SettlementSettings.lod0_end_for(c, 128.0) >= 128.0 * 0.7071, "LOD0 still covers the camera's own cell")
	Settings.apply_preset("high")
	var h := SettlementSettings.current()
	expect_eq(int(h["lod1_kit"]), 1, "desktop LOD1 unchanged")
	expect(not bool(h["merge_far"]) and not bool(h["quad_lod0"]) and not bool(h["mesh_lods"]), "desktop chain unchanged")
	expect_near(SettlementSettings.lod0_end_for(h, 128.0), 220.0, 0.01, "desktop LOD0 range unchanged")
	expect_eq(float(VegetationSettings.current()["far_density"]), 1.0, "desktop keeps every far impostor")
	Settings.apply_preset("mobile")
	expect(float(VegetationSettings.current()["far_density"]) < 0.6, "phones thin the far impostor forests")


func test_merger_slot_map_folds_surfaces() -> void:
	var kit := BuildingKit.new(NationPalette.get_palette(&"water_tribe"), 0, 3)
	kit.box(Vector3(0, 1, 0), Vector3(2, 2, 2), &"wall")
	kit.box(Vector3(3, 1, 0), Vector3(2, 2, 2), &"ice", true, &"ice")
	kit.lantern(Vector3(0, 2.5, -1.2), {"style": &"ice"})
	var r := kit.build()
	expect(r.surfaces.size() >= 2, "kit built several surfaces (%d)" % r.surfaces.size())
	var m := KitMerger.new()
	m.slot_map = SettlementProvider.MERGED_SLOTS
	m.add(r)
	var merged := m.to_result()
	expect_eq(merged.surfaces.size(), 1, "merged into one surface (one draw call)")
	expect_eq(merged.triangle_count, r.triangle_count, "no triangle lost")


# --- settlement cells -------------------------------------------------------------------------------------

func test_phone_quadrant_lod0_keeps_collision_and_lightens() -> void:
	if not WorldData.has_world_data():
		return
	Settings.apply_preset("mobile")
	var p := Settlements.plan(Settlements.WATER_TRIBE)
	var b := Settlements.builder(Settlements.WATER_TRIBE)
	var prov := SettlementProvider.new(p, b)
	prov.cfg = SettlementSettings.current()
	# the cell under the Water spawn (the heaviest one)
	var sp := WorldData.get_spawn(E.WATER).origin
	var coord := Vector2i(int(floor(sp.x / p.cell_size)), int(floor(sp.z / p.cell_size)))
	expect(p.has_cell(coord), "the spawn cell has pieces")
	var origin := Vector3((coord.x + 0.5) * p.cell_size, 0, (coord.y + 0.5) * p.cell_size)
	var q := prov.build_quads(coord, origin)
	var full := prov.build_lods(coord, origin)
	var r0: KitResult = full[0]
	var qr0: KitResult = q["r0"]
	expect_eq(qr0.boxes.size(), r0.boxes.size(), "same collision boxes as the full LOD0 build")
	expect_eq(qr0.faces.size(), r0.faces.size(), "same collision faces as the full LOD0 build")
	expect_eq(qr0.lights.size(), r0.lights.size(), "same lights / glow records")
	var fine := 0
	var mid := 0
	for i in 4:
		var f: KitResult = q["fine"][i]
		var m: KitResult = q["mid"][i]
		fine += f.triangle_count
		mid += m.triangle_count
		expect(m.surfaces.size() <= 1, "quadrant %d mid is one surface" % i)
		if not f.surfaces.is_empty() and not m.surfaces.is_empty():
			expect(f.aabb.is_equal_approx(m.aabb), "quadrant %d fine and mid share one AABB (exact hand-over)" % i)
			var c := f.aabb.get_center()
			var want := Vector2(p.cell_size * 0.25 * (1 if i % 2 == 1 else -1), p.cell_size * 0.25 * (1 if i >= 2 else -1))
			expect(Vector2(c.x, c.z).distance_to(want) < 0.01, "quadrant %d AABB centred on the quadrant" % i)
	expect_eq(fine, r0.triangle_count, "the fine quadrants are the full detail split four ways")
	expect(mid * 2 < fine, "the mid version is much lighter (%d vs %d triangles)" % [mid, fine])
	var light_lod1: KitResult = q["lod1"]
	prov.cfg["lod1_kit"] = 1
	var regular_lod1: KitResult = prov.build_lods(coord, origin)[1]
	expect(light_lod1.triangle_count * 2 < regular_lod1.triangle_count, "phone LOD1 lighter than the regular one (%d vs %d)" % [
			light_lod1.triangle_count, regular_lod1.triangle_count])
	expect(prov.quad_fine() > p.cell_size * 0.25 * sqrt(2.0), "the quadrant around the camera is always full detail")


func test_phone_cell_payload_hierarchy() -> void:
	if not WorldData.has_world_data():
		return
	Settings.apply_preset("mobile")
	var p := Settlements.plan(Settlements.AIR_TEMPLE)
	var prov := SettlementProvider.new(p, Settlements.builder(Settlements.AIR_TEMPLE))
	prov.configure()
	var sp := WorldData.get_spawn(E.AIR).origin
	var coord := Vector2i(int(floor(sp.x / p.cell_size)), int(floor(sp.z / p.cell_size)))
	var cell := ContentCell.new(prov, coord)
	SettlementFx.prepare()
	prov.build_cell(cell)
	var pay := cell.payload as CellPayload
	var tags: Array = []
	var parent_idx := -1
	for i in pay.meshes.size():
		var d: Dictionary = pay.meshes[i]
		tags.append(String(d["tag"]))
		if String(d["tag"]).ends_with("_lod1"):
			parent_idx = i
	expect(parent_idx >= 0, "the LOD1 parent is in the payload")
	var children := 0
	for i in pay.meshes.size():
		var d: Dictionary = pay.meshes[i]
		var tag := String(d["tag"])
		if tag.contains("_lod0q") or tag.contains("_lod0m"):
			children += 1
			expect(i > parent_idx, "%s spawns after its visibility parent" % tag)
			expect(String(d["vis_parent"]).ends_with("_lod1"), "%s is a child of the cell's LOD1 (HLOD)" % tag)
			for s: Array in d["surfaces"]:
				expect(s.size() == 3, "%s carries its LOD index buffers" % tag)
		if tag.contains("_lod0m") or tag.ends_with("_lod1"):
			for s: Array in d["surfaces"]:
				expect((s[1] as ShaderMaterial).next_pass == null, "%s draws no outline pass" % tag)
	expect(children >= 2, "quadrant meshes present (%d)" % children)
	var glows := 0
	for d: Dictionary in pay.multimeshes:
		if bool(d.get("night_only", false)):
			glows += 1
	expect(glows <= 1, "at most one night-glow MultiMesh per cell")


func test_desktop_lod_handovers_cross_fade() -> void:
	if not WorldData.has_world_data():
		return
	for preset: String in ["high", "mobile"]:
		Settings.apply_preset(preset)
		var p := Settlements.plan(Settlements.WATER_TRIBE)
		var b := Settlements.builder(Settlements.WATER_TRIBE)
		var prov := SettlementProvider.new(p, b)
		prov.configure()
		var far := SettlementFarProvider.new(p, b)
		far.configure()
		var fm := float(prov.cfg["fade_margin"])
		var want := GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if preset == "high" else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		expect_eq(fm > 0.0, preset == "high", "%s: fade margin %.0f m" % [preset, fm])
		SettlementFx.prepare()
		var sp := WorldData.get_spawn(E.WATER).origin
		var coord := Vector2i(int(floor(sp.x / p.cell_size)), int(floor(sp.z / p.cell_size)))
		var cell := ContentCell.new(prov, coord)
		prov.build_cell(cell)
		var seen := {}
		for d: Dictionary in (cell.payload as CellPayload).meshes:
			var tag := String(d["tag"])
			if tag.ends_with("_lod0") or tag.ends_with("_lod1"):
				seen[tag.get_slice("_", tag.get_slice_count("_") - 1)] = true
				expect_eq(int(d["fade"]), want, "%s %s fade mode" % [preset, tag])
				expect_near(float(d["margin"]), fm, 0.01, "%s %s fade band" % [preset, tag])
		if preset == "high":
			expect(seen.has("lod0") and seen.has("lod1"), "desktop cell has LOD0 and LOD1 meshes (%s)" % str(seen.keys()))
		var fcoord := Vector2i(int(floor(sp.x / far.cell_size)), int(floor(sp.z / far.cell_size)))
		var fcell := ContentCell.new(far, fcoord)
		far.build_cell(fcell)
		var subs := 0
		for d: Dictionary in (fcell.payload as CellPayload).meshes:
			subs += 1
			expect_eq(int(d["fade"]), want, "%s silhouette fade mode" % preset)
			expect_near(float(d["margin"]), fm, 0.01, "%s silhouette fade band = LOD1's (same hand-over)" % preset)
		expect(subs > 0, "%s: silhouettes built" % preset)


func test_world_content_night_only_and_visibility_parent() -> void:
	var wc := WorldContent.new()
	wc.use_default_providers = false
	add_child(wc)
	var prov := ContentProvider.new()
	var cell := ContentCell.new(prov, Vector2i.ZERO)
	cell.root = Node3D.new()
	wc.add_child(cell.root)
	var quad := QuadMesh.new()
	var mm := wc.spawn_multimesh(cell, {"mesh": quad, "material": null, "buffer": PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1]),
		"count": 1, "aabb": AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), "night_only": true, "tag": &"glow"})
	var sun_before: Variant = WorldShaderGlobals.get_value(&"world_sun_color")
	WorldShaderGlobals.set_value(&"world_sun_color", Color(1.0, 0.95, 0.9))
	wc._update_night()
	expect(not mm.visible and not wc.is_night(), "night glows are not drawn by day")
	WorldShaderGlobals.set_value(&"world_sun_color", Color(0.02, 0.02, 0.05))
	wc._update_night()
	expect(mm.visible and wc.is_night(), "they come back at dusk")
	WorldShaderGlobals.set_value(&"world_sun_color", Color(0.47, 0.47, 0.47))
	wc._update_night()
	expect(mm.visible, "hysteresis: stays on until the sun is clearly up")
	if sun_before != null:
		WorldShaderGlobals.set_value(&"world_sun_color", sun_before)
	var g := GeoBuilder.new()
	g.box(Transform3D.IDENTITY, Vector3.ONE)
	var arr := g.arrays()
	wc.spawn_mesh(cell, {"surfaces": [[arr, null]], "tag": &"x_lod1", "vis_begin": 50.0})
	var child := wc.spawn_mesh(cell, {"surfaces": [[arr, null, {}]], "tag": &"x_lod0q0", "vis_end": 30.0, "vis_parent": &"x_lod1"})
	expect(not child.visibility_parent.is_empty(), "visibility parent set from the payload tag")
	expect(child.get_node_or_null(child.visibility_parent) == cell.root.get_node("x_lod1"), "points at the LOD1 mesh")
	wc.queue_free()


func test_mesh_lods_keep_vertices() -> void:
	var g := GeoBuilder.new()
	for i in 40:
		g.cylinder(Vector3(i * 1.5, 0, 0), Vector3(i * 1.5, 3, 0), 0.5, 0.5, 16, Color.WHITE, 3, true)
	var arr := g.arrays()
	var verts := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var lods := MeshLods.for_arrays(arr)
	expect(not lods.is_empty(), "LOD buffers generated for a %d-triangle surface" % ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3))
	var chain := MeshLods.chain(lods)
	expect(not chain.is_empty() and chain[0] < (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3, "coarser than the base (%s)" % str(chain))
	for k: float in lods:
		for idx in (lods[k] as PackedInt32Array):
			if idx >= verts:
				fail("LOD index %d outside the unchanged vertex array (%d)" % [idx, verts])
				return
	var small := GeoBuilder.new()
	small.box(Transform3D.IDENTITY, Vector3.ONE)
	expect(MeshLods.for_arrays(small.arrays()).is_empty(), "tiny surfaces get no LOD buffers")


func test_character_mesh_lods_keep_the_mesh() -> void:
	var rig := HumanoidRig.create({"preset": &"water_tribe", "seed": 11})
	add_child(rig)
	var m := rig.mesh_instance.mesh
	expect(m != null and m.get_surface_count() == 2, "body + detail surfaces")
	expect((m.surface_get_material(0) as ShaderMaterial).next_pass != null, "body keeps its outline material")
	var arr := m.surface_get_arrays(0)
	expect((arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() > 0, "skinning data kept")


# --- shader warm-up ---------------------------------------------------------------------------------------

func test_warmup_program_covers_the_kit() -> void:
	for e in [E.AIR, E.EARTH, E.FIRE, E.WATER]:
		var prog := ShaderWarmup.program(e, true)
		var mine := 0
		var others := 0
		for entry: Array in prog:
			var d: AbilityDef = entry[1]
			expect(d.slot != AbilityDef.Slot.PASSIVE and d.slot != AbilityDef.Slot.INNATE, "only castable abilities")
			if int(entry[0]) == e:
				mine += 1
			else:
				others += 1
				expect(d.slot == AbilityDef.Slot.LIGHT or d.slot == AbilityDef.Slot.HEAVY, "other elements: strikes only")
		var castable := 0
		for d: AbilityDef in AbilityRegistry.for_element(e):
			if d.slot != AbilityDef.Slot.PASSIVE and d.slot != AbilityDef.Slot.INNATE and not d.script_path.is_empty():
				castable += 1
		expect_eq(mine, castable, "%s: every technique of the element" % ElementDefs.id_of(e))
		expect_eq(others, 6, "%s: light + heavy of the three other elements" % ElementDefs.id_of(e))
	var o := ShaderWarmup.stage_origin()
	expect(not WorldData.get_bounds().has_point(Vector2(o.x, o.z)), "the stage stands outside the world")


func test_warmup_is_skipped_headless() -> void:
	var w := ShaderWarmup.start(self, E.FIRE)
	expect(w.done and bool(w.report.get("skipped", false)), "nothing renders headless: skipped at once")
	w.queue_free()


## The full pass on its stage (forced: the headless runner never renders, but the casts, hits,
## FX spawns and the cleanup are the same code).
func test_warmup_run_casts_everything_and_cleans_up() -> void:
	WorldData.use_flat_world(true)
	var proj0 := BendingProjectile.live.size()
	var cons0 := BendingConstruct.live.size()
	var sfx := AudioServer.get_bus_index("SFX")
	var muted0 := AudioServer.is_bus_mute(sfx) if sfx >= 0 else false
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for e in [E.FIRE, E.WATER, E.EARTH, E.AIR]:
		var w := ShaderWarmup.new()
		w.element = e
		add_child(w)
		w._run()
		var ok := await w.wait_done(60.0)
		expect(ok, "%s warm-up finished" % ElementDefs.id_of(e))
		expect(int(w.report.get("abilities", 0)) >= 12, "%s: casts every technique (%d)" % [ElementDefs.id_of(e), int(w.report.get("abilities", 0))])
		expect(not GroundSampler.has_zones(), "%s: stage surfaces removed" % ElementDefs.id_of(e))
		if sfx >= 0:
			expect_eq(AudioServer.is_bus_mute(sfx), muted0, "%s: SFX bus restored" % ElementDefs.id_of(e))
		expect(cam.current, "%s: the previous camera is current again" % ElementDefs.id_of(e))
		w.queue_free()
		await frames(2)
	var mine_left := 0
	for c in BendingConstruct.live:
		if is_instance_valid(c) and (c as Node3D).global_position.distance_to(ShaderWarmup.stage_origin()) < 300.0:
			mine_left += 1
	expect_eq(mine_left, 0, "no warm-up construct left on the stage")
	expect(BendingProjectile.live.size() <= proj0 + 2, "warm-up projectiles cleared (%d -> %d)" % [proj0, BendingProjectile.live.size()])
	expect(BendingConstruct.live.size() <= cons0, "constructs cleared")


# --- camera ------------------------------------------------------------------------------------------------

func test_dither_twin_copies_the_toon_look() -> void:
	var src := ToonMaterials.make(Color(0.3, 0.5, 0.7), {"vertex_color": true, "rim": 0.42, "outline_width": 1.3})
	var twin := OccluderFader.twin_of(src)
	expect(twin != null and twin.shader == OccluderFader.TOON_DITHER, "toon material -> dither twin")
	expect_eq(twin.get_shader_parameter(&"albedo"), src.get_shader_parameter(&"albedo"), "albedo copied")
	expect_eq(twin.get_shader_parameter(&"rim_strength"), src.get_shader_parameter(&"rim_strength"), "rim copied")
	expect_eq(twin.get_shader_parameter(&"use_vertex_color"), true, "vertex colours copied")
	expect(twin.next_pass is ShaderMaterial and (twin.next_pass as ShaderMaterial).shader == OccluderFader.OUTLINE_DITHER, "outline twin")
	expect_eq((twin.next_pass as ShaderMaterial).get_shader_parameter(&"width"), 1.3, "outline width copied")
	expect(OccluderFader.twin_of(src) == twin, "cached per source")
	expect(OccluderFader.twin_of(StandardMaterial3D.new()) == null, "other materials are left alone")
	# the twin shader declares every toon uniform (kept in sync with assets/shaders/toon.gdshader)
	var names := {}
	for u: Dictionary in OccluderFader.TOON_DITHER.get_shader_uniform_list():
		names[u["name"]] = true
	for u: Dictionary in ToonMaterials.TOON_SHADER.get_shader_uniform_list():
		expect(names.has(u["name"]), "toon_dither declares %s" % u["name"])


func test_occluder_between_camera_and_player_fades_and_restores() -> void:
	var p := PlayerSim.player(self, E.WATER, Vector3.ZERO, true)
	await PlayerSim.step(p, 2)
	var cam := p.camera_rig
	await seconds(0.3)
	var cpos := cam.camera.global_position
	# an NPC body right on the line camera -> chest
	var npc := CharacterBody3D.new()
	npc.collision_layer = Layers.NPC
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	npc.add_child(cs)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	mi.mesh = box
	var mat := ToonMaterials.make(Color(0.8, 0.2, 0.2))
	box.material = mat
	npc.add_child(mi)
	add_child(npc)
	var mid := (cpos + p.global_position) * 0.5
	npc.global_position = Vector3(mid.x, 0.0, mid.z)
	await seconds(0.6)
	expect(cam.occluders.fade_of(npc) > 0.3, "the NPC between lens and player fades (%.2f)" % cam.occluders.fade_of(npc))
	var over := mi.get_surface_override_material(0) as ShaderMaterial
	expect(over != null and over.shader == OccluderFader.TOON_DITHER, "dither twin on the occluder")
	expect(mat.next_pass == null or not (mat.next_pass as ShaderMaterial).shader == OccluderFader.OUTLINE_DITHER, "the shared material is untouched")
	npc.global_position = Vector3(30, 0, 30)
	await seconds(0.9)
	expect_eq(cam.occluders.fade_of(npc), 0.0, "fades back once clear")
	expect(mi.get_surface_override_material(0) == null, "original material restored")


func test_lock_on_close_target_stays_in_view() -> void:
	var p := PlayerSim.player(self, E.FIRE, Vector3.ZERO, true)
	await PlayerSim.step(p, 2)
	var cam := p.camera_rig
	var d := TrainingDummy.new()
	d.look = &"post"
	add_child(d)
	d.global_position = Vector3(0, 0, -1.6)
	await frames(2)
	p.targeting.lock_target = d
	await seconds(2.0)
	var cpos := cam.camera.global_position
	var tp := BendingContext.target_point(d)
	# distance of the player's axis (chest) from the camera -> target sight line
	var chest := p.global_position + Vector3.UP * 1.1
	var seg := tp - cpos
	var t := clampf((chest - cpos).dot(seg) / seg.length_squared(), 0.0, 1.0)
	var clearance := (cpos + seg * t).distance_to(chest)
	expect(clearance > 0.55, "a 1.6 m attacker is not hidden behind the player (sight line passes %.2f m beside)" % clearance)
	expect(cam.lock_close > 0.8, "close-quarters framing engaged (%.2f)" % cam.lock_close)
	var yaw_a := cam.get_yaw()
	await seconds(0.5)
	expect(absf(angle_difference(yaw_a, cam.get_yaw())) < deg_to_rad(2.0), "stable: no drift or flip while holding still")
	d.global_position = Vector3(0, 0, -12.0)
	await seconds(2.0)
	expect(cam.lock_close < 0.1, "far target: normal lock framing (%.2f)" % cam.lock_close)
	var to := d.global_position - p.global_position
	expect(absf(angle_difference(cam.get_yaw(), atan2(-to.x, -to.z))) < deg_to_rad(6.0), "far target: camera behind the player again")
	p.targeting.lock_target = null
	await frames(2)
	expect_eq(cam.lock_side, 0.0, "unlock resets the side")
