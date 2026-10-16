extends RefCounted
## Nature features and POI structures in the real world: waterfalls (close-up + frozen), natural
## arches, the Air Temple rope bridge (the player walks across it), a cave mouth (the player walks
## in), POI structures by type (shrines, camps, training grounds, ruins, docks, vista, spirit
## spots, resource sites, lighthouse, pass gate), road dressing (fences, lanterns at night,
## signposts) and a resource pickup harvest. `--views=a,b` limits the set (view names below).

const POI_SHOTS := ["wt_moon_shrine", "fn_eternal_flame", "ek_moonmirror_pavilion", "ek_dustwind_camp", "wt_seal_hunters_camp",
		"ek_stonefist_yard", "at_meditation_ledge", "fn_overgrown_sun_temple", "ek_frostbitten_tower", "ek_northreach",
		"wt_kayak_landing", "ek_red_mesa", "ek_whispering_banyan", "fn_hissing_vents", "ek_jade_quarry",
		"wl_whalefall_skerries", "wl_lantern_isle", "at_pass_gate"]

var scene: Node
var content: WorldContent
var only: PackedStringArray = []


func run(p: Playtest) -> void:
	scene = await p.load_scene("res://scenes/dev/worldcontent_world.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	content = scene.content
	var world: WorldRenderer = scene.world
	await p.wait_until(func() -> bool: return world.normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--views="):
			only = a.substr(8).split(",")
	p.check(content.get_provider(&"landmarks") != null and content.get_provider(&"poi_structures") != null
			and content.get_provider(&"road_dressing") != null, "structure providers registered")
	await _waterfalls(p)
	await _arches(p)
	await _bridge(p)
	await _cave(p)
	await _pois(p)
	await _roads(p)


func _want(v: String) -> bool:
	return only.is_empty() or only.has(v)


func _shoot(p: Playtest, v: String, pos: Vector3, look: Vector3, hour: float, fov: float = 62.0) -> void:
	scene.place_camera(pos, look, fov)
	scene.world.set_time_of_day(hour)
	scene.world.set_weather(&"clear", 0.0)
	var ok: bool = content.load_now(pos)
	await p.frames(3)
	await p.wait(0.8)
	var t := Time.get_ticks_usec()
	await p.frames(8)
	var ms := (Time.get_ticks_usec() - t) / 8000.0
	var per: Dictionary = content.get_stats()["providers"]
	var act := []
	for id: StringName in [&"landmarks", &"poi_structures", &"road_dressing"]:
		if per.has(id):
			act.append("%s %d" % [id, per[id]["active"]])
	p.note("%s: %s, %.0f ms/frame, %d draw calls, lights %d/%d, cells %s" % [v, "ok" if ok else "load timeout", ms,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			LightBudget.active_count(), LightBudget.light_count(), ", ".join(act)])
	await p.screenshot("worldcontent_poi_%s" % v)


static func _agl(p: Vector3, h: float) -> Vector3:
	return Vector3(p.x, maxf(WorldData.get_height(p.x, p.z), 0.0) + h, p.z)


## Camera position `dist` from target (height above ground) with a terrain-free line of sight,
## trying directions around `prefer` first.
static func _clear_view(target: Vector3, prefer: Vector3, dist: float, height: float) -> Vector3:
	var base := atan2(prefer.x, prefer.z)
	for lift in [0.0, 0.4, 1.0]:
		for k in 13:
			var a := base + (ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)) * deg_to_rad(28.0)
			var cam := _agl(target + Vector3(sin(a), 0, cos(a)) * dist, height + dist * lift)
			var to := target - cam
			var hit := WorldData.raycast_terrain(cam, to, to.length())
			if not hit["hit"] or float(hit["distance"]) > to.length() - 4.0:
				return cam
	return _agl(target + prefer.normalized() * dist, height + dist)


func _waterfalls(p: Playtest) -> void:
	for w in WorldData.get_waterfalls():
		var v := "waterfall_%s" % w["id"]
		if not _want(v):
			continue
		var top: Vector3 = w["top"]
		var bottom: Vector3 = w["bottom"]
		var d := Vector3(bottom.x - top.x, 0, bottom.z - top.z).normalized()
		var dist := 40.0 + float(w["height"]) * 0.45
		var mid := (top + bottom) * 0.5
		var cam := _clear_view(mid, d, dist, 6.0)
		await _shoot(p, v, cam, mid, 10.5, 66.0)
	if _want("waterfall_closeup"):
		var w: Dictionary = WorldData.get_waterfalls()[2]
		var bottom: Vector3 = w["bottom"]
		var top: Vector3 = w["top"]
		var d := Vector3(bottom.x - top.x, 0, bottom.z - top.z).normalized()
		var focus := bottom + Vector3(0, 14, 0)
		await _shoot(p, "waterfall_closeup", _clear_view(focus, d, 26.0, 3.0), focus, 15.0, 70.0)
		var wf := _find(content.get_cells(&"landmarks"), String(w["id"]))
		p.check(wf != null and wf.find_child("Mist", true, false) != null, "waterfall has mist particles")
		p.check(content.get_cells(&"landmarks").any(func(c: ContentCell) -> bool: return not c.loops.is_empty()), "waterfall roar loop playing")


func _arches(p: Playtest) -> void:
	for a in WorldData.get_arches():
		var v := "arch_%s" % a["id"]
		if not _want(v):
			continue
		var pa: Vector3 = a["a"]
		var pb: Vector3 = a["b"]
		var mid := (pa + pb) * 0.5
		var across := Vector3(pb.x - pa.x, 0, pb.z - pa.z).normalized().cross(Vector3.UP)
		var span := Vector2(pb.x - pa.x, pb.z - pa.z).length()
		var look := Vector3(mid.x, float(a["apex_height"]) - 10.0, mid.z)
		var cam := _clear_view(look, across, span * 1.1, 12.0)
		if cam.y < look.y - 40.0:
			# a span climbing a mountainside: look at it from the air, level with the crown
			cam = look + across * span * 1.3 + Vector3(0, -15.0, 0)
		await _shoot(p, v, cam, look, 9.5)


func _bridge(p: Playtest) -> void:
	if not _want("bridge_walk") and not _want("bridge_view"):
		return
	var b: Dictionary = {}
	for r in WorldData.get_bridges():
		if r["id"] == &"at_bridge_west":
			b = r
	if b.is_empty():
		p.check(false, "at_bridge_west record")
		return
	var a: Vector3 = b["a"]
	var c: Vector3 = b["b"]
	var dir := Vector3(c.x - a.x, 0, c.z - a.z).normalized()
	var side := dir.cross(Vector3.UP)
	var mid := (a + c) * 0.5
	if _want("bridge_view"):
		await _shoot(p, "bridge_view", mid + side * 70.0 + Vector3(0, 6.0, 0) - dir * 20.0, mid - Vector3(0, 4, 0), 8.5)
	if not _want("bridge_walk"):
		return
	scene.world.set_time_of_day(9.0)
	content.load_now(a)
	var pl: PlayerCharacter = scene.spawn_player(Transform3D(Basis.looking_at(dir), a - dir * 3.0 + Vector3(0, 0.3, 0)))
	await p.wait_game(1.0)
	var sag := float(b.get("sag", 5.0))
	var edges := BridgeBuilder.edges(a, c, Vector3.ZERO)
	var length := Vector2(c.x - a.x, c.z - a.z).length()
	var lowest := INF
	var below := 0.0
	p.hold(&"move_forward")
	var shots := 0
	var t := 0.0
	var best_s := 0.0
	var stall := 0.0
	while t < 60.0:
		await p.wait_game(0.5)
		t += 0.5
		var pos := pl.global_position
		var s := clampf((pos - a).dot(dir) / length, 0.0, 1.0)
		var deck := BridgeBuilder.deck_height(a, c, sag, Vector3.ZERO, s, edges)
		lowest = minf(lowest, pos.y)
		below = maxf(below, deck - pos.y)
		if s > 0.3 and shots == 0 or s > 0.7 and shots == 1:
			shots += 1
			await p.screenshot("worldcontent_poi_bridge_walk_%d" % shots)
		if s >= 0.98 or pos.y < a.y - sag - 20.0:
			break
		if s > best_s + 0.01:
			best_s = s
			stall = 0.0
		else:
			stall += 0.5
			if stall >= 4.0:
				p.note("bridge walk stalled at s %.2f, pos %s, state %s" % [s, pos, pl.get_state_name()])
				var q := PhysicsShapeQueryParameters3D.new()
				var cap := CapsuleShape3D.new()
				cap.radius = 0.45
				cap.height = 1.6
				q.shape = cap
				q.collision_mask = 0xffffffff
				q.transform = Transform3D(Basis(), pos + dir * 0.6 + Vector3(0, 1.0, 0))
				for hit in pl.get_world_3d().direct_space_state.intersect_shape(q, 8):
					var col: Object = hit["collider"]
					p.note("  blocked by %s shape %d" % [(col as Node).get_path() if col is Node else str(col), int(hit["shape"])])
				p.note("  vel %s floor %s wall %s" % [pl.velocity, pl.is_on_floor(), pl.is_on_wall()])
				for k in pl.get_slide_collision_count():
					var sc := pl.get_slide_collision(k)
					var cn: Object = sc.get_collider()
					p.note("  slide %s normal %s at %s" % [(cn as Node).get_path() if cn is Node else str(cn), sc.get_normal(), sc.get_position()])
				break
	p.release(&"move_forward")
	var end := pl.global_position
	var crossed := (end - a).dot(dir) >= length - 2.0
	p.note("bridge walk: %.1f s, end %s, lowest y %.1f, max below deck %.2f m" % [t, end, lowest, below])
	p.check(crossed, "player crossed the rope bridge")
	p.check(below < 1.0, "player stayed on the deck (max %.2f m below)" % below)
	scene.remove_player()
	await p.frames(2)


func _cave(p: Playtest) -> void:
	if not _want("cave_mouth") and not _want("cave_walk"):
		return
	var poi := WorldData.get_poi(&"ek_two_lanterns_tunnels")
	var yaw := float(poi["yaw"])
	var out := Vector3(-sin(yaw), 0, -cos(yaw))
	var e: Vector3 = CaveBuilder.anchor(poi["tunnel"], out)[0]
	if _want("cave_mouth"):
		await _shoot(p, "cave_mouth", _clear_view(e + Vector3(0, 2.0, 0), out + out.cross(Vector3.UP) * 0.3, 16.0, 3.0), e + Vector3(0, 2.0, 0), 16.0, 66.0)
		for c in WorldData.get_pois():
			if c["type"] == &"cave" and c["id"] != poi["id"] and _want("cave_" + String(c["id"])):
				var co := Vector3(-sin(float(c["yaw"])), 0, -cos(float(c["yaw"])))
				var ce: Vector3 = CaveBuilder.anchor(c["tunnel"], co)[0]
				var cc := _clear_view(ce + Vector3(0, 2.0, 0), co, 20.0, 4.0)
				if cc.y < ce.y - 4.0:
					cc = ce + co * 24.0 + co.cross(Vector3.UP) * 6.0 + Vector3(0, 3.0, 0)     # mouth high on a cliff
				await _shoot(p, "cave_" + String(c["id"]), cc, ce + Vector3(0, 2.0, 0), 13.0, 66.0)
		p.check(TerrainHoles.count() > 0, "cave registered a terrain collision hole (%d)" % TerrainHoles.count())
	if not _want("cave_walk"):
		return
	scene.world.set_time_of_day(16.0)
	var start := _agl(e + out * 12.0, 0.5)
	content.load_now(start)
	var pl: PlayerCharacter = scene.spawn_player(Transform3D(Basis.looking_at(-out), start))
	await p.wait_game(1.5)
	p.hold(&"move_forward")
	var t := 0.0
	while t < 10.0:
		await p.wait_game(0.5)
		t += 0.5
		if (pl.global_position - e).dot(-out) > 18.0:
			break
	p.release(&"move_forward")
	await p.wait_game(0.6)
	var depth := (pl.global_position - e).dot(-out)
	var floor_y: float = e.y
	p.note("cave walk: depth %.1f m, player y %.1f (entrance floor %.1f, terrain %.1f)" % [depth, pl.global_position.y, floor_y,
			WorldData.get_height(pl.global_position.x, pl.global_position.z)])
	var camp := pl.camera_rig.get_camera().global_position
	var space := pl.get_world_3d().direct_space_state
	var up_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pl.global_position + Vector3(0, 1, 0), pl.global_position + Vector3(0, 12, 0), Layers.WORLD))
	p.note("  camera %s (terrain there %.1f), ceiling hit %s" % [camp, WorldData.get_height(camp.x, camp.z), up_hit.get("position", "none")])
	p.check(depth > 8.0, "player walked into the cave (%.1f m)" % depth)
	p.check(not up_hit.is_empty() and (up_hit["position"] as Vector3).y - pl.global_position.y < 6.0, "player is inside the tunnel (roof overhead)")
	await p.screenshot("worldcontent_poi_cave_inside")
	pl.camera_rig.set_yaw(pl.camera_rig.get_yaw() + PI)
	await p.wait_game(0.5)
	await p.screenshot("worldcontent_poi_cave_looking_out")
	scene.remove_player()
	await p.frames(2)


