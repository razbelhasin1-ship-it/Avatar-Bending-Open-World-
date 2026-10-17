extends TestCase
## bughunt_world (wave 4 QA): regression tests for the world / streaming / settlements / quests /
## UI / save / mobile bugs found by the adversarial bug hunt (docs/qa/bughunt_world.md). Each test
## reproduces the original failure on the old code.

const E := ElementDefs.Element


func before_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.load_world()


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	GroundSampler.clear_zones()
	for n in get_children():
		n.queue_free()
	await frames(2)


# --- water: gameplay water matches the drawn water ------------------------------------------------

## Points of an unfrozen lake whose ground lies below the lake level but outside the water the
## renderer draws (WorldRecords.lake_surface_polygon) - [Vector3 ground point, lake level].
func _dry_points_below_level(lk: Dictionary, step: float = 2.0) -> Array:
	var out: Array = []
	var c: Vector3 = lk["center"]
	var surf := WorldRecords.lake_surface_polygon(lk)
	var r := float(lk["radius"]) + 2.0
	var x := c.x - r
	while x <= c.x + r:
		var z := c.z - r
		while z <= c.z + r:
			var p := Vector2(x, z)
			if p.distance_to(Vector2(c.x, c.z)) <= float(lk["radius"]) and not Geometry2D.is_point_in_polygon(p, surf):
				var g := WorldData.get_height(x, z)
				if float(lk["level"]) - g > 2.0:
					out.append([Vector3(x, g, z), float(lk["level"])])
			z += step
		x += step
	return out


## The lake test used the bounding radius while the water is drawn by the (grown) polygon: below
## the Thundering Steps falls the outlet gorge lies 15-18 m under the pool level inside that
## radius, so the ground there counted as deep water. A player walking down the gorge "swam" -
## the motor pulls a swimmer up to the surface, i.e. 15 m into the air - and companions / safe
## ground / fast travel treated dry land as lake. Now water is reported exactly where it is drawn.
func test_lake_water_only_where_it_is_drawn() -> void:
	if not expect(WorldData.has_world_data(), "baked world data"):
		return
	var checked := 0
	var wrong: Array[String] = []
	for lk: Dictionary in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		for e: Array in _dry_points_below_level(lk):
			var g: Vector3 = e[0]
			checked += 1
			if WorldData.get_water_height(g.x, g.z) > -INF and wrong.size() < 6:
				wrong.append("%s (%.0f, %.0f) ground %.1f, %.1f m under the level" % [lk["id"], g.x, g.z, g.y, float(e[1]) - g.y])
		# ...and inside the drawn water below the level it still is water
		var c: Vector3 = lk["center"]
		var gc := WorldData.get_height(c.x, c.z)
		if gc < float(lk["level"]) - 0.3:
			expect(WorldData.get_water_height(c.x, c.z) == float(lk["level"]), "%s: water at its centre" % lk["id"])
	expect(checked > 20, "found dry ground below lake levels to check (%d)" % checked)
	expect(wrong.is_empty(), "no water reported outside the drawn lakes: %s" % ", ".join(wrong))


## The real symptom: a player standing on the dry gorge floor below the falls pool did not stand,
## it swam (and rose towards the pool level, high above the ground).
func test_player_below_a_falls_pool_walks_instead_of_swimming() -> void:
	var spot := Vector3.INF
	var level := 0.0
	for lk: Dictionary in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		for e: Array in _dry_points_below_level(lk, 1.0):
			if float(e[1]) - (e[0] as Vector3).y > 6.0:
				spot = e[0]
				level = e[1]
				break
		if spot.is_finite():
			break
	if not expect(spot.is_finite(), "a dry point well below a lake level exists"):
		return
	PlayerSim.box(self, spot + Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	var p := PlayerSim.player(self, E.EARTH, spot + Vector3.UP * 0.05)
	await PlayerSim.step(p, 90)
	expect(not p.motor.swimming, "not swimming on dry ground %.1f m below the pool level (depth read %.1f)" % [level - spot.y, p.motor.water_depth])
	expect(p.global_position.y < spot.y + 0.6, "stays on the ground (y %.2f, ground %.2f)" % [p.global_position.y, spot.y])
