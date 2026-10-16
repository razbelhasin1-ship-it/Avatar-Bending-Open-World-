extends RefCounted
## Wildlife in the real world: finds a herd of each species with the provider's own rules
## (otter penguins on the arctic shore, ostrich horses by Earth Kingdom roads, komodo rhinos on
## Fire Nation grassland, turtle ducks on a lake, resting sky bison in the Air Temple stalls),
## fast-travels next to it, frames it, then walks at it to show the flight reaction.
## SPECIES=a,b to limit.

var p: Playtest
var w: WorldScene


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(ElementDefs.Element.WATER)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": ElementDefs.Element.WATER, "skip_intro": true, "time_of_day": 11.0}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 400.0)
	p.check(ok, "world ready")
	if not ok:
		return
	w.player.health.invulnerable = true
	var only := OS.get_environment("SPECIES")
	var lake := Vector3(1500, 0, 600)
	for lk in WorldData.get_lakes():
		if not bool(lk.get("frozen", false)) and float(lk.get("level", 0.0)) > 2.0:
			lake = QuestTargets.to_vec3(lk.get("center"))
			p.note("lake for the turtle ducks: %s (%s)" % [lk.get("name", "?"), lake])
			break
	var plan := [
		[&"otter_penguin", WorldData.get_spawn(ElementDefs.Element.WATER).origin],
		[&"ostrich_horse", WorldData.get_spawn(ElementDefs.Element.EARTH).origin],
		[&"komodo_rhino", WorldData.get_spawn(ElementDefs.Element.FIRE).origin],
		[&"turtle_duck", lake],
		[&"sky_bison", WorldData.get_spawn(ElementDefs.Element.AIR).origin],
	]
	for e: Array in plan:
		if only != "" and not only.split(",").has(String(e[0])):
			continue
		await _visit(e[0], e[1])


func _wild() -> WildlifeDirector:
	for h in w.hooks:
		if h.get("wildlife") is WildlifeDirector:
			return h.get("wildlife")
	return null


## Nearest herd of `species` around `near` by the provider's rules (worker-safe data, run here).
func _find(species: StringName, near: Vector3) -> Dictionary:
	var prov := WildlifeProvider.new(null)
	prov.configure()
	var c0 := prov.coord_of(near.x, near.z)
	var best := {}
	var bd := INF
	for r in 14:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cell := ContentCell.new(prov, c0 + Vector2i(dx, dz))
				prov.build_cell(cell)
				for rec: Dictionary in (cell.payload as CellPayload).data["wildlife"]:
					if rec.get("species", &"") == species:
						var d := (rec["pos"] as Vector3).distance_to(near)
						if d < bd:
							bd = d
							best = rec
		if not best.is_empty():
			return best
	return best


## An observer spot `dist` m from `focus` (preferring direction `pref`) with a clear line of sight
## (walls of the bison stalls, hillsides); pulled in before the first wall when none is clear.
func _eye_for(focus: Vector3, pref: Vector3, dist: float, up: float) -> Vector3:
	var space := w.get_world_3d().direct_space_state
	pref.y = 0.0
	pref = pref.normalized() if pref.length() > 0.1 else Vector3.BACK
	var best := Vector3.INF
	var best_len := -1.0
	for i in 8:
		var d := pref.rotated(Vector3.UP, TAU * i / 8.0)
		var e := focus + d * dist + Vector3(0, up, 0)
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(focus, e, Layers.CAMERA_BLOCKERS))
		if r.is_empty():
			return e
		var free := focus.distance_to(r["position"])
		if free > best_len:
			best_len = free
			best = focus.lerp(r["position"], 0.85)
	return best


func _visit(species: StringName, near: Vector3) -> void:
	var rec := _find(species, near)
	if not p.check(not rec.is_empty(), "%s herd found" % species):
		return
	var c: Vector3 = rec["pos"]
	var away := Vector3(1, 0, 0.4).normalized() * 16.0
	var stand := c + away
	stand.y = WorldData.get_height(stand.x, stand.z)
	if species == &"sky_bison":
		stand = c + Basis(Vector3.UP, float(rec["yaw"])) * Vector3(0, 0, -9.0)
	if species == &"turtle_duck":
		# stand on the shore: walk out from the herd (swimming at the surface, c.y) until the
		# ground rises above the water
		for k in 80:
			var q := c + away.normalized() * (6.0 + k * 2.0)
			var gy := WorldData.get_height(q.x, q.z)
			if gy > c.y + 0.6:
				stand = Vector3(q.x, gy, q.z)
				break
	var yaw := atan2(-(c - stand).x, -(c - stand).z)
	var ok: bool = await w.travel.travel_to(Transform3D(Basis(Vector3.UP, yaw), stand), {"text": "", "autosave": false})
	p.check(ok, "travelled to the %s" % species)
	var wd := _wild()
	var seen := await p.wait_until(func() -> bool:
		for a in wd.animals():
			if a.species == species:
				return true
		return false, 40.0)
	p.check(seen, "%s spawned (animals alive: %d, flocks %d)" % [species, wd.animal_count(), wd.flock_count()])
	await p.wait_game(2.5)
	var cam := Camera3D.new()
	w.add_child(cam)
	var mid := c + Vector3(0, 0.6 if species != &"sky_bison" else 1.6, 0)
	var eye := _eye_for(mid, stand - c, minf((stand - c).length() + 2.0, 9.0), 2.0 if species != &"sky_bison" else 3.5)
	cam.global_transform = Transform3D(Basis.looking_at(mid - eye, Vector3.UP), eye)
	cam.fov = 50.0
	cam.make_current()
	await p.wait_game(0.5)
	await p.screenshot("quests_npcs_wildlife_%s" % species)
	if species != &"sky_bison":
		# walk at the herd: they flee
		var pl := w.player
		var t := 0.0
		var fled := false
		while t < 6.0 and not fled:
			var to := c - pl.global_position
			to.y = 0.0
			pl.rotation.y = atan2(-to.x, -to.z)
			pl.camera_rig.snap_behind(pl)
			p.hold(&"move_forward")
			p.hold(&"sprint")
			await p.wait_game(0.2)
			t += 0.2
			for a in wd.animals():
				if a.species == species and a.state == &"flee":
					fled = true
		p.release(&"move_forward")
		p.release(&"sprint")
		p.check(fled, "the %s fled from the player" % species)
		await p.wait_game(1.0)
		await p.screenshot("quests_npcs_wildlife_%s_flee" % species)
	w.player.camera_rig.make_current()
	cam.queue_free()
