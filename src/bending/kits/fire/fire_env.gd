class_name FireEnv
extends RefCounted
## Fire <-> world (docs/modules/bending_fire.md "Environment"). Every Fire technique calls
## heat() where its fire reaches the world (an explosion, a wave front, a whip crack,
## a jet), and the world answers by what is there:
##
## * IGNITE HOOK (shared contract): a Node3D in group &"ignitable" with
##   `func ignite(by: Node, at: Vector3) -> bool` (true = it caught fire) and optional
##   `var ignite_radius: float` is lit by fire reaching it. FireBrazier (brazier / torch /
##   stone lantern) is the ready-made implementation; quests can listen to its signals.
## * EXTINGUISH HOOK (the contract WaterEnv defined): group &"extinguishable",
##   `func extinguish(by: Node, at: Vector3) -> bool`, optional `var extinguish_radius`.
##   Every fire this module makes implements it (grass fires, braziers), and
##   FireEnv.extinguish(from, center, radius) puts them out for any module (air gusts,
##   earth smothering, scripted rain). FireHitProxy also lets water / air / earth HITS
##   douse them with no change to those kits.
## * MELT HOOK: group &"meltable" with `func melt(by: Node, at: Vector3, heat: float) -> bool`;
##   ice constructs (BendingConstruct kind ice) take a fire "melt" hit (x1.8 vs ice) and
##   sag; ice floes (group &"ice_floe", melt()) melt away.
## * GROUND: snow steams and melts a hollow (snow trails), water hisses into steam, dry
##   grass catches fire (GrassFire, strict spread budget), everything else is left with a
##   charred burn mark (FireMarks).
##
##   FireEnv.heat(ctx, impact_point, 2.5, 1.0)             # everything above, once
##   FireEnv.heat(ctx, p, 1.2, 0.5, {"ground": false})       # air-only (no grass / marks)
##   FireEnv.ignite_at(from, p, 1.5); FireEnv.extinguish(from, p, 3.0)

const IGNITABLE := &"ignitable"
const EXTINGUISHABLE := &"extinguishable"
const MELTABLE := &"meltable"
const BURNABLE_BIOMES: Array[int] = [WorldData.Biome.GRASSLAND, WorldData.Biome.FARMLAND, WorldData.Biome.FOREST, WorldData.Biome.VOLCANIC]
const STEAM := Color(0.92, 0.95, 0.97)

## Stats (tests / debugging).
static var ignited := 0
static var extinguished := 0
static var melted := 0
static var steamed := 0

static var _renderer_ref: WeakRef = null
## Scripted weather override: true = it is wet (rain spell, quests, tests), false = use
## the world's weather.
static var force_wet := false


