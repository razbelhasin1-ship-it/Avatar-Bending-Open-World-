extends TestCase
## World renderer (worldrender module): height consistency CPU/GPU formula and collision,
## clipmap structure + crack-free morphing, collision streaming, time/weather state machines,
## atmosphere palettes, snow trails and water helpers.

var _rng := RandomNumberGenerator.new()


func before_each() -> void:
	_rng.seed = 20261015
	WorldData.load_world()


# --- height consistency --------------------------------------------------------------------------

## The shader include decodes RG8 texels (R low byte, G high byte) and interpolates in a fixed
## order; this mirrors it op by op on the same bytes and must equal WorldData.get_height.
func test_shader_height_formula_mirrors_cpu() -> void:
	if not expect(WorldData.has_world_data(), "world data present"):
		return
	var raw := WorldData.get_height_image().get_data()
	var worst := 0.0
	for k in 600:
		var x := _rng.randf_range(-4090.0, 4090.0)
		var z := _rng.randf_range(-4090.0, 4090.0)
		worst = maxf(worst, absf(_shader_world_height(raw, x, z) - WorldData.get_height(x, z)))
	expect(worst < 1e-4, "shader formula == WorldData.get_height (worst %.6f m)" % worst)


func _shader_texel(raw: PackedByteArray, i: int, j: int) -> float:
	i = clampi(i, 0, 4095)
	j = clampi(j, 0, 4095)
	var r := raw[(j * 4096 + i) * 2] / 255.0
	var g := raw[(j * 4096 + i) * 2 + 1] / 255.0
	var code := floorf(r * 255.0 + 0.5) + floorf(g * 255.0 + 0.5) * 256.0
	return code * 0.03125 - 256.0


func _shader_world_height(raw: PackedByteArray, x: float, z: float) -> float:
	var u := clampf((x + 4096.0) / 2.0 - 0.5, 0.0, 4095.0)
	var v := clampf((z + 4096.0) / 2.0 - 0.5, 0.0, 4095.0)
	var i0 := int(floorf(u))
	var j0 := int(floorf(v))
	var i1 := mini(i0 + 1, 4095)
	var j1 := mini(j0 + 1, 4095)
	var fx := u - i0
	var fz := v - j0
	var h00 := _shader_texel(raw, i0, j0)
	var h10 := _shader_texel(raw, i1, j0)
	var h01 := _shader_texel(raw, i0, j1)
	var h11 := _shader_texel(raw, i1, j1)
	var a := h00 + (h10 - h00) * fx
	var b := h01 + (h11 - h01) * fx
	return a + (b - a) * fz


func test_collision_heights_equal_worlddata() -> void:
	if not WorldData.has_world_data():
		return
	var col := TerrainCollision.new()
	add_child(col)
	# a steep, varied spot (Omashu's mountain) and a gentle one (Ba Sing Se plain)
	var spots := [Vector3(420, 0, -380), Vector3(1500, 0, 400), Vector3(-2600, 0, 2400)]
	for p: Vector3 in spots:
		col.ensure_now(p)
	await physics_frames(2)
	var space := get_viewport().world_3d.direct_space_state
	var worst_sample := 0.0
	var worst_twist_ratio := 0.0
	var hits := 0
	for p: Vector3 in spots:
		var key := TerrainCollision.patch_key(p)
		var o := TerrainCollision.patch_origin(key)
		for k in 120:
			# sample points (1 m grid): must match exactly (float32 precision)
			var sx := o.x + float(_rng.randi_range(1, 63))
			var sz := o.y + float(_rng.randi_range(1, 63))
			var hit := _ray(space, sx, sz)
			if hit.is_finite():
				hits += 1
				worst_sample = maxf(worst_sample, absf(hit.y - WorldData.get_height(sx, sz)))
			# arbitrary points: within 1/16 of the local 2 m cell twist (+1 mm)
			var rx := o.x + _rng.randf_range(1.0, 63.0)
			var rz := o.y + _rng.randf_range(1.0, 63.0)
			var hit2 := _ray(space, rx, rz)
			if hit2.is_finite():
				var bound := _twist(rx, rz) / 16.0 * 1.6 + 0.002
				worst_twist_ratio = maxf(worst_twist_ratio, absf(hit2.y - WorldData.get_height(rx, rz)) / bound)
	expect(hits > 300, "raycasts hit the streamed collision (%d)" % hits)
	expect(worst_sample < 0.002, "collision == WorldData at samples (worst %.5f m)" % worst_sample)
	expect(worst_twist_ratio <= 1.0, "collision within the bilinear twist bound (ratio %.3f)" % worst_twist_ratio)
	col.queue_free()