func _pois(p: Playtest) -> void:
	for id: String in POI_SHOTS:
		if not _want(id):
			continue
		var poi := WorldData.get_poi(StringName(id))
		if poi.is_empty():
			p.check(false, "poi %s exists" % id)
			continue
		var pos: Vector3 = poi["position"]
		var yaw := PoiStructures.facing(poi)
		var front := Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
		var fp := maxf(PoiStructures.footprint(poi), 6.0)
		var dist := fp * 2.0 + 10.0
		if poi["type"] == &"dock":
			# the pier stands at the nearest shoreline, not at the POI point
			var shore := PoiSites.find_shore(Vector3(pos.x, WorldData.get_height(pos.x, pos.z), pos.z), Vector3.ZERO)
			if not shore.is_empty():
				var sd: Vector3 = shore[1]
				pos = (shore[0] as Vector3) + sd * 14.0
				front = sd.cross(Vector3.UP)
				dist = 34.0
		var cam := _clear_view(_agl(pos, 2.0), front + front.cross(Vector3.UP) * 0.35, dist, dist * 0.5 + 3.0)
		var hour := 20.5 if id in ["ek_dustwind_camp", "ek_whispering_banyan"] else (17.5 if id == "fn_hissing_vents" else 11.0)
		await _shoot(p, id, cam, _agl(pos, 2.0), hour, 62.0)
	if _want("ek_jade_quarry"):
		var pk: ResourcePickup = null
		for c in content.get_cells(&"poi_structures"):
			if c.root:
				for n in c.root.find_children("*", "ResourcePickup", true, false):
					pk = n
		p.check(pk != null, "resource pickups spawned")
		if pk:
			var before := GameState.item_count(pk.item_id)
			pk.interact(null)
			p.check(GameState.item_count(pk.item_id) == before + pk.count and not pk.is_available(), "pickup adds %s to GameState and regrows later" % pk.item_id)
			p.check(PoiProvider.harvested.has(pk.get_meta(&"harvest_key", "")), "harvest remembered across cell reloads")
	var groups := {}
	for g: StringName in [&"shrine", &"enemy_spawn", &"training_dummy", &"dock_berth", &"spirit_spot", &"vista", &"cave_entrance"]:
		groups[g] = scene.get_tree().get_nodes_in_group(g).size()
	p.note("markers in groups: %s" % str(groups))


