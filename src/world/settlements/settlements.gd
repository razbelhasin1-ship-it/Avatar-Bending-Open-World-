class_name Settlements
extends RefCounted
## Settlement registry and public API (docs/modules/settlements.md).
##
## Plans are built lazily from WorldData on the main thread (deterministic, cached for the run);
## `register(content)` streams every settlement through WorldContent (near + far providers) and
## adds their vegetation keep-out areas. The NPC / quest modules read the anchor data:
##
##   Settlements.register(world_content)                         # world hook does this
##   Settlements.get_anchors(&"northern_water_tribe", &"market_stall")
##   Settlements.anchors_near(player.global_position, 60.0, &"guard_post")
##   Settlements.get_anchor(&"northern_water_tribe_trainer_3")
##   Settlements.settlement_at(pos)     Settlements.district_at(pos)
##
## Settlement ids: &"northern_water_tribe" (city), &"arctic_villages" (igloo villages + fishing
## camps of the arctic wilds), &"southern_air_temple" (temple + Foothills Landing).

const WATER_TRIBE := &"northern_water_tribe"
const ARCTIC := &"arctic_villages"
const AIR_TEMPLE := &"southern_air_temple"
const ALL: Array[StringName] = [WATER_TRIBE, ARCTIC, AIR_TEMPLE]

static var _plans: Dictionary = {}
static var _builders: Dictionary = {}


## The plan of a settlement (built on first use; empty plan without world data).
static func plan(settlement_id: StringName) -> SettlementPlan:
	if _plans.has(settlement_id):
		return _plans[settlement_id]
	var p: SettlementPlan
	match settlement_id:
		WATER_TRIBE:
			p = NwtPlanner.new().build()
		ARCTIC:
			p = ArcticPlanner.new().build()
		AIR_TEMPLE:
			p = SatPlanner.new().build()
		_:
			p = SettlementPlan.new(settlement_id)
	p.index()
	_plans[settlement_id] = p
	return p


## The recipe builder of a settlement.
static func builder(settlement_id: StringName) -> SettlementBuilder:
	if _builders.has(settlement_id):
		return _builders[settlement_id]
	var b: SettlementBuilder
	var p := plan(settlement_id)
	match settlement_id:
		WATER_TRIBE, ARCTIC:
			b = NwtBuilder.new(p)
		AIR_TEMPLE:
			b = SatBuilder.new(p)
		_:
			b = SettlementBuilder.new(p)
	_builders[settlement_id] = b
	return b


static func plans() -> Array[SettlementPlan]:
	var out: Array[SettlementPlan] = []
	for sid in ALL:
		out.append(plan(sid))
	return out


## Registers the near + far providers of every settlement on `content` and their keep-out
## areas. opts: only (Array of ids), skip_tags (Array: piece tags to leave out, e.g.
## [&"airball_court"] while the tutorial's training ground stands there). Returns the providers.
static func register(content: WorldContent, opts: Dictionary = {}) -> Array[ContentProvider]:
	var out: Array[ContentProvider] = []
	if content == null or not WorldData.has_world_data():
		return out
	NationPalette.prepare_materials()
	SettlementFx.prepare()
	var only: Array = opts.get("only", [])
	for sid in ALL:
		if not only.is_empty() and not only.has(sid):
			continue
		var p := plan(sid)
		if p.pieces.is_empty():
			continue
		var b := builder(sid)
		var near := SettlementProvider.new(p, b)
		near.skip_tags = opts.get("skip_tags", [])
		var far := SettlementFarProvider.new(p, b)
		far.skip_tags = near.skip_tags
		if content.get_provider(near.id) == null:
			content.register_provider(near)
			out.append(near)
		if content.get_provider(far.id) == null:
			content.register_provider(far)
			out.append(far)
		for e: Array in p.data.get("exclusions", []):
			content.add_exclusion(e[0], float(e[1]), int(e[2]) if e.size() > 2 else ContentExclusions.TAG_ALL, 6.0)
		for c: StringName in p.data.get("claims", []):
			ContentClaims.claim(c, sid)
	return out


static func unregister(content: WorldContent) -> void:
	if content == null:
		return
	for sid in ALL:
		content.unregister_provider(StringName("settlement_%s" % sid))
		content.unregister_provider(StringName("settlement_far_%s" % sid))


# --- NPC anchors ------------------------------------------------------------------------------

## Anchors of one settlement (&"" = all) and kind (&"" = all).
static func get_anchors(settlement_id: StringName = &"", kind: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid in ALL:
		if settlement_id == &"" or settlement_id == sid:
			out.append_array(plan(sid).get_anchors(kind))
	return out


static func get_anchor(anchor_id: StringName) -> Dictionary:
	for sid in ALL:
		for a in plan(sid).anchors:
			if a["id"] == anchor_id:
				return a
	return {}


## Anchors within `radius` of pos (closest first), optionally of one kind.
static func anchors_near(pos: Vector3, radius: float, kind: StringName = &"") -> Array[Dictionary]:
	var hits: Array = []
	for sid in ALL:
		var p := plan(sid)
		if not p.contains(pos, radius + 200.0) and sid != ARCTIC:
			continue
		for a in p.anchors:
			if kind != &"" and a["kind"] != kind:
				continue
			var d := (a["position"] as Vector3).distance_to(pos)
			if d <= radius:
				hits.append([d, a])
	hits.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var out: Array[Dictionary] = []
	for h: Array in hits:
		out.append(h[1])
	return out


## Settlement whose area contains pos (&"" if none).
static func settlement_at(pos: Vector3) -> StringName:
	for sid in [WATER_TRIBE, AIR_TEMPLE]:
		if plan(sid).contains(pos):
			return sid
	if plan(ARCTIC).district_at(pos) != &"":
		return ARCTIC
	return &""


## District id at pos (e.g. &"nwt_harbor", &"nwt_palace", &"sat_courtyard"), &"" if none.
static func district_at(pos: Vector3) -> StringName:
	for sid in ALL:
		var d := plan(sid).district_at(pos)
		if d != &"":
			return d
	return &""


## Summary of a settlement: {id, name, nation, center, radius, districts, pieces, anchors}.
static func get_info(settlement_id: StringName) -> Dictionary:
	var p := plan(settlement_id)
	return {"id": p.id, "name": p.display_name, "nation": p.nation, "center": p.center, "radius": p.radius,
		"districts": p.districts, "pieces": p.pieces.size(), "anchors": p.anchors.size()}


## Drops cached plans (tests).
static func reset() -> void:
	_plans.clear()
	_builders.clear()