func _ray(space: PhysicsDirectSpaceState3D, x: float, z: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 2500.0, z), Vector3(x, -600.0, z), Layers.WORLD)
	var r := space.intersect_ray(q)
	return r["position"] if not r.is_empty() else Vector3.INF


## |h00 + h11 - h10 - h01| of the 2 m heightmap cell containing x/z.
func _twist(x: float, z: float) -> float:
	var u := floorf((x + 4096.0) / 2.0 - 0.5)
	var v := floorf((z + 4096.0) / 2.0 - 0.5)
	var cx := -4096.0 + (u + 0.5) * 2.0
	var cz := -4096.0 + (v + 0.5) * 2.0
	var h00 := WorldData.get_height(cx, cz)
	var h10 := WorldData.get_height(cx + 2.0, cz)
	var h01 := WorldData.get_height(cx, cz + 2.0)
	var h11 := WorldData.get_height(cx + 2.0, cz + 2.0)
	return absf(h00 + h11 - h10 - h01)


# --- clipmap -------------------------------------------------------------------------------------

func test_clipmap_meshes_structure() -> void:
	var m := ClipmapMeshes.new(16)
	expect_eq(m.tile.surface_get_array_len(0), 17 * 17, "tile vertices")
	expect_eq(m.tile_origins(0).size(), 16, "level 0 has 16 tiles")
	expect_eq(m.tile_origins(1).size(), 12, "outer levels skip the inner 2x2")
	expect_eq(m.trims.size(), 4, "four trim variants")
	# the seam ring has 2 * (4T + 2) * 4 / 2 segments, both windings
	expect_eq(m.seam.surface_get_array_index_len(0), (4 * 16 + 2) * 4 / 2 * 6, "seam triangles")
	# every quad uses the (0,0)-(1,1) diagonal and is clockwise from above
	var verts: PackedVector3Array = m.tile.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = m.tile.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var cw := true
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		if (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a).y >= 0.0:
			cw = false
	expect(cw, "tile triangles are front-facing (clockwise from above)")


func test_clipmap_levels_snap_and_reach() -> void:
	var cm := TerrainClipmap.new()
	cm.configure(24, 0.25, 4000.0)
	expect(cm.reach() >= 4000.0, "clipmap reaches the view distance (%.0f m)" % cm.reach())
	expect(cm.reach() < 8000.1 * 2.0, "no needless extra levels")
	for k in 50:
		var cam := Vector2(_rng.randf_range(-4000, 4000), _rng.randf_range(-4000, 4000))
		for l in cm.level_count - 1:
			var s := cm.spacing(l)
			var p := cm.level_origin(l, cam)
			var pn := cm.level_origin(l + 1, cam)
			var off := (p - pn) / s
			expect(is_equal_approx(off.x, roundf(off.x)) and off.x >= -0.01 and off.x <= 1.01, "x offset to next level is 0 or 1 cell")
			expect(is_equal_approx(off.y, roundf(off.y)) and off.y >= -0.01 and off.y <= 1.01, "z offset to next level is 0 or 1 cell")
			if s >= 2.0:
				# vertices on texel centres (odd metres)
				expect(is_equal_approx(fposmod(p.x - 1.0, 2.0), 0.0), "level origin on a texel centre")
	cm.free()


