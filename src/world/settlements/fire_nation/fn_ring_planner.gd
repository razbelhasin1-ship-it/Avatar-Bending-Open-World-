class_name FnRingPlanner
extends RingCityPlanner
## Fire Nation ring-city planning (the capital in the caldera, Crimson Harbor, the terraced
## villages): RingCityPlanner with the Fire Nation house recipes (FnHomes) and retaining walls
## (FnWalls.fn_tier_wall), plus Fire Nation street furniture helpers.


func _init() -> void:
	wall_kind = &"fn_tier_wall"
	fallback_kind = &"fn_house"


func house_footprint(kind: StringName, v: int) -> Vector2:
	return FnHomes.footprint(kind, v)


func house_height(kind: StringName, v: int) -> float:
	return FnHomes.height(kind, v)


func house_piece(kind: StringName, v: int, style: int) -> Array:
	return ["fn_%s:%d:%d" % [kind, v, style], {"v": v, "style": style}]


func house_anchors(kind: StringName, v: int, style: int, tier: StringName, _pos: Vector3, yaw: float, _fp: Vector2, door: Vector3) -> void:
	var shop: bool = kind == &"fn_house" and v % 4 == 0 and style == FnStyle.LOWER
	plan.anchor(&"market_stall" if shop else &"home", door, yaw + PI, {"tags": [String(tier)] + (["shop"] as Array if shop else []),
		"building": kind, "capacity": {&"noble_house": 10, &"fn_townhouse": 6, &"fn_villa": 5, &"fisher_hut": 3}.get(kind, 3),
		"goods": ["spices", "fireworks", "fish", "silk"][v % 4] if shop else ""})


## Courtyard trees of every noble_house placed so far (FnHomes.noble_trees), batched as tree_row
## pieces per 64 m block and species (one vegetation node each instead of one per house).
func courtyard_trees() -> void:
	var groups := {}
	for p: Dictionary in plan.pieces:
		if p["kind"] != &"noble_house":
			continue
		for t: Array in FnHomes.noble_trees(int((p["spec"] as Dictionary).get("v", 0))):
			var w := SettlementLayout.world(p["pos"], float(p["yaw"]), t[1])
			var key := "%d:%d:%s" % [floori(w.x / 64.0), floori(w.z / 64.0), t[0]]
			if not groups.has(key):
				groups[key] = [t[0], []]
			(groups[key][1] as Array).append(w)
	for key: String in groups:
		var g: Array = groups[key]
		var pts := PackedVector3Array(g[1])
		plan.add(&"tree_row", pts[0], 0.0, {"points": pts, "species": g[0], "scale": 0.7}, 0, "", 4.0)


## Lamps (fn_lamp) along a ring street at radius r every ~step_m, braziers every `brazier_every`.
func street_lights(tier: StringName, y: float, r: float, step_m: float, brazier_every: int = 4, avenue_clear: float = 12.0) -> void:
	var step := RingLayout.half_angle(2.0 * step_m, r)
	var b := 2.0
	var k := 0
	while b < 362.0:
		var bb := wrapf(b, -180.0, 180.0)
		var side := 1.0 if k % 2 == 0 else -1.0
		var p := p3(r + side * 2.4, bb, y)
		if plan.is_free(p.x, p.z, 0.8) and not on_avenue(bb, r, avenue_clear):
			plan.reserve(p.x, p.z, 0.8)
			if brazier_every > 0 and k % brazier_every == brazier_every - 1:
				plan.add(&"fn_brazier", p, 0.0, {"v": 0}, 1, "fn_brazier:0", 0.9)
			else:
				plan.add(&"fn_lamp", p, yaw_in(bb), {"v": k % 2, "light": k % 3 == 0}, 1, "fn_lamp:%d:%d" % [k % 2, int(k % 3 == 0)], 0.7)
		b += step
		k += 1