## Fire reaching the world at `center` within `radius`, with `power` (0.3 a jab .. 2 the
## Inferno). opts: ground (default true: grass / snow / water / marks), mark (burn mark
## radius, default radius * 0.6; 0 = none), grass (default true), melt (default true),
## ignite (default true), normal (ground normal for the mark), glow (mark embers).
## Returns {"ignited", "melted", "ground": &"grass"/&"snow"/&"water"/&"ice"/&"scorch"/&""}.
static func heat(ctx: BendingContext, center: Vector3, radius: float, power: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	var out := {"ignited": 0, "melted": 0, "ground": &""}
	if ctx == null or not ctx.is_valid():
		return out
	var from: Node = ctx.caster
	if bool(opts.get("ignite", true)):
		out["ignited"] = ignite_at(from, center, radius, ctx.caster)
	if bool(opts.get("melt", true)):
		out["melted"] = melt_at(ctx, center, radius, power)
	if bool(opts.get("ground", true)):
		out["ground"] = ground(ctx, center, radius, power, opts)
	return out


## Lights every ignitable within `radius`. Returns how many caught fire.
static func ignite_at(from: Node, center: Vector3, radius: float, by: Node = null) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var n := 0
	for node in from.get_tree().get_nodes_in_group(IGNITABLE):
		if not (node is Node3D) or not is_instance_valid(node) or not node.has_method("ignite"):
			continue
		var extra := float(node.get("ignite_radius")) if "ignite_radius" in node else 0.0
		if (node as Node3D).global_position.distance_to(center) > radius + extra:
			continue
		if bool(node.call("ignite", by, center)):
			n += 1
	ignited += n
	return n


## Puts out every extinguishable fire within `radius` (air gusts, earth, rain, scripts).
## Same contract as WaterEnv.extinguish. Returns how many went out.
static func extinguish(from: Node, center: Vector3, radius: float, by: Node = null) -> int:
	if from == null or not from.is_inside_tree():
		return 0
	var n := 0
	for node in from.get_tree().get_nodes_in_group(EXTINGUISHABLE):
		if not (node is Node3D) or not is_instance_valid(node) or not node.has_method("extinguish"):
			continue
		var extra := float(node.get("extinguish_radius")) if "extinguish_radius" in node else 0.0
		if (node as Node3D).global_position.distance_to(center) > radius + extra:
			continue
		if bool(node.call("extinguish", by, center)):
			n += 1
	extinguished += n
	return n


## Melts ice within `radius`: enemy-team ice constructs take a fire hit (they melt and
## sag), meltables melt, ice floes melt away. Returns how many were affected.
static func melt_at(ctx: BendingContext, center: Vector3, radius: float, power: float = 1.0) -> int:
	var n := 0
	for c: BendingConstruct in BendingConstruct.live.duplicate():
		if not is_instance_valid(c) or c.kind != &"ice" or not c.is_alive():
			continue
		var reach := radius + maxf(c.size.x, c.size.z) * 0.5
		var mid := c.global_position + Vector3.UP * c.size.y * 0.5
		if mid.distance_to(center) > reach + c.size.y * 0.5:
			continue
		var hit := ctx.make_hit({"damage": 14.0 * power, "reaction": HitInfo.Reaction.NONE, "poise": 0.0}, mid - center, HitInfo.new_attack_id(), &"melt")
		hit.position = mid
		if Combat.can_hit(c, hit):
			var r := Combat.deal(c, hit)
			if r != Combat.Result.IGNORED:
				n += 1
				_melt_fx(ctx.caster, c, mid)
	for node in ctx.tree().get_nodes_in_group(MELTABLE):
		if node is Node3D and is_instance_valid(node) and node.has_method("melt") and (node as Node3D).global_position.distance_to(center) <= radius + 1.0:
			if bool(node.call("melt", ctx.caster, center, power)):
				n += 1
	for node in ctx.tree().get_nodes_in_group(&"ice_floe"):
		if node is Node3D and is_instance_valid(node) and node.has_method("melt") and (node as Node3D).global_position.distance_to(center) <= radius + 2.0:
			node.call("melt")
			steam(ctx.caster, (node as Node3D).global_position, 1.2)
			n += 1
	melted += n
	return n


static func _melt_fx(from: Node, c: BendingConstruct, mid: Vector3) -> void:
	steam(from, mid, 1.0 + c.size.y * 0.3)
	FxBurst.spawn(from, &"droplets", mid, {"count": 0.6, "size": 0.8})
	FxDecal.spawn(from, Vector3(mid.x, c.ground_y, mid.z), &"wet", maxf(c.size.x, c.size.z) * 0.45)
	# The block sags as it melts (keeps its collision: the gameplay HP decides when it breaks).
	if c.mesh_i != null and is_instance_valid(c.mesh_i) and c.max_hp > 0.0:
		var k := clampf(c.hp / c.max_hp, 0.0, 1.0)
		c.mesh_i.scale = Vector3(lerpf(0.9, 1.0, k), lerpf(0.55, 1.0, k), lerpf(0.9, 1.0, k))


## Steam puff + hiss.
static func steam(from: Node, p: Vector3, size: float = 1.0) -> void:
	steamed += 1
	FxBurst.spawn(from, &"steam", p, {"count": 0.8 + size * 0.5, "size": 0.8 + size * 0.5, "radius": clampf(size, 0.5, 2.5)})
	Audio.play_bending(ElementDefs.Element.FIRE, &"extinguish", p, -6.0 + minf(size, 2.0) * 2.0)


## What the ground under `center` does with the heat. Returns the reaction kind.
static func ground(ctx: BendingContext, center: Vector3, radius: float, power: float = 1.0, opts: Dictionary = {}) -> StringName:
	var g := ctx.ground_y(center, 1.5, 4.0)
	if center.y - g > maxf(1.6, radius * 0.9):
		return &""     # too high above the ground to reach it
	var p := Vector3(center.x, g, center.z)
	var from: Node = ctx.caster
	renderer(from)     # caches the world renderer (weather, snow) when there is one
	var w := GroundSampler.water_height(p)
	if w > -INF and w > g - 0.05:
		steam(from, Vector3(p.x, w + 0.1, p.z), radius * 0.6)
		return &"water"
	var surf := GroundSampler.surface(p)
	match surf:
		&"snow":
			steam(from, p + Vector3.UP * 0.2, radius * 0.7)
			FxDecal.spawn(from, p, &"wet", radius * 0.8)
			var r := renderer(from)
			if r != null and r.get("snow") != null:
				var snow: Object = r.get("snow")
				if snow.has_method("add_crater"):
					snow.call("add_crater", p, 6.0 + 8.0 * power * clampf(radius / 2.0, 0.5, 1.5), &"snow")
			return &"snow"
		&"ice":
			steam(from, p + Vector3.UP * 0.1, radius * 0.5)
			FxDecal.spawn(from, p, &"wet", radius * 0.6)
			return &"ice"
	var mark := float(opts.get("mark", radius * 0.6))
	if bool(opts.get("grass", true)) and is_burnable(p):
		GrassFire.ignite(ctx, p, clampf(power, 0.3, 2.0))
		if mark > 0.0:
			FireMarks.burn(from, p, mark, {"glow": 1.2, "normal": opts.get("normal", Vector3.UP)})
		return &"grass"
	if mark > 0.0:
		FireMarks.burn(from, p, mark, {"glow": float(opts.get("glow", 1.0)), "normal": opts.get("normal", Vector3.UP),
			"stretch": float(opts.get("stretch", 1.0)), "dir": opts.get("dir", Vector3.ZERO)})
	return &"scorch"


## Can grass at ground point `p` catch fire? Zones (test patches) decide inside them;
## otherwise the baked world: grass surface in a dry biome, on the terrain itself (not a
## bridge or plaza above it), not marshy or under water, not raining.
static func is_burnable(p: Vector3) -> bool:
	if is_wet_weather():
		return false
	var zone: Dictionary = GroundSampler._zone_at(p)
	if not zone.is_empty():
		return StringName(zone.get("surface", &"")) == &"grass"
	if not WorldData.has_world_data():
		return false
	if GroundSampler.surface(p) != &"grass":
		return false
	if not BURNABLE_BIOMES.has(WorldData.get_biome(p.x, p.z)):
		return false
	if absf(p.y - WorldData.get_height(p.x, p.z)) > 0.6:
		return false
	var w := GroundSampler.water_height(p)
	if w > -INF and w > p.y - 0.3:
		return false
	return WorldData.get_ground_hints(p.x, p.z).a < 0.55


## Raining (the world's weather): grass will not catch and fires burn out fast.
static func is_wet_weather() -> bool:
	if force_wet:
		return true
	var r: Node = _renderer_ref.get_ref() as Node if _renderer_ref != null else null
	if r == null or not is_instance_valid(r) or not r.has_method("get_weather"):
		return false
	return StringName(r.call("get_weather")) == &"rain"


## The scene's WorldRenderer (snow trails, weather) or null (arenas).
static func renderer(from: Node) -> Node:
	var r: Node = _renderer_ref.get_ref() as Node if _renderer_ref != null else null
	if r != null and is_instance_valid(r) and r.is_inside_tree():
		return r
	_renderer_ref = null
	if from == null or not from.is_inside_tree():
		return null
	# The playable scene the caster lives in (it may not be the current scene: tools, tests).
	var n: Node = from
	while n != null:
		var rr: Variant = n.get("renderer") if "renderer" in n else null
		if rr is WorldRenderer:
			_renderer_ref = weakref(rr)
			return rr
		n = n.get_parent()
	var cs := from.get_tree().current_scene
	if cs == null:
		return null
	var cand: Variant = cs.get("renderer") if "renderer" in cs else null
	if cand is WorldRenderer:
		_renderer_ref = weakref(cand)
		return cand
	for c in cs.get_children():
		if c is WorldRenderer:
			_renderer_ref = weakref(c)
			return c
	return null