## Crack-free rings: every vertex on the seam of level l (the hole of level l + 1) is fully
## morphed, so its height equals the linear interpolation of level l + 1's edge.
func test_clipmap_rings_meet_without_cracks() -> void:
	if not WorldData.has_world_data():
		return
	var cm := TerrainClipmap.new()
	cm.configure(16, 0.25, 2000.0)
	var t := cm.tile_res
	var worst := 0.0
	var min_morph := 1.0
	for trial in 6:
		var cam := Vector2(_rng.randf_range(-3000, 3000), _rng.randf_range(-3000, 3000))
		for l in range(0, cm.level_count - 1):
			var s := cm.spacing(l)
			var pn := cm.level_origin(l + 1, cam)
			var side := 4 * t + 2
			var o := pn + Vector2(-2 * t, -2 * t) * s
			for k in range(0, side, 3):
				for edge in 4:
					var v: Vector2
					match edge:
						0: v = o + Vector2(k, 0) * s
						1: v = o + Vector2(side, k) * s
						2: v = o + Vector2(k, side) * s
						_: v = o + Vector2(0, k) * s
					min_morph = minf(min_morph, cm.morph_factor(v, cam, s))
					var hf := cm.vertex_height(v, cam, s)
					# the coarse edge through v: even neighbours on the coarse grid
					var g := Vector2(roundf((v.x - 1.0) / s), roundf((v.y - 1.0) / s))
					var odd := Vector2(fposmod(g.x, 2.0), fposmod(g.y, 2.0))
					var hc: float
					if odd.x + odd.y < 0.5:
						hc = cm.vertex_height(v, cam, s * 2.0)
					else:
						var d := odd * s
						hc = 0.5 * (cm.vertex_height(v - d, cam, s * 2.0) + cm.vertex_height(v + d, cam, s * 2.0))
					worst = maxf(worst, absf(hf - hc))
	expect_near(min_morph, 1.0, 1e-6, "seam vertices fully morphed")
	expect(worst < 1e-3, "fine ring boundary == coarse ring edge (worst %.6f m)" % worst)
	cm.free()


func test_height_bounds_conservative() -> void:
	if not WorldData.has_world_data():
		return
	var hb := HeightBounds.new()
	hb.build_now()
	expect(hb.ready, "bounds built")
	for k in 200:
		var r := Rect2(_rng.randf_range(-4000, 3800), _rng.randf_range(-4000, 3800), _rng.randf_range(5, 400), _rng.randf_range(5, 400))
		var b := hb.range_for_rect(r)
		for n in 6:
			var x := _rng.randf_range(r.position.x, r.end.x)
			var z := _rng.randf_range(r.position.y, r.end.y)
			var h := WorldData.get_height(x, z)
			expect(h >= b.x - 0.01 and h <= b.y + 0.01, "height %.2f inside bounds %s" % [h, b])


# --- collision streaming ------------------------------------------------------------------------

func test_collision_streaming_readiness() -> void:
	var col := TerrainCollision.new()
	col.focus_radius = 70.0
	add_child(col)
	var p := Vector3(1500, 0, 400)
	col.update(p, 0.016)
	expect(col.patch_count() >= 1, "patch under the focus built synchronously")
	expect(not col.is_ready_at(p), "not ready before a physics frame")
	await physics_frames(2)
	expect(col.is_ready_at(p), "ready after a physics frame")
	var far := Vector3(-2600, 0, 2400)
	expect(not col.is_ready_at(far), "far point not ready")
	var id := col.request_around(far, 40.0)
	var ok := false
	for i in 240:
		col.update(p, 0.016)
		await physics_frames(1)
		if col.is_ready_at(far) and col.is_ready_at(far + Vector3(30, 0, 0)):
			ok = true
			break
	expect(ok, "requested area streamed in")
	var with_request := col.patch_count()
	col.release_request(id)
	col.update(p, 0.016)
	await frames(2)
	expect(col.patch_count() < with_request, "released area unloaded (%d -> %d)" % [with_request, col.patch_count()])
	expect(col.is_ready_at(p), "focus area kept")
	# bounded: never more than the patches covering the radii
	expect(col.patch_count() <= 16, "patch budget respected (%d)" % col.patch_count())
	col.queue_free()


