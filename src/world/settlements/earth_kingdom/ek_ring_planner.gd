class_name EkRingPlanner
extends RingCityPlanner
## Earth Kingdom ring-city planning (Ba Sing Se, Omashu, the terraced villages): the shared
## RingCityPlanner with the Earth Kingdom house recipes (EkHomes) and retaining walls
## (EkWalls.ring_wall).


func _init() -> void:
	wall_kind = &"ring_wall"


func house_footprint(kind: StringName, v: int) -> Vector2:
	return EkHomes.footprint(kind, v)


func house_height(kind: StringName, v: int) -> float:
	return EkHomes.height(kind, v)


func house_piece(kind: StringName, v: int, style: int) -> Array:
	if kind == &"teahouse":
		return ["ek_teahouse:%d:%d" % [v % 2, style], {"v": v % 2, "style": style}]
	return ["ek_%s:%d:%d" % [kind, v, style], {"v": v, "style": style}]


func house_anchors(kind: StringName, v: int, style: int, tier: StringName, pos: Vector3, yaw: float, fp: Vector2, door: Vector3) -> void:
	match kind:
		&"teahouse":
			plan.anchor(&"worker", door, yaw + PI, {"tags": [String(tier), "teahouse"], "building": kind})
			plan.anchor(&"idle", SettlementLayout.world(pos, yaw, Vector3(-fp.x * 0.3, 0.5, -fp.y * 0.12)), yaw, {"tags": [String(tier), "teahouse", "customer"]})
		&"row_house":
			var shop: bool = v % 4 == 0 and style == EkStyle.LOWER
			plan.anchor(&"market_stall" if shop else &"home", door, yaw + PI, {"tags": [String(tier)] + (["shop"] as Array if shop else []),
				"building": kind, "capacity": 2 + v % 4, "goods": EkProps.GOODS[v % EkProps.GOODS.size()] if shop else ""})
		_:
			plan.anchor(&"home", door, yaw + PI, {"tags": [String(tier)], "building": kind, "capacity": {&"tenement": 9, &"shack": 2,
				&"town_house": 4, &"court_house": 7, &"mansion": 12, &"farmhouse": 4}.get(kind, 3)})


## Earth Kingdom bands: the fallback kind follows the district style; Lower Ring rows are tight.
func band(tier: StringName, y: float, rf: float, depth: float, facing_in: bool, kinds: Dictionary, style: int, b0: float = 0.0,
		b1: float = 360.0, inside_fn: Callable = Callable(), gap_range: Vector2 = Vector2(-1.0, -1.0)) -> int:
	fallback_kind = &"row_house" if style == EkStyle.LOWER else &"town_house"
	var g := gap_range
	if g.x < 0.0:
		g = Vector2(0.05, 0.4) if style == EkStyle.LOWER else Vector2(0.6, 2.0)
	return super(tier, y, rf, depth, facing_in, kinds, style, b0, b1, inside_fn, g)