func _roads(p: Playtest) -> void:
	var rp := content.get_provider(&"road_dressing") as RoadDressingProvider
	if _want("road_fence"):
		var spot := _find_fence_spot(rp)
		if spot.is_finite():
			await _shoot(p, "road_fence", spot + Vector3(14, 6, 14), spot, 16.5, 62.0)
		else:
			p.note("no farmland roadside found")
	if _want("road_signpost") and not rp._junctions.is_empty():
		var j: Dictionary = rp._junctions[0]
		var jp: Vector3 = j["pos"]
		await _shoot(p, "road_signpost", _agl(jp + Vector3(12, 0, 12), 4.0), _agl(jp, 1.5), 12.0, 60.0)
	if _want("road_lanterns_night"):
		var spot := _lantern_spot(rp)
		if spot.is_finite():
			await _shoot(p, "road_lanterns_night", _agl(spot, 3.0) + Vector3(8, 0, 8), _agl(spot, 1.0), 21.5, 66.0)


func _find_fence_spot(rp: RoadDressingProvider) -> Vector3:
	for rd: Dictionary in rp._roads:
		var pts: PackedVector3Array = rd["pts"]
		for i in pts.size() - 1:
			var dir := Vector3(pts[i + 1].x - pts[i].x, 0, pts[i + 1].z - pts[i].z).normalized()
			var c := pts[i] + dir.cross(Vector3.UP) * (float(rd["width"]) * 0.5 + 1.4)
			if rp._is_fence(c):
				return _agl(c, 0.0)
	return Vector3.INF


func _lantern_spot(rp: RoadDressingProvider) -> Vector3:
	for rd: Dictionary in rp._roads:
		var pts: PackedVector3Array = rd["pts"]
		for q in pts:
			var gap := rp._settlement_gap(Vector2(q.x, q.z))
			if gap > 30.0 and gap < 90.0 and WorldData.get_region(q.x, q.z) == &"earth_kingdom":
				return q
	return Vector3.INF


func _find(cells: Array[ContentCell], node_name: String) -> Node:
	for c in cells:
		if c.root:
			var n := c.root.find_child(node_name, true, false)
			if n:
				return n
	return null