func test_collision_safety_net_rescues_falling_body() -> void:
	var col := TerrainCollision.new()
	add_child(col)
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	body.add_child(cs)
	add_child(body)
	var x := 1500.0
	var z := 400.0
	var ground := WorldData.get_height(x, z)
	body.global_position = Vector3(x, ground - 8.0, z)
	col.focus = body
	var rescued := [false]
	col.body_rescued.connect(func(_b: Node3D) -> void: rescued[0] = true)
	await physics_frames(3)
	expect(rescued[0], "safety net fired")
	expect(body.global_position.y > ground, "body back above the ground")
	body.queue_free()
	col.queue_free()


# --- time of day -----------------------------------------------------------------------------------

func test_day_night_cycle() -> void:
	var c := DayNightCycle.new()
	add_child(c)
	var got: Array[float] = []
	var cb := func(h: float) -> void: got.append(h)
	Events.time_of_day_changed.connect(cb)
	c.set_hour(25.5)
	expect_near(c.hour, 1.5, 1e-6, "hour wraps")
	expect(got.size() >= 1 and is_equal_approx(got[-1], 1.5), "explicit set emits time_of_day_changed")
	expect_near(GameState.time_of_day, 1.5, 1e-6, "GameState mirrors the clock")
	c.set_hour(9.0)
	c.time_scale = DayNightCycle.DEFAULT_TIME_SCALE
	got.clear()
	for i in 120:
		c.advance(1.0)
	expect_near(c.hour, 10.0, 1e-4, "default scale: one game hour per two real minutes")
	expect(got.size() >= 3, "emits during the hour (every %.2f h, got %d)" % [DayNightCycle.EMIT_STEP, got.size()])
	Events.time_of_day_changed.disconnect(cb)
	# sun path
	var e := DayNightCycle.sun_direction_at(6.0, 55.0)
	expect(e.x > 0.99 and absf(e.y) < 1e-3, "sun rises in the east")
	var n := DayNightCycle.sun_direction_at(12.0, 55.0)
	expect_near(rad_to_deg(asin(n.y)), 55.0, 0.01, "noon elevation")
	expect(n.z > 0.0, "noon sun stands in the south (+Z)")
	expect(DayNightCycle.sun_direction_at(18.0, 55.0).x < -0.99, "sun sets in the west")
	expect(DayNightCycle.sun_direction_at(0.0, 55.0).y < -0.5, "below horizon at midnight")
	c.set_hour(23.0)
	expect(c.moon_direction().y > 0.0, "moon up at night")
	expect(c.daylight() < 0.01, "night has no daylight")
	c.paused = true
	c.advance(600.0)
	expect_near(c.hour, 23.0, 1e-6, "paused clock does not move")
	c.queue_free()


func test_atmosphere_palettes() -> void:
	for r: StringName in WorldRenderer.REGIONS:
		var day := AtmospherePalettes.for_region(r, 40.0)
		var night := AtmospherePalettes.for_region(r, -30.0)
		for k in AtmospherePalettes.KEYS:
			expect(day.has(k), "%s day has %s" % [r, k])
		expect((night[&"zenith"] as Color).get_luminance() < (day[&"zenith"] as Color).get_luminance(), "%s night darker" % r)
		expect(float(night[&"stars"]) > 0.5 and float(day[&"stars"]) == 0.0, "%s stars only at night" % r)
	var wt := AtmospherePalettes.for_region(&"water_tribe", 30.0)
	var fn := AtmospherePalettes.for_region(&"fire_nation", 30.0)
	expect((fn[&"fog"] as Color).r - (fn[&"fog"] as Color).b > (wt[&"fog"] as Color).r - (wt[&"fog"] as Color).b, "fire nation haze is warmer than the arctic")
	var mix := AtmospherePalettes.blend([wt, fn], PackedFloat32Array([1.0, 1.0]))
	expect_near(float(mix[&"fog_density"]), (float(wt[&"fog_density"]) + float(fn[&"fog_density"])) * 0.5, 1e-7, "blend averages")
	# golden hour lies between night and day
	var g := AtmospherePalettes.for_region(&"earth_kingdom", 4.0)
	expect((g[&"horizon"] as Color).r > 0.9, "golden horizon is warm")
	expect(AtmospherePalettes.sun_max_elevation({&"water_tribe": 1.0}) < AtmospherePalettes.sun_max_elevation({&"fire_nation": 1.0}), "arctic sun lower")


# --- weather ------------------------------------------------------------------------------------

func test_weather_transitions_and_events() -> void:
	var w := WeatherSystem.new()
	add_child(w)
	var events: Array[StringName] = []
	var cb := func(name: StringName) -> void: events.append(name)
	Events.weather_changed.connect(cb)
	w.set_weather(&"blizzard", 4.0)
	expect_eq(w.current, &"blizzard", "target set")
	expect(not w.auto, "manual weather locks auto mode")
	expect(events.has(&"blizzard"), "Events.weather_changed emitted")
	w.update(1.0, &"water_tribe")
	var mid := float(w.params["blizzard"])
	expect(mid > 0.0 and mid < 1.0, "transition in progress (%.2f)" % mid)
	for i in 5:
		w.update(1.0, &"water_tribe")
	expect_near(float(w.params["blizzard"]), 1.0, 1e-6, "transition complete")
	expect(float(w.params["fog_mult"]) > 5.0, "blizzard thickens the fog")
	expect(float(w.params["refill"]) > 5.0, "blizzard refills trails fast")
	expect(w.wind_speed > 10.0, "blizzard wind")
	expect_eq(WorldShaderGlobals.get_value(&"wind_strength"), w.wind_speed, "wind global updated")
	# instant change
	w.set_weather(&"clear", 0.0)
	w.update(0.016, &"water_tribe")
	expect_near(float(w.params["blizzard"]), 0.0, 1e-6, "instant transition")
	Events.weather_changed.disconnect(cb)
	w.queue_free()


func test_weather_auto_respects_regions() -> void:
	var w := WeatherSystem.new()
	add_child(w)
	w.set_weather(&"blizzard", 0.0)
	w.set_auto(true)
	w.update(0.1, &"fire_nation")
	expect(w.current != &"blizzard", "auto mode replaces weather the region does not allow")
	expect(WeatherSystem.is_allowed(w.current, &"fire_nation"), "new weather allowed in the fire nation")
	for i in 200:
		expect(WeatherSystem.is_allowed(w.roll(&"water_tribe"), &"water_tribe"), "roll stays in the table")
	expect(not WeatherSystem.is_allowed(&"ash", &"water_tribe"), "no ash fall in the arctic")
	expect(not WeatherSystem.is_allowed(&"blizzard", &"fire_nation"), "no blizzard in the fire nation")
	w.queue_free()


# --- snow trails ----------------------------------------------------------------------------------

func test_snow_trails_stamp_and_refill() -> void:
	if not WorldData.has_world_data():
		return
	var st := SnowTrails.new()
	add_child(st)
	var p := Vector3(1000, 0, -2808)
	p.y = WorldData.get_height(p.x, p.z)
	st.update(p, 0.016)
	expect(SnowTrails.has_snow(p), "snowfield has snow")
	expect(st.add_footprint(p, -PI * 0.5, 0.28, 1.0), "footprint accepted")
	var d := st.get_sink_depth(p)
	expect(d > 0.03 and d <= WorldData.get_snow_depth(p.x, p.z), "print depth %.3f within snow depth" % d)
	expect_near(st.get_sink_depth(p + Vector3(0, 0, 1.0)), 0.0, 1e-6, "no sink beside the print")
	# heavier and bigger feet press deeper
	var q := p + Vector3(3, 0, 0)
	st.add_footprint(q, 0.0, 0.55, 2.5)
	expect(st.get_sink_depth(q) > d, "heavy creature print deeper")
	var c := p + Vector3(-4, 0, 0)
	expect(st.add_crater(c, 10.0), "crater accepted")
	expect(st.get_sink_depth(c) > d, "landing crater deeper than a step")
	# no prints on ice or bare ground
	expect(not st.add_footprint(p, 0.0, 0.28, 1.0, 0.0, &"ice"), "no print on ice")
	var grass := Vector3(1500, 0, 400)
	grass.y = WorldData.get_height(grass.x, grass.z)
	expect(not st.add_footprint(grass, 0.0, 0.28, 1.0, 0.0, &"grass"), "no print on grass")
	# Events drive it too
	var n := st.stamp_count()
	Events.footstep.emit(null, p + Vector3(0, 0, 3), 0.0, 0.28, 1.0, &"snow")
	Events.landed.emit(null, p + Vector3(0, 0, 6), -8.0, &"snow")
	expect_eq(st.stamp_count(), n + 2, "footstep + landed events stamp")
	# refill: faster when snowing
	st.refill_multiplier = 9.0
	for i in 20:
		st.update(p, 1.0)
	var refilled := st.get_sink_depth(p)
	expect(refilled < d, "prints refill (%.3f -> %.3f)" % [d, refilled])
	for i in 60:
		st.update(p, 1.0)
	expect_near(st.get_sink_depth(p), 0.0, 1e-6, "fully refilled")
	st.queue_free()


# --- water ---------------------------------------------------------------------------------------

func test_water_waves_and_surface() -> void:
	var w := WaterWaves.new()
	w.params = Vector4(0.6, 0.7, 1.0, 1.0)
	var maxh := 0.0
	for k in 300:
		maxh = maxf(maxh, absf(w.height_at(_rng.randf_range(-500, 500), _rng.randf_range(-500, 500), _rng.randf_range(0, 100))))
	expect(maxh <= w.max_amplitude() + 1e-6 and maxh > 0.1, "swell bounded (%.2f <= %.2f)" % [maxh, w.max_amplitude()])
	expect_near(w.height_at(10, 10, 5.0, 0.0), 0.0, 1e-9, "masked swell is flat")


# --- integration -----------------------------------------------------------------------------------

func test_world_renderer_api() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var world := WorldRenderer.new()
	add_child(world)
	var focus := Node3D.new()
	add_child(focus)
	focus.global_position = Vector3(1500, WorldData.get_height(1500, 400) + 1.0, 400)
	cam.global_position = focus.global_position + Vector3(0, 3, 6)
	world.setup(focus, cam)
	world.set_time_of_day(17.25)
	expect_near(world.get_time_of_day(), 17.25, 1e-6, "time of day")
	world.set_time_scale(0.0)
	await frames(3)
	expect_near(world.get_time_of_day(), 17.25, 1e-6, "time scale 0 freezes the clock")
	world.set_weather(&"rain", 0.0)
	expect_eq(world.get_weather(), &"rain", "weather")
	await frames(2)
	expect(world.get_sun() is DirectionalLight3D and world.get_environment() != null, "sun + environment owned")
	expect(world.get_environment().fog_enabled, "atmospheric fog on")
	expect(world.get_dominant_region() == &"earth_kingdom", "region at Ba Sing Se plain (%s)" % world.get_dominant_region())
	await physics_frames(2)
	await frames(1)
	expect(world.is_collision_ready_at(focus.global_position), "collision ready under the focus")
	var sea := Vector3(0, 0, -1900)
	expect(WorldData.get_water_height(sea.x, sea.z) > -INF, "test point is sea")
	expect(world.splash(sea, 1.5), "splash on water")
	expect(not world.splash(focus.global_position, 1.0), "no splash on land")
	var wh := world.get_water_surface_height(sea.x, sea.z)
	expect(absf(wh) < 2.5, "ocean surface near sea level (%.2f)" % wh)
	expect(world.get_water_surface_height(focus.global_position.x, focus.global_position.z) == -INF, "no water on land")
	var id := world.request_collision_around(Vector3(-2600, 0, 2400), 30.0)
	expect(id > 0, "collision request id")
	world.release_collision_request(id)
	var g: Variant = WorldShaderGlobals.get_value(&"world_sun_direction")
	expect(g is Vector3, "shader globals published")
	world.queue_free()
	focus.queue_free()
	cam.queue_free()
